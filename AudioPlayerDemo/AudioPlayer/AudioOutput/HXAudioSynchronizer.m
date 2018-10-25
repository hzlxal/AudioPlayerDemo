//
//  AudioSynchronizer.m
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/21.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import "HXAudioSynchronizer.h"
#import "HXCacheAPIProxy.h"
#import <pthread.h>

static const NSString *kAudioFramesKey = @"kAudioFramesKey";
static const NSString *kAudioSampleRateKey = @"kAudioSampleRateKey";
static const NSString *kAudioChannelsKey = @"kAudioChannelsKey";

static const NSTimeInterval kAudioCacheExpirationTime = 200;

@interface HXAudioSynchronizer ()

@property (nonatomic, strong) NSMutableArray *audioFrames;
@property (nonatomic, strong) NSMutableArray *totalFrames;

@property (nonatomic, strong) HXDecoder *decoder;

@property (nonatomic, strong) NSData *currentAudioFrame;
@property (nonatomic, assign) NSUInteger currentAudioFramePos;
@property (nonatomic, assign) CGFloat audioPosition;

@property (nonatomic, assign) CGFloat lastPosition;

@property (nonatomic, assign) NSTimeInterval bufferedBeginTime;
@property (nonatomic, assign) NSTimeInterval bufferedTotalTime;

@property (nonatomic, assign) NSTimeInterval decodeAudioErrorBeginTime;
@property (nonatomic, assign) NSTimeInterval decodeAudioErrorTotalTime;

@property (nonatomic, assign) BOOL isBuffered;
@property (nonatomic, assign) CGFloat bufferedDuration;
@property (nonatomic, assign) CGFloat minBufferDuration;
@property (nonatomic, assign) CGFloat maxBufferedDuration;

// 解码第一段buffer
@property (nonatomic, assign) pthread_mutex_t decodeFirstBufferMutex;
@property (nonatomic, assign) pthread_cond_t decodeFirstBufferCondition;
@property (nonatomic, assign) pthread_t decodeFirstBufferThread;
@property (nonatomic, assign) BOOL isDecodingFirstBuffer;

@property (nonatomic, assign) pthread_mutex_t audioDecodeMutex;
@property (nonatomic, assign) pthread_cond_t audioDecodeCondition;
@property (nonatomic, assign) pthread_t audioDecodeThread;
@property (nonatomic, assign) BOOL isDecoding;

@property (nonatomic, assign) CGFloat syncMaxTimeDiff;

@property (nonatomic, assign) CGFloat firstBufferedDuration;

@property (nonatomic, assign) BOOL isDestoryed;

@property (nonatomic, assign) BOOL isCompletion;

@property (nonatomic, strong) NSString *urlStr;

@property (nonatomic, assign) BOOL hasCache;
@property (nonatomic, strong) NSDictionary *cacheDic;
@property (nonatomic, assign) BOOL isCaching;

@end

@implementation HXAudioSynchronizer
#pragma makr - life cycle
- (instancetype)initWithPlayerStateDelegate:(id<HXAudioPlayerStateDelegate>)delegate{
    self = [super init];
    if (self) {
        self.delegate = delegate;
    }
    return self;
}

#pragma mark - public method
- (HXPlayerOpenState)openResourceWithUrlStr:(NSString *)urlStr{
    return [self openResourceWithUrlStr:urlStr range:NSMakeRange(0, 0)];
}

- (HXPlayerOpenState)openResourceWithUrlStr:(NSString *)urlStr range:(NSRange)range{
    if (self.minBufferDuration <= 0 || self.maxBufferedDuration <= 0) {
        self.minBufferDuration = kMinBufferedDuration;
        self.maxBufferedDuration = kMaxBufferedDuration;
    }
    
    self.syncMaxTimeDiff = kSyncMaxTimeDiff;
    self.firstBufferedDuration = kFirstBufferedDuration;
    self.urlStr = urlStr;
    
    if (self.hasCache) {
        self.cacheDic = [[HXCacheAPIProxy shareInstance] cacheForUrl:self.urlStr];
        self.audioFrames = self.cacheDic[kAudioFramesKey];
        if (self.audioFrames.count > 0) {
            return HXPlayerOpenStateSuccess;
        }else{
            self.hasCache = false;
        }
    }
    
    BOOL openState;
    self.isCaching = false;
    if (range.length > 0) {
        openState = [self.decoder openResourceWithUrlStr:urlStr range:range];
    }else{
        openState = [self.decoder openResourceWithUrlStr:urlStr];
    }
    if (!openState || !self.decoder.isSubscribed) {
        NSLog(@"HXPlayerDecoder decode file fail");
        [self closeResource];
        return self.decoder.isSubscribed ? HXPlayerOpenStateFail : HXPlayerOpenStateCancel;
    }
    
    [self setupDecoderThread];
    [self setupDecodeFirstBufferThread];
    
    return HXPlayerOpenStateSuccess;
}

