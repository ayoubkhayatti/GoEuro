//
//  ViewController.m
//  GoEuro
//
//  Created by Ayoub Khayati on 08/04/14.
//  Copyright (c) 2014 Ayoub Khayati. All rights reserved.
//

#import "ViewController.h"
#import <CoreLocation/CoreLocation.h>
#import <QuartzCore/QuartzCore.h>

@interface ViewController () <UITextFieldDelegate, NSURLSessionDelegate, CLLocationManagerDelegate, UITableViewDataSource, UITableViewDelegate>

@property (weak, nonatomic) IBOutlet UITextField *startTextField;
@property (weak, nonatomic) IBOutlet UITextField *endTextField;
@property (weak, nonatomic) IBOutlet UITextField *dateTextField;
@property (weak, nonatomic) IBOutlet UIButton *searchButton;

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *dataTask;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) NSMutableArray *autoCompleteData;
@property (nonatomic, strong) UITableView *autoCompleteTable;


@end

@implementation ViewController

-(instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [super initWithCoder:aDecoder];
    if (self) {
        //Initiate session
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        [configuration setHTTPAdditionalHeaders:@{@"Accept": @"application/json"}];
        configuration.timeoutIntervalForRequest = 20.0;
        configuration.timeoutIntervalForResource = 20.0;
        self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    }
    return self;
}

- (void)viewDidLoad{
    [super viewDidLoad];
    
    //Initiate CoreLocation
    self.locationManager = [CLLocationManager new];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    [self.locationManager startUpdatingLocation];
    
    self.autoCompleteData = [[NSMutableArray alloc]init];

    //TextFields Delegate
    self.startTextField.delegate = self;
    self.endTextField.delegate   = self;
    self.dateTextField.delegate  = self;
    
    //Keyboard Notifications
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    
    //DatePicker
    UIDatePicker *datePicker = [[UIDatePicker alloc]init];
    datePicker.datePickerMode = UIDatePickerModeDate;
    datePicker.date = [NSDate date];
    [datePicker addTarget:self action:@selector(updateTextField:) forControlEvents:UIControlEventValueChanged];
    [self.dateTextField setInputView:datePicker];

    //Search Button
    [self.searchButton addTarget:self action:@selector(search:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    [[NSNotificationCenter defaultCenter]removeObserver:self name:UIKeyboardDidShowNotification object:nil];
    [[NSNotificationCenter defaultCenter]removeObserver:self name:UIKeyboardDidHideNotification object:nil];
}

#pragma mark - TextField Delegate Methods

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string{
    if (textField.tag == 1) {
        NSString *searchString = [textField.text stringByReplacingCharactersInRange:range withString:string];

        if (![searchString isEqualToString:@""]) {
            [self sendRequestWithString:searchString completion:^(NSDictionary *results) {
                [self.autoCompleteData removeAllObjects];
                if (results.count > 0) {
                    [self.autoCompleteData addObjectsFromArray:(NSArray*)results];
                    [self sortDistancesFromCurrentLocation:self.autoCompleteData completion:^(NSArray *array) {
                        self.autoCompleteData = [array mutableCopy];
                    }];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self triggerAutoCompleteFor:textField];
                });
            }];
        }else{
            [self triggerAutoCompleteFor:textField];
        }
    }
    return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField{
    [self.autoCompleteData removeAllObjects];
    [self triggerAutoCompleteFor:textField];
    return YES;
}

#pragma mark - My methods

- (void)sendRequestWithString:(NSString*)string completion:(void(^)(NSDictionary *))results{
    [self.dataTask cancel];//cancel any ongoing task before sending new one.

    NSString *apiUrl = [NSString stringWithFormat:@"https://api.goeuro.com/api/v2/position/suggest/de/%@",
                        [string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    
    self.dataTask = [self.session dataTaskWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:apiUrl]]
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
                                        if (!error) {
                                            if (httpResponse.statusCode == 200) {
                                                NSError *JsonError;
                                                NSDictionary *JsonResponse = [NSJSONSerialization JSONObjectWithData:data
                                                                                                             options:kNilOptions
                                                                                                               error:&JsonError];
                                                results(JsonResponse);
                                            }else{
                                                //Handle Bad responses!
                                                NSLog(@"Bad response: %@",response.description);
                                            }
                                        }
                                        else {
                                            //Handle Errors!
                                            NSLog(@"Error: %@",error.localizedDescription);
                                        }
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                                        });
                                    }];
    [self.dataTask resume];
}

