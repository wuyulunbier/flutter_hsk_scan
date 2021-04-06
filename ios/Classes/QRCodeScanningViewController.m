//
//  QRCodeScanningViewController.m
//  flutter_dong_scan
//
//  Created by hsk on 2021/4/6.
//
#import "QRCodeScanningViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import "SDScanMaskView.h"
#import "UIView+Extension.h"
#import "UIColor+HexStringColor.h"


@interface QRCodeScanningViewController ()<AVCaptureMetadataOutputObjectsDelegate,AVCaptureVideoDataOutputSampleBufferDelegate,UIGestureRecognizerDelegate>{
    BOOL bHadAutoVideoZoom;
}

@property (weak, nonatomic) IBOutlet UIButton *torchBtn;//灯泡开关
@property (weak, nonatomic) IBOutlet UILabel *torchStatusLabel;//灯泡底下的开关显示

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *scanBottomConstraint;
@property (weak, nonatomic) IBOutlet UIImageView *scanningBar;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *leftReturnBtnTopConstraint;

@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) AVCaptureDevice *device;
@property (nonatomic, strong) AVCaptureSession *session;
@property (strong, nonatomic) AVCaptureDeviceInput * input;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *layer;
@property (nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;//拍照
@property (nonatomic, strong) UIView *videoPreView; ///视频预览显示视图
@property (nonatomic, assign) CGPoint centerPoint;//二维码的中心点
@property (nonatomic, assign) BOOL isAutoOpen;//默认NO 闪光灯

@property(nonatomic,strong)SDScanMaskView *maskView;
@property(nonatomic,strong)UIImageView *topLeftImageView;

@property(nonatomic,strong)SDScanConfig *config;
@end

@implementation QRCodeScanningViewController

- (instancetype)initWithConfig:(SDScanConfig *)scanConfig {
    
    if (self = [super init]) {
        self.config = scanConfig;
    }
    return self;
}
-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
//    self.navigationController.navigationBar.hidden = YES;
}

- (void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
//    self.navigationController.navigationBar.hidden = NO;
    [self turnTorchOn:NO];
    [self stopScanning];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapAction:)];
    [self.view addGestureRecognizer:tap];
    
    self.view.backgroundColor = [UIColor whiteColor];
    [self  creatSubviews];
    [self scanCameraAuth];
    [self.view addSubview:self.maskView];
}

- (void)tapAction:(UITapGestureRecognizer *)ges{
    NSLog(@"--点击了扫码页面") ;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    
    UIResponder *next = [self nextResponder];
    while (next) {
        next = [next nextResponder];
    }
}
#pragma mark - UI

- (void)creatSubviews{
    //默认不显示闪光灯
    [self.maskView.torchBtn setSelected:NO];
//    self.torchBtn.hidden = self.torchStatusLabel.hidden =YES;
    //适配齐刘海
//    self.leftReturnBtnTopConstraint.constant = (6+STATUSH);
    
}
#pragma mark - 懒加载

- (SDScanMaskView *)maskView {
    
    if (_maskView == nil) {
        _maskView = [[SDScanMaskView alloc] initWithFrame:self.view.bounds config:self.config];
        __weak typeof(self) weakSelf = self;
        [_maskView.torchBtn addTarget:self action:@selector(lighting:) forControlEvents:UIControlEventTouchUpInside];
        _maskView.exitBlock = ^{
            [weakSelf dismissViewControllerAnimated:YES completion:nil];
        };
    }
    return _maskView;
}

- (void)scanCameraAuth{
    __weak typeof(self)  weakSelf = self;
    [self requestCameraPemissionWithResult:^(BOOL granted) {
        if (granted) {
            [weakSelf startScanning];
            [weakSelf networkStatusAlert];
        } else {
            [weakSelf showAlertToPromptCameraAuthorization];
        }
    }];

}

+ (UIImage *)getBundleImageName:(NSString *)imageName {
    
    NSBundle *bundle = [NSBundle bundleForClass:[SDScanMaskView class]];
    NSURL *url = [bundle URLForResource:@"SDScanResource" withExtension:@"bundle"];
    NSBundle *imageBundle = [NSBundle bundleWithURL:url];
    if (imageBundle == nil) {
        NSLog(@"获取包失败");
    }
    if ([UIImage imageWithContentsOfFile:[imageBundle pathForResource:imageName ofType:@"png"]] == nil) {
        NSLog(@"获取资源失败");
    }
    return [UIImage imageWithContentsOfFile:[imageBundle pathForResource:imageName ofType:@"png"]];
}
#pragma mark - btn

