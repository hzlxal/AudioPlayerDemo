//
//  HXCacheAPIProxy.h
//  WeiboDemo
//
//  Created by hzl on 2018/6/27.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HXCacheAPIProxy : NSObject

+ (instancetype)shareInstance;

- (BOOL)hasCacheWithUrl:(NSString *)url;

- (id)cacheForUrl:(NSString *)url;

- (void)setCacheWithObject:(id)object url:(NSString *)url cacheExpirationTime:(NSTimeInterval)expirationTime;

- (void)cleanCache;

@end
