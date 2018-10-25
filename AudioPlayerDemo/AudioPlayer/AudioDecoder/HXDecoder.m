//
//  HXDecoder.m
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/20.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import "HXDecoder.h"
@interface HXDecoder ()

@property (nonatomic, assign) AVFrame *audioFrame;

@property (nonatomic, assign) CGFloat startTime;
@property (nonatomic, assign) CGFloat endTime;

@property (nonatomic, assign) SwrContext *swrCtx;
@property (nonatomic, assign) void *swrBuffer;
@property (nonatomic, assign) NSUInteger swrBufferSize;

@property (nonatomic, assign) NSTimeInterval subscribeTimeOutTimeInSecs;
@property (nonatomic, assign) NSTimeInterval readLastFrameTime;
@property (nonatomic, assign) NSInteger connectionRetryCount;

@property (nonatomic, assign) BOOL isInterrupted;

@property (nonatomic, strong) HXAudioFrame *lastFrame;

@end

@implementation HXAudioFrame

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeFloat:_position forKey:@"position"];
    [aCoder encodeFloat:_duration forKey:@"duration"];
    [aCoder encodeObject:_samples forKey:@"samples"];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [super init];
    if (self) {
        _position = [aDecoder decodeFloatForKey:@"position"];
        _duration = [aDecoder decodeFloatForKey:@"duration"];
        _samples = [aDecoder decodeObjectForKey:@"samples"];
    }
    return self;
}

@end

@implementation HXDecoder
#pragma mark - public method
- (BOOL)openResourceWithUrlStr:(NSString *)urlStr{
    return [self openResourceWithUrlStr:urlStr range:NSMakeRange(0, 0)];
}

- (BOOL)openResourceWithUrlStr:(NSString *)urlStr range:(NSRange)range{
    BOOL isOpenResourceSuccess = true;
    
    if (urlStr.length <= 0) {
        return false;
    }
    [self commitInitWithRange:range];
    
    int openResourceErrorCode = [self OpenResourceWithUrlStr:urlStr];
    if (openResourceErrorCode > 0) {
        if (![self openAudioStream]) {
            [self closeResource];
            isOpenResourceSuccess = false;
        }
    }else{
        isOpenResourceSuccess = false;
    }
    
    self.isOpenResourceSuccess = isOpenResourceSuccess;
    return isOpenResourceSuccess;
}

- (NSArray *)decodeFramesWithMinDuration:(CGFloat)minDuration error:(NSError *__autoreleasing *)error{
    
    if (self.audioStreamIndex == -1) {
        return nil;
    }
    
    NSMutableArray *result = [[NSMutableArray alloc] init];
    AVPacket packet;
    CGFloat decodeDuration = 0;
    
    BOOL finished = NO;
    
    while (!finished) {
        if (av_read_frame(self.formatCtx, &packet) < 0 || ([self.lastFrame position] > self.endTime && self.endTime > 0)) {
            self.isEOF = YES;
            
            [self closeResource];
            
            break;
        }
        int errorCode = avcodec_send_packet(self.audioCodecCtx, &packet);
        if (errorCode != 0) {
            NSLog(@"decode aduio error: %s",av_err2str(errorCode));
            continue;
        }
        errorCode = avcodec_receive_frame(self.audioCodecCtx, self.audioFrame);
        if (errorCode != 0) {
            NSLog(@"decode audio error: %s",av_err2str(errorCode));
            continue;
        }
            
        HXAudioFrame *frame = [self handleAudioFrame];
        if (frame) {
            [result addObject:frame];
            decodeDuration += frame.duration;
            if (decodeDuration > minDuration) {
                finished = YES;
            }
        }
        av_packet_unref(&packet);
        self.lastFrame = frame;
    }
    self.readLastFrameTime = [[NSDate date] timeIntervalSince1970];
    return [result copy];
}

- (BOOL)detectInterrupted
{
    if ([[NSDate date] timeIntervalSince1970] - self.readLastFrameTime > self.subscribeTimeOutTimeInSecs) {
        return YES;
    }
    return self.isInterrupted;
}

- (void)interrupt{
    self.subscribeTimeOutTimeInSecs = -1;
    self.isInterrupted = YES;
    self.isSubscribed = NO;;
}

