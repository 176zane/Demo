//
//  Son.m
//  debug
//
//  Created by Deep Thought on 2018/5/1.
//

#import "Son.h"

@implementation Son
+ (void)load {
    NSLog(@"load");
}
- (id)init
{
    self = [super init];
    if (self)
    {
        NSLog(@"%@", NSStringFromClass([self class]));
        NSLog(@"%@", NSStringFromClass([super class]));
    }
    return self;
}

@end
