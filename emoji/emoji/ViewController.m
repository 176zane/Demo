//
//  ViewController.m
//  emoji
//
//  Created by mac on 16/10/25.
//  Copyright © 2016年 lkgame. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextField *textField;
@property (weak, nonatomic) IBOutlet UILabel *label;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}
- (IBAction)btnTaped:(id)sender {
    NSString *str = self.textField.text;
    NSUInteger length = str.length;
    NSString *a = @"";
    
    
    NSString * jsonstr = @"{\n";
    for (NSUInteger i = 0; i< str.length; i++) {
        NSRange range = [str rangeOfComposedCharacterSequenceAtIndex:i];
        NSString* temps = @"";
        
        jsonstr = [jsonstr stringByAppendingString:@"\""];
        for (NSUInteger j=range.location, jend = range.location+range.length; j<jend; ++j) {
            unichar ch = [str characterAtIndex:j];
            
            temps = [temps stringByAppendingString:[NSString stringWithFormat:@"%04x", ch]];
            
            jsonstr = [jsonstr stringByAppendingString:@"\\u"];
            jsonstr = [jsonstr stringByAppendingString:[NSString stringWithFormat:@"%04x", ch]];
            if (j!=jend-1)
            {
                temps = [temps stringByAppendingString:@"-"];
            }
        }
        jsonstr = [jsonstr stringByAppendingString:@"\":\""];
        a = [a stringByAppendingString:temps];
        
        i = range.location+range.length-1;
        
        unichar *chs = (unichar *)malloc(sizeof(unichar)*range.length);
        [str getCharacters:chs range:range];
        a = [a stringByAppendingString:@" "];
        a = [a stringByAppendingString:[NSString stringWithCharacters:chs length:range.length]];
        a = [a stringByAppendingString:@"\n"];
        
        // 转换为unicode编码形式
        NSString *pngName = @"";
        unsigned int bits;
        for (int k = 0; k < range.length; k++) {
            unichar  ch = chs[k];
            if (ch >> 8 == 0xD8) {
                unichar ch2 = chs[k+1];
                k = k+1;
            
                unsigned int highBits = ch & 0x3FF;
                unsigned int lowBits = ch2 & 0x3FF;
                
              
                bits = (highBits << 10 ) | lowBits;
                bits += 0x10000;
                
            }else {
                bits = ch;
            }
            pngName = [pngName stringByAppendingString:[NSString stringWithFormat:@"%04x", bits]];
            jsonstr = [jsonstr stringByAppendingString:[NSString stringWithFormat:@"%04x", bits]];
            if (k<range.length-1)
            {
                pngName = [pngName stringByAppendingString:@"-"];
                jsonstr = [jsonstr stringByAppendingString:@"-"];
            }
        }
        jsonstr = [jsonstr stringByAppendingString:@"\",\n"];
        
        
        
        
        
        NSString *emoji = [NSString stringWithCharacters:chs length:range.length];
        free(chs);
        
    
        NSString * filePath = [NSString stringWithFormat:@"/Users/mac/Desktop/emoji2/%@.png",pngName];
        
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(32, 32), NO, 2.0);
        [emoji drawInRect:CGRectMake(1, -2, 32, 33) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:30]}];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        NSData * pic = UIImagePNGRepresentation(image);
        [pic writeToFile:filePath atomically:YES];
        
    }
    jsonstr = [jsonstr stringByAppendingString:@"}"];
    NSString * filePath2 = [NSString stringWithFormat:@"/Users/mac/Desktop/emoji2/emoji.json"];
    
    [jsonstr writeToFile:filePath2 atomically:YES encoding:NSUTF8StringEncoding error:nil];
    self.label.text = a;
 
    
}
- (IBAction)cancleTapped:(id)sender {
    self.textField.text = @"";
    self.label.text = @"";
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)signalBtn:(id)sender {
    [self getSignalStrength];
}

- (void)getSignalStrength{
    UIApplication *app = [UIApplication sharedApplication];
    NSArray *subviews = [[[app valueForKey:@"statusBar"] valueForKey:@"foregroundView"] subviews];
    NSString *dataNetworkItemView = nil;
    
    for (id subview in subviews) {
        if([subview isKindOfClass:[NSClassFromString(@"UIStatusBarDataNetworkItemView") class]]) {
            dataNetworkItemView = subview;
            break;
        }
    }
    
    int signalStrength = [[dataNetworkItemView valueForKey:@"_wifiStrengthBars"] intValue];
    
    NSLog(@"signal %d", signalStrength);
}


@end
