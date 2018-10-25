//
//  HXAudioPlayer.m
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/20.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import "HXAudioPlayer.h"
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#import "HXAudioSession.h"

static const AudioUnitElement inputElement = 1;

@interface HXAudioPlayer ()

@property (nonatomic, assign) AUGraph auGraph;

@property (nonatomic, assign) AUNode ioNode;
@property (nonatomic, assign) AudioUnit ioUnit;

@property (nonatomic, assign) AUNode convertNode;
@property (nonatomic, assign) AudioUnit convertUnit;

@property (nonatomic, assign) SInt16 *outputData;

@property (nonatomic, weak) id<HXFillAudioDataDelegate> delegate;

@end

@implementation HXAudioPlayer

#pragma mark - life cycle
- (instancetype)initWithCahnnels:(NSInteger)channels sampleRate:(NSInteger) sampleRate bytesPerSample:(NSInteger)bytesPerSample fillDataDelegate:(id<HXFillAudioDataDelegate>)delegate{
    self = [super init];
    if (self) {
        [[HXAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord];
        [[HXAudioSession sharedInstance] setPreferredSampleRate:bytesPerSample];
        [[HXAudioSession sharedInstance] setActive:YES];
        [[HXAudioSession sharedInstance] addRouteChangeListener];
        [self addAudioSessionInterruptedObserver];
        self.outputData = (SInt16 *)calloc(8192, sizeof(SInt16));
        self.delegate = delegate;
        self.sampleRate = sampleRate;
        self.channels = channels;
        [self creatAudioUnitGraph];
    }
    return self;
}

- (void)dealloc{
    if (self.outputData) {
        free(self.outputData);
        self.outputData = NULL;
    }
    
    [self destroyAudioUnitGraph];
    [self removeAudioSessionInterruptedObserver];
}

#pragma mark - public method
- (void)play{
    OSStatus status = AUGraphStart(_auGraph);
    CheckStatus(status, @"Could not start AUGraph", YES);
}

- (void)stop{
    OSStatus status = AUGraphStop(_auGraph);
    CheckStatus(status, @"Could not stop AUGraph", YES);
}

#pragma mark - private method
- (void)creatAudioUnitGraph{
    OSStatus status = noErr;
    
    status = NewAUGraph(&_auGraph);
    CheckStatus(status, @"Could not create a new AUGraph", YES);
    
    [self addAudioUnitNodes];
    
    status = AUGraphOpen(self.auGraph);
    CheckStatus(status, @"Could not open AUGraph", YES);
    
    [self getUnitsFromNodes];
    
    [self setupAudioUnitProperties];
    
    [self makeNodeConnections];
    
    CAShow(_auGraph);
    
    status = AUGraphInitialize(_auGraph);
    CheckStatus(status, @"Could not initialize AUGraph", YES);
}

- (void)addAudioUnitNodes{
    OSStatus status = noErr;
    
    // IONode
    AudioComponentDescription ioDescription;
    bzero(&ioDescription, sizeof(ioDescription));
    ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioDescription.componentType = kAudioUnitType_Output;
    ioDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    status = AUGraphAddNode(self.auGraph, &ioDescription, &_ioNode);
    CheckStatus(status, @"Could not add I/O node to AUGraph", YES);
    
    // ConvertNode
    AudioComponentDescription convertDescription;
    bzero(&convertDescription, sizeof(convertDescription));
    convertDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    convertDescription.componentType = kAudioUnitType_FormatConverter;
    convertDescription.componentSubType = kAudioUnitSubType_AUConverter;
    status = AUGraphAddNode(self.auGraph, &convertDescription, &_convertNode);
    CheckStatus(status, @"Could not add convert node to AUGraph", YES);
}

- (void)destroyAudioUnitGraph{
    
    AUGraphStop(self.auGraph);
    AUGraphUninitialize(self.auGraph);
    AUGraphClose(self.auGraph);
    AUGraphRemoveNode(self.auGraph, self.ioNode);
    DisposeAUGraph(self.auGraph);
    self.ioUnit = NULL;
    self.ioNode = 0;
    self.auGraph = NULL;
}


- (void)getUnitsFromNodes{
    OSStatus status = noErr;
    
    status = AUGraphNodeInfo(self.auGraph, self.ioNode, NULL, &_ioUnit);
    CheckStatus(status, @"Could not retrieve node info for I/O node", YES);
    
    status = AUGraphNodeInfo(self.auGraph, self.convertNode, NULL, &_convertUnit);
    CheckStatus(status, @"Could not retrieve node info for Convert node", YES);
}

- (void)setupAudioUnitProperties{
    OSStatus status = noErr;
    AudioStreamBasicDescription streamFormat = [self nonInterleavedPCMFormatWithChannels:self.channels];
    
    status = AudioUnitSetProperty(self.ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputElement, &streamFormat, sizeof(streamFormat));
    CheckStatus(status, @"Could not set stream format on I/O unit output scope", YES);
    
    AudioStreamBasicDescription clientFormat16int;
    UInt32 bytesPerSample = sizeof (SInt16);
    bzero(&clientFormat16int, sizeof(clientFormat16int));
    clientFormat16int.mFormatID          = kAudioFormatLinearPCM;
    clientFormat16int.mFormatFlags       = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    clientFormat16int.mBytesPerPacket    = bytesPerSample * self.channels;
    clientFormat16int.mFramesPerPacket   = 1;
    clientFormat16int.mBytesPerFrame     = bytesPerSample * self.channels;
    clientFormat16int.mChannelsPerFrame  = self.channels;
    clientFormat16int.mBitsPerChannel    = 8 * bytesPerSample;
    clientFormat16int.mSampleRate        = _sampleRate;
    
    status =AudioUnitSetProperty(self.convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &streamFormat, sizeof(streamFormat));
    CheckStatus(status, @"augraph recorder normal unit set client format error", YES);
    
    status = AudioUnitSetProperty(self.convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &clientFormat16int, sizeof(clientFormat16int));
    CheckStatus(status, @"augraph recorder normal unit set client format error", YES);
}

- (AudioStreamBasicDescription)nonInterleavedPCMFormatWithChannels:(UInt32)channels{
    UInt32 bytesPerSample = sizeof(Float32);
    
    AudioStreamBasicDescription asbDescription;
    bzero(&asbDescription, sizeof(asbDescription));
    asbDescription.mFormatID = kAudioFormatLinearPCM;
    asbDescription.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    asbDescription.mSampleRate = self.sampleRate;
    asbDescription.mBitsPerChannel = 8 * bytesPerSample;
    asbDescription.mBytesPerFrame = bytesPerSample;
    asbDescription.mBytesPerPacket = bytesPerSample;
    asbDescription.mFramesPerPacket = 1;
    asbDescription.mChannelsPerFrame = channels;
    
    return asbDescription;
}

- (void)makeNodeConnections{
    OSStatus status = noErr;
    
    status = AUGraphConnectNodeInput(self.auGraph, self.convertNode, 0, self.ioNode, 0);
    CheckStatus(status, @"Could not connect I/O node input to mixer node input", YES);
    
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = &InputRenderCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)self;
    
    status = AudioUnitSetProperty(self.convertUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callbackStruct, sizeof(callbackStruct));
    CheckStatus(status, @"Could not set render callback on mixer input scope, element 1", YES);
}

