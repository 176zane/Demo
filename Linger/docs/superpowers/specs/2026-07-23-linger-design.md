# Linger（去留学习版）设计规格

**日期：** 2026-07-23  
**状态：** 已锁定，按阶段实现

## 一句话

随机展示系统相册媒体，像刷短视频一样浏览；上划标记删除，组末批量确认；不展示「待办积压」，只展示「已浏览 / 已删除」。

## 目标与非目标

### 目标

- P0：相册权限、随机一组照片、浏览、上划标记删、组末确认、统计、设置
- P1：「回到那天」、实况照片播放
- P2：类型筛选、视频随机回顾

### 非目标

- StoreKit / 付费墙 / 每日限额
- 云同步、社交、AI、Android

## UX 原则

- 不展示「还剩 N 张待处理」
- 一组固定数量（默认 20，设置可调 10/20/30）
- 删除必须二次确认（组末确认后 `PHAssetChangeRequest.deleteAssets`）
- 设置页展示 done-list：累计浏览数、累计删除数

## 架构

SwiftUI + MVVM；Photos / PhotoKit 读写相册；`UserDefaults` 存统计与偏好；媒体加载与删除经独立 Service。

```
Linger/
  App/
  Features/   Onboarding, Review, DayTimeline, ConfirmDelete, Settings
  Domain/     Models, Protocols
  Data/       PhotoLibraryService, ImageLoader, LivePhotoLoader, VideoLoader, Stores
  Components/
  Resources/
```

### 领域模型

- `MediaItem`：`localIdentifier`、`mediaKind`、`creationDate` 等轻量元数据
- `ReviewDeal`：本组 items、当前索引、`markedForDeletion`
- `UserStats`：`viewedCount`、`deletedCount`

### Photos 要点

- 权限：`readWrite`（删除需要）
- 随机抽组，排除近期已看
- `PHCachingImageManager` 预取
- 实况：`PHLivePhotoView`
- 视频：`AVPlayer` 短预览（默认静音）
- 回到那天：按 `creationDate` 当日区间 fetch

## 手势

- 上划：标记删除并前进（可短时撤销）
- 左滑 /「下一张」：保留并前进
- 双指捏合：进入「回到那天」

## 错误处理

- 权限拒绝 / Limited / 空相册 → 专用空态
- iCloud 占位 → loading / 低清 / 可跳过
- 删除部分失败 → 提示并可重试
- 资源已不存在 → 跳过

## 已锁定决策

- 技术：SwiftUI + MVVM + Photos
- 范围：P0 + P1 + P2
- 默认每组 20
- 最低 iOS 17
- 项目名：Linger
