/**
 * ******************************************************************************************
 * Copyright (C) 2014 - Food and Agriculture Organization of the United Nations (FAO).
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 *    1. Redistributions of source code must retain the above copyright notice,this list
 *       of conditions and the following disclaimer.
 *    2. Redistributions in binary form must reproduce the above copyright notice,this list
 *       of conditions and the following disclaimer in the documentation and/or other
 *       materials provided with the distribution.
 *    3. Neither the name of FAO nor the names of its contributors may be used to endorse or
 *       promote products derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,PROCUREMENT
 * OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,STRICT LIABILITY,OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * *********************************************************************************************
 */

#import "SaveClaimTask.h"
#import "SaveAttachmentTask.h"

@interface SaveClaimTask () <SaveAttachmentTaskDelegate>

@property (nonatomic, strong) Claim *claim;

@property (nonatomic) NSOperationQueue *saveAttachmentQueue;

@property (nonatomic, assign) NSUInteger totalAttachment;
@property (nonatomic, assign) NSUInteger totalAttachmentDownloaded;

@end

static NSURLSessionUploadTask *uploadTask;

@implementation SaveClaimTask

- (id)initWithClaim:(Claim *)claim {
    if (self = [super init]) {
        _claim = claim;
        _claim.lodgementDate = [[OT dateFormatter] stringFromDate:[NSDate date]];
    }
    return self;
}

