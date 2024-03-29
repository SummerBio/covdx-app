/********* CMBScanner.m Cordova Plugin Implementation *******/

#import <Cordova/CDV.h>
#import <cmbSDK/cmbSDK.h>

#pragma INTERFACE
@interface CMBScanner : CDVPlugin {
    
}

// CMBReaderDeviceDelegate Cordova callbacks
-(void)didReceiveReadResultFromReaderCallback:(CDVInvokedUrlCommand*)cdvCommand;
-(void)availabilityDidChangeOfReaderCallback:(CDVInvokedUrlCommand*)cdvCommand;
-(void)connectionStateDidChangeOfReaderCallback:(CDVInvokedUrlCommand*)cdvCommand;


// public methods
-(void)loadScanner:(CDVInvokedUrlCommand*)cdvCommand;
-(void)getAvailability:(CDVInvokedUrlCommand*)cdvCommand;
-(void)getSdkVersion:(CDVInvokedUrlCommand*)cdvCommand;
-(void)enableImage:(CDVInvokedUrlCommand*)cdvCommand;
-(void)enableImageGraphics:(CDVInvokedUrlCommand*)cdvCommand;
-(void)getConnectionState:(CDVInvokedUrlCommand*)cdvCommand;
-(void)connect:(CDVInvokedUrlCommand*)cdvCommand;
-(void)startScanning:(CDVInvokedUrlCommand*)cdvCommand;
-(void)stopScanning:(CDVInvokedUrlCommand*)cdvCommand;
-(void)getDeviceBatteryLevel:(CDVInvokedUrlCommand*)cdvCommand;
-(void)setSymbologyEnabled:(CDVInvokedUrlCommand*)cdvCommand;
-(void)isSymbologyEnabled:(CDVInvokedUrlCommand*)cdvCommand;
-(void)setLightsOn:(CDVInvokedUrlCommand*)cdvCommand;
-(void)isLightsOn:(CDVInvokedUrlCommand*)cdvCommand;
-(void)resetConfig:(CDVInvokedUrlCommand*)cdvCommand;
-(void)sendCommand:(CDVInvokedUrlCommand*)cdvCommand;
-(void)setPreviewContainerPositionAndSize:(CDVInvokedUrlCommand*)cdvCommand;
-(void)setPreviewContainerBelowStatusBar:(CDVInvokedUrlCommand*)cdvCommand;
-(void)setPreviewContainerFullScreen:(CDVInvokedUrlCommand*)cdvCommand;
-(void)setCameraMode:(CDVInvokedUrlCommand*)cdvCommand;
-(void)setPreviewOptions:(CDVInvokedUrlCommand*)cdvCommand;
-(void)disconnect:(CDVInvokedUrlCommand*)cdvCommand;
-(void)beep:(CDVInvokedUrlCommand*)cdvCommand;
-(void)registerSDK:(CDVInvokedUrlCommand*)cdvCommand;
-(void)enableCameraFlag:(CDVInvokedUrlCommand*)cdvCommand;
-(void)disableCameraFlag:(CDVInvokedUrlCommand*)cdvCommand;
-(void)setCameraDuplicatesTimeout:(CDVInvokedUrlCommand*)cdvCommand;
-(void)setPreviewOverlayMode:(CDVInvokedUrlCommand*)cdvCommand;
-(void)showToast:(CDVInvokedUrlCommand*)cdvCommand;
-(void)hideToast:(CDVInvokedUrlCommand*)cdvCommand;
-(void)checkCameraPermission:(CDVInvokedUrlCommand*)cdvCommand;
-(void)requestCameraPermission:(CDVInvokedUrlCommand*)cdvCommand;
-(void)setParser:(CDVInvokedUrlCommand*)cdvCommand;
-(void)setStopScannerOnRotate:(CDVInvokedUrlCommand*)cdvCommand;
@end

// CMBReaderDevice delegate
@interface CMBScanner() <CMBReaderDeviceDelegate>
@end
#pragma END INTERFACE