- (BOOL)validAudio;{
    return self.audioStreamIndex != -1;
}

- (CGFloat)sampleRate;{
    return self.audioCodecCtx ? self.audioCodecCtx->sample_rate : 0;
}

- (NSUInteger)channels;{
    return self.audioCodecCtx ? self.audioCodecCtx->channels : 0;
}

- (CGFloat)duration{
    if(self.formatCtx){
        if(self.formatCtx->duration == AV_NOPTS_VALUE){
            return -1;
        }
        return self.formatCtx->duration / AV_TIME_BASE;
    }
    return -1;
}


#pragma mark - private method for openResource
// 打开资源并查找流
- (int)OpenResourceWithUrlStr:(NSString *)urlStr{
    AVFormatContext *formatCtx = avformat_alloc_context();
    // 设置超时回调
    AVIOInterruptCB interruptCB = {interrupt_callback, (__bridge void *)(self)};
    formatCtx->interrupt_callback = interruptCB;
    
    int openResourceErrorCode = [self openFormatWithFormatContext:&formatCtx urlStr:urlStr];
    
    // 打开失败
    if (openResourceErrorCode != 0) {
        NSLog(@"audio decoder open input file failed... videoURL is %@ openInputErr is : %s", urlStr, av_err2str(openResourceErrorCode));
        if (formatCtx)
            avformat_free_context(formatCtx);
        return openResourceErrorCode;
    }
    [self setupAnaylyzeDurationAndProbesizeWithFormatContext:formatCtx];
    
    int findStreamErrorCode = avformat_find_stream_info(formatCtx, NULL);
    
    if (findStreamErrorCode < 0) {
        avformat_close_input(&formatCtx);
        avformat_free_context(formatCtx);
        NSLog(@"audio decoder find stream info failed... find stream ErrCode is %s", av_err2str(findStreamErrorCode));
        return findStreamErrorCode;
    }
    
    // 没有找到流数据
    if (formatCtx->streams[0]->codecpar->codec_id == AV_CODEC_ID_NONE) {
        avformat_close_input(&formatCtx);
        avformat_free_context(formatCtx);
        if ([self isNeedRetry]) {
            return [self OpenResourceWithUrlStr:urlStr];
        }else{
            return -1;
        }
    }
    self.formatCtx = formatCtx;
    
    return 1;
}

// 初始化分析数据大小和长度
- (void)setupAnaylyzeDurationAndProbesizeWithFormatContext:(AVFormatContext *)formatCtx{
    formatCtx->probesize = kProbsize;
    
//    float multiplier = 0.5 + (double)pow(2.0, (double)self.connectionRetryCount) * 0.25;
//    formatCtx->max_analyze_duration = multiplier * AV_TIME_BASE;
}

- (void)seekWithStartTime:(CGFloat)startTime{
    int64_t seekPosition = startTime * AV_TIME_BASE;
    if (self.formatCtx->start_time != AV_NOPTS_VALUE) {
        seekPosition += self.formatCtx->start_time;
    }
    
    int seekFrameErrorCode = av_seek_frame(self.formatCtx, -1, seekPosition, AVSEEK_FLAG_BACKWARD);
    if (seekFrameErrorCode < 0) {
        NSLog(@"fail to seek with error code: %s", av_err2str(seekFrameErrorCode));
    }
}

// 打开资源
- (int)openFormatWithFormatContext:(AVFormatContext **)formatCtx urlStr:(NSString *)urlStr{
    const char *videoUrl = [urlStr cStringUsingEncoding:NSUTF8StringEncoding];
    AVDictionary *options = NULL;
    const char *bufferSizeStr = [@"2048" cStringUsingEncoding:NSUTF8StringEncoding];
    const char *bufferSizeKey = [@"bufsize" cStringUsingEncoding:NSUTF8StringEncoding];
    int dicSetErrorCode = av_dict_set(&options, bufferSizeStr, bufferSizeKey, 0);
    if (dicSetErrorCode < 0) {
        NSLog(@"fail to set options with error: %s",av_err2str(dicSetErrorCode));
    }
    return avformat_open_input(formatCtx, videoUrl, NULL, &options);
}

