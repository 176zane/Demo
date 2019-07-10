//
//  ViewController.m
//  AudioEncoder
//
//  Created by Deep Thought on 2019/3/31.
//  Copyright © 2019 Zane. All rights reserved.
//

#import "ViewController.h"
#import "Mp3Encoder.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}
- (IBAction)starEncode:(id)sender {
    Mp3Encoder *encoder = new Mp3Encoder;
    encoder->encode();
    delete encoder;
    
}



@end