#pragma IMPLEMENTATION
@implementation CMBScanner

// CMBReaderDeviceDelegate Cordova callbacks
NSString *didReceiveReadResultFromReaderCallbackID;
NSString *availabilityDidChangeOfReaderCallbackID;
NSString *connectionStateDidChangeOfReaderCallbackID;
CDVInvokedUrlCommand *scanningStateChangedCallback;

CDMCameraMode param_cameraMode = 0;
CDMPreviewOption param_previewOptions = 0;
float param_positionX = 0;
float param_positionY = 0;
float param_sizeWidth = 100;
float param_sizeHeight = 50;
int param_triggerType = 2;
int param_deviceType = 0;
BOOL param_closeScannerOnRotate = NO;

CMBReaderDevice *readerDevice;
NSString *regKey = nil;

UITextView *cmbToastView;

-(void)loadScanner:(CDVInvokedUrlCommand*)cdvCommand {
    param_deviceType = [cdvCommand.arguments.firstObject intValue];
    
    if (readerDevice && readerDevice.connectionState == CMBConnectionStateConnected) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (connectionStateDidChangeOfReaderCallbackID) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:CMBConnectionStateDisconnected];
                [result setKeepCallbackAsBool:YES];
                [self.commandDelegate sendPluginResult:result callbackId:connectionStateDidChangeOfReaderCallbackID];
            }
            [readerDevice disconnect];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self loadScanner:cdvCommand];
            });
        });
        return;
    }
    
    if (param_deviceType == 1){
        currentAppOrientation = [[UIApplication sharedApplication]statusBarOrientation];
        [self performSelectorOnMainThread:@selector(setPreviewContainerPositionAndSize:) withObject:nil waitUntilDone:YES];
        [self performSelectorOnMainThread:@selector(addScannerView) withObject:nil waitUntilDone:YES];
    }else
        [self performSelectorOnMainThread:@selector(removeScannerView) withObject:nil waitUntilDone:NO];
    
    switch (param_deviceType) {
        default:
        case 0:
            readerDevice = [CMBReaderDevice readerOfMXDevice];
            break;
            
        case 1:
        readerDevice = [CMBReaderDevice readerOfDeviceCameraWithCameraMode:param_cameraMode previewOptions:param_previewOptions previewView:scannerView registrationKey:regKey];
            [self performSelectorOnMainThread:@selector(setScannerViewHidden:) withObject:[NSNumber numberWithBool:YES] waitUntilDone:NO];
            break;
    }
    
    readerDevice.delegate = self;
    
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
    
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (param_deviceType == 0) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(disconnectReaderDevice)
                                                     name:UIApplicationWillResignActiveNotification object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appBecameActive)
                                                     name:UIApplicationDidBecomeActiveNotification object:nil];
    }else{
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidRotate:)
                                                     name:@"UIDeviceOrientationDidChangeNotification" object:nil];
    }
}

-(void) appBecameActive {
    if (readerDevice != nil
        && readerDevice.availability == CMBReaderAvailibilityAvailable
        && readerDevice.connectionState != CMBConnectionStateConnecting && readerDevice.connectionState != CMBConnectionStateConnected)
    {
        [readerDevice connectWithCompletion:^(NSError *error) {
            if (error) {
                [self disconnectReaderDevice];
            }
        }];
    }
}

-(void)getAvailability:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:cdvCommand]) {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:readerDevice.availability];
        [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
    }
}
-(void)enableImage:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:cdvCommand]) {
        [readerDevice setImageResultEnabled:[cdvCommand.arguments.firstObject boolValue]];
    }
}
-(void)enableImageGraphics:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:cdvCommand]) {
        [readerDevice setSVGResultEnabled:[cdvCommand.arguments.firstObject boolValue]];
    }
}

-(void)getConnectionState:(CDVInvokedUrlCommand*)cdvCommand{
    CMBConnectionState state = (readerDevice != nil) ? readerDevice.connectionState : -1;
    
    CDVPluginResult *result = ((int)state != -1)?[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:state] : [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:NO];
    [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
}

-(void)connect:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:cdvCommand]) {
        [readerDevice connectWithCompletion:^(NSError *error) {
            if (error == nil) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }else{
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }
        }];
    }
}

