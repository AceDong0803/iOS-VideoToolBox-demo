//
//  H264DecodeTool.h
//  VideoToolBoxDecodeH264
//
//  Created by AnDong on 2018/7/2.
//  Copyright © 2018年 AnDong. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

@protocol  H264DecodeFrameCallbackDelegate <NSObject>

//回调sps和pps数据
- (void)gotDecodedFrame:(CVImageBufferRef )imageBuffer;

@end

@interface H264DecodeTool : NSObject

-(BOOL)initH264Decoder;

//解码nalu
-(void)decodeNalu:(uint8_t *)frame size:(uint32_t)frameSize;

- (void)endDecode;

@property (weak, nonatomic) id<H264DecodeFrameCallbackDelegate> delegate;

@end
