//
//  main.m
//  debug
//
//  Created by Deep Thought on 2018/4/27.
//

#import <Foundation/Foundation.h>
#import "runtime.h"
#import "objc-runtime.h"

#import "Son.h"
#import "Car.h"


#import "Test.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        //NSObject * objc = [[NSObject alloc] init];
       //[[Test alloc] init];
       
       
        
//        Car *car = [[Car alloc] init];
//        [car run];
//        NSString *string = [NSString stringWithUTF8String:object_getClassName(car)];
//        
//        NSLog(@"%@",NSStringFromClass([car class])) ;
//        NSLog(@"%@",NSStringFromClass([Car class])) ;
//        
//        Son *son = [[Son alloc] init];
//        
//        
//        
//        NSString *foo = @"foo 123";
//        NSString *boo = [NSString stringWithFormat:@"foo %d",123];
//        NSLog(@"%ld",foo.hash);
//        NSLog(@"%ld",boo.hash);
//        NSLog(@"%p",foo);
//        NSLog(@"%p",boo);
//        NSLog(@"%d",foo == boo);
//        NSLog(@"%@",NSStringFromClass([foo class]));
//        NSLog(@"%@",NSStringFromClass([boo class]));
//        
//        NSLog(@"========");
//        NSObject *object = [NSObject new];
//        // 在 ARC 模式下，通过 __bridge 转换 id 类型为 (void *) 类型
//        NSLog(@"isa: %p ", *(void **)(__bridge void *)object);
//        static void *someKey = &someKey;
//        objc_setAssociatedObject(object, someKey, @"Desgard_Duan", 0);
//        NSLog(@"isa: %p ", *(void **)(__bridge void *)object);
        
        dispatch_queue_t que = dispatch_queue_create("com.zane.concurrentQueue", DISPATCH_QUEUE_CONCURRENT);
        void (^blk)(void) = ^{
            NSLog(@"block");
        };
        blk();
        dispatch_async(que, ^{
            NSLog(@"000");
            dispatch_sync(que, ^{
                NSLog(@"not locked");
            });
            NSLog(@"222");
        });
        NSLog(@"111");
        //dispatch_release(que);
    }
    return 0;
}
