//
//  HXAudioSession.h
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/21.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

static const NSTimeInterval kAudioSessionLatencyBackground = 0.0929;
static const NSTimeInterval kAudioSessionLatencyDefault = 0.0232;
static const NSTimeInterval kAudioSessionLatencyLowLatency = 0.0058;

@interface HXAudioSession : NSObject

+ (HXAudioSession *)sharedInstance;

@property (nonatomic, strong) AVAudioSession *audioSession;

@property (nonatomic, assign) NSInteger preferredSampleRate;
@property (nonatomic, assign) NSInteger currentSampleRate;

@property (nonatomic, assign) NSTimeInterval preferredLatency;

@property (nonatomic, assign) BOOL active;

@property (nonatomic, strong) NSString *category;

- (void)addRouteChangeListener;
@end