- (OSStatus)renderData:(AudioBufferList *)ioData atTimeStamp:(const AudioTimeStamp *)timeStamp forElement:(UInt32)element numberFrames:(UInt32)numFrames flags:(AudioUnitRenderActionFlags *)flags
{
    @autoreleasepool {
        for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
            memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);
        }
        if(self.delegate)
        {
            
            [self.delegate fillAudioData:_outputData numFrames:numFrames numChannels:self.channels];
            for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
                memcpy((SInt16 *)ioData->mBuffers[iBuffer].mData, self.outputData, ioData->mBuffers[iBuffer].mDataByteSize);
            }
        }
        return noErr;
    }
}

#pragma mark - AVAudioSessionInterruptionNotification
- (void)addAudioSessionInterruptedObserver{
    [self removeAudioSessionInterruptedObserver];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onNotificationAudioInterrupted:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
}

- (void)removeAudioSessionInterruptedObserver{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
}

- (void)onNotificationAudioInterrupted:(NSNotification *)sender {
    AVAudioSessionInterruptionType interruptionType = [[[sender userInfo] objectForKey:AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    switch (interruptionType) {
        case AVAudioSessionInterruptionTypeBegan:
            [self stop];
            break;
        case AVAudioSessionInterruptionTypeEnded:
            [self play];
            break;
        default:
            break;
    }
}

#pragma mark - c method
static OSStatus InputRenderCallback(void *inRefCon,
                                    AudioUnitRenderActionFlags *ioActionFlags,
                                    const AudioTimeStamp *inTimeStamp,
                                    UInt32 inBusNumber,
                                    UInt32 inNumberFrames,
                                    AudioBufferList *ioData){
    HXAudioPlayer *auidoPlayer = (__bridge id)inRefCon;
    return [auidoPlayer renderData:ioData
                       atTimeStamp:inTimeStamp
                        forElement:inBusNumber
                      numberFrames:inNumberFrames
                             flags:ioActionFlags];
    
}


static void CheckStatus(OSStatus status, NSString *message, BOOL fatal){
    if(status != noErr){
        char fourCC[16];
        *(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
        fourCC[4] = '\0';
        
        if(isprint(fourCC[0]) && isprint(fourCC[1]) && isprint(fourCC[2]) && isprint(fourCC[3])){
            NSLog(@"%@: %s", message, fourCC);
        }else{
            NSLog(@"%@: %d", message, (int)status);
        }
        if(fatal){
            exit(-1);
        }
    }
}

@end