- (BOOL)isNeedRetry{
    self.connectionRetryCount++;
    return self.connectionRetryCount < kNetWorkStreamRetryTime;
}

// 找音频流和音频流解码器
- (BOOL)openAudioStream{
    self.audioStreamIndex = -1;
    self.audioStreams = collectStreamIndexs(self.formatCtx, AVMEDIA_TYPE_AUDIO);
    
    for (NSNumber *index in self.audioStreams) {
        AVCodecParameters *codecpar = self.formatCtx->streams[index.integerValue]->codecpar;
        AVCodec *codec = avcodec_find_decoder(codecpar->codec_id);
        AVCodecContext *codecCtx = avcodec_alloc_context3(codec);
        avcodec_parameters_to_context(codecCtx, codecpar);
        
        if(!codec){
            NSLog(@"Find Audio Decoder Failed codec_id %d CODEC_ID_AAC is %d", codecCtx->codec_id, AV_CODEC_ID_AAC);
            return false;
        }
        
        int openCodecErrorCode = avcodec_open2(codecCtx, codec, NULL);
        if (openCodecErrorCode < 0) {
            NSLog(@"Open Audio Codec Failed openCodecErr is %s", av_err2str(openCodecErrorCode));
            return false;
        }
        
        // 如果格式不符合要重采样
        SwrContext *swrCtx = NULL;
        if (![self audioCodecIsSupported:codecCtx]) {
            swrCtx = swr_alloc_set_opts(NULL, av_get_default_channel_layout(codecCtx->channels), AV_SAMPLE_FMT_S16, codecCtx->sample_rate, av_get_default_channel_layout(codecCtx->channels), codecCtx->sample_fmt, codecCtx->sample_rate, 0, NULL);
            if (!swrCtx || swr_init(swrCtx)) {
                if (swrCtx) {
                    swr_free(&swrCtx);
                }
                avcodec_close(codecCtx);
                NSLog(@"init resampler failed...");
                return false;
            }
        }
        
        self.audioFrame = av_frame_alloc();
        if (!self.audioFrame) {
            NSLog(@"Alloc Audio Frame Failed...");
            if (swrCtx){
                swr_free(&swrCtx);
            }
            avcodec_close(codecCtx);
            return false;
        }
        
        self.audioStreamIndex = index.integerValue;
        self.audioCodecCtx = codecCtx;
        self.swrCtx = swrCtx;
        
        AVStream *stream = self.formatCtx->streams[index.integerValue];
        avStreamFPSTimeBase(stream, codecCtx, 0.025, &_audioTimeBase);
        
        if (self.startTime > 0 && self.endTime > 0) {
            [self seekWithStartTime:self.startTime];
        }
    }
    
    return true;
}

- (HXAudioFrame *)handleAudioFrame{
    if (!self.audioFrame->data[0]) {
        return nil;
    }
    
    const NSUInteger numChannels = self.audioCodecCtx->channels;
    NSInteger numFrames = 0;
    
    void *audioData = NULL;
    
    if (self.swrCtx) {
        const NSUInteger ratio = 2;
        const int bufferSize = av_samples_get_buffer_size(NULL, (int)numChannels, (int)(self.audioFrame->nb_samples * ratio), AV_SAMPLE_FMT_S16, 1);
        if (!self.swrBuffer || self.swrBufferSize < bufferSize) {
            self.swrBufferSize = bufferSize;
            self.swrBuffer = realloc(self.swrBuffer, self.swrBufferSize);
        }
        
        Byte *outBuf[2] = {self.swrBuffer, 0};
        numFrames = swr_convert(self.swrCtx, outBuf, (int)(self.audioFrame->nb_samples * ratio), (const uint8_t **)self.audioFrame->data, self.audioFrame->nb_samples);
        if (numFrames < 0) {
            NSLog(@"fail resample audio");
            return nil;
        }
        audioData = self.swrBuffer;
    }else{
        if (_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
            NSLog(@"Audio format is invalid");
            return nil;
        }
        audioData = self.audioFrame->data[0];
        numFrames = self.audioFrame->nb_samples;
    }
    
    const NSUInteger numElements = numFrames * numChannels;
    NSMutableData *pcmData = [NSMutableData dataWithLength:numElements * sizeof(SInt16)];
    memcpy(pcmData.mutableBytes, audioData, numElements * sizeof(SInt16));
    
    HXAudioFrame *audioFrame = [[HXAudioFrame alloc] init];
    audioFrame.position = av_frame_get_best_effort_timestamp(self.audioFrame) * self.audioTimeBase;
    audioFrame.duration = av_frame_get_pkt_pos(self.audioFrame) * self.audioTimeBase;
    audioFrame.samples = [pcmData copy];
    
    return audioFrame;
}


