# Linger（去留学习版）

用 SwiftUI + PhotoKit 实现的「随机回顾相册、顺手整理」学习项目，灵感来自 iOS App「去留」。

**不含**订阅、付费墙、云同步。

## 功能

| Tab | 内容 |
|-----|------|
| 照片 | 3D 卡片堆随机回顾；上划标记删除 → **组末确认**；捏合「回到那天」；菜单「那年今日」 |
| 视频 | 全屏播放；右侧收藏 / 分享 / 垃圾桶；垃圾桶为 **5 秒可撤销的延迟删除**（无确认页） |
| 统计 | 照片/截屏/视频分桶：查看、删除、腾出空间；可重置浏览记录（无 Pro） |

## 架构

```
Linger/
  App/           RootView → MainTabView（悬浮胶囊 Tab）
  Features/      PhotoReview / VideoReview / Stats / OnThisDay / DayTimeline / ConfirmDelete / Settings
  Domain/        Models + PhotoLibraryServing
  Data/          PhotoKit services、Stores、抽样
  Components/    CardStack、媒体视图、玻璃按钮等
  Theme/         LingerTheme
```

设计与计划：

- [设计规格](docs/superpowers/specs/2026-07-23-linger-design.md)
- [UI 对齐计划](docs/superpowers/plans/2026-07-23-linger-ui-parity.md)

## 环境要求

- macOS + Xcode 16+（工程目标 iOS 17+）
- 真机更佳：删除、实况、分享、iCloud 照片在模拟器上能力有限

## 如何运行

```bash
cd /path/to/Linger
xcodegen generate
open Linger.xcodeproj
```

1. 在 Xcode → Signing & Capabilities 选择你的 Team（`project.yml` 中 `DEVELOPMENT_TEAM` 默认为空）
2. 真机或模拟器运行 `Linger`
3. 允许「完整相册访问」以便删除（读写权限）

### 照片手势

- **上划**：标记删除（可短时撤销标记）→ 组末确认页才真正删除
- **左滑**：保留并下一张
- **双指捏合**：回到那天（沉浸横向浏览）

### 视频操作

- **垃圾桶**：进入待删队列，5 秒内可撤销；超时或切下一批时执行 `deleteAssets`
- **爱心**：切换系统收藏
- **分享**：导出后系统分享面板

## 测试

```bash
xcodebuild -scheme Linger -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' test
```

## 权限说明

`NSPhotoLibraryUsageDescription`：随机回顾并在确认后删除。  
照片删除走组末确认；视频删除走延迟即时删除路径。
