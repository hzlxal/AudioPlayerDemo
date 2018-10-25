//
//  AVAudioSession+HXAdd.h
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/21.
//  Copyright © 2018年 hzl. All rights reserved.
//
#import <AVFoundation/AVFoundation.h>

@interface AVAudioSession (HXAdd)

- (BOOL)usingBlueTooth;

- (BOOL)usingWiredMicrophone;

@end