- (void)run{
    while (self.isDecoding) {
        pthread_mutex_lock(&_audioDecodeMutex);
        pthread_cond_wait(&_audioDecodeCondition, &_audioDecodeMutex);
        pthread_mutex_unlock(&_audioDecodeMutex);
        [self decodeFrames];
    }
}

- (BOOL)isPlayCompleted{
    return self.isCompletion;
}

- (BOOL)isOpenResourceSuccess{
    return [self.decoder isOpenResourceSuccess];
}

- (void)interrupt{
    [self.decoder interrupt];
}

- (void)closeResource{
    [self.decoder interrupt];
    [self destroyDecodeFirstBufferThread];
    [self destroyDecoderThread];
    [self.decoder closeResource];
    
    @synchronized(self.audioFrames) {
        [self.audioFrames removeAllObjects];
        self.currentAudioFrame = nil;
    }
}

- (NSInteger)getAudioSampleRate {
    return [self.decoder sampleRate] > 0 ? [self.decoder sampleRate] : [self.cacheDic[kAudioSampleRateKey] integerValue];
}

- (NSInteger)getAudioChannels {
    return [self.decoder channels] > 0 ? [self.decoder channels] : [self.cacheDic[kAudioChannelsKey] integerValue];
}

- (BOOL)isAudioValid {
    return ([self.decoder validAudio] || self.hasCache);
}

#pragma mark - private method for decode
- (void)decodeFrames {
    [self decodeFramesWithDuration:0.f];
}

- (void)decodeFramesWithDuration:(CGFloat)duration {
    BOOL isContinue = YES;
    while (isContinue) {
        isContinue = NO;
        
        @autoreleasepool {
            if ([self.decoder validAudio]) {
                NSError *error;
                NSArray *frames = [self.decoder decodeFramesWithMinDuration:duration error:&error];
                if (error) {
                    NSLog(@"faild to decode frame with error: %@",error.localizedDescription);
                }
                if (frames.count) {
                    isContinue = [self addFrames:frames duration:duration];
                }
            }
        }
    }
}

- (BOOL)addFrames:(NSArray *)frames duration:(CGFloat)duration {
        @synchronized(self.audioFrames) {
            for (HXAudioFrame *frame in frames){
                if (![self.audioFrames containsObject:frame]) {
                    [self.audioFrames addObject:frame];
                }
                if (![self.totalFrames containsObject:frame]) {
                    [self.totalFrames addObject:frame];
                }
                self.bufferedDuration += frame.duration;
             }
        }
    return self.bufferedDuration > duration;
}

- (void)setupDecoderThread {
    self.isDestoryed = false;
    self.isDecoding = true;
    
    pthread_mutex_init(&_audioDecodeMutex, NULL);
    pthread_cond_init(&_audioDecodeCondition, NULL);
    pthread_create(&_audioDecodeThread, NULL, runDecoderThread, (__bridge void*)self);
}

- (void)setupDecodeFirstBufferThread {
    pthread_mutex_init(&_decodeFirstBufferMutex, NULL);
    pthread_cond_init(&_decodeFirstBufferCondition, NULL);
    self.isDecodingFirstBuffer = true;
    
    pthread_create(&_decodeFirstBufferThread, NULL, decodeFirstBufferRunLoop, (__bridge void*)self);
}

- (void)decodeFirstBuffer {
    [self decodeFramesWithDuration:kFirstBufferedDuration];
    
    pthread_mutex_lock(&_decodeFirstBufferMutex);
    pthread_cond_signal(&_decodeFirstBufferCondition);
    pthread_mutex_unlock(&_decodeFirstBufferMutex);
    self.isDecodingFirstBuffer = false;
}

- (void)signalDecoderThread {
    if (!self.decoder || self.isDestoryed) {
        return;
    }
    
    pthread_mutex_lock(&_audioDecodeMutex);
    pthread_cond_signal(&_audioDecodeCondition);
    pthread_mutex_unlock(&_audioDecodeMutex);
}

- (void)destroyDecodeFirstBufferThread {
    if (self.isDecodingFirstBuffer) {
        pthread_mutex_lock(&_decodeFirstBufferMutex);
        pthread_cond_wait(&_decodeFirstBufferCondition, &_decodeFirstBufferMutex);
        pthread_mutex_unlock(&_decodeFirstBufferMutex);
    }
}

- (void)destroyDecoderThread {
    self.isDestoryed = true;
    self.isDecoding = false;
    self.bufferedDuration = 0;
    
    void* status;
    pthread_mutex_lock(&_audioDecodeMutex);
    pthread_cond_signal(&_audioDecodeCondition);
    pthread_mutex_unlock(&_audioDecodeMutex);
    pthread_join(self.audioDecodeThread, &status);
    pthread_mutex_destroy(&_audioDecodeMutex);
    pthread_cond_destroy(&_audioDecodeCondition);
}

