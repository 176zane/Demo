//
//  LKChatManager.m
//  voiceDemo
//
//  Created by 许桂斌 on 16/12/17.
//  Copyright © 2016年 lkgame. All rights reserved.
//

#import "LKChatManager.h"
#import "RecorderManager.h"
#import "PlayerManager.h"
#import "NSMutableURLRequest+PostFile.h"
#import <AVFoundation/AVFoundation.h>

#define UploadUrl @"https://pandamjupload.lkgame.com/api/uploadlog"
#define DownloadUrl @"https://pandamjupload.lkgame.com/Upload/Logs/"
NSString *const LKRecorderIsRecordingNotification = @"LKRecorderIsRecordingNotification";

@interface LKChatManager () <RecordingDelegate, PlayingDelegate>

/** 是否正在播放文件名 */
@property (nonatomic, strong) NSString *playingFilename;
/** 是否正在录音 */
@property (nonatomic, assign) BOOL isRecording;
/** 是否授权使用麦克风 */
@property (nonatomic, assign) BOOL hadAuthorized;
/** 用户ID，用于保证文件名唯一 */
@property (nonatomic, strong) NSString *userID;
/** 音频存放路径 */
@property (nonatomic, strong) NSString *voiceDirectory;
/** 停止录音回调 */
@property (nonatomic, copy) void (^stopRecordingCallBack)(NSString *filename);
/** 上传录音回调 */
@property (nonatomic, copy) void (^uploadRecordingCallBack)(BOOL isSuccess, NSString *downloadUrl);
/** 播放录音回调 */
@property (nonatomic, copy) void (^playRecordingCallBack)(BOOL isSuccess);
/** 停止播放录音回调 */
@property (nonatomic, copy) void (^stopPlayingRecordingCallBack)(BOOL isSuccess);

@end

@implementation LKChatManager

static LKChatManager *singleton = nil;
static NSString * const LKUserHasAuthorized = @"LKUserHasAuthorized";

#pragma mark 接口方法
+ (instancetype)shareManager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        singleton = [[self alloc] init];
        singleton.hadAuthorized = NO;
        singleton.isRecording = NO;
        [[NSNotificationCenter defaultCenter] addObserver:singleton selector:@selector(receivedRecordingStateNoticifation:) name:LKRecorderIsRecordingNotification object:nil];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsPath = [paths objectAtIndex:0];
        singleton.voiceDirectory = [documentsPath stringByAppendingPathComponent:@"voice"];
        
        //删除7天以前的音频文件以及取消录音时留下的临时文件
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if (![fileManager fileExistsAtPath:singleton.voiceDirectory]) {
                [fileManager createDirectoryAtPath:singleton.voiceDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
                return;
            }
            NSError *error;
            NSArray *files = [fileManager contentsOfDirectoryAtPath:singleton.voiceDirectory error:&error];
            NSLog(@"directory error : %@", error);
            for (NSString *filename in files) {
                if ([[filename pathExtension] isEqualToString:@"snd"]) {
                    NSArray *components = [filename componentsSeparatedByString:@"_"];
                    NSTimeInterval saveTime = [components[components.count - 3] doubleValue];
                    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
                    if (currentTime - saveTime > 7 * 24 * 3600) {
                        [fileManager removeItemAtPath:[singleton.voiceDirectory stringByAppendingPathComponent:filename] error:&error];
                    }
                } else if ([[filename pathExtension] isEqualToString:@"spx"]) {
                    [fileManager removeItemAtPath:[singleton.voiceDirectory stringByAppendingPathComponent:filename] error:&error];
                }
                if (error) {
                    [[[UIAlertView alloc] initWithTitle:nil message:[NSString stringWithFormat:@"删除文件错误：%@", error] delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil] show];
                }
            }
        });
    });
    return singleton;
}

- (void)starRecordingWithCallBack:(void (^)(NSString *))callBack {
    NSLog(@"starRecordingWithCallBack");
    
    NSLog(@"开始调用录音：%f",[[NSDate date] timeIntervalSinceReferenceDate]);
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            //麦克风权限
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    _hadAuthorized = YES;
                    
                    NSString *authorized = [[NSUserDefaults standardUserDefaults] objectForKey:LKUserHasAuthorized];
                    if (authorized) {
                        callBack(@"success");
                        [RecorderManager sharedManager].delegate = self;
                        [[RecorderManager sharedManager] startRecording];
                    } else {
                        callBack(@"first");
                    }
                    [[NSUserDefaults standardUserDefaults] setObject:@"yes" forKey:LKUserHasAuthorized];
                    
                } else {
                    _hadAuthorized = NO;
                    callBack(@"fail");
                    [[NSUserDefaults standardUserDefaults] setObject:nil forKey:LKUserHasAuthorized];
                    [[[UIAlertView alloc] initWithTitle:@"请允许游戏使用麦克风" message:@"请在系统的设置>隐私>麦克风界面允许游戏使用您的麦克风" delegate:self cancelButtonTitle:@"取消" otherButtonTitles:@"确定", nil] show];
                }
            });
        }];
    });
    
    if (_hadAuthorized) {
        callBack(@"success");
        NSLog(@"录音开始已经回调：%f",[[NSDate date] timeIntervalSinceReferenceDate]);
        [RecorderManager sharedManager].delegate = self;
        [[RecorderManager sharedManager] startRecording];
    }
}

