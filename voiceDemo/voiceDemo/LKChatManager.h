//
//  LKChatManager.h
//  voiceDemo
//
//  Created by 许桂斌 on 16/12/17.
//  Copyright © 2016年 lkgame. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString *const LKRecorderIsRecordingNotification;
@interface LKChatManager : NSObject


+ (instancetype)shareManager;


/**
 设置用户ID，用于保证文件名唯一

 @param userID 用户ID
 */
- (void)setUserID:(NSString *)userID;


/**
 开始录音

 @param callBack 回调，仅在第一次录音时回调 authorized:success:已授权；fail:授权失败；first:请求授权
 */
- (void)starRecordingWithCallBack:(void (^)(NSString *authorized))callBack;


/**
 取消录音
 */
- (void)cancelRecording;

/**
 是否正在录音
 */
- (BOOL)recordingState;

/**
 结束录音

 @param callBack 回调 filename:保存文件名
 */
- (void)stopRecordingWithCallBack:(void (^)(NSString *filename))callBack;


/**
 播放录音

 @param filename 文件名
 @param callBack 回调 isSuccess:是否成功 播放结束时回调
 */
- (void)playRecordingWithFilename:(NSString *)filename callBack:(void (^)(BOOL isSuccess))callBack;


/**
 停止播放上一个录音

 @param callBack 回调 isSuccess:是否成功
 */
- (void)stopPlayingRecordingWithCallBack:(void (^)(BOOL isSuccess))callBack;


/**
 上传录音

 @param filename 需上传录音文件文件名
 @param callBack 回调 isSuccess:是否上传成功 downloadUrl:文件下载URL
 */
- (void)uploadRecordingWithFilename:(NSString *)filename callBack:(void (^)(BOOL isSuccess, NSString *downloadUrl))callBack;


/**
 下载录音

 @param url 下载URL
 @param callBack 回调 isSuccess:是否下载成功 filename:保存录音文件名 duration:录音时长
 @return 是否下载成功
 */
- (void)downloadRecordingWithUrl:(NSString *)url callBack:(void (^)(BOOL isSuccess, NSString *filename, NSInteger duration))callBack;


/**
 删除录音

 @param filename 文件名
 @return 是否删除成功
 */
- (BOOL)delRecordingWithFilename:(NSString *)filename;


/**
 删除全部录音
 
 @return 是否删除成功
 */
- (BOOL)delAllRecording;


@end