- (void)audioCallbackFillData:(SInt16 *)outData numFrames:(UInt32)numFrames numChannels: (UInt32)numChannels{
    [self checkPlayState];
    if (self.isBuffered && !self.hasCache) {
        memset(outData, 0, numFrames * numChannels * sizeof(SInt16));
        return;
    }
    
    @autoreleasepool {
        while (numFrames > 0) {
            if (!self.currentAudioFrame) {
                //从队列中取出音频数据
                @synchronized(self.audioFrames) {
                    NSUInteger count = self.audioFrames.count;
                    if (count > 0) {
                        HXAudioFrame *frame = self.audioFrames[0];
                        self.bufferedDuration -= frame.duration;
                        
                        [self.audioFrames removeObjectAtIndex:0];
                        self.audioPosition = frame.position;
                        
                        self.currentAudioFramePos = 0;
                        self.currentAudioFrame = frame.samples;
                    }
                }
            }
            
            if (self.currentAudioFrame) {
                const void *bytes = (Byte *)self.currentAudioFrame.bytes + self.currentAudioFramePos;
                const NSUInteger bytesLeft = (self.currentAudioFrame.length - self.currentAudioFramePos);
                const NSUInteger frameSize = numChannels * sizeof(SInt16);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSize, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSize;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                
                if (bytesToCopy < bytesLeft){
                    self.currentAudioFramePos += bytesToCopy;
                }else{
                    self.currentAudioFrame = nil;
                }
            }else {
                memset(outData, 0, numFrames * numChannels * sizeof(SInt16));
                break;
            }
        }
    }
}

- (void)checkPlayState{
    if (!self.decoder && !self.hasCache) {
        return;
    }
    if (self.isBuffered && ((self.bufferedDuration > self.minBufferDuration))) {
        self.isBuffered = NO;
        if([self.delegate respondsToSelector:@selector(hideLoading)]){
            [self.delegate hideLoading];
        }
    }
    
    NSUInteger leftAudioFrames = ([self.decoder validAudio] || self.hasCache) ? self.audioFrames.count : 0;
    if (leftAudioFrames == 0) {
        if (self.minBufferDuration > 0 && !self.isBuffered) {
            self.isBuffered = YES;
            self.bufferedBeginTime = [[NSDate date] timeIntervalSince1970];
            if([self.delegate respondsToSelector:@selector(showLoading)]){
                [self.delegate showLoading];
            }
        }
        if([self.decoder isEOF] || self.hasCache){
            if([self.delegate respondsToSelector:@selector(onCompletion)]){
                self.isCompletion = YES;
                [self.delegate onCompletion];
            }
            if (!self.hasCache && !self.isCaching) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    @synchronized (self) {
                        self.isCaching = YES;
                        NSDictionary *dic = @{
                                              kAudioChannelsKey : @([self getAudioChannels]),
                                              kAudioSampleRateKey : @([self getAudioSampleRate]),
                                              kAudioFramesKey : self.totalFrames
                                              };
                        [[HXCacheAPIProxy shareInstance] setCacheWithObject:dic url:self.urlStr cacheExpirationTime:kAudioCacheExpirationTime];
                        self.hasCache = YES;
                        self.isCaching = NO;
                    }
                });
                }
            }
        }
    
    if (self.isBuffered) {
        self.bufferedTotalTime = [[NSDate date] timeIntervalSince1970] - self.bufferedBeginTime;
        if (self.bufferedTotalTime > 10) {
            _bufferedTotalTime = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                if([self.delegate respondsToSelector:@selector(restart)]){
                    [self.delegate restart];
                }
            });
            return;
        }
    }
    
    if (!self.isDecodingFirstBuffer && (leftAudioFrames == 0 || !(self.bufferedDuration > self.minBufferDuration))) {
        [self signalDecoderThread];
    }
}

#pragma mark - c method
static void *runDecoderThread(void* ptr){
    HXAudioSynchronizer *synchronizer = (__bridge HXAudioSynchronizer*)ptr;
    [synchronizer run];
    return NULL;
}

static void *decodeFirstBufferRunLoop(void* ptr){
    HXAudioSynchronizer *synchronizer = (__bridge HXAudioSynchronizer*)ptr;
    [synchronizer decodeFirstBuffer];
    return NULL;
}

#pragma mark - getter && setter
- (HXDecoder *)decoder{
    if (!_decoder) {
        _decoder = [[HXDecoder alloc] init];
    }
    return _decoder;
}

- (NSMutableArray *)audioFrames{
    if (!_audioFrames) {
        _audioFrames = [[NSMutableArray alloc] init];
    }
    return _audioFrames;
}

- (NSMutableArray *)totalFrames{
    if (!_totalFrames) {
        _totalFrames = [[NSMutableArray alloc] init];
    }
    return _totalFrames;
}

- (void)setUrlStr:(NSString *)urlStr{
    _urlStr = urlStr;
    if ([[HXCacheAPIProxy shareInstance] hasCacheWithUrl:urlStr]) {
        self.hasCache = YES;
    }else{
        self.hasCache = NO;
    }
}

@end