- (void)cancelRecording {
    NSLog(@"cancelRecording");
    
    BOOL setCategory = [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    BOOL active = [[AVAudioSession sharedInstance] setActive:YES error:nil];
    NSLog(@"取消录音setCategory: %@,sessionActive：%@",setCategory ? @"yes" : @"no",active ? @"yes" : @"no");
    [[RecorderManager sharedManager] cancelRecording];
}

- (BOOL)recordingState {
    return self.isRecording;
}

- (void)stopRecordingWithCallBack:(void (^)(NSString *))callBack {
    NSLog(@"stopRecordingWithCallBack");
    _stopRecordingCallBack = callBack;
    
    [[RecorderManager sharedManager] stopRecording];
}

- (void)playRecordingWithFilename:(NSString *)filename callBack:(void (^)(BOOL))callBack {
    if (self.isRecording) {
        NSLog(@"录音时点击播放");
        callBack(NO);
        return;
    }
    NSLog(@"playRecordingWithFilename:%@", filename);
    //文件名为空，则直接返回播放失败
    if ([filename isEqualToString:@""] || !filename) {
        if (callBack) {
            callBack(NO);
        }
        return;
    }
    //如果当前真在播放的语音未播放完，则先停止当前语音，再播放新语音
    if ([_playingFilename isEqualToString:filename]) return;
    if (_playingFilename != nil) {
        [[PlayerManager sharedManager] stopPlaying];
    }
    
    _playingFilename = filename;
    _playRecordingCallBack = callBack;
    
    [[PlayerManager sharedManager] playAudioWithFileName:[_voiceDirectory stringByAppendingPathComponent:filename] delegate:self];
}

- (void)stopPlayingRecordingWithCallBack:(void (^)(BOOL))callBack {
    NSLog(@"stopPlayingRecordingWithCallBack");
    _stopPlayingRecordingCallBack = callBack;
    
    [[PlayerManager sharedManager] stopPlaying];
}

- (void)uploadRecordingWithFilename:(NSString *)filename callBack:(void (^)(BOOL, NSString *))callBack {
    NSLog(@"uploadRecordingWithFilename:%@", filename);
    _uploadRecordingCallBack = callBack;
    
    //url
    NSURL *url = [NSURL URLWithString:UploadUrl];
    
    //post请求
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url andFilenName:filename andLocalFilePath:[_voiceDirectory stringByAppendingPathComponent:filename]];
    
    NSLog(@"request url : %@", request.URL);
    
    //连接(NSURLSession)
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        NSLog(@"error : %@", error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        NSString *responseStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
        NSLog(@"thread : %@", [NSThread currentThread]);
        
        NSLog(@"respond data : %@, stateCode : %ld %@", responseStr, httpResponse.statusCode, response);
        
        if (error || [responseStr isEqualToString:@"-1"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (_uploadRecordingCallBack) {
                    _uploadRecordingCallBack(NO, @"");
                    _uploadRecordingCallBack = nil;
                }
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (_uploadRecordingCallBack) {
                    _uploadRecordingCallBack(YES, [DownloadUrl stringByAppendingString:filename]);
                    _uploadRecordingCallBack = nil;
                }
            });
        }
        
    }];
    [dataTask resume];
}

- (void)downloadRecordingWithUrl:(NSString *)url callBack:(void (^)(BOOL, NSString *, NSInteger))callBack {
    NSLog(@"downloadRecordingWithUrl:%@", url);
    
    NSString *filename = [url lastPathComponent];
    
    NSInteger duration = 0;
    NSInteger fileSize = 0;
    if ([[filename pathExtension] isEqualToString:@"snd"]) {
        NSArray *components = [[filename substringToIndex:filename.length - 4] componentsSeparatedByString:@"_"];
        duration = [components[components.count - 2] integerValue];
        fileSize = [components[components.count - 1] integerValue];
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isExist = [fileManager fileExistsAtPath:[_voiceDirectory stringByAppendingPathComponent:filename]];
    
    if (isExist) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (callBack) {
                callBack(YES, filename, duration);
            }
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]] queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                
                NSHTTPURLResponse *httpRespond = (NSHTTPURLResponse *)response;
                
                NSLog(@"response statusCode : %ld", httpRespond.statusCode);
                NSLog(@"thread : %@", [NSThread currentThread]);
                NSLog(@"url : %@", url);
                NSLog(@"file size : %ld", data.length);
                
                if (httpRespond.statusCode == 200 && data.length == fileSize) {
                    NSString *filePath = [_voiceDirectory stringByAppendingPathComponent:filename];
                    
                    BOOL isSuccess = [data writeToFile:filePath atomically:YES];
                    NSLog(@"writeToFile isSuccess : %@", isSuccess?@"YES":@"NO");
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (callBack) {
                            callBack(YES, filename, duration);
                        }
                    });
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (callBack) {
                            callBack(NO, @"", 0);
                        }
                    });
                }
            }];
        });
    }
}