- (void)sortDistancesFromCurrentLocation:(NSMutableArray *)locations completion:(void(^)(NSArray *))array{
    __weak typeof(self) weakSelf = self;
    NSArray *sortedArray = [(NSArray*)locations sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        CLLocation *obj1Location = [[CLLocation alloc]initWithLatitude:[obj1[@"geo_position"][@"latitude"] floatValue]
                                                             longitude:[obj1[@"geo_position"][@"longitude"] floatValue]];
        CLLocation *obj2Location = [[CLLocation alloc]initWithLatitude:[obj2[@"geo_position"][@"latitude"] floatValue]
                                                             longitude:[obj2[@"geo_position"][@"longitude"] floatValue]];
        
        CLLocationDistance obj1Distance = [obj1Location distanceFromLocation:weakSelf.locationManager.location];
        CLLocationDistance obj2Distance = [obj2Location distanceFromLocation:weakSelf.locationManager.location];
        
        if (obj1Distance > obj2Distance) {
            return (NSComparisonResult)NSOrderedDescending;
        }
        if (obj1Distance < obj2Distance) {
            return (NSComparisonResult)NSOrderedAscending;
        }
        return (NSComparisonResult)NSOrderedSame;
    }];
    array(sortedArray);
}

- (void)triggerAutoCompleteFor:(UITextField*)textField{
    if (self.autoCompleteData.count > 0 && ![textField.text isEqual:@""]) {
        
        CGFloat height;
        if ((self.autoCompleteData.count * 25.0f) < 100) {
            height = self.autoCompleteData.count * 25.0f;
        }else height = 100;
        CGRect autoCompleteRect = CGRectMake(textField.frame.origin.x, textField.frame.origin.y+textField.frame.size.height,
                                             textField.frame.size.width, height);
        
        if (![self.view.subviews containsObject:self.autoCompleteTable]) {
            [UIView animateWithDuration:0.5f delay:0.0f options:UIViewAnimationOptionAllowUserInteraction animations:^{
                self.autoCompleteTable = [[UITableView alloc]initWithFrame:autoCompleteRect style:UITableViewStylePlain];
                self.autoCompleteTable.delegate = self;
                self.autoCompleteTable.dataSource = self;
                self.autoCompleteTable.layer.borderWidth = 1.0;
                self.autoCompleteTable.layer.borderColor = [UIColor blackColor].CGColor;
                [self.view addSubview:self.autoCompleteTable];
            } completion:^(BOOL finished) {
                    //Nothing
            }];

        }else {
            self.autoCompleteTable.frame = autoCompleteRect;
            [self.autoCompleteTable reloadData];
        }
    }else{
        [UIView animateWithDuration:0.2f animations:^{
            self.autoCompleteTable.alpha = 0.0f;
        }completion:^(BOOL finished) {
            [self.autoCompleteTable removeFromSuperview];
        }];
    }
    
}

- (void)updateTextField:(id)sender {
    UIDatePicker *datePicker = (UIDatePicker*)self.dateTextField.inputView;
    NSDate *date = datePicker.date;
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"MM-dd-yyyy";
    self.dateTextField.text = [dateFormatter stringFromDate:date];
}

- (void)search:(UIButton*)button{
    [self.view.subviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isFirstResponder]) {
            [obj resignFirstResponder];
        }
    }];
    UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"GoEuro"
                                                   message:@"Search is not yet implemented!"
                                                  delegate:self
                                         cancelButtonTitle:@"OK"
                                         otherButtonTitles:nil, nil];
    [alert show];
}

#pragma mark - TableView Delegates Methods

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return self.autoCompleteData.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    return 25.0f;
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MyIdentifier"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"MyIdentifier"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.textLabel.attributedText = [[NSAttributedString alloc]initWithString:self.autoCompleteData[indexPath.row][@"fullName"]
                                                                   attributes:@{NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleCaption2]}];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    [self.view.subviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isFirstResponder] && [obj isKindOfClass:[UITextField class]]) {
            ((UITextField*)obj).text = [tableView cellForRowAtIndexPath:indexPath].textLabel.text;
            [obj resignFirstResponder];
        }
    }];
}


#pragma mark - CoreLocation Delegate Methods

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if ([error domain] == kCLErrorDomain) {
        switch ([error code]) {
            case kCLErrorDenied:
                NSLog(@"Access to the location service is denied by the user");
            case kCLErrorLocationUnknown:
                NSLog(@"The location manager is unable to obtain a location value right now");
            default:
                break;
        }
    } else {
        // We handle all non-CoreLocation errors here
    }
}

#pragma mark - KeyBoard Notifcations

- (void)keyboardWillShow:(NSNotification*)notification{
    CGSize keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
    [UIView animateWithDuration:0.2f delay:0.0f options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.view.frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y-keyboardSize.height/3,
                                     self.view.frame.size.width, self.view.frame.size.height);
    } completion:^(BOOL finished) {
        //
    }];
}

- (void)keyboardWillHide:(NSNotification*)notification{
    CGSize keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
    [UIView animateWithDuration:0.1f delay:0.0f options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.view.frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y+keyboardSize.height/3,
                                     self.view.frame.size.width, self.view.frame.size.height);
    } completion:^(BOOL finished) {
        //
    }];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

- (void)didReceiveMemoryWarning{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
