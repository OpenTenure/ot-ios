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
#import "OTSharesUpdateViewController.h"
#import "OTSelectionTabBarViewController.h"
#import "PickerView.h"

@interface OTSharesUpdateViewController () <OTSelectionTabBarViewControllerDelegate, UITextFieldDelegate>
@property (nonatomic, strong) PickerView *pickerView;

@property  NSInteger *selectedRow;
@end

@implementation OTSharesUpdateViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self loadData];
     NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < 100; i++)
    {
        [items addObject:@(i)];
    }
   
    self.pickerView = [[PickerView alloc] initWithPickItems:items];
    [_pickerView setPickType:PickTypeList];
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Data

- (void)loadData {
    __weak typeof(self) weakSelf = self;
    // TODO: Progress start
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [weakSelf displayData];
        // TODO Progress dismiss
    });
}

#pragma mark - Overridden getters

- (NSManagedObjectContext *)managedObjectContext {
    return _claim.managedObjectContext;
}

- (NSString *)mainTableSectionNameKeyPath {
    return nil;
}

- (NSString *)mainTableCache {
    return @"ShareCache";
}

- (NSArray *)sortKeys {
    return @[@"nominator"];
}

- (NSString *)entityName {
    return @"Share";
}

- (BOOL)showIndexes {
    return NO;
}

- (NSUInteger)fetchBatchSize {
    return 30;
}

- (NSPredicate *)frcPredicate {
    return [NSPredicate predicateWithFormat:@"(claim = %@)", _claim];
}

- (NSPredicate *)searchPredicateWithSearchText:(NSString *)searchText scope:(NSInteger)scope {
    return nil;
}

- (NSUInteger)noOfLettersInSearch {
    return 1;
}

- (void)configureCell:(UITableViewCell *)cell forTableView:(UITableView *)tableView atIndexPath:(NSIndexPath *)indexPath {
    [super configureCell:cell forTableView:tableView atIndexPath:indexPath];

    cell.tintColor = [UIColor otDarkBlue];
    
    Share *share;
    
    if (_filteredObjects == nil)
        share = [_fetchedResultsController objectAtIndexPath:indexPath];
    else
        share = [_filteredObjects objectAtIndex:indexPath.row];
    
    ///
    UITextField *textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 64, 32)];
    textField.text = [@([share.nominator integerValue]) stringValue];
    textField.delegate = self;
//    textField.layer.borderColor = [UIColor otDarkBlue].CGColor;
//    textField.backgroundColor = [UIColor clearColor];
//    textField.layer.borderWidth = 0.5;
    CALayer *bottomBorder = [CALayer layer];
    bottomBorder.borderColor = [UIColor otDarkBlue].CGColor;
    bottomBorder.borderWidth = 1;
    bottomBorder.frame = CGRectMake(0, textField.frame.size.height-1, textField.frame.size.width, 1);
    [textField.layer addSublayer:bottomBorder];
    UIImageView *comboView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"combo"]];
    textField.rightView = comboView;
    textField.rightViewMode = UITextFieldViewModeAlways;
    cell.accessoryView = textField;
    
    ///

    cell.textLabel.numberOfLines = 0;
    cell.textLabel.text = [NSString stringWithFormat:@"Share %tu : %tu/%tu", indexPath.row + 1, [share.nominator integerValue], [share.denominator integerValue]];
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\nOwners : %tu", share.shareId, share.owners.count];
}

#pragma Bar Buttons Action

- (IBAction)addShare:(id)sender {
    NSInteger freeShare = [self getFreeShare];
    if (freeShare <= 0) {
        //If number of owner
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"message_no_available_shares", nil)];
   } else {
        // TODO: Select person, create new Owner
        /*
         Owner *owner = [OwnerEntity create];
         owner.ownerId = [[[NSUUID UUID] UUIDString] lowercaseString];
         owner.person = person;
         owner.denominator = [NSNumber numberWithInteger:100];
         owner.nominator = [NSNumber numberWithInteger:freeShare];
         owner.claim = _claim;
         */
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInteger:OTPersonSelectionAction] forKey:@"OTSelectionAction"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        OTAppDelegate* appDelegate = (OTAppDelegate*)[[UIApplication sharedApplication] delegate];
        id main = appDelegate.window.rootViewController;
        OTSelectionTabBarViewController *selectionViewController = (OTSelectionTabBarViewController *)[[main storyboard] instantiateViewControllerWithIdentifier:@"SelectionTabBarDetail"];
        selectionViewController.selectionDelegate = self;
        
        UINavigationController *nav = [[main storyboard] instantiateViewControllerWithIdentifier:@"SelectionTabBar"];
        nav = [nav initWithRootViewController:selectionViewController];
        
        if (nav != nil) {
            [self.navigationController presentViewController:nav animated:YES completion:nil];
        }

  }
}