-(void)startScanning:(CDVInvokedUrlCommand*)cdvCommand{
    //    scanningStateChangedCallback = cdvCommand;
    //if there is a reader toggle the scanner and it's connected,
    // but if there isn't a reader we need to return a special callback which will contain false as a message
    if (readerDevice != nil && readerDevice.connectionState == kCDMConnectionStateConnected) {
        [self performSelectorOnMainThread:@selector(setScannerViewHidden:) withObject:[NSNumber numberWithBool:NO] waitUntilDone:YES];
        [self toggleScannerWithBool:YES];
    }else{
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsBool:NO];
        [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
    }
}

//stop scanning callback will always return false, which is the state of the "SCANNER"
//on the javascript side of things we use the same callback function for both startScanning and stopScanning
//and a true value would mean the scanner is active, a false value would mean it's not
-(void)stopScanning:(CDVInvokedUrlCommand*)cdvCommand{
    //    scanningStateChangedCallback = cdvCommand;
    if ([self isReaderInit:cdvCommand]) {
        [self performSelectorOnMainThread:@selector(setScannerViewHidden:) withObject:[NSNumber numberWithBool:YES] waitUntilDone:YES];
        [self toggleScannerWithBool:NO];
    }
}

-(void)getDeviceBatteryLevel:(CDVInvokedUrlCommand*)cdvCommand {
    if ([self isReaderInit:cdvCommand]) {
        [readerDevice getDeviceBatteryLevelWithCompletion:^(int batteryLevel, NSError *error) {
            if (error == nil) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:batteryLevel];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }else{
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }
        }];
    }
}

-(void)setSymbologyEnabled:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:cdvCommand]) {
        [readerDevice setSymbology:[[cdvCommand.arguments firstObject] intValue]/*[self getSymbologyFromJSEnum:(int)cdvCommand.arguments.firstObject]*/ enabled:[cdvCommand.arguments[1] boolValue]  completion:^(NSError *error) {
            if (error == nil) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:[cdvCommand.arguments[1] boolValue]];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }else{
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }
        }];
    }
}

-(void)isSymbologyEnabled:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:cdvCommand]) {
        [readerDevice isSymbologyEnabled:[[cdvCommand.arguments firstObject] intValue]/*[self getSymbologyFromJSEnum:(int)cdvCommand.arguments.firstObject]*/ completion:^(BOOL enabled, NSError *error) {
            if (error == nil) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:enabled];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }else{
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }
        }];
    }
}

-(void)setLightsOn:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:cdvCommand]) {
        [readerDevice setLightsON:[cdvCommand.arguments.firstObject boolValue] completion:^(NSError *error) {
            if (error == nil) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:[cdvCommand.arguments.firstObject boolValue]];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }else{
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }
        }];
    }
}

-(void)isLightsOn:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:cdvCommand]) {
        [readerDevice getLightsStateWithCompletion:^(BOOL enabled, NSError *error) {
            if (error == nil) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:enabled];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }else{
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }
        }];
    }
}

-(void)resetConfig:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:cdvCommand]) {
        [readerDevice resetConfigWithCompletion:^(NSError *error) {
            if (error == nil) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }else{
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }
        }];
    }
}

-(void)sendCommand:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:cdvCommand]) {
        [readerDevice.dataManSystem sendCommand:cdvCommand.arguments.firstObject withCallback:^(CDMResponse *response) {
            if (response.status == DMCC_STATUS_NO_ERROR) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:response.payload];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }else{
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:response.payload];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }
        }];
    }
}

-(BOOL) isReaderInit:(CDVInvokedUrlCommand*)cdvCommand {
    if (readerDevice != nil) {
        return YES;
    }else{
        if (cdvCommand) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Reader device not initialized"];
            [result setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
        }
        return NO;
    }
}

