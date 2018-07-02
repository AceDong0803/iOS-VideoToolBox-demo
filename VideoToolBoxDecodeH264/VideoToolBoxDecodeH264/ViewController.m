//
//  ViewController.m
//  VideoToolBoxDecodeH264
//
//  Created by AnDong on 2018/7/2.
//  Copyright © 2018年 AnDong. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "AAPLEAGLLayer.h"
#import "H264EncodeTool.h"
#import "H264DecodeTool.h"

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate,H264EncodeCallBackDelegate,H264DecodeFrameCallbackDelegate>{
    //录制队列
    dispatch_queue_t captureQueue;
}


@property (nonatomic,strong)AVCaptureSession *captureSession; //输入和输出数据传输session
@property (nonatomic,strong)AVCaptureDeviceInput *captureDeviceInput; //从AVdevice获得输入数据
@property (nonatomic,strong)AVCaptureVideoDataOutput *captureDeviceOutput; //获取输出数据
@property (nonatomic,strong)AVCaptureConnection *connection; //connection
@property (nonatomic,strong)AVCaptureVideoPreviewLayer *previewLayer; //摄像头预览layer
@property (nonatomic,strong)AAPLEAGLLayer *playLayer;  //解码后播放layer

@property (nonatomic,strong)UIButton *startBtn;
@property (nonatomic,strong)UILabel *titleLabel;
@property (nonatomic,strong)UILabel *firstLabel;
@property (nonatomic,strong)UILabel *secondLabel;


//编解码器
@property (nonatomic,strong)H264DecodeTool *h264Decoder;
@property (nonatomic,strong)H264EncodeTool *h264Encoder;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    //初始化UI和参数
    [self initUIAndParameter];
    
    [self configH264Decoder];
    [self configH264Encoder];
}


- (void)initUIAndParameter{
    
    [self.view addSubview:self.startBtn];
    [self.view addSubview:self.titleLabel];
    [self.view addSubview:self.firstLabel];
    [self.view addSubview:self.secondLabel];
    
    //初始化队列
    captureQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
}

- (void)configH264Encoder{
    if (!self.h264Encoder) {
        self.h264Encoder = [[H264EncodeTool alloc]init];
        //640 * 480
        [self.h264Encoder initEncode:640 height:480];
        self.h264Encoder.delegate = self;
    }
}

- (void)configH264Decoder{
    if (!self.h264Decoder) {
        self.h264Decoder = [[H264DecodeTool alloc] init];
        self.h264Decoder.delegate = self;
    }
}

#pragma mark - EventHandle
- (void)startBtnAction{
    BOOL isRunning = self.captureSession && self.captureSession.running;
    
    if (isRunning) {
        //停止采集编码
        [self.startBtn setTitle:@"Start" forState:UIControlStateNormal];
        [self endCaputureSession];
    }
    else{
        //开始采集编码
        [self.startBtn setTitle:@"End" forState:UIControlStateNormal];
        [self startCaputureSession];
    }
}

- (void)startCaputureSession{
    //填充编码器和解码器
//    [self configH264Decoder];
    [self configH264Encoder];
  
    //填充预览
    [self initCapture];
    [self initPreviewLayer];
    [self initPlayLayer];
    
    //开始采集
    [self.captureSession startRunning];
}

- (void)endCaputureSession{
    //停止采集
    [self.captureSession stopRunning];
    [self.previewLayer removeFromSuperlayer];
    [self.playLayer removeFromSuperlayer];
    
    //停止编码
    [self.h264Encoder stopEncode];
    
    //停止解码
    [self.h264Decoder endDecode];
    
    self.h264Decoder = nil;
    self.h264Encoder = nil;
}


#pragma mark - 摄像头采集端

//初始化摄像头采集端
- (void)initCapture{
    
    self.captureSession = [[AVCaptureSession alloc]init];
    
    //设置录制720p
    self.captureSession.sessionPreset = AVCaptureSessionPreset640x480;
    
    AVCaptureDevice *inputCamera = [self cameraWithPostion:AVCaptureDevicePositionBack];
    
    self.captureDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:inputCamera error:nil];
    
    if ([self.captureSession canAddInput:self.captureDeviceInput]) {
        [self.captureSession addInput:self.captureDeviceInput];
    }
    
    self.captureDeviceOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.captureDeviceOutput setAlwaysDiscardsLateVideoFrames:NO];
    
    //设置YUV420p输出
    [self.captureDeviceOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    
    [self.captureDeviceOutput setSampleBufferDelegate:self queue:captureQueue];
    
    if ([self.captureSession canAddOutput:self.captureDeviceOutput]) {
        [self.captureSession addOutput:self.captureDeviceOutput];
    }
    
    //建立连接
    self.connection = [self.captureDeviceOutput connectionWithMediaType:AVMediaTypeVideo];
    [self.connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
}

//config 摄像头预览layer
- (void)initPreviewLayer{
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.captureSession];
    CGFloat height = (self.view.frame.size.height - 100)/2.0 - 20;
    CGFloat width = self.view.frame.size.width - 100;
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    [self.previewLayer setFrame:CGRectMake(100, 100,width,height)];
    [self.view.layer addSublayer:self.previewLayer];
}

