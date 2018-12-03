//
//  Test.m
//  debug
//
//  Created by Deep Thought on 2018/6/23.
//

#import "Test.h"
#import "Sark.h"

@implementation Test
- (instancetype)init{
    self = [super init];
    if (self) {
        id cls = [Sark class];
        void *obj = &cls;
        [(__bridge id)obj speak];
        
        NSLog(@"obj 地址 = %p",&obj);
        Sark *sark = [[Sark alloc]init];
        NSLog(@"Sark instance = %@ 地址 = %p",sark,&sark);
        
        [sark speak];
    }
    return self;
}

@end