-(void)registerSDK:(CDVInvokedUrlCommand*)cdvCommand{
    @try {
        regKey = cdvCommand.arguments.firstObject;
    } @catch (NSException *exception) {
    } @finally {
    }
}

-(void)didReceiveReadResultFromReaderCallback:(CDVInvokedUrlCommand*)cdvCommand{
    didReceiveReadResultFromReaderCallbackID = cdvCommand.callbackId;
}

-(void)setActiveStartScanningCallback:(CDVInvokedUrlCommand*)cdvCommand{
    scanningStateChangedCallback = cdvCommand;
}

-(void)availabilityDidChangeOfReaderCallback:(CDVInvokedUrlCommand*)cdvCommand{
    availabilityDidChangeOfReaderCallbackID = cdvCommand.callbackId;
}

-(void)connectionStateDidChangeOfReaderCallback:(CDVInvokedUrlCommand*)cdvCommand{
    connectionStateDidChangeOfReaderCallbackID = cdvCommand.callbackId;
}

-(void)enableCameraFlag:(CDVInvokedUrlCommand*)cdvCommand {
    int mask = 0;
    int flag = 0;
    @try {
        mask = [cdvCommand.arguments.firstObject intValue];
        flag = [cdvCommand.arguments[1] intValue];
    } @catch (NSException *exception) {
    } @finally {
    }
    
    CDVPluginResult *result;
    switch (MWB_enableFlag(mask, flag)) {
        case MWB_RT_OK:
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            break;
        case MWB_RT_BAD_PARAM:
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Flag value out of range"];
            break;
        case MWB_RT_NOT_SUPPORTED:
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Flag value not supported for selected decoder"];
            break;
        default:
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Unknown"];
            break;
    };
    
    [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
}

-(void)disableCameraFlag:(CDVInvokedUrlCommand*)cdvCommand {
    int mask = 0;
    int flag = 0;
    @try {
        mask = [cdvCommand.arguments.firstObject intValue];
        flag = [cdvCommand.arguments[1] intValue];
    } @catch (NSException *exception) {
    } @finally {
    }
    
    CDVPluginResult *result;
    switch (MWB_disableFlag(mask, flag)) {
        case MWB_RT_OK:
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            break;
        case MWB_RT_BAD_PARAM:
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Flag value out of range"];
            break;
        case MWB_RT_NOT_SUPPORTED:
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Flag value not supported for selected decoder"];
            break;
        default:
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Unknown"];
            break;
    };
    
    [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
}

-(void)setCameraDuplicatesTimeout:(CDVInvokedUrlCommand*)cdvCommand {
    @try {
        MWB_setDuplicatesTimeout([cdvCommand.arguments.firstObject intValue]);
    } @catch (NSException *exception) {
    } @finally {
    }
}

-(void)setPreviewOverlayMode:(CDVInvokedUrlCommand*)cdvCommand {
    int overlayMode = OM_CMB;
    @try {
        overlayMode = [cdvCommand.arguments.firstObject intValue];
    } @catch (NSException *exception) {
    }
    
    if (overlayMode == OM_CMB || overlayMode == OM_LEGACY){
        [MWOverlay setOverlayMode:overlayMode];
    }
}

-(void)showToast:(CDVInvokedUrlCommand*)cdvCommand{
    if (!cmbToastView) {
        cmbToastView = UITextView.new;
    }
    
    [cmbToastView setFrame:CGRectMake(0, 0, (scannerView && issScanning) ? scannerView.frame.size.width : self.viewController.view.frame.size.width, 100)];
    [cmbToastView setAlpha:0];
    
    if (cmbToastView && cmbToastView.superview)
        [cmbToastView removeFromSuperview];
    
    if (scannerView && issScanning) {
        [scannerView addSubview:cmbToastView];
    } else {
        [self.viewController.view addSubview:cmbToastView];
    }
    
    [self updateToastPadding];
    
    [cmbToastView setFont:[UIFont systemFontOfSize:14]];
    [cmbToastView setTextColor:UIColor.whiteColor];
    [cmbToastView setBackgroundColor:[UIColor colorWithRed:0 green:0 blue:0 alpha:0.5]];
    [cmbToastView setTextAlignment:NSTextAlignmentCenter];
    
    [cmbToastView.superview bringSubviewToFront:cmbToastView];
    
    @try {
        [cmbToastView setText:cdvCommand.arguments.firstObject];
        
        [cmbToastView sizeToFit];
        [cmbToastView setFrame:CGRectMake(0, 0, (scannerView && issScanning) ? scannerView.frame.size.width : self.viewController.view.frame.size.width, cmbToastView.frame.size.height)];
        [cmbToastView setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin)];

        [UIView animateWithDuration:0.2 animations:^{
            [cmbToastView setAlpha:1];
        }];
    } @catch (NSException *exception) {
        [self hideToast:nil];
    }
}

-(void)hideToast:(CDVInvokedUrlCommand*)cdvCommand{
    if (cmbToastView && cmbToastView.superview) {
        [UIView animateWithDuration:0.2 animations:^{
            [cmbToastView setAlpha:0];
        } completion:^(BOOL finished) {
            [cmbToastView removeFromSuperview];
        }];
    }
}

- (void)updateToastPadding {
    if (cmbToastView && cmbToastView.superview) {
        // top padding correction for notch
        int topPadding = UIApplication.sharedApplication.statusBarFrame.size.height;
        
        if (cmbToastView.superview == scannerView) {
            topPadding = topPadding - param_positionY;
            if (topPadding < 0) {
                topPadding = 0;
            }
        }
        
        cmbToastView.textContainerInset = UIEdgeInsetsMake(8 + topPadding, 8, 8, 8);
    }
}

-(void)checkCameraPermission:(CDVInvokedUrlCommand*)cdvCommand {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    CDVPluginResult *result;
    switch (status) {
        case AVAuthorizationStatusDenied:
        case AVAuthorizationStatusRestricted:
            // no access, user can't request
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsInt:0];
            break;
        case AVAuthorizationStatusNotDetermined:
            // no access, user can request
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsInt:1];
            break;
        case AVAuthorizationStatusAuthorized:
            // access granted
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            break;
    };
    
    [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
}

