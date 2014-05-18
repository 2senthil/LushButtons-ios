/*
 * Copyright 2010-present Facebook.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "SCViewController.h"

#import <AddressBook/AddressBook.h>

#import "SCAppDelegate.h"
#import "SCLoginViewController.h"
#import "SCPhotoViewController.h"
#import "SCProtocols.h"
#import "TargetConditionals.h"

#define DEFAULT_IMAGE_URL @"http://facebooksampleapp.com/scrumptious/static/images/logo.png"

@interface SCViewController () < UITableViewDataSource,
UIImagePickerControllerDelegate,
FBFriendPickerDelegate,
UINavigationControllerDelegate,
FBPlacePickerDelegate,
CLLocationManagerDelegate,
UIActionSheetDelegate> {
@private NSUInteger _retryCount;
}

@property (strong, nonatomic) FBUserSettingsViewController *settingsViewController;
@property (strong, nonatomic) IBOutlet FBProfilePictureView *userProfileImage;
@property (strong, nonatomic) IBOutlet UILabel *userNameLabel;
@property (strong, nonatomic) IBOutlet UITableView *menuTableView;
@property (strong, nonatomic) UIActionSheet *mealPickerActionSheet;
@property (retain, nonatomic) NSArray *mealTypes;

@property (strong, nonatomic) NSObject<FBGraphPlace> *selectedPlace;
@property (strong, nonatomic) NSString *selectedMeal;
@property (strong, nonatomic) NSArray *selectedFriends;
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) FBCacheDescriptor *placeCacheDescriptor;
@property (strong, nonatomic) UIActivityIndicatorView *activityIndicator;

@property (strong, nonatomic) UIImagePickerController *imagePicker;
@property (strong, nonatomic) UIActionSheet *imagePickerActionSheet;
@property (strong, nonatomic) UIImage *selectedPhoto;
@property (strong, nonatomic) UIPopoverController *popover;
@property (strong, nonatomic) SCPhotoViewController *photoViewController;
@property (nonatomic) CGRect popoverFromRect;

@end

@implementation SCViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
        self.navigationItem.hidesBackButton = YES;
    }
    return self;
}

#pragma mark - Open Graph Helpers


- (void)enableUserInteraction:(BOOL)enabled {
    if (enabled) {
        [self.activityIndicator stopAnimating];
    } else {
        [self centerAndShowActivityIndicator];
    }

    [self _updateUserInteractionEnabled:enabled];
}



- (void)presentAlertForError:(NSError *)error {
    // Facebook SDK * error handling *
    // Error handling is an important part of providing a good user experience.
    // When shouldNotifyUser is YES, a userMessage can be
    // presented as a user-ready message
    if ([FBErrorUtility shouldNotifyUserForError:error]) {
        // The SDK has a message for the user, surface it.
        [[[UIAlertView alloc] initWithTitle:@"Something Went Wrong"
                                    message:[FBErrorUtility userMessageForError:error]
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
    } else {
        NSLog(@"unexpected error:%@", error);
    }
}

#pragma mark - UI Behavior

-(void)settingsButtonWasPressed:(id)sender {
    [self presentLoginSettings];
}

-(void)presentLoginSettings {
    if (self.settingsViewController == nil) {
        self.settingsViewController = [[FBUserSettingsViewController alloc] init];
#ifdef __IPHONE_7_0
        if ([self.settingsViewController respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
            self.settingsViewController.edgesForExtendedLayout &= ~UIRectEdgeTop;
        }
#endif
        self.settingsViewController.delegate = self;
    }

    [self.navigationController pushViewController:self.settingsViewController animated:YES];
}


- (void)centerAndShowActivityIndicator {
    CGRect frame = self.view.frame;
    CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    self.activityIndicator.center = center;
    [self.activityIndicator startAnimating];
}

// Displays the user's name and profile picture so they are aware of the Facebook
// identity they are logged in as.
- (void)populateUserDetails {
    if (FBSession.activeSession.isOpen) {
        [[FBRequest requestForMe] startWithCompletionHandler:
         ^(FBRequestConnection *connection, NSDictionary<FBGraphUser> *user, NSError *error) {
             if (!error) {
                 self.userNameLabel.text = user.name;
                 self.userProfileImage.profileID = [user objectForKey:@"id"];
             }
         }];
    }
}

#pragma mark UIImagePickerControllerDelegate methods

- (void)imagePickerController:(UIImagePickerController *)picker
        didFinishPickingImage:(UIImage *)image
                  editingInfo:(NSDictionary *)editingInfo {

    if (!self.photoViewController) {
        __block SCViewController *myself = self;
        self.photoViewController = [[SCPhotoViewController alloc]initWithNibName:@"SCPhotoViewController" bundle:nil image:image];
        self.photoViewController.confirmCallback = ^(id sender, bool confirm) {
            if(confirm) {
                myself.selectedPhoto = image;
            }
        };
    }
    [self.navigationController pushViewController:self.photoViewController animated:true];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [self.popover dismissPopoverAnimated:YES];
    } else {
        [self dismissModalViewControllerAnimated:YES];
    }
    self.photoViewController = nil;
}

#pragma mark - UIActionSheetDelegate methods

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {

    // If user presses cancel, do nothing
    if (buttonIndex == actionSheet.cancelButtonIndex) {
        return;
    }

    // One method handles the delegate action for two action sheets
    if (actionSheet == self.mealPickerActionSheet) {
        switch (buttonIndex) {
            case 0:{
                // They chose manual entry so prompt the user for an entry.
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:@"What are you eating?" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"OK", nil];
                alert.alertViewStyle = UIAlertViewStylePlainTextInput;
                [alert textFieldAtIndex:0].autocapitalizationType = UITextAutocapitalizationTypeSentences;
                [alert show];
                break;
            }
            default:{
                self.selectedMeal = [self.mealTypes objectAtIndex:buttonIndex];
                break;
            }
        }
    } else if (actionSheet == self.imagePickerActionSheet) {
        NSAssert(actionSheet == self.imagePickerActionSheet, @"Delegate method's else-case should be for image picker");

        if (!self.imagePicker) {
            self.imagePicker = [[UIImagePickerController alloc] init];
            self.imagePicker.delegate = self;
        }

        // Set the source type of the imagePicker to the users selection
        switch (buttonIndex) {
            case 0:{
                // If its the simulator, camera is no good
                if(TARGET_IPHONE_SIMULATOR) {
                    [[[UIAlertView alloc] initWithTitle:@"Camera not supported in simulator."
                                                message:@"(>'_')>"
                                               delegate:nil
                                      cancelButtonTitle:@"Ok"
                                      otherButtonTitles:nil] show];
                    return;
                }
                self.imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
                break;
            }
            case 1:{
                self.imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
                break;
            }
            default:{
                NSAssert1(NO, @"Unexpected button index: %lu", (unsigned long)buttonIndex);
                break;
            }
        }

        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            // Can't use presentModalViewController for image picker on iPad
            if (!self.popover) {
                self.popover = [[UIPopoverController alloc] initWithContentViewController:self.imagePicker];
            }
            [self.popover presentPopoverFromRect:self.popoverFromRect
                                          inView:self.view
                        permittedArrowDirections:UIPopoverArrowDirectionAny
                                        animated:YES];
        } else {
            [self presentViewController:self.imagePicker animated:YES completion:NULL];
        }
    } else {
        NSAssert1(NO, @"Unexpected actionSheet: %@", actionSheet);
    }
}

#pragma mark - Overrides

- (void)dealloc {
    _locationManager.delegate = nil;
    _mealPickerActionSheet.delegate = nil;
    _settingsViewController.delegate = nil;
    _imagePicker.delegate = nil;
    _imagePickerActionSheet.delegate = nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Lush Buttons";

    // Get the CLLocationManager going.
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    // We don't want to be notified of small changes in location, preferring to use our
    // last cached results, if any.
    self.locationManager.distanceFilter = 50;

    FBCacheDescriptor *cacheDescriptor = [FBFriendPickerViewController cacheDescriptor];
    [cacheDescriptor prefetchAndCacheForSession:FBSession.activeSession];

    // This avoids a gray background in the table view on iPad.
    if ([self.menuTableView respondsToSelector:@selector(backgroundView)]) {
        self.menuTableView.backgroundView = nil;
    }

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                                              initWithTitle:@"Settings"
                                              style:UIBarButtonItemStyleBordered
                                              target:self
                                              action:@selector(settingsButtonWasPressed:)];

    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.activityIndicator];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (FBSession.activeSession.isOpen) {
        [self populateUserDetails];
        self.userProfileImage.hidden = NO;
    } else {
        self.userProfileImage.hidden = YES;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    if (FBSession.activeSession.isOpen) {
        [self.locationManager startUpdatingLocation];
    }
}

- (void)viewDidUnload {
    [super viewDidUnload];

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // Release any retained subviews of the main view.
    self.mealPickerActionSheet = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

#pragma mark - FBUserSettingsDelegate methods

- (void)loginViewControllerDidLogUserOut:(id)sender {
    // Facebook SDK * login flow *
    // There are many ways to implement the Facebook login flow.
    // In this sample, the FBLoginView delegate (SCLoginViewController)
    // will already handle logging out so this method is a no-op.
}

- (void)loginViewController:(id)sender receivedError:(NSError *)error {
    // Facebook SDK * login flow *
    // There are many ways to implement the Facebook login flow.
    // In this sample, the FBUserSettingsViewController is only presented
    // as a log out option after the user has been authenticated, so
    // no real errors should occur. If the FBUserSettingsViewController
    // had been the entry point to the app, then this error handler should
    // be as rigorous as the FBLoginView delegate (SCLoginViewController)
    // in order to handle login errors.
    if (error) {
        NSLog(@"Unexpected error sent to the FBUserSettingsViewController delegate: %@", error);
    }
}

#pragma mark - UITableViewDataSource methods and related helpers

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";

    UITableViewCell *cell = (UITableViewCell *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.textLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0];
        cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        cell.textLabel.clipsToBounds = YES;

        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0];
        cell.detailTextLabel.textColor = [UIColor colorWithRed:0.4 green:0.6 blue:0.8 alpha:1];
        cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        cell.detailTextLabel.clipsToBounds = YES;
    }

    switch (indexPath.row) {
        case 0:
            cell.textLabel.text = @"Got a picture?";
            cell.detailTextLabel.text = @"Take one";
            cell.imageView.image = [UIImage imageNamed:@"action-photo.png"];
            break;

        default:
            break;
    }

    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
            if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
                self.popoverFromRect = [tableView rectForRowAtIndexPath:indexPath];
            }
            if(!self.imagePickerActionSheet) {
                self.imagePickerActionSheet = [[UIActionSheet alloc] initWithTitle:@""
                                                                          delegate:self
                                                                 cancelButtonTitle:@"Cancel"
                                                            destructiveButtonTitle:nil
                                                                 otherButtonTitles:@"Take Photo", @"Choose Existing", nil];
            }

            [self.imagePickerActionSheet showInView:self.view];
            return;
}

- (void)updateCellIndex:(NSUInteger)index withSubtitle:(NSString *)subtitle {
    UITableViewCell *cell = (UITableViewCell *)[self.menuTableView cellForRowAtIndexPath:
                                                [NSIndexPath indexPathForRow:index inSection:0]];
    cell.detailTextLabel.text = subtitle;
}


#pragma mark -

- (void)_updateUserInteractionEnabled:(BOOL)enabled
{
    [self.view setUserInteractionEnabled:enabled];
}

- (UIImage *)normalizedImage:(UIImage *)image {
    CGImageRef imgRef = image.CGImage;
    CGFloat width = CGImageGetWidth(imgRef);
    CGFloat height = CGImageGetHeight(imgRef);
    CGAffineTransform transform = CGAffineTransformIdentity;
    CGRect bounds = CGRectMake(0, 0, width, height);
    CGSize imageSize = bounds.size;
    CGFloat boundHeight;
    UIImageOrientation orient = image.imageOrientation;

    switch (orient) {
        case UIImageOrientationUp: //EXIF = 1
            transform = CGAffineTransformIdentity;
            break;

        case UIImageOrientationDown: //EXIF = 3
            transform = CGAffineTransformMakeTranslation(imageSize.width, imageSize.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;

        case UIImageOrientationLeft: //EXIF = 6
            boundHeight = bounds.size.height;
            bounds.size.height = bounds.size.width;
            bounds.size.width = boundHeight;
            transform = CGAffineTransformMakeTranslation(imageSize.height, imageSize.width);
            transform = CGAffineTransformScale(transform, -1.0, 1.0);
            transform = CGAffineTransformRotate(transform, 3.0 * M_PI / 2.0);
            break;

        case UIImageOrientationRight: //EXIF = 8
            boundHeight = bounds.size.height;
            bounds.size.height = bounds.size.width;
            bounds.size.width = boundHeight;
            transform = CGAffineTransformMakeTranslation(0.0, imageSize.width);
            transform = CGAffineTransformRotate(transform, 3.0 * M_PI / 2.0);
            break;

        default:
            // image is not auto-rotated by the photo picker, so whatever the user
            // sees is what they expect to get. No modification necessary
            transform = CGAffineTransformIdentity;
            break;
    }

    UIGraphicsBeginImageContext(bounds.size);
    CGContextRef context = UIGraphicsGetCurrentContext();

    if ((image.imageOrientation == UIImageOrientationDown) ||
        (image.imageOrientation == UIImageOrientationRight) ||
        (image.imageOrientation == UIImageOrientationUp)) {
        // flip the coordinate space upside down
        CGContextScaleCTM(context, 1, -1);
        CGContextTranslateCTM(context, 0, -height);
    }

    CGContextConcatCTM(context, transform);
    CGContextDrawImage(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, width, height), imgRef);
    UIImage *imageCopy = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return imageCopy;
}

@end
