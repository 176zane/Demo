//
//  main.m
//  Characters
//
//  Created by Deep Thought on 2018/4/20.
//  Copyright © 2018年 Zane. All rights reserved.
//

#import <Foundation/Foundation.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {

        
        
        NSString *s = @"\U0001F32D"; // earth globe emoji 🌍
        NSLog(@"The length of %@ is %lu", s, [s length]);
        // => The length of 🌍 is 2
        
        NSUInteger realLength =
        [s lengthOfBytesUsingEncoding:NSUTF32StringEncoding] / 4;
        NSLog(@"The real length of %@ is %lu", s, realLength);
        // => The real length of 🌍 is 1
        
        NSString *s2 = @"e\u0301"; // e + ´
        NSLog(@"The length of %@ is %lu", s2, [s2 length]);
        // => The length of é is 2
        NSString *n = [s2 precomposedStringWithCanonicalMapping];
        NSLog(@"The length of %@ is %lu", n, [n length]);
        // => The length of é is 1
        
        //循环遍历一个字符串
        NSString *s3 = @"The weather on \U0001F30D is \U0001F31E today.";
        // The weather on 🌍 is 🌞 today.
        NSRange fullRange = NSMakeRange(0, [s3 length]);
        [s3 enumerateSubstringsInRange:fullRange
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop)
        {
            NSLog(@"%@ %@", substring, NSStringFromRange(substringRange));
        }];
        
        //isEqual: 和 isEqualToString: 这两个方法都是一个字节一个字节地比较的。如果希望字符串的合成和分解的形式相吻合，得先自己正规化
        NSString *s4 = @"\u00E9"; // é
        NSString *t = @"e\u0301"; // e + ´
        BOOL isEqual = [s4 isEqualToString:t];
        NSLog(@"%@ is %@ to %@", s4, isEqual ? @"equal" : @"not equal", t);
        // => é is not equal to é
        
        // Normalizing to form C
        NSString *sNorm = [s4 precomposedStringWithCanonicalMapping];
        NSString *tNorm = [t precomposedStringWithCanonicalMapping];
        BOOL isEqualNorm = [sNorm isEqualToString:tNorm];
        NSLog(@"%@ is %@ to %@", sNorm, isEqualNorm ? @"equal" : @"not equal", tNorm);
        // => é is equal to é
        
        
        NSString *s5 = @"ff"; // ff
        NSString *t5 = @"\uFB00"; // ﬀ ligature
        NSComparisonResult result = [s5 localizedCompare:t5];
        NSLog(@"%@ is %@ to %@", s5, result == NSOrderedSame ? @"equal" : @"not equal", t5);
        // => ff is equal to ﬀ
        
        
        
        
        
        
        
        
        
        
        
        
        
        
    }
    return 0;
}