-(void)requestCameraPermission:(CDVInvokedUrlCommand*)cdvCommand {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    switch (status) {
        case AVAuthorizationStatusDenied:
        case AVAuthorizationStatusRestricted:
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsInt:0] callbackId:cdvCommand.callbackId];
            break;
        case AVAuthorizationStatusNotDetermined: {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (granted) {
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:cdvCommand.callbackId];
                } else {
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsInt:0] callbackId:cdvCommand.callbackId];
                }
            }];
            
            break;
        }
        case AVAuthorizationStatusAuthorized:
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:cdvCommand.callbackId];
            break;
    };
}

// CMBSDK DELEGATES
- (void)connectionStateDidChangeOfReader:(CMBReaderDevice *)reader{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (connectionStateDidChangeOfReaderCallbackID) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:reader?reader.connectionState:0];
            [result setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:result callbackId:connectionStateDidChangeOfReaderCallbackID];
        }
    });
}

- (void)availabilityDidChangeOfReader:(CMBReaderDevice *)reader
{
    if (availabilityDidChangeOfReaderCallbackID) {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:reader.availability];
        [result setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:result callbackId:availabilityDidChangeOfReaderCallbackID];
    }
}

- (void)didReceiveReadResultFromReader:(CMBReaderDevice *)reader results:(CMBReadResults *)readResults
{
    if (didReceiveReadResultFromReaderCallbackID != nil) {
        NSMutableDictionary *resultDict = [NSMutableDictionary new];
        [resultDict setObject:readResults.XML forKey:@"xml"];
        
        NSMutableArray *results = [NSMutableArray new];
        NSMutableArray *subResults = [NSMutableArray new];
        
        if (readResults.readResults && readResults.readResults.count > 0) {
            [results addObject:[self getDictionaryFromResult:readResults.readResults.firstObject]];
        }
        
        if (readResults.subReadResults && readResults.subReadResults.count > 0) {
            for (CMBReadResult *subResult in readResults.subReadResults) {
                NSDictionary *result = [self getDictionaryFromResult:subResult];
                [results addObject:result];
                [subResults addObject:result];
            }
        }
        
        [resultDict setObject:results forKey:@"readResults"];
        [resultDict setObject:subResults forKey:@"subReadResults"];
        
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:resultDict];
        [result setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:result callbackId:didReceiveReadResultFromReaderCallbackID];
    }
    
    if (param_triggerType == 2) {
        issScanning = NO;
        [self stopScanning:scanningStateChangedCallback];
    }
}