//- (IBAction)returnBack:(UIButton *)sender {
//    [self leftBarButtonItemReturnAction];
//}

- (void)lighting:(UIButton *)sender {
    sender.selected = !sender.selected;
    [self turnTorchOn:sender.selected];
}


#pragma mark - Helpers
- (void)startScanning {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.02 target:self selector:@selector(animateScanningBar) userInfo:nil repeats:YES];

    if (!self.layer) {
        AVCaptureSession *session = [[AVCaptureSession alloc] init];
        session.sessionPreset = AVCaptureSessionPresetHigh;

        /// Input.
        self.device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        self.input = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:nil];

        /// Output. Must work in a serial queue.
        dispatch_queue_t serialQueue = dispatch_queue_create("ScanningQueue", NULL);
        //扫描结果 自动放大
        AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
        [output setMetadataObjectsDelegate:self queue:serialQueue];
        //闪光灯
        AVCaptureVideoDataOutput *dataOutput = [[AVCaptureVideoDataOutput alloc] init];
        [dataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];

//        CGRect cropRect = CGRectMake((SCREEN_WIDTH-220)*0.5, SCREEN_HEIGHT*0.5-60, 220, 220);
//        if (!CGRectEqualToRect(cropRect,CGRectZero)){
//            output.rectOfInterest = cropRect;
//        }

        self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
        NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys:AVVideoCodecJPEG, AVVideoCodecKey,nil];
        [self.stillImageOutput setOutputSettings:outputSettings];

        if ([session canAddInput:self.input]) {
            [session addInput:self.input];
        }
        if ([session canAddOutput:output]) {
            [session addOutput:output];
        }
        if ([session canAddOutput:dataOutput]) {
            [session addOutput:dataOutput];
        }
        if ([session canAddOutput:self.stillImageOutput]){
            [session addOutput:self.stillImageOutput];
        }

        /* 扫条形码
        AVMetadataObjectTypeEAN13Code,
        AVMetadataObjectTypeEAN8Code,
        AVMetadataObjectTypeUPCECode,
        AVMetadataObjectTypeCode39Code,
        AVMetadataObjectTypeCode39Mod43Code,
        AVMetadataObjectTypeCode93Code,
        AVMetadataObjectTypeCode128Code,
        AVMetadataObjectTypePDF417Code
        */

        NSArray *types = @[AVMetadataObjectTypeQRCode];
        NSMutableArray *typesAvailable = [NSMutableArray array];
        for (NSString *type in types) {
            if ([output.availableMetadataObjectTypes containsObject:type]) [typesAvailable addObject:type];
        }
        output.metadataObjectTypes = typesAvailable;
//        self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
//        self.previewLayer.frame = self.view.bounds;
//        self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
//        self.previewLayer.backgroundColor = [UIColor yellowColor].CGColor;
//        [self.view.layer addSublayer:self.previewLayer];
        /// Preview layer.
        AVCaptureVideoPreviewLayer *layer = [AVCaptureVideoPreviewLayer layerWithSession:session];
        layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        layer.frame = self.view.bounds;

//        [self.view insertSubview:self.maskView atIndex:0];
//        [self.videoPreView.layer insertSublayer:layer atIndex:0];
        
        [self.view.layer addSublayer:layer];

        self.layer = layer;
        self.session = session;
    }

    [self.session startRunning];
    bHadAutoVideoZoom = NO;//还未自动拉近的值
    [self setVideoScale:1 ];//设置拉近倍数为1

}

- (void)stopScanning {
    if (self.session.isRunning) {
        [self.session stopRunning];
    }

    if (self.timer.isValid) {
        [self.timer invalidate];
        self.timer = nil;
    }
}

- (void)animateScanningBar {
    int constant = (int)self.scanBottomConstraint.constant;
    if (constant > 0) {
        constant --;
    }else {
        constant = 218;
    }
    self.scanBottomConstraint.constant = constant;
}

