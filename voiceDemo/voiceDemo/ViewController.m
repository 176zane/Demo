//
//  ViewController.m
//  RLAudioRecord
//
//  Created by Rachel on 16/2/26.
//  Copyright © 2016年 Rachel. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

#import "RecorderManager.h"
#import "PlayerManager.h"
#import "LKChatManager.h"

#import "NSMutableURLRequest+PostFile.h"


# define COUNTDOWN 60

@interface ViewController () <RecordingDelegate, PlayingDelegate> {

    NSTimer *_timer; //定时器
    NSInteger countDown;  //倒计时
}

@property (weak, nonatomic) IBOutlet UILabel *noticeLabel;

//@property (nonatomic, strong) AVAudioSession *session;
//
//
//@property (nonatomic, strong) AVAudioRecorder *recorder;//录音器
//
//@property (nonatomic, strong) AVAudioPlayer *player; //播放器
//@property (nonatomic, strong) NSURL *recordFileUrl; //文件地址

@property (weak, nonatomic) IBOutlet UIButton *recordBtn;
@property (weak, nonatomic) IBOutlet UIButton *stopBtn;
@property (weak, nonatomic) IBOutlet UIButton *playBtn;

@property (strong, nonatomic) UIImageView *voiceLevelImageView;

@property (nonatomic, copy) NSString *filename;
@property (nonatomic, assign) BOOL isPlaying;

@property (nonatomic, strong) NSString *downloadUrl;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [[LKChatManager shareManager] setUserID:@"110"];
}



- (IBAction)startRecord:(id)sender {
//    self.recordBtn.enabled = NO;
//    self.stopBtn.enabled = YES;
//    self.playBtn.enabled = NO;

    [[LKChatManager shareManager] starRecordingWithCallBack:^(NSString *authorized) {
        NSLog(@"hadAuthorized : %@", authorized);
    }];
    
//    AVAudioSession *session =[AVAudioSession sharedInstance];
//    NSError *sessionError;
//    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&sessionError];
//    
//    if (session == nil) {
//        
//        NSLog(@"Error creating session: %@",[sessionError description]);
//        
//    }else{
//        [session setActive:YES error:nil];
//        
//    }
//    
//    self.session = session;
//    
//    
//    //1.获取沙盒地址
//    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
//    filePath = [path stringByAppendingString:@"/RRecord.caf"];
//    
//    //2.获取文件路径
//    self.recordFileUrl = [NSURL fileURLWithPath:filePath];
//    
//    //设置参数
//    NSDictionary *recordSetting = [[NSDictionary alloc] initWithObjectsAndKeys:
//                                     //采样率  8000/11025/22050/44100/96000（影响音频的质量）
//                                   [NSNumber numberWithFloat: 8000.0],AVSampleRateKey,
//                                   // 音频格式
//                                   [NSNumber numberWithInt: kAudioFormatLinearPCM],AVFormatIDKey,
//                                   //采样位数  8、16、24、32 默认为16
//                                   [NSNumber numberWithInt:16],AVLinearPCMBitDepthKey,
//                                   // 音频通道数 1 或 2
//                                   [NSNumber numberWithInt: 1], AVNumberOfChannelsKey,
//                                   //录音质量
//                                   [NSNumber numberWithInt:AVAudioQualityHigh],AVEncoderAudioQualityKey,
//                                   nil];
//
//    
//    _recorder = [[AVAudioRecorder alloc] initWithURL:self.recordFileUrl settings:recordSetting error:nil];
//    
//    if (_recorder) {
//        
//        _recorder.meteringEnabled = YES;
//        [_recorder prepareToRecord];
//        [_recorder record];
//        
//        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//            
//            [self stopRecord:nil];
//        });
//        
//        
//        
//    }else{
//        NSLog(@"音频格式和文件存储格式不匹配,无法初始化Recorder");
//        
//    }
    
    
    



}