-(NSDictionary*) getDictionaryFromResult:(CMBReadResult*) readResult {
    NSMutableDictionary *resultDict = [NSMutableDictionary new];
    
    if (readResult.goodRead) {
         [resultDict setObject:[NSString.alloc initWithData:[readResult.readString dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES] encoding:NSUTF8StringEncoding] forKey:@"readString"];
        [resultDict setObject:@(readResult.symbology) forKey:@"symbology"];
        [resultDict setObject:[self stringFromSymbology:readResult.symbology] forKey:@"symbologyString"];
    }else{
        [resultDict setObject:@"" forKey:@"readString"];
        [resultDict setObject:@(-1) forKey:@"symbology"];
        [resultDict setObject:@"NO READ" forKey:@"symbologyString"];
    }
    
    [resultDict setObject:@(readResult.goodRead) forKey:@"goodRead"];
    
    if (readResult.parsedText)
        [resultDict setObject:readResult.parsedText forKey:@"parsedText"];
    
    if (readResult.parsedJSON)
        [resultDict setObject:readResult.parsedJSON forKey:@"parsedJSON"];

    [resultDict setObject:@(readResult.isGS1) forKey:@"isGS1"];
    
    if (readResult.image) {
        NSData *imageData = UIImagePNGRepresentation(readResult.image);
        NSString *base64image = [imageData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
        [resultDict setObject:base64image forKey:@"image"];
    }
    
    if (readResult.XML) {
        NSString* xmlStr = [[NSString alloc] initWithData:readResult.XML encoding:NSUTF8StringEncoding];
        [resultDict setObject:xmlStr forKey:@"xml"];
    }
    
    if (readResult.imageGraphics) {
        NSString* imageGraphicsStr = [[NSString alloc] initWithData:readResult.imageGraphics encoding:NSUTF8StringEncoding];
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<image .*\"snapshot\\.img\"\\/>" options:NSRegularExpressionCaseInsensitive error:&error];
        imageGraphicsStr = [regex stringByReplacingMatchesInString:imageGraphicsStr options:0 range:NSMakeRange(0, [imageGraphicsStr length]) withTemplate:@""];

        [resultDict setObject:imageGraphicsStr forKey:@"imageGraphics"];
    }
    
    return resultDict;
}

float position_xp = 0;
float position_yp = 0;
float position_wp = 100;
float position_hp = 50;

UIView *scannerView;
-(void)setPreviewContainerPositionAndSize:(CDVInvokedUrlCommand*)cdvCommand{
    if (cdvCommand && cdvCommand.arguments && cdvCommand.arguments.count == 4) {
        position_xp = [cdvCommand.arguments[0] floatValue];
        position_yp = [cdvCommand.arguments[1] floatValue];
        position_wp = [cdvCommand.arguments[2] floatValue];
        position_hp = [cdvCommand.arguments[3] floatValue];
    }
    [self updatePreviewContainerValues];
}

