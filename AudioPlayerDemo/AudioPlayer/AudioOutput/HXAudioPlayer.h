//
//  HXAudioPlayer.h
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/20.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol HXFillAudioDataDelegate <NSObject>

- (NSInteger)fillAudioData:(SInt16*) sampleBuffer numFrames:(NSInteger)frameNum numChannels:(NSInteger)channels;

@end

@interface HXAudioPlayer : NSObject

@property(nonatomic, assign) Float64 sampleRate;
@property(nonatomic, assign) Float64 channels;

- (instancetype)initWithCahnnels:(NSInteger)channels sampleRate:(NSInteger) sampleRate bytesPerSample:(NSInteger)bytesPerSample fillDataDelegate:(id<HXFillAudioDataDelegate>)delegate;

- (void)play;
- (void)stop;

@end