- (NSInteger)getFreeShare {
    double scale = 0.0;
    for (Share *share in _claim.shares) {
        scale += ([share.nominator doubleValue] / [share.denominator doubleValue]);
    }
    return (1 - scale) * 100;
}

#pragma UITableViewDelegate methods

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    cell.accessoryType = UITableViewCellAccessoryDetailButton;
    cell.tintColor = [UIColor otDarkBlue];
    
    [self configureCell:cell forTableView:tableView atIndexPath:indexPath];
  
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 64;
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    // TODO: Free share
    // Test
    [UIAlertView showWithTitle:@"New share percentage" message:nil style:UIAlertViewStylePlainTextInput cancelButtonTitle:NSLocalizedString(@"cancel", nil) otherButtonTitles:@[NSLocalizedString(@"OK", nil)] tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
        if (buttonIndex == 1) {
            Share *share = [_fetchedResultsController objectAtIndexPath:indexPath];
            NSString *s = [[alertView textFieldAtIndex:0] text];
            NSInteger num = [s integerValue];
            // TODO check valid
            [share setNominator:[NSNumber numberWithInteger:num]];
        }
    }];
//    
//   UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"New share percentage"
//                                                        message:nil
//                                                       delegate:self
//                                              cancelButtonTitle:NSLocalizedString(@"cancel", nil)
//                                              otherButtonTitles:NSLocalizedString(@"Ok", nil), nil];
//
//    //ALog(@"%i",[[tableView indexPathForSelectedRow] row]);
//    [alertView setAlertViewStyle:UIAlertViewStylePlainTextInput];
//    [[alertView textFieldAtIndex:0] setPlaceholder:NSLocalizedString(@"message_enter_description", nil)];
//    //[[alertView textFieldAtIndex:0] setDelegate:self];
//    [alertView show];
//    
//    //[[_claim.owners.allObjects firstObject] setNominator:[NSNumber numberWithInteger:60]];
   // [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:@"Do free share %tu", [self getFreeShare]]];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UITableViewCellEditingStyle) tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        Share *share = [_fetchedResultsController objectAtIndexPath:indexPath];
        [self.managedObjectContext deleteObject:share];
    }
}
//
//- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
//    
//    //which button was pressed in the alert view
//    NSString *buttonTitle = [alertView buttonTitleAtIndex:buttonIndex];
//    if ([buttonTitle isEqualToString:@"Ok"]){
//        NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
//        [f setNumberStyle:NSNumberFormatterDecimalStyle];
//        NSNumber * myNumber = [f numberFromString:[[alertView textFieldAtIndex:0] text]];
//     
//        
//       // Person* p= _claim.owners.allObjects[(int)_selectedRow];
////       Person* p= [_claim.owners.allObjects[(int)_selectedRow] valueForKey:@"person"];
//      //  ALog(@"%@ %@", p.lastName, );
//        [_claim.owners.allObjects[(int)_selectedRow] setNominator:myNumber];
//        //ALog(@"%@",p.lastName );
//        [_tableView reloadData];
//    }
//    else if ([buttonTitle isEqualToString:@"Cancel"]){
//        ALog(@"Cancel button was pressed.");
//    }
//}

#pragma OTSelectionTabBarViewControllerDelegate methods

- (void)personSelection:(OTSelectionTabBarViewController *)controller didSelectPerson:(Person *)person {
    // TODO: Thêm share ở đây
   // _claim.owners
   // _claim.person = person;
   // _claimantBlock.textField.text = [person fullNameType:OTFullNameTypeDefault];
   // _claimantBlock.validationState = BPFormValidationStateValid;
    NSInteger nominator = [self getFreeShare];
    if (nominator < 100) {
        ShareEntity *shareEntity = [ShareEntity new];
        [shareEntity setManagedObjectContext:_claim.managedObjectContext];
        Share *share = [shareEntity create];
        share.shareId = [[[NSUUID UUID] UUIDString] lowercaseString];
        [share addOwnersObject:person];
        share.denominator = [NSNumber numberWithInteger:100];
        share.nominator = [NSNumber numberWithInteger:nominator];
        share.claim = _claim;

        [_claim.managedObjectContext save:nil];
        [controller.navigationController dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