-(void)updatePreviewContainerValues {
    if ([self isReaderInit:nil]) {
        [readerDevice setCameraPreviewContainer:scannerView completion:^(NSError *error) {}];
    }
    
    CGSize screenSize = [[UIScreen mainScreen] bounds].size;
    
    param_positionX =  position_xp /100 * screenSize.width;
    param_positionY =  (position_yp /100 * screenSize.height) + (showCMBScannerPreviewBelowStatusBar ? UIApplication.sharedApplication.statusBarFrame.size.height : 0);
    
    param_sizeWidth = position_wp /100 * screenSize.width;
    param_sizeHeight = (position_hp /100 * screenSize.height) - (showCMBScannerPreviewBelowStatusBar ? UIApplication.sharedApplication.statusBarFrame.size.height : 0);
}

BOOL showCMBScannerPreviewBelowStatusBar = NO;
-(void)setPreviewContainerBelowStatusBar:(CDVInvokedUrlCommand*)cdvCommand {
    if (cdvCommand.arguments.firstObject) {
        showCMBScannerPreviewBelowStatusBar = [cdvCommand.arguments.firstObject boolValue];
    }
}

-(void)setPreviewContainerFullScreen:(CDVInvokedUrlCommand*)cdvCommand {
    if ([self isReaderInit:nil]) {
        [readerDevice setCameraPreviewContainer:nil completion:^(NSError *error) { }];
    }
}

-(void) addScannerView {
    if (!scannerView) {
        scannerView = [UIView new];
        [scannerView setTag:7639];
        [scannerView setClipsToBounds:YES];
    }
    [self updateScannerViewPosition];
    
    if (![UIApplication.sharedApplication.keyWindow.rootViewController.view viewWithTag:7639]) {
        [UIApplication.sharedApplication.keyWindow.rootViewController.view addSubview:scannerView];
    }
}

-(void)updateScannerViewPosition {
    if (scannerView) {
        [scannerView setFrame:CGRectMake(param_positionX, param_positionY, param_sizeWidth, param_sizeHeight)];
        
        [self updateToastPadding];
    }
}

-(void) removeScannerView {
    if (!scannerView)
        return;
    
    if (scannerView.superview) {
        [scannerView removeFromSuperview];
    }
    scannerView = nil;
}

-(void) setScannerViewHidden:(NSNumber*) hidden {
    if (scannerView) {
        [scannerView setHidden:hidden.boolValue];
        [scannerView.superview bringSubviewToFront:scannerView];
    }
}

-(void)setCameraMode:(CDVInvokedUrlCommand*)cdvCommand{
    @try {
        param_cameraMode = [[cdvCommand.arguments firstObject] intValue];
    } @catch (NSException *exception) {
        param_cameraMode = 0;
    } @finally {
    }
}

-(void)setPreviewOptions:(CDVInvokedUrlCommand*)cdvCommand{
    @try {
        param_previewOptions = [[cdvCommand.arguments firstObject] intValue];
    } @catch (NSException *exception) {
        param_previewOptions = 0;
    } @finally {
    }
}

-(void)disconnect:(CDVInvokedUrlCommand*)cdvCommand{
    //    connectionStateDidChangeOfReaderCallbackID = cdvCommand.callbackId;
    if ([self isReaderInit:cdvCommand]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [readerDevice disconnect];
            if (cdvCommand) {
                CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
                [result setKeepCallbackAsBool:YES];
                [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
            }
        });
    }
}

-(void)beep:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:cdvCommand]) {
        [readerDevice beep];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
        [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
    }
}
    
-(void)setParser:(CDVInvokedUrlCommand*)cdvCommand{
    if ([self isReaderInit:nil]) {
        NSNumber *arg = cdvCommand.arguments.firstObject;
        if (arg && arg.intValue >= CMBResultParserNone && arg.intValue <= CMBResultParserSCM)
            [readerDevice setParser:arg.intValue];
    }
}
    
-(void)getSdkVersion:(CDVInvokedUrlCommand*)cdvCommand {
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:CDMDataManSystem.getVersion];
    [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
}

-(void)setStopScannerOnRotate:(CDVInvokedUrlCommand*)cdvCommand{
    param_closeScannerOnRotate = cdvCommand.arguments.firstObject;
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:cdvCommand.callbackId];
}