#pragma mark - get
- (UIView *)videoPreView{
    if (!_videoPreView) {
        UIView *videoView = [[UIView alloc]initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
        videoView.backgroundColor = [UIColor clearColor];
        _videoPreView = videoView;
    }
    return _videoPreView;
}

#pragma mark - Delegate Methods AVCaptureMetadataOutputObjectsDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
//    NetworkStatus internetStatus = [Helper internetStatus];
//    if (internetStatus == NotReachable) {
//        return;
//    }
    //识别扫码类型
    NSString *result;
    for(AVMetadataObject *current in metadataObjects){
        if ([current isKindOfClass:[AVMetadataMachineReadableCodeObject class]]){
            NSString *scannedResult = [(AVMetadataMachineReadableCodeObject *) current stringValue];
            if (scannedResult && ![scannedResult isEqualToString:@""]){
                result = scannedResult;
            }
        }
    }
    NSLog(@"扫描%@", result);
    if (result.length<1) {
        return;
    }
    
    

    if (!bHadAutoVideoZoom) {
        AVMetadataMachineReadableCodeObject *obj = (AVMetadataMachineReadableCodeObject *)[self.layer transformedMetadataObjectForMetadataObject:metadataObjects.lastObject];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self changeVideoScale:obj];
        });
        bHadAutoVideoZoom  =YES;
        return;
    }
    if ([result hasPrefix:@"https"]||[result hasPrefix:@"http"]) {
        [self stopScanning];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handlerJump:result];

        });
    }else{
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
//            [Helper addAlerViewOrAlertControllerWithTitle:@"提示" message: @"无效的二维码" buttonTitle:@"我知道了" forViewController:weakSelf];
        });
    }
}

//处理跳转
- (void)handlerJump:(NSString *)resultString{
    
        if (self.config.resultBlock != nil) {
            self.config.resultBlock(resultString);
        }
        [self dismissViewControllerAnimated:YES completion:nil];
    
//     NSDictionary *dic = [NSDictionary dictionaryWithDictionary:[Helper getDictionaryFormURL:resultString]];
//    if(![resultString containsString:@"nqyong.com"]){
//        __weak typeof(self) weakSelf = self;
//        NSString *msg = [NSString stringWithFormat:@"可能存在安全风险，是否打开此链接？\n%@",resultString];
//        [self addTwoAlertControllerAction:@"提示" message:msg leftTitle:@"打开链接" rightTitle:@"取消" leftAction:^(UIAlertAction * _Nonnull action) {
//            [weakSelf passScanningGoNextBaseWebviewTitle:@"" updateTitle:YES url:resultString contactKefu:NO];
//        } rightAction:^(UIAlertAction * _Nonnull action) {
////            [weakSelf leftBarButtonItemReturnAction];
//        }];
//    }else if ([resultString containsString:@"www.nqyong.com/downloadsApp.html"]){
//         NSString *jumpString = [NSString stringWithFormat:@"https://store-h5.nqyong.com/channelShop?appid=%@",dic[@"appid"]];
//        [self passScanningGoNextBaseWebviewTitle:@"商品列表" updateTitle:YES url:jumpString contactKefu:NO];
//     }else if ([resultString containsString:@"h5.nqyong.com/goodsDetail?"]) {
//        GoodsDetailViewController *GoodsDetailVC = (GoodsDetailViewController *)[UIStoryboard vcFrom:Goods identifier:[NSString stringWithFormat:@"%@",GoodsDetailViewController.class]];
//        GoodsDetailVC.hidesBottomBarWhenPushed = YES;
//        GoodsDetailVC.goodsID = dic[@"id"];
//        GoodsDetailVC.goodsName = @"";
//        [DataKeeper sharedKeeper].appId = dic[@"appid"];
//        [self passScanningGoNextVC:GoodsDetailVC];
//     }else{
//        [self passScanningGoNextBaseWebviewTitle:@"" updateTitle:YES url:resultString contactKefu:NO];
//     }
}