- (void)main {
    
    NSDictionary *jsonObject = _claim.dictionary;
    
    if ([NSJSONSerialization isValidJSONObject:jsonObject]) {

        self.saveAttachmentQueue = [NSOperationQueue new];
        //[self.saveAttachmentQueue addObserver:self forKeyPath:@"attachmentCount" options:0 context:NULL];
        
        NSLog(@"%@", jsonObject.description);
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject options:NSJSONWritingPrettyPrinted error:nil];
        
        [CommunityServerAPI saveClaim:jsonData completionHandler:^(NSError *error, NSHTTPURLResponse *httpResponse, NSData *data) {
            if (error != nil) {
                [OT handleError:error];
            } else {
                if ([[httpResponse MIMEType] isEqual:@"application/json"]) {
                    NSError *parseError = nil;
                    id returnedData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&parseError];
                    
                    if (!returnedData) {
                        [OT handleError:parseError];
                    } else {
                        switch (httpResponse.statusCode) {
                            case 100: /* UnknownHostException: */
                                if (([_claim.statusCode isEqualToString:kClaimStatusCreated]
                                     || [_claim.statusCode isEqualToString:kClaimStatusUploadIncomplete])
                                    && [_claim.statusCode isEqualToString:kClaimStatusUploadError]) {
                                    _claim.statusCode = kClaimStatusUploadIncomplete;
                                }
                                if ([_claim.statusCode isEqualToString:kClaimStatusUnmoderated]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUpdateError]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUpdateIncomplete]) {
                                    _claim.statusCode = kClaimStatusUpdateIncomplete;
                                }
                                [OT handleErrorWithMessage:[returnedData message]];
                                break;
                                
                            case 105: /* IOException: */
                                if (([_claim.statusCode isEqualToString:kClaimStatusCreated]
                                     || [_claim.statusCode isEqualToString:kClaimStatusUploadIncomplete])
                                    && [_claim.statusCode isEqualToString:kClaimStatusUploadError]) {
                                    _claim.statusCode = kClaimStatusUploadError;
                                }
                                if ([_claim.statusCode isEqualToString:kClaimStatusUnmoderated]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUpdateError]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUpdateIncomplete]) {
                                    _claim.statusCode = kClaimStatusUpdateError;
                                }
                                [OT handleErrorWithMessage:[returnedData message]];
                                break;
                                
                            case 110:
                                if (([_claim.statusCode isEqualToString:kClaimStatusCreated]
                                     || [_claim.statusCode isEqualToString:kClaimStatusUploadIncomplete])
                                    && [_claim.statusCode isEqualToString:kClaimStatusUploadError]) {
                                    _claim.statusCode = kClaimStatusUploadError;
                                }
                                if ([_claim.statusCode isEqualToString:kClaimStatusUnmoderated]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUpdateError]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUpdateIncomplete]) {
                                    _claim.statusCode = kClaimStatusUpdateError;
                                }
                                [OT handleErrorWithMessage:[returnedData message]];
                                break;
                                
                            case 200: { /* OK */
                                NSLog(@"return: %@", [returnedData description]);
                                NSDateFormatter *dateFormatter = [NSDateFormatter new];
                                [dateFormatter setDateFormat:[[OT dateFormatter] dateFormat]];
                                NSTimeZone *utc = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
                                [dateFormatter setTimeZone:utc];
                                NSDate *date = [dateFormatter dateFromString:[returnedData objectForKey:@"challengeExpiryDate"]];
                                _claim.challengeExpiryDate = [[OT dateFormatter] stringFromDate:date];
                                
                                _claim.nr = [returnedData objectForKey:@"nr"];
                                
                                _claim.statusCode = kClaimStatusUnmoderated;
                                
                                _claim.recorderName = [OTAppDelegate userName];
                                
                                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"message_submitted", nil)];
                                
                                break;
                            }
                                
                            case 403:
                            case 404:{ /* Error Login */
                                [OT handleErrorWithMessage:NSLocalizedString(@"message_login_no_more_valid", nil)];
                                [OT login];
                                break;
                            }
                                
                            case 452: { /* Missing Attachments */
                                
                                [SVProgressHUD showProgress:0.0 status:NSLocalizedString(@"message_uploading", nil)];
                                
                                if (([_claim.statusCode isEqualToString:kClaimStatusCreated]
                                     || [_claim.statusCode isEqualToString:kClaimStatusUploadIncomplete])
                                    && [_claim.statusCode isEqualToString:kClaimStatusUploadError]) {
                                    _claim.statusCode = kClaimStatusUploading;
                                }
                                if ([_claim.statusCode isEqualToString:kClaimStatusUnmoderated]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUpdateError]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUpdateIncomplete]) {
                                    _claim.statusCode = kClaimStatusUpdating;
                                }
                                if ([_claim.managedObjectContext hasChanges])
                                    [_claim.managedObjectContext save:nil];
                                
                                NSLog(@"Uploading attachments");
                                
                                NSMutableArray *saveAttachmentTaskList = [NSMutableArray array];
                                for (Attachment *attachment in _claim.attachments) {
                                    if (attachment.statusCode != kAttachmentStatusUploaded
                                        && attachment.statusCode != kAttachmentStatusUploading) {
                                        SaveAttachmentTask *saveAttachmentTask = [[SaveAttachmentTask alloc] initWithAttachment:attachment];
                                        saveAttachmentTask.delegate = self;
                                        [saveAttachmentTaskList addObject:saveAttachmentTask];
                                    }
                                }
                                _totalAttachment = saveAttachmentTaskList.count;
                                [self.saveAttachmentQueue addOperations:saveAttachmentTaskList waitUntilFinished:NO];

                                break;
                            }
                            case 450: {
                                if ([_claim.statusCode isEqualToString:kClaimStatusCreated]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUploading]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUploadIncomplete]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUploadError]) {
                                    _claim.statusCode = kClaimStatusUploadError;
                                } else {
                                    _claim.statusCode = kClaimStatusUpdateError;
                                }
                                
                                [OT handleErrorWithMessage:[returnedData message]];
                                break;
                            }
                            case 400:
                                NSLog(@"%@", [returnedData description]);
                                if ([_claim.statusCode isEqualToString:kClaimStatusCreated]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUploading]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUploadIncomplete]
                                    || [_claim.statusCode isEqualToString:kClaimStatusUploadError]) {
                                    _claim.statusCode = kClaimStatusUploadError;
                                } else {
                                    _claim.statusCode = kClaimStatusUpdateError;
                                }
                                [OT handleErrorWithMessage:[returnedData message]];
                                break;
                            default:
                                break;
                        }
                    }
                } else {
                    NSString *errorString = NSLocalizedString(@"error_generic_conection", @"An error has occurred during connection");
                    NSDictionary *userInfo = @{NSLocalizedDescriptionKey : errorString};
                    NSError *reportError = [NSError errorWithDomain:@"HTTP"
                                                               code:[httpResponse statusCode]
                                                           userInfo:userInfo];
                    [OT handleError:reportError];
                }
                if ([_claim.managedObjectContext hasChanges]) [_claim.managedObjectContext save:nil];
            }
        }];
    }
}

// observe the queue's operationCount, stop activity indicator if there is no operatation ongoing.
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == self.saveAttachmentQueue && [keyPath isEqualToString:@"attachmentCount"]) {
        if (self.saveAttachmentQueue.operationCount == 0) {
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"message_submitted", nil)];
            [self removeObserver:self forKeyPath:@"attachmentCount" context:nil];
        }
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma SaveAttachmentTaskDelegate method

- (void)saveAttachment:(SaveAttachmentTask *)controller didFinishTask:(id)task {
    _totalAttachmentDownloaded++;
    double progress = (double)_totalAttachmentDownloaded / (double)_totalAttachment;
    dispatch_async(dispatch_get_main_queue(), ^{
        [SVProgressHUD showProgress:progress status:NSLocalizedString(@"message_uploading", nil)];
    });
}

@end
