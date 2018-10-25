//
//  HXAudioPlayerController.m
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/21.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import "HXAudioPlayerController.h"

@interface HXAudioPlayerController ()<HXFillAudioDataDelegate>

@property (nonatomic, strong) HXAudioSynchronizer *synchronizer;
@property (nonatomic, strong) HXAudioPlayer *audioPlayer;

@property (nonatomic, assign) NSRange range;

@property (nonatomic, assign) BOOL isPlaying;

@end

@implementation HXAudioPlayerController
#pragma mark - life cycle
- (instancetype)initWithUrlStr:(NSString *)urlStr playStateDelegate:(id<HXAudioPlayerStateDelegate>)delegate{
    return [self initWithUrlStr:urlStr playStateDelegate:delegate playRange:NSMakeRange(0,0)];
}

- (instancetype)initWithUrlStr:(NSString *)urlStr playStateDelegate:(id<HXAudioPlayerStateDelegate>)delegate playRange:(NSRange)range{
    self = [super init];
    if (self) {
        self.delegate = delegate;
        self.urlStr = urlStr;
        self.range = range;
        [self startWithRange:range];
    }
    return self;
}

#pragma mark - public method
- (void)play{
    if (!self.isPlaying) {
        [self.audioPlayer play];
        self.isPlaying = YES;
    }
}

- (void)pause{
    if (self.isPlaying) {
        self.isPlaying = NO;
        [self.audioPlayer stop];
    }
}

- (void)stop{
    if (self.isPlaying) {
        [self.audioPlayer stop];
        self.isPlaying = NO;
        [self.synchronizer closeResource];
    }
}

- (BOOL)playing{
    return self.isPlaying;
}

- (void)restart{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stop];
        [self startWithRange:self.range];
    });
}

#pragma mark - private method
- (void)startWithRange:(NSRange)range{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        
        HXPlayerOpenState state;
        if (range.length > 0) {
            state = [strongSelf.synchronizer openResourceWithUrlStr:strongSelf.urlStr range:range];
        }else{
            state = [strongSelf.synchronizer openResourceWithUrlStr:strongSelf.urlStr];
        }
        
        if (state == HXPlayerOpenStateSuccess) {
            
            NSInteger audioChannels = [self.synchronizer getAudioChannels];
            NSInteger audioSampleRate = [self.synchronizer getAudioSampleRate];
            NSInteger bytesPerSample = 2;
            
            self.audioPlayer = [[HXAudioPlayer alloc] initWithCahnnels:audioChannels sampleRate:audioSampleRate bytesPerSample:bytesPerSample fillDataDelegate:self];
            
            if ([self.delegate respondsToSelector:@selector(openSucceed)]) {
                [self.delegate openSucceed];
            }
        }else if (state == HXPlayerOpenStateFail){
            if ([self.delegate respondsToSelector:@selector(connectFailed)]){
                [self.delegate connectFailed];
            }
        }
    });
}

#pragma mark - HXFillAudioDataDelegate
- (NSInteger)fillAudioData:(SInt16*) sampleBuffer numFrames:(NSInteger)frameNum numChannels:(NSInteger)channels{
    if(self.synchronizer && ![self.synchronizer isPlayCompleted]){
        [self.synchronizer audioCallbackFillData:sampleBuffer numFrames:(UInt32)frameNum numChannels:(UInt32)channels];
    } else {
        memset(sampleBuffer, 0, frameNum * channels * sizeof(SInt16));
    }
    return 1;
}

#pragma mark - getter && setter
- (HXAudioSynchronizer *)synchronizer{
    if (!_synchronizer) {
        _synchronizer = [[HXAudioSynchronizer alloc] initWithPlayerStateDelegate:self.delegate];
    }
    return _synchronizer;
}

@end