- (BOOL) audioCodecIsSupported:(AVCodecContext *) audioCodecCtx;
{
    if (audioCodecCtx->sample_fmt == AV_SAMPLE_FMT_S16) {
        return true;
    }
    return false;
}


#pragma mark - private method for life cycle
// 初始化一些全局变量
- (void)commitInitWithRange:(NSRange)range{
    avformat_network_init();
    av_register_all();
    
    self.subscribeTimeOutTimeInSecs = kSubscribeVideoDataTimeOut;
    self.isInterrupted = NO;
    self.isSubscribed = YES;
    self.startTime = range.location;
    self.endTime = range.location + range.length;
    self.readLastFrameTime = [[NSDate date] timeIntervalSince1970];
}

- (void)closeResource{
    [self interrupt];
    
    [self closeAudioStream];
    
    self.audioStreams = nil;
    
    if (self.formatCtx) {
        self.formatCtx->interrupt_callback.opaque = NULL;
        self.formatCtx->interrupt_callback.callback = NULL;
        avformat_close_input(&_formatCtx);
        self.formatCtx = NULL;
    }
}

- (void)closeAudioStream{
    self.audioStreamIndex = -1;
    
    if (self.swrBuffer) {
        free(self.swrBuffer);
        self.swrBuffer = NULL;
        self.swrBufferSize = 0;
    }
    
    if (self.swrCtx) {
        swr_free(&_swrCtx);
        _swrCtx = NULL;
    }
    
    if (self.audioFrame) {
        av_free(self.audioFrame);
        self.audioFrame = NULL;
    }
    
    if (self.audioCodecCtx) {
        avcodec_close(self.audioCodecCtx);
        self.audioCodecCtx = NULL;
    }
    
    if (self.lastFrame) {
        self.lastFrame = nil;
    }
}


#pragma mark - c method
// 超时回调
static int interrupt_callback(void *ctx)
{
    if (!ctx){
        return 0;
    }
    __unsafe_unretained HXDecoder *decoder = (__bridge HXDecoder *)ctx;
    const BOOL isInterrupt = [decoder detectInterrupted];
    if (isInterrupt) {
        NSLog(@"DEBUG: INTERRUPT_CALLBACK!");
    }
    return isInterrupt;
}

// 查找文件中的音频流
static NSArray *collectStreamIndexs(AVFormatContext *formatCtx, enum AVMediaType codecType)
{
    NSMutableArray *streamIndexs = [NSMutableArray array];
    for (NSInteger i = 0; i < formatCtx->nb_streams; ++i)
        if (codecType == formatCtx->streams[i]->codecpar->codec_type){
            [streamIndexs addObject: [NSNumber numberWithInteger: i]];
        }
    return [streamIndexs copy];
}

// 设置timeBase和fps
static void avStreamFPSTimeBase(AVStream *stream, AVCodecContext *codecCtx, CGFloat defaultTimeBase, CGFloat *pTimeBase)
{
    CGFloat timebase;
    
    if (stream->time_base.den && stream->time_base.num){
        timebase = av_q2d(stream->time_base);
    }else if (codecCtx->time_base.den && stream->time_base.num){
        timebase = av_q2d(codecCtx->time_base);
    }else{
        timebase = defaultTimeBase;
    }
    
    if (codecCtx->ticks_per_frame != 1) {
        NSLog(@"WARNING: codec.ticks_per_frame=%d", codecCtx->ticks_per_frame);
    }
    
    if (pTimeBase){
        *pTimeBase = timebase;
    }
}
@end
