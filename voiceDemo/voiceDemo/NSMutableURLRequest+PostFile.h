//
//  NSMutableURLRequest+PostFile.h
//  voiceDemo
//
//  Created by 许桂斌 on 16/12/9.
//  Copyright © 2016年 lkgame. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMutableURLRequest (PostFile)

+ (instancetype)requestWithURL:(NSURL *)url andFilenName:(NSString *)fileName andLocalFilePath:(NSString *)localFilePath;

@end