//跳转到webview之前，去掉扫码页
- (void)passScanningGoNextBaseWebviewTitle:(NSString *)title updateTitle:(BOOL)updateTitle url:(NSString *)url contactKefu:(BOOL)contactKefu{
//    if (url.length == 0) return;
//    RootWebViewController *root = [[RootWebViewController alloc]init];
//    root.hidesBottomBarWhenPushed = YES;
//    root.aTitle = title;
//    root.contactKefu = contactKefu;
//    root.updateTitle = updateTitle;
//    root.request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
//    [self passScanningGoNextVC:root];
}
//设置navabar的代理路由
- (void)passScanningGoNextVC:(UIViewController *)vc{
    NSMutableArray *vcArray = [NSMutableArray arrayWithArray:self.navigationController.viewControllers];
    int index = (int)[vcArray indexOfObject:self];
    if (vcArray.count<2) {
        return;
    }
    [vcArray removeObjectAtIndex:index];
    [vcArray addObject: vc];
    [self.navigationController setViewControllers:vcArray animated:NO];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    CFDictionaryRef metadataDict = CMCopyDictionaryOfAttachments(NULL,sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    NSDictionary *metadata = [[NSMutableDictionary alloc] initWithDictionary:(__bridge NSDictionary*)metadataDict];
    CFRelease(metadataDict);
    NSDictionary *exifMetadata = [[metadata objectForKey:(NSString *)kCGImagePropertyExifDictionary] mutableCopy];
    float brightnessValue = [[exifMetadata objectForKey:(NSString *)kCGImagePropertyExifBrightnessValue] floatValue];
    // brightnessValue 值代表光线强度，值越小代表光线越暗
//    NSLog(@"光线%f", brightnessValue);
    if (brightnessValue <= -2 &&!self.isAutoOpen) {
        self.isAutoOpen = YES;
        [self turnTorchOn:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.torchBtn setSelected:YES];
            self.torchBtn.hidden = self.torchStatusLabel.hidden= NO;
        });
    }
}

#pragma mark -  打开/关闭手电筒
- (void)turnTorchOn:(BOOL)on{
    if ([self.device hasTorch] && [self.device hasFlash]){

        dispatch_async(dispatch_get_main_queue(), ^{
            self.torchStatusLabel.text = on?@"点击关闭":@"点击开启";
        });

        [self.device lockForConfiguration:nil];
        if (on) {
            [self.device setTorchMode:AVCaptureTorchModeOn];
            [self.device setFlashMode:AVCaptureFlashModeOn];
        } else {
            [self.device setTorchMode:AVCaptureTorchModeOff];
            [self.device setFlashMode:AVCaptureFlashModeOff];
        }
        [self.device unlockForConfiguration];
    } else {
//        [Helper addAlerViewOrAlertControllerWithTitle:@"提示" message:@"当前设备没有闪光灯，不能提供手电筒功能"  buttonTitle:@"我知道了" forViewController:self];
    }
}

#pragma mark - 二维码自动拉近

- (void)changeVideoScale:(AVMetadataMachineReadableCodeObject *)objc
{
    NSArray *array = objc.corners;
    NSLog(@"cornersArray = %@",array);
    CGPoint point = CGPointZero;
    // 把字典转换为点，存在point里，成功返回true 其他false
    CGPointMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)array[0], &point);

    NSLog(@"X:%f -- Y:%f",point.x,point.y);
    CGPoint point2 = CGPointZero;
    CGPointMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)array[2], &point2);
    NSLog(@"X:%f -- Y:%f",point2.x,point2.y);

    self.centerPoint = CGPointMake((point.x + point2.x) / 2, (point.y + point2.y) / 2);
    CGFloat scace = 150 / (point2.x - point.x); //当二维码图片宽小于150，进行放大
    [self setVideoScale:scace];
    return;
}

- (void)setVideoScale:(CGFloat)scale
{
    [self.input.device lockForConfiguration:nil];

    AVCaptureConnection *videoConnection = [self connectionWithMediaType:AVMediaTypeVideo fromConnections:[[self stillImageOutput] connections]];
    CGFloat maxScaleAndCropFactor = ([[self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo] videoMaxScaleAndCropFactor])/16;

    if (scale > maxScaleAndCropFactor){
        scale = maxScaleAndCropFactor;
    }else if (scale < 1){
        scale = 1;
    }

    CGFloat zoom = scale / videoConnection.videoScaleAndCropFactor;
    videoConnection.videoScaleAndCropFactor = scale;

    [self.input.device unlockForConfiguration];

    CGAffineTransform transform = self.maskView.transform;

    //自动拉近放大
    if (scale == 1) {
        self.maskView.transform = CGAffineTransformScale(transform, zoom, zoom);
        CGRect rect = self.videoPreView.frame;
        rect.origin = CGPointZero;
        self.maskView.frame = rect;
    } else {
        CGFloat x = self.maskView.center.x - self.centerPoint.x;
        CGFloat y = self.maskView.center.y - self.centerPoint.y;
        CGRect rect = self.maskView.frame;
        rect.origin.x = rect.size.width / 2.0 * (1 - scale);
        rect.origin.y = rect.size.height / 2.0 * (1 - scale);
        rect.origin.x += x * zoom;
        rect.origin.y += y * zoom;
        rect.size.width = rect.size.width * scale;
        rect.size.height = rect.size.height * scale;

        [UIView animateWithDuration:.5f animations:^{
            self.maskView.transform = CGAffineTransformScale(transform, zoom, zoom);
            self.maskView.frame = rect;
        } completion:^(BOOL finished) {
        }];
    }

    NSLog(@"放大%f",zoom);
}

