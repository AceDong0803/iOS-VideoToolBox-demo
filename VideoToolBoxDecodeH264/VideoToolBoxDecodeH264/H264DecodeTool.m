//
//  H264DecodeTool.m
//  VideoToolBoxDecodeH264
//
//  Created by AnDong on 2018/7/2.
//  Copyright © 2018年 AnDong. All rights reserved.
//

#import "H264DecodeTool.h"

@interface H264DecodeTool(){
    
    //解码session
    VTDecompressionSessionRef _decoderSession;
    
    //解码format 封装了sps和pps
    CMVideoFormatDescriptionRef _decoderFormatDescription;
    
    //sps & pps
    uint8_t *_sps;
    NSInteger _spsSize;
    uint8_t *_pps;
    NSInteger _ppsSize;
    
}

@end

@implementation H264DecodeTool

- (BOOL)initH264Decoder{
    if(_decoderSession){
        return YES;
    }
    
    const uint8_t* const parameterSetPointers[2] = { _sps, _pps };
    const size_t parameterSetSizes[2] = { _spsSize, _ppsSize };
    
    //用sps 和pps 实例化_decoderFormatDescription
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2, //参数个数
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4, //nal startcode开始的size
                                                                          &_decoderFormatDescription);
    
    if(status == noErr) {
        NSDictionary* destinationPixelBufferAttributes = @{
                                                           (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
                                                           //硬解必须是 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                                                           //                                                           或者是kCVPixelFormatType_420YpCbCr8Planar
                                                           //因为iOS是  nv12  其他是nv21
                                                           (id)kCVPixelBufferWidthKey : [NSNumber numberWithInt:1280],
                                                           (id)kCVPixelBufferHeightKey : [NSNumber numberWithInt:960],
                                                           //这里宽高和编码反的 两倍关系
                                                           (id)kCVPixelBufferOpenGLCompatibilityKey : [NSNumber numberWithBool:YES]
                                                           };

        
        
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _decoderFormatDescription,
                                              NULL,
                                              (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                              &callBackRecord,
                                              &_decoderSession);
        VTSessionSetProperty(_decoderSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
        VTSessionSetProperty(_decoderSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    } else {
        NSLog(@"IOS8VT: reset decoder session failed status=%d", status);
        return NO;
    }
    
    return YES;
}

//解码回调
static void didDecompress( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    
    //持有pixelBuffer数据，否则会被释放
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
    H264DecodeTool *decoder = (__bridge H264DecodeTool *)decompressionOutputRefCon;
    if (decoder.delegate)
    {
        [decoder.delegate gotDecodedFrame:pixelBuffer];
    }
}


//解码nalu裸数据
-(void) decodeNalu:(uint8_t *)frame size:(uint32_t)frameSize
{
    //    NSLog(@"------------开始解码");
    
    //获取nalu type
    int nalu_type = (frame[4] & 0x1F);
    CVPixelBufferRef pixelBuffer = NULL;
    
    //填充nalu size 去掉start code 替换成nalu size
    uint32_t nalSize = (uint32_t)(frameSize - 4);
    uint8_t *pNalSize = (uint8_t*)(&nalSize);
    frame[0] = *(pNalSize + 3);
    frame[1] = *(pNalSize + 2);
    frame[2] = *(pNalSize + 1);
    frame[3] = *(pNalSize);
  
    switch (nalu_type)
    {
        case 0x05:
            //关键帧
            if([self initH264Decoder])
            {
                pixelBuffer = [self decode:frame size:frameSize];
            }
            break;
        case 0x07:
            //sps
            _spsSize = frameSize - 4;
            _sps = malloc(_spsSize);
            memcpy(_sps, &frame[4], _spsSize);
            break;
        case 0x08:
        {
            //pps
            _ppsSize = frameSize - 4;
            _pps = malloc(_ppsSize);
            memcpy(_pps, &frame[4], _ppsSize);
            break;
        }
        default:
        {
            // B/P frame
            if([self initH264Decoder])
            {
                pixelBuffer = [self decode:frame size:frameSize];
            }
            break;
        }
            
            
    }
}


//解码帧数据
- (CVPixelBufferRef)decode:(uint8_t *)frame size:(uint32_t)frameSize{
    CVPixelBufferRef outputPixelBuffer = NULL;
    
    CMBlockBufferRef blockBuffer = NULL;
    
    //创建CMBlockBufferRef
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL,
                                                         (void *)frame,
                                                         frameSize,
                                                         kCFAllocatorNull,
                                                         NULL,
                                                         0,
                                                         frameSize,
                                                         FALSE,
                                                         &blockBuffer);
    if (status == kCMBlockBufferNoErr) {
        
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {frameSize};
        
        //创建sampleBuffer
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           _decoderFormatDescription ,
                                           1, 0, NULL, 1, sampleSizeArray,
                                           &sampleBuffer);
        
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            //CMSampleBufferRef丢进去解码
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_decoderSession,
                                                                      sampleBuffer,
                                                                      flags,
                                                                      &outputPixelBuffer,
                                                                      &flagOut);
            
            if(decodeStatus == kVTInvalidSessionErr) {
                NSLog(@"IOS8VT: Invalid session, reset decoder session");
            } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                NSLog(@"IOS8VT: decode failed status=%d(Bad data)", decodeStatus);
            } else if(decodeStatus != noErr) {
                NSLog(@"IOS8VT: decode failed status=%d", decodeStatus);
            }
            CFRelease(sampleBuffer);
        }
         CFRelease(blockBuffer);
    }
    //返回pixelBuffer数据
    return outputPixelBuffer;
}

- (void)endDecode{
    
    if(_decoderSession) {
        VTDecompressionSessionInvalidate(_decoderSession);
        CFRelease(_decoderSession);
        _decoderSession = NULL;
    }
    
    if(_decoderFormatDescription) {
        CFRelease(_decoderFormatDescription);
        _decoderFormatDescription = NULL;
    }
    
    if (_sps) {
        free(_sps);
    }
    
    if (_pps) {
        free(_pps);
    }

    _ppsSize = _spsSize = 0;
}



@end
