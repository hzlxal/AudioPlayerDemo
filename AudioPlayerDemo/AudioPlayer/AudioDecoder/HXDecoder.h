//
//  HXDecoder.h
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/20.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <libavformat/avformat.h>
#import <libswscale/swscale.h>
#import <libswresample/swresample.h>
#import <libavutil/pixdesc.h>

static const NSTimeInterval kSubscribeVideoDataTimeOut = 60;
static const NSTimeInterval kNetWorkStreamRetryTime = 3;

static const NSInteger kProbsize = 32;


@interface HXAudioFrame : NSObject <NSCoding>
@property (nonatomic, assign) CGFloat position;
@property (nonatomic, assign) CGFloat duration;
@property (nonatomic, copy) NSData *samples;
@end

@interface HXDecoder : NSObject

@property (nonatomic, assign) AVFormatContext *formatCtx; // 封装文件
@property (nonatomic, assign) AVCodecContext *audioCodecCtx; // 音频解码器

@property (nonatomic, copy) NSArray *audioStreams; // 音频流

@property (nonatomic, assign) NSInteger audioStreamIndex; // 音频流索引

@property (nonatomic, assign) CGFloat audioTimeBase; // 音频时间基

@property (nonatomic, assign) BOOL isOpenResourceSuccess; // 是否能够连接到资源

@property (nonatomic, assign) BOOL isSubscribed;
@property (nonatomic, assign) BOOL isEOF;

- (BOOL)openResourceWithUrlStr:(NSString *)urlStr;

- (BOOL)openResourceWithUrlStr:(NSString *)urlStr range:(NSRange)range;

- (NSArray *)decodeFramesWithMinDuration:(CGFloat)minDuration error:(NSError **)error;

- (BOOL)detectInterrupted;
- (void)interrupt;

- (BOOL)validAudio;

- (CGFloat)sampleRate;
- (NSUInteger)channels;

- (CGFloat)duration;

- (void)closeResource;

@end