- (BOOL)delRecordingWithFilename:(NSString *)filename {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *filePath = [_voiceDirectory stringByAppendingPathComponent:filename];
    if (![fileManager fileExistsAtPath:filePath]) return NO;
    NSError *error;
    [fileManager removeItemAtPath:filePath error:&error];
    NSLog(@"error : %@", error);
    return YES;
}

- (BOOL)delAllRecording {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:_voiceDirectory]) return NO;
    NSError *error;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:_voiceDirectory error:&error];
    NSLog(@"directory error : %@", error);
    for (int i = 0; i < files.count; i++) {
        NSLog(@"files[%d] : %@", i, files[i]);
        [fileManager removeItemAtPath:[_voiceDirectory stringByAppendingPathComponent:files[i]] error:&error];
        NSLog(@"files[%d] error : %@", i, error);
    }
    return YES;
}

#pragma mark RecordingDelegate代理方法
- (void)recordingFinishedWithFileName:(NSString *)filePath time:(NSTimeInterval)interval {
    NSLog(@"recordingFinishedWithFileName");
    BOOL setCategory = [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    BOOL active = [[AVAudioSession sharedInstance] setActive:YES error:nil];
    NSLog(@"录音完成回调setCategory: %@,sessionActive：%@",setCategory ? @"yes" : @"no",active ? @"yes" : @"no");
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        //通过移动该文件对文件重命名
        NSString *filename = [NSString stringWithFormat:@"%@_%.0f_%.0f_%llu.snd", _userID, [[NSDate date] timeIntervalSince1970], interval, [[fileManager attributesOfItemAtPath:filePath error:nil] fileSize]];
        NSLog(@"filename : %@", filename);
        
        NSString *moveToPath = [_voiceDirectory stringByAppendingPathComponent:filename];
        BOOL isSuccess = [fileManager moveItemAtPath:filePath toPath:moveToPath error:nil];
        if (isSuccess) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (_stopRecordingCallBack) {
                    _stopRecordingCallBack(filename);
                    _stopRecordingCallBack = nil;
                }
            });
        } else {
            NSLog(@"rename fail");
        }
    });
}

- (void)recordingFailed:(NSString *)failureInfoString {
    NSLog(@"recordingFailed");
    BOOL setCategory = [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    BOOL active = [[AVAudioSession sharedInstance] setActive:YES error:nil];
    NSLog(@"录音失败回调setCategory: %@,sessionActive：%@",setCategory ? @"yes" : @"no",active ? @"yes" : @"no");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_stopRecordingCallBack) {
            _stopRecordingCallBack(@"");
            _stopRecordingCallBack = nil;
        }
    });
}

- (void)recordingStopped {
    NSLog(@"recordingStopped");
}

- (void)recordingTimeout {
    NSLog(@"recordingTimeout");
}

#pragma mark PlayingDelegate代理方法
- (void)playingStoped {
    NSLog(@"playingStoped");
    _playingFilename = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_stopPlayingRecordingCallBack) {
            if (_playRecordingCallBack) {
                _playRecordingCallBack(NO);
                _playRecordingCallBack = nil;
            }
            _stopPlayingRecordingCallBack(YES);
            _stopPlayingRecordingCallBack = nil;
        } else if (_playRecordingCallBack) {
            _playRecordingCallBack(YES);
            _playRecordingCallBack = nil;
        }
    });
}

#pragma mark UIAlertViewDelegate代理方法
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        NSURL *url = nil;
        if ([[[UIDevice currentDevice] systemVersion] floatValue] > 7.9) {
            url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        } else {
            url = [NSURL URLWithString:@"perfs:root=LOCATION_SERVICES"];
        }
        if([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication  sharedApplication] openURL:url];
        }
    }
}

#pragma mark Recording状态通知处理
- (void)receivedRecordingStateNoticifation:(NSNotification *)noti {
    self.isRecording = [[noti.userInfo objectForKey:@"state"] boolValue];
    NSLog(@"录音状态改变：%d", self.isRecording);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:singleton];
}
@end