- (IBAction)stopRecord:(id)sender {
//    self.recordBtn.enabled = YES;
//    self.stopBtn.enabled = NO;
//    self.playBtn.enabled = YES;
    
    [[LKChatManager shareManager] stopRecordingWithCallBack:^(NSString *filename) {
        NSLog(@"filename : %@", filename);
        _filename = filename;
    }];
    
//    if (_voiceLevelImageView) {
//        [_voiceLevelImageView removeFromSuperview];
//        _voiceLevelImageView = nil;
//    }
    
//    NSFileManager *manager = [NSFileManager defaultManager];
//    if ([manager fileExistsAtPath:self.filename]){
//        _noticeLabel.text = [NSString stringWithFormat:@"录了 %ld 秒,文件大小为 %.2fKb",COUNTDOWN - (long)countDown,[[manager attributesOfItemAtPath:self.filename error:nil] fileSize]/1024.0];
//    }
}


- (IBAction)cancelRecord:(id)sender {
    
    [[LKChatManager shareManager] cancelRecording];
}

static int i = 1;

- (IBAction)PlayRecord:(id)sender {
    self.recordBtn.enabled = YES;
    self.stopBtn.enabled = YES;
    self.playBtn.enabled = YES;
    
    NSLog(@"播放录音");

//    if (!self.isPlaying) {
//        [PlayerManager sharedManager].delegate = nil;
//        
//        self.isPlaying = YES;
//        self.noticeLabel.text = [NSString stringWithFormat:@"正在播放: %@", [self.filename substringFromIndex:[self.filename rangeOfString:@"Documents"].location]];
//        [[PlayerManager sharedManager] playAudioWithFileName:self.filename delegate:self];
//    }
//    else {
//        self.isPlaying = NO;
//        [[PlayerManager sharedManager] stopPlaying];
//    }
    
    [[LKChatManager shareManager] playRecordingWithFilename:_filename callBack:^(BOOL isSuccess) {
            NSLog(@"playRecordingWithCallBack : %@", isSuccess?@"success":@"fail");
    }];
}

- (IBAction)stopPlay:(id)sender {
    [[LKChatManager shareManager] stopPlayingRecordingWithCallBack:^(BOOL isSuccess) {
        NSLog(@"stop playing : %@", isSuccess?@"success":@"fail");
    }];
}


- (IBAction)postFile:(id)sender {
//    //url
//    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://pandamjupload.lkgame.com/api/uploadlog"]];
//    
//    //post请求
//    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url andFilenName:@"gauss.snd" andLocalFilePath:self.filename];
//    
//    //连接(NSURLSession)
//    NSURLSession *session = [NSURLSession sharedSession];
//    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
//        
//        NSLog(@"thread : %@", [NSThread currentThread]);
//        
//        NSLog(@"respond data : %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
//    }];
//    [dataTask resume];
    
    [[LKChatManager shareManager] uploadRecordingWithFilename:_filename callBack:^(BOOL isSuccess, NSString *downloadUrl) {
        if (isSuccess) {
            _downloadUrl = downloadUrl;
        }
        NSLog(@"isSuccess : %@, downloadUrl : %@", isSuccess?@"YES":@"NO", downloadUrl);
    }];
}


