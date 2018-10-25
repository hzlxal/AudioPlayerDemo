//
//  HXCacheAPIProxy.m
//  WeiboDemo
//
//  Created by hzl on 2018/6/27.
//  Copyright © 2018年 hzl. All rights reserved.
//

#import "HXCacheAPIProxy.h"
#import "YYCache.h"

// 通过key从缓存的数据字典中取出相应的value
static NSString *const kHXAudioPlayerCacheKeyCacheData = @"hx.kHXNetWorkingCacheKeyCacheData";
static NSString *const kHXAudioPlayerCacheKeyCacheTime = @"hx.kHXNetWorkingCacheKeyCacheTime";
static NSString *const kHXAudioPlayerCacheKeyCacheExpirationTime = @"hx.kHXNetWorkingCacheKeyCacheExpirationTime";


static NSString *const kHXAudioPlayerCache = @"kHXNetWorkingCahce";

@interface HXCacheAPIProxy()<NSCopying, NSMutableCopying>
@property (nonatomic, strong) YYCache *cache;
@end

@implementation HXCacheAPIProxy
#pragma mark - public method

- (id)cacheForUrl:(NSString *)url{
   return [self cacheForKey:url];
}

- (void)setCacheWithObject:(id)object url:(NSString *)url cacheExpirationTime:(NSTimeInterval)expirationTime{
    [self setCacheWithObject:object forKey:url cacheExpirationTime:expirationTime];
}

- (BOOL)hasCacheWithUrl:(NSString *)url{
   return [self.cache containsObjectForKey:url];
}

#pragma mark - private method

- (void)setCacheWithObject:(id)object forKey:(NSString *)key cacheExpirationTime:(NSTimeInterval)expirationTime{
    if (!object) {
        NSLog(@"[%@]:<%s>:data is nil",NSStringFromClass([self class]), __func__);
    }
    
    NSDictionary *cacheDic = @{kHXAudioPlayerCacheKeyCacheData : object,
                               kHXAudioPlayerCacheKeyCacheTime : @([NSDate timeIntervalSinceReferenceDate]),
                     kHXAudioPlayerCacheKeyCacheExpirationTime : @(expirationTime)
                           };
    [self.cache setObject:cacheDic forKey:key];
    NSLog(@"写入缓存成功 key为:%@",key);
}


- (id)cacheForKey:(NSString *)key{
    NSDictionary *cacheDic = (NSDictionary *)[self.cache objectForKey:key];
    
    id cacheData = cacheDic[kHXAudioPlayerCacheKeyCacheData];
    NSTimeInterval cacheTimeIterval = [cacheDic[kHXAudioPlayerCacheKeyCacheTime] doubleValue];
    NSTimeInterval cacheExpirationTime = [cacheDic[kHXAudioPlayerCacheKeyCacheExpirationTime] doubleValue];
    
    NSTimeInterval nowTimeInterval = [NSDate timeIntervalSinceReferenceDate];
    
    // 超时处理
    if (cacheData && (nowTimeInterval - cacheTimeIterval > cacheExpirationTime)) {
        NSLog(@"cache 过期 key : %@",key);
        [self.cache removeObjectForKey:key];
        return nil;
    }
    
    return cacheData;
}


#pragma mark - singal patterns method

static HXCacheAPIProxy *_instance = nil;
+ (instancetype)shareInstance{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[HXCacheAPIProxy alloc] init];
    });
    
    return _instance;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [super allocWithZone:zone];
    });
    return _instance;
}

- (nonnull id)copyWithZone:(nullable NSZone *)zone {
    return _instance;
}

- (nonnull id)mutableCopyWithZone:(nullable NSZone *)zone {
    return  _instance;
}

#pragma mark - getter && setter

- (YYCache *)cache{
    if (!_cache) {
        _cache = [[YYCache alloc] initWithName:kHXAudioPlayerCache];
    }
    return _cache;
}

- (void)cleanCache
{
    [self.cache removeAllObjects];
}

@end
