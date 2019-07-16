//
//  DownsizeImageViewController.m
//  LargeImageDownsizing
//
//  Created by Deep Thought on 2019/7/2.
//  Copyright © 2019 Zane. All rights reserved.
//

#import "DownsizeImageViewController.h"
#import "UIImageView+DownsizeLargeImage.h"

static NSString *const kLargeImageName = @"large_leaves_70mp.jpg";// 7033x10110 image, 271 MB uncompressed

@interface DownsizeImageViewController () 

//@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;
//@property (nonatomic, strong) UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UIImageView *largeImageView;

@end

@implementation DownsizeImageViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

     [self.largeImageView ybw_setImageWithFilename:kLargeImageName];
}


/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