- (IBAction)downloadFile:(id)sender {
//    NSURL* url = [NSURL URLWithString:@"https://pandamjupload.lkgame.com/Upload/Logs/gauss.snd"];
//    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:url] queue:[[NSOperationQueue alloc] init] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
//        
//        NSLog(@"thread : %@", [NSThread currentThread]);
//        
//        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
//        NSString *documentsDirectory = [paths objectAtIndex:0];
//        NSString *voiceDirectory = [documentsDirectory stringByAppendingPathComponent:@"voice"];
//        if ( ! [[NSFileManager defaultManager] fileExistsAtPath:voiceDirectory]) {
//            [[NSFileManager defaultManager] createDirectoryAtPath:voiceDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
//        }
//        self.filename = [voiceDirectory stringByAppendingPathComponent:@"gauss.spx"];
//        
//        [data writeToFile:self.filename atomically:YES];
//    }];

    [[LKChatManager shareManager] downloadRecordingWithUrl:@"https://pandamjupload.lkgame.com/Upload/Logs/1092_1495786377_1_1248.snd"/*_downloadUrl*/ callBack:^(BOOL isSuccess, NSString *filename, NSInteger duration) {
        NSLog(@"downloadFileSuccess : %@, filename : %@, duration : %ld", isSuccess?@"YES":@"NO", filename, duration);
        [[LKChatManager shareManager] playRecordingWithFilename:filename callBack:^(BOOL isSuccess) {
            NSLog(@"isSuccess : %@", isSuccess?@"YES":@"NO");
        }];
    }];
}




#pragma mark - Recording & Playing Delegate

- (void)recordingFinishedWithFileName:(NSString *)filePath time:(NSTimeInterval)interval {
    
//    self.filename = filePath;
//    NSFileManager *manager = [NSFileManager defaultManager];
//    if ([manager fileExistsAtPath:self.filename]){
//        dispatch_async(dispatch_get_main_queue(), ^{
//           _noticeLabel.text = [NSString stringWithFormat:@"录了 %ld 秒,文件大小为 %.2fKb",COUNTDOWN - (long)countDown,[[manager attributesOfItemAtPath:self.filename error:nil] fileSize]/1024.0];
//        });
//    }

}

- (void)recordingTimeout {
    self.noticeLabel.text = @"录音超时";
}

- (void)recordingStopped {
    self.recordBtn.enabled = YES;
    self.stopBtn.enabled = NO;
    self.playBtn.enabled = YES;

}

- (void)recordingFailed:(NSString *)failureInfoString {
    self.recordBtn.enabled = YES;
    self.stopBtn.enabled = NO;
    self.playBtn.enabled = NO;
    self.noticeLabel.text = @"录音失败";
}

- (void)levelMeterChanged:(float)levelMeter {
    
    float result  = 10 * (float)levelMeter;
//    NSLog(@"levelMeter : %.0f", result);
    int no = 0;
    if (result > 0 && result <= 1.3) {
        no = 1;
    } else if (result > 1.3 && result <= 2) {
        no = 2;
    } else if (result > 2 && result <= 3.0) {
        no = 3;
    } else if (result > 3.0 && result <= 3.0) {
        no = 4;
    } else if (result > 5.0 && result <= 10) {
        no = 5;
    } else if (result > 10 && result <= 40) {
        no = 6;
    } else if (result > 40) {
        no = 7;
    }
    
    if (!_voiceLevelImageView) {
        _voiceLevelImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
        _voiceLevelImageView.center = self.view.center;
        _voiceLevelImageView.userInteractionEnabled = YES;
        [self.view addSubview:_voiceLevelImageView];
        NSLog(@"_voiceLevelImageView : %@", NSStringFromCGRect(_voiceLevelImageView.frame));
    }
    
    NSString *imageName = [NSString stringWithFormat:@"mic_%d", no];
    _voiceLevelImageView.image = [UIImage imageNamed:imageName];
}

- (void)playingStoped {
    self.isPlaying = NO;
//    NSFileManager *manager = [NSFileManager defaultManager];
//    if ([manager fileExistsAtPath:self.filename]){
//        dispatch_async(dispatch_get_main_queue(), ^{
//            _noticeLabel.text = [NSString stringWithFormat:@"录了 %ld 秒,文件大小为 %.2fKb",COUNTDOWN - (long)countDown,[[manager attributesOfItemAtPath:self.filename error:nil] fileSize]/1024.0];
//        });
//    }
}

- (IBAction)delFile:(id)sender {
    [[LKChatManager shareManager] delRecordingWithFilename:_filename];
}


- (IBAction)delAllFiles:(id)sender {
    [[LKChatManager shareManager] delAllRecording];
}


@end
