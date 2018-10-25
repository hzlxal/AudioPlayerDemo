//
//  HXAudioSession.m
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/21.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import "HXAudioSession.h"
#import "AVAudioSession+HXAdd.h"

@implementation HXAudioSession

#pragma mark - life cycle
+ (HXAudioSession *)sharedInstance{
    static HXAudioSession *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HXAudioSession alloc] init];
    });
    return instance;
}

- (instancetype)init{
    self = [super init];
    if (self) {
        self.preferredSampleRate = 44100.0;
        self.audioSession = [AVAudioSession sharedInstance];
        [self addRouteChangeListener];
    }
    return self;
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
}

#pragma mark - public method
- (void)addRouteChangeListener
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onNotificationAudioRouteChange:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:nil];
    [self adjustOnRouteChange];
}

#pragma mark - getter && setter
- (void)setActive:(BOOL)active{
    _active = active;
    NSError *error = nil;
    
    if(![self.audioSession setPreferredSampleRate:self.preferredSampleRate error:&error]){
        NSLog(@"Error when setting sample rate on audio session: %@", error.localizedDescription);
    }
    if(![self.audioSession setActive:active error:&error]){
        NSLog(@"Error when setting active state of audio session: %@", error.localizedDescription);
    }
    self.currentSampleRate = [self.audioSession sampleRate];
}

- (void)setCategory:(NSString *)category{
    _category = category;
    
    NSError *error = nil;
    if (![self.audioSession setCategory:category error:&error]) {
        NSLog(@"Could note set category on audio session: %@", error.localizedDescription);
    }
}

- (void)setPreferredLatency:(NSTimeInterval)preferredLatency{
    _preferredLatency = preferredLatency;
    
    NSError *error = nil;
    if(![self.audioSession setPreferredIOBufferDuration:_preferredLatency error:&error]){
        NSLog(@"Error when setting preferred I/O buffer duration");
    }
}

#pragma mark - AVAudioSessionRouteChangeNotification observer

- (void)onNotificationAudioRouteChange:(NSNotification *)sender {
    [self adjustOnRouteChange];
}

- (void)adjustOnRouteChange
{
    AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
    if (currentRoute) {
        if ([[AVAudioSession sharedInstance] usingWiredMicrophone]) {
        } else {
            if (![[AVAudioSession sharedInstance] usingBlueTooth]) {
                [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
            }
        }
    }
}

@end
