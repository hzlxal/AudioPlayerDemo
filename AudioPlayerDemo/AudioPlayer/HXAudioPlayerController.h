//
//  HXAudioPlayerController.h
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/21.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HXAudioSynchronizer.h"
#import "HXAudioPlayer.h"
@interface HXAudioPlayerController : NSObject

@property (nonatomic, strong) NSString *urlStr;
@property (nonatomic, strong) id<HXAudioPlayerStateDelegate> delegate;

- (instancetype)initWithUrlStr:(NSString *)urlStr playStateDelegate:(id<HXAudioPlayerStateDelegate>)delegate;

- (instancetype)initWithUrlStr:(NSString *)urlStr playStateDelegate:(id<HXAudioPlayerStateDelegate>)delegate playRange:(NSRange)range;

- (void)play;

- (void)pause;

- (void)stop;

- (void)restart;

- (BOOL)playing;

@end
