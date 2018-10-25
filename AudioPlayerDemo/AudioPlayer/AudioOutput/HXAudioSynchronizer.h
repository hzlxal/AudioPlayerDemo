//
//  AudioSynchronizer.h
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/21.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HXDecoder.h"

static const CGFloat kMinBufferedDuration = 0.5;
static const CGFloat kMaxBufferedDuration = 1.0;

static const CGFloat kSyncMaxTimeDiff = 0.05;
static const CGFloat kFirstBufferedDuration = 0.5;

typedef NS_ENUM(NSInteger, HXPlayerOpenState) {
    HXPlayerOpenStateSuccess = 0,
    HXPlayerOpenStateFail,
    HXPlayerOpenStateCancel
};

@protocol HXAudioPlayerStateDelegate <NSObject>
- (void)openSucceed;
- (void)connectFailed;
- (void)hideLoading;
- (void)showLoading;
- (void)onCompletion;
- (void)restart;
@end

@interface HXAudioSynchronizer : NSObject

@property (nonatomic, weak) id<HXAudioPlayerStateDelegate> delegate;

- (instancetype)initWithPlayerStateDelegate:(id<HXAudioPlayerStateDelegate>) delegate;

- (HXPlayerOpenState)openResourceWithUrlStr:(NSString *)urlStr;

- (HXPlayerOpenState)openResourceWithUrlStr:(NSString *)urlStr range:(NSRange)range;

- (void)closeResource;

- (void)audioCallbackFillData:(SInt16 *)outData numFrames:(UInt32)numFrames numChannels: (UInt32)numChannels;

- (BOOL)isOpenResourceSuccess;
- (void)interrupt;

- (BOOL)isPlayCompleted;

- (NSInteger)getAudioSampleRate;
- (NSInteger)getAudioChannels;

- (BOOL)isAudioValid;

@end

