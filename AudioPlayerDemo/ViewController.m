//
//  ViewController.m
//  AudioPlayerDemo
//
//  Created by hzl on 2018/10/20.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import "ViewController.h"
#import "HXAudioPlayerController.h"
#import "HXCacheAPIProxy.h"

@interface ViewController ()

@property (nonatomic, strong) HXAudioPlayerController *player;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.player = [[HXAudioPlayerController alloc] initWithUrlStr:@"http://ws.stream.qqmusic.qq.com/C1000015H75B1NvYzl.m4a?fromtag=0&guid=126548448" playStateDelegate:nil playRange:NSMakeRange(95, 3)];
    self.view.backgroundColor = [UIColor whiteColor];
    
    
    UIButton *btn = [[UIButton alloc] initWithFrame:CGRectMake(100, 100, 50, 50)];
    btn.backgroundColor = [UIColor redColor];
    [btn setTitle:@"play" forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:btn];
    
    
    UIButton *btn1 = [[UIButton alloc] initWithFrame:CGRectMake(100, 200, 50, 50)];
    btn1.backgroundColor = [UIColor redColor];
    [btn1 setTitle:@"pause" forState:UIControlStateNormal];
    [btn1 addTarget:self action:@selector(pause) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:btn1];
    
    UIButton *btn2 = [[UIButton alloc] initWithFrame:CGRectMake(100, 300, 50, 50)];
    btn2.backgroundColor = [UIColor redColor];
    [btn2 setTitle:@"restar" forState:UIControlStateNormal];
    [btn2 addTarget:self action:@selector(restar) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:btn2];
}

- (void)play{
    [[HXCacheAPIProxy shareInstance] cleanCache];
    
    [self.player play];
}

- (void)pause{
    [self.player pause];
}

- (void)restar{
    [self.player restart];
}

@end