- (void)initPlayLayer{
    CGFloat height = (self.view.frame.size.height - 100)/2.0 - 20;
    CGFloat width = self.view.frame.size.width - 100;
    self.playLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(100, (self.view.frame.size.height - 100)/2.0 + 100,width,height)];
    self.playLayer.backgroundColor = [UIColor whiteColor].CGColor;
    [self.view.layer addSublayer:self.playLayer];
}


//兼容iOS10以上获取AVCaptureDevice
- (AVCaptureDevice *)cameraWithPostion:(AVCaptureDevicePosition)position{
    NSString *version = [UIDevice currentDevice].systemVersion;
    if (version.doubleValue >= 10.0) {
        // iOS10以上
        AVCaptureDeviceDiscoverySession *devicesIOS10 = [AVCaptureDeviceDiscoverySession  discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:position];
        NSArray *devicesIOS  = devicesIOS10.devices;
        for (AVCaptureDevice *device in devicesIOS) {
            if ([device position] == position) {
                return device;
            }
        }
        return nil;
    } else {
        // iOS10以下
        NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        for (AVCaptureDevice *device in devices)
        {
            if ([device position] == position)
            {
                return device;
            }
        }
        return nil;
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    if (connection == self.connection) {
        [self.h264Encoder encode:sampleBuffer];
    }
}

#pragma mark - 编码回调
- (void)gotSpsPps:(NSData *)sps pps:(NSData *)pps{
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    //sps
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:sps];
    [self.h264Decoder decodeNalu:(uint8_t *)[h264Data bytes] size:(uint32_t)h264Data.length];
    
    
    //pps
    [h264Data resetBytesInRange:NSMakeRange(0, [h264Data length])];
    [h264Data setLength:0];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:pps];
    [self.h264Decoder decodeNalu:(uint8_t *)[h264Data bytes] size:(uint32_t)h264Data.length];
}

- (void)gotEncodedData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame{
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:data];
    [self.h264Decoder decodeNalu:(uint8_t *)[h264Data bytes] size:(uint32_t)h264Data.length];
}


#pragma mark - 解码回调
- (void)gotDecodedFrame:(CVImageBufferRef)imageBuffer{
    if(imageBuffer)
    {
        //解码回来的数据绘制播放
        self.playLayer.pixelBuffer = imageBuffer;
        CVPixelBufferRelease(imageBuffer);
    }
}

#pragma mark - Getters

- (UIButton *)startBtn{
    if (!_startBtn) {
        _startBtn = [[UIButton alloc]initWithFrame:CGRectMake(220, 30, 100, 50)];
        [_startBtn setBackgroundColor:[UIColor cyanColor]];
        [_startBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [_startBtn setTitle:@"start" forState:UIControlStateNormal];
        [_startBtn addTarget:self action:@selector(startBtnAction) forControlEvents:UIControlEventTouchUpInside];
    }
    return _startBtn;
}

- (UILabel *)titleLabel{
    if (!_titleLabel) {
        _titleLabel = [[UILabel alloc]initWithFrame:CGRectMake(50, 40, 150, 30)];
        _titleLabel.textColor = [UIColor blackColor];
        _titleLabel.text = @"测试H264解码";
    }
    return _titleLabel;
}


- (UILabel *)firstLabel{
    if (!_firstLabel) {
        _firstLabel = [[UILabel alloc]initWithFrame:CGRectMake(0, self.view.frame.size.height/4.0f, 100, 30)];
        _firstLabel.textColor = [UIColor blackColor];
        _firstLabel.font = [UIFont boldSystemFontOfSize:14.0f];
        _firstLabel.text = @"摄像头采集数据";
    }
    return _firstLabel;
}


- (UILabel *)secondLabel{
    if (!_secondLabel) {
        _secondLabel = [[UILabel alloc]initWithFrame:CGRectMake(0, self.view.frame.size.height*3/4.0f, 100, 30)];
        _secondLabel.textColor = [UIColor blackColor];
        _secondLabel.font = [UIFont boldSystemFontOfSize:14.0f];
        _secondLabel.text = @"解码后播放数据";
    }
    return _secondLabel;
}


@end