- (AVCaptureConnection *)connectionWithMediaType:(NSString *)mediaType fromConnections:(NSArray *)connections
{
    for ( AVCaptureConnection *connection in connections ) {
        for ( AVCaptureInputPort *port in [connection inputPorts] ) {
            if ( [[port mediaType] isEqual:mediaType] ) {
                return connection;
            }
        }
    }
    return nil;
}

//#pragma mark 手势拉近/远 界面
//- (void)cameraInitOver{
//    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchDetected:)];
//    pinch.delegate = self;
//    [self.view addGestureRecognizer:pinch];
//}
//
//- (void)pinchDetected:(UIPinchGestureRecognizer*)recogniser
//{
//    self.effectiveScale = self.beginGestureScale * recogniser.scale;
//    if (self.effectiveScale < 1.0){
//        self.effectiveScale = 1.0;
//    }
//    [self setVideoScale:self.effectiveScale pinch:YES];
//}
//
//- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
//{
//    if ( [gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]] ) {
//        _beginGestureScale = _effectiveScale;
//    }
//    return YES;
//}

#pragma mark - 相机权限Alert

- (void)requestCameraPemissionWithResult:(void(^)( BOOL granted))completion
{
    if ([AVCaptureDevice respondsToSelector:@selector(authorizationStatusForMediaType:)])
    {
        AVAuthorizationStatus permission =
        [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];

        switch (permission) {
            case AVAuthorizationStatusAuthorized:
                completion(YES);
                break;
            case AVAuthorizationStatusDenied:
            case AVAuthorizationStatusRestricted:
                completion(NO);
                break;
            case AVAuthorizationStatusNotDetermined:{
                [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                         completionHandler:^(BOOL granted) {

                 dispatch_async(dispatch_get_main_queue(), ^{
                     if (granted) {
                         completion(true);
                     } else {
                         completion(false);
                     }
                 });
               }];
            }
            break;
        }
    }
}

- (void)showAlertToPromptCameraAuthorization {
    UIAlertController *alertCtr = [UIAlertController alertControllerWithTitle:@"提示" message:@"您的相机功能没有打开，去“设置>拿趣用”设置一下吧" preferredStyle:UIAlertControllerStyleAlert];
    [alertCtr addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^(void){
//            [self leftBarButtonItemReturnAction];
        });
    }]];
    [alertCtr addAction:[UIAlertAction actionWithTitle:@"去设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [self.navigationController popToRootViewControllerAnimated:YES];
//            [Helper openURL:UIApplicationOpenSettingsURLString];
        });
    }]];
    [self presentViewController:alertCtr animated:YES completion:nil];
}

-(void)addTwoAlertControllerAction:(NSString *)title message:(NSString *)message leftTitle:(NSString *)leftTitle rightTitle:(NSString *)rightTitle leftAction:(void (^)(UIAlertAction * _Nonnull action))leftAction  rightAction:(void (^)(UIAlertAction * _Nonnull action))rightAction{
    UIAlertController *alertCtr = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alertCtr addAction:[UIAlertAction actionWithTitle:leftTitle style:UIAlertActionStyleDefault handler:leftAction]];
    [alertCtr addAction:[UIAlertAction actionWithTitle:rightTitle style:UIAlertActionStyleDefault handler:rightAction]];
    [self presentViewController:alertCtr animated:YES completion:nil];
}

-(void)networkStatusAlert{
//    NetworkStatus internetStatus = [Helper internetStatus];
//    switch (internetStatus) {
//        case NotReachable:{
//            __weak typeof(self) weakSelf = self;
//            dispatch_async(dispatch_get_main_queue(), ^{
//                [weakSelf addTwoAlertControllerAction:@"提示" message:@"您的WLAN与蜂窝移动网功能没有打开，去“设置>拿趣用”设置一下吧" leftTitle:@"关闭" rightTitle:@"去设置" leftAction:^(UIAlertAction * _Nonnull action) {
//                } rightAction:^(UIAlertAction * _Nonnull action) {
//                    [weakSelf.navigationController popToRootViewControllerAnimated:YES];
////                    [Helper openURL:UIApplicationOpenSettingsURLString];
//                }];
//            });
//        }
//            break;
//
//        default:
//            break;
//    }
}

@end
