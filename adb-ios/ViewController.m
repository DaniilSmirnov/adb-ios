//
//  ViewController.m
//  adb-ios
//
//  Created by Li Zonghai on 9/28/15.
//  Copyright (c) 2015 Li Zonghai. All rights reserved.
//

#import "ViewController.h"
#import "adb/AdbClient.h"


@interface ViewController ()
@property(strong) AdbClient *adb;

@end

@implementation ViewController
@synthesize adb = _adb;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _adb = [[AdbClient alloc] initWithVerbose:YES];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void) list:(id)sender
{
    self.textview.text = @"loading...";
    [_adb devices:^(BOOL succ, NSString *result1) {
        [self.textview performSelectorOnMainThread:@selector(setText:) withObject:result1 waitUntilDone:YES];
    }];
}


-(IBAction)connectBtn:(id)sender
{
    self.textview.text = @"loading...";
    [_adb connect: self.textField.text didResponse:^(BOOL succ, NSString *result) {
        
        [self.textview performSelectorOnMainThread:@selector(setText:) withObject:result waitUntilDone:YES];

    }];
}

-(IBAction)installApkBtn:(id)sender
{
    self.textview.text = @"loading...";
    NSString *apkPath = [[NSBundle mainBundle] pathForResource:@"Term" ofType:@"apk"];
    [_adb installApk:apkPath flags:ADBInstallFlag_Replace didResponse:^(BOOL succ, NSString *result) {
        [self.textview performSelectorOnMainThread:@selector(setText:) withObject:result waitUntilDone:YES];
    }];
}


-(IBAction)uninstallApkBtn:(id)sender
{
    self.textview.text = @"loading...";
    [_adb uninstallApk:@"jackpal.androidterm" didResponse:^(BOOL succ, NSString *result) {
        [self.textview performSelectorOnMainThread:@selector(setText:) withObject:result waitUntilDone:YES];
    }];
}


-(IBAction)startApk:(id)sender
{
    self.textview.text = @"loading...";
    [_adb shell:@"am start jackpal.androidterm/.Term" didResponse:^(BOOL succ, NSString *result) {
        [self.textview performSelectorOnMainThread:@selector(setText:) withObject:result waitUntilDone:YES];
    }];
}


-(IBAction)disconnect:(id)sender
{
    self.textview.text = @"loading...";
    [_adb disconnect: self.textField.text didResponse:^(BOOL succ, NSString *result) {
        
        [self.textview performSelectorOnMainThread:@selector(setText:) withObject:result waitUntilDone:YES];
    }];
}


-(IBAction)ps:(id)sender
{
    self.textview.text = @"loading...";
    [_adb shell:@"pm list packages" didResponse:^(BOOL succ, NSString *result) {
        
        [self.textview performSelectorOnMainThread:@selector(setText:) withObject:result waitUntilDone:YES];
    }];
}




@end
