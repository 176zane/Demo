//
//  Car.m
//  debug
//
//  Created by Deep Thought on 2018/4/27.
//

#import "Car.h"

@interface Car()
@property (nonatomic, strong) NSString *target;
@end

@implementation Car
-(void)run {
    NSLog(@"run");
//    dispatch_queue_t queue = dispatch_queue_create("parallel", DISPATCH_QUEUE_CONCURRENT);
//    for (int i = 0; i < 1000000 ; i++) {
//        dispatch_async(queue, ^{
//            NSString *str = [NSString stringWithFormat:@"%d", i];
//            NSLog(@"%d, %s, %p", i, object_getClassName(str), str);
//            self.target = str;
////            self.target = [NSString stringWithFormat:@"ksddkjalkjd%d",i];
//        });
//    }
}
@end
