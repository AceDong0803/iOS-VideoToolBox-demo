//
//  H264EncodeTool.m
//  VideoToolBoxDecodeH264
//
//  Created by AnDong on 2018/7/2.
//  Copyright © 2018年 AnDong. All rights reserved.
//

#import "H264EncodeTool.h"
#import <VideoToolbox/VideoToolbox.h>

@interface H264EncodeTool (){
    
    //帧号
    int frameNO;
    
    //编码队列
    dispatch_queue_t encodeQueue;
    
    //编码session
    VTCompressionSessionRef encodingSession;
    
    //sps和pps
    NSData *sps;
    NSData *pps;
}


@end

@implementation H264EncodeTool

- (instancetype)init{
    
    if (self = [super init]) {
        frameNO = 0;
        encodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        sps = nil;
        pps = nil;
    }
    return self;
}

- (void)initEncode:(int)width height:(int)height{
    
    dispatch_async(encodeQueue, ^{
        OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)(self),  &encodingSession);
        NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
        if (status != 0)
        {
            NSLog(@"H264: Unable to create a H264 session");
            return ;
        }
        
        // 设置实时编码输出（避免延迟）
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        
        // 设置关键帧（GOPsize)间隔
        int frameInterval = 24;
        CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
        
        //设置期望帧率
        int fps = 24;
        CFNumberRef  fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
        
        
        //设置码率，均值，单位是byte
        int bitRate = width * height * 3 * 4 * 8;
        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
        
        //设置码率，上限，单位是bps
        int bitRateLimit = width * height * 3 * 4;
        CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRateLimit);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
        
        //开始编码
        VTCompressionSessionPrepareToEncodeFrames(encodingSession);
    });
    
}

// 编码完成回调
void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags);
    if (status != 0) {
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    H264EncodeTool* encoder = (__bridge H264EncodeTool*)outputCallbackRefCon;
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    // 判断当前帧是否为关键帧
    // 获取sps & pps数据
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        if (statusCode == noErr)
        {
            // 获得了sps，再获取pps
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            if (statusCode == noErr)
            {
                // 获取SPS和PPS data
                NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                if (encoder.delegate)
                {
                    //回调解码完成的sps和pps数据
                    [encoder.delegate gotSpsPps:sps pps:pps];
                }
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    
    //这里获取了数据指针，和NALU的帧总长度，前四个字节里面保存的
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4; // 返回的nalu数据前四个字节不是0001的startcode，而是大端模式的帧长度length
        
        // 循环获取nalu数据
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            uint32_t NALUnitLength = 0;
            // 读取NALU长度的数据
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // 从大端转系统端
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            if (encoder.delegate) {
                [encoder.delegate gotEncodedData:data isKeyFrame:keyframe];
            }
            // 移动到下一个NALU单元
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
    
}


//编码sampleBuffer
- (void) encode:(CMSampleBufferRef )sampleBuffer
{
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    // 帧时间，如果不设置会导致时间轴过长。
    CMTime presentationTimeStamp = CMTimeMake(frameNO++, 1000);
    VTEncodeInfoFlags flags;
    OSStatus statusCode = VTCompressionSessionEncodeFrame(encodingSession,
                                                          imageBuffer,
                                                          presentationTimeStamp,
                                                          kCMTimeInvalid,
                                                          NULL, NULL, &flags);
    if (statusCode != noErr) {
        NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
        
        if (encodingSession) {
            VTCompressionSessionInvalidate(encodingSession);
            CFRelease(encodingSession);
            encodingSession = NULL;
        }
        return;
    }
    NSLog(@"H264: VTCompressionSessionEncodeFrame Success");
}

- (void)stopEncode
{
    if (encodingSession) {
        VTCompressionSessionCompleteFrames(encodingSession, kCMTimeInvalid);
        VTCompressionSessionInvalidate(encodingSession);
        CFRelease(encodingSession);
        encodingSession = NULL;
        frameNO = 0;
    }
}

@end