// READER CONNECTION AND APIS
BOOL issScanning = NO;
-(void) toggleScannerWithBool:(BOOL) scan {
    
    if (!scan) {
        if (issScanning) {
            [self stopScan];
        }
    }else{
        [self startScan];
    }
    issScanning = scan;
    
    if (scanningStateChangedCallback) {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:issScanning];
        [result setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:result callbackId:scanningStateChangedCallback.callbackId];
    }
}

-(void) startScan {
    [readerDevice.dataManSystem sendCommand:@"GET TRIGGER.TYPE" withCallback:^(CDMResponse *response) {
        if (response.status == DMCC_STATUS_NO_ERROR) {
            param_triggerType = [response.payload intValue];
        }
    }];
    [readerDevice startScanning];
}

-(void) stopScan {
    [readerDevice stopScanning];
}

-(void) disconnectReaderDevice {
    if (readerDevice != nil && readerDevice.connectionState != CMBConnectionStateDisconnected && readerDevice.connectionState != kCDMConnectionStateDisconnecting) {
        [readerDevice disconnect];
    }
}

UIInterfaceOrientation currentAppOrientation;
-(void) appDidRotate:(NSNotification *)notification {
    if (currentAppOrientation != [[UIApplication sharedApplication]statusBarOrientation]) {
        currentAppOrientation = [[UIApplication sharedApplication]statusBarOrientation];
        if (issScanning && param_closeScannerOnRotate) {
            [self toggleScannerWithBool:NO];
        }

        [self performSelectorOnMainThread:@selector(updatePreviewContainerValues) withObject:nil waitUntilDone:YES];
        [self performSelectorOnMainThread:@selector(updateScannerViewPosition) withObject:nil waitUntilDone:YES];
        [self performSelectorOnMainThread:@selector(updateToastPadding) withObject:nil waitUntilDone:YES];
    }
}

-(NSString*) stringFromSymbology:(CMBSymbology) symbology {
    switch (symbology) {
        case CMBSymbologyDataMatrix : return @"Data Matrix";
        case CMBSymbologyQR : return @"QR";
        case CMBSymbologyC128 : return @"Code 128";
        case CMBSymbologyUpcEan : return @"UPC/EAN";
        case CMBSymbologyC11 : return @"Code 11";
        case CMBSymbologyC39 : return @"Code 39";
        case CMBSymbologyC93 : return @"Code 93";
        case CMBSymbologyI2o5 : return @"Interleaved 2 of 5";
        case CMBSymbologyCodaBar : return @"Codabar";
        case CMBSymbologyEanUcc : return @"EAN-UCC";
        case CMBSymbologyPharmaCode : return @"Pharmacode";
        case CMBSymbologyMaxicode : return @"MaxiCode";
        case CMBSymbologyPdf417 : return @"PDF417";
        case CMBSymbologyMicropdf417 : return @"Micro PDF417";
        case CMBSymbologyDatabar : return @"Databar";
        case CMBSymbologyPlanet : return @"PLANET";
        case CMBSymbologyPostnet : return @"POSTNET";
        case CMBSymbologyFourStateJap : return @"Japan Post";
        case CMBSymbologyFourStateAus : return @"Australia Post";
        case CMBSymbologyFourStateUpu : return @"UPU";
        case CMBSymbologyFourStateImb : return @"IMB";
        case CMBSymbologyVericode : return @"VERICODE";
        case CMBSymbologyRpc : return @"RPC";
        case CMBSymbologyMsi : return @"MSI";
        case CMBSymbologyAzteccode : return @"AztecCode";
        case CMBSymbologyDotcode : return @"DotCode";
        case CMBSymbologyC25 : return @"C25";
        case CMBSymbologyC39ConvertToC32 : return @"C39 to C32";
        case CMBSymbologyOcr : return @"OCR";
        case CMBSymbologyFourStateRmc : return @"RMC";
        case CMBSymbologyTelepen : return @"Telepen";
            
        default:
        case CMBSymbologyUnknown : return @"Unknown";
            break;
    }
}

@end
