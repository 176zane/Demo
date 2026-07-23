# Linger（去留学习版）

用 SwiftUI + PhotoKit 实现的「随机回顾相册、顺手整理」学习项目，灵感来自 iOS App「去留」。

**不含**订阅、付费墙、云同步。

## 功能阶段

| 阶段 | 内容 |
|------|------|
| P0 | 相册权限、随机一组、上划标记删除、组末确认、统计与设置 |
| P1 | 「回到那天」（双指捏合）、实况照片 |
| P2 | 类型筛选、视频随机回顾 |

## 架构

```
Linger/
  App/           入口与根路由
  Features/      Onboarding / Review / ConfirmDelete / DayTimeline / Settings
  Domain/        模型与协议
  Data/          PhotoLibraryService、ImageLoader、Stores
  Components/    可复用媒体视图
```

- **MVVM**：`ReviewViewModel` 编排抽组 / 手势 / 确认删除
- **PhotoLibraryServing**：便于单测 mock
- **随机抽样**：`RandomSampler` 纯函数，可单测

设计与任务文档：

- [设计规格](docs/superpowers/specs/2026-07-23-linger-design.md)
- [实现计划](docs/superpowers/plans/2026-07-23-linger-implementation.md)

## 环境要求

- macOS + Xcode 16+（工程目标 iOS 17+）
- 真机更佳：删除、实况、iCloud 照片在模拟器上能力有限

## 如何运行

```bash
cd ~/Projects/Linger
xcodegen generate   # 若尚未生成 Linger.xcodeproj
open Linger.xcodeproj
```

1. 在 Xcode → Signing & Capabilities 选择你的 Team（`project.yml` 中 `DEVELOPMENT_TEAM` 默认为空，避免误绑他人账号）
2. 真机或模拟器运行 `Linger`
3. 允许「完整相册访问」以便删除（读写权限）

### 手势

- **上划**：标记删除（可短时撤销）
- **左滑**：保留并下一张
- **双指捏合**：回到那天

## 测试

```bash
# 若 name 匹配到多个模拟器，请改用 id=...
xcodebuild -scheme Linger -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' test
```

覆盖：随机抽样、ReviewDeal、Stats/Preferences、Mock 相册按日查询。

## 权限说明

`NSPhotoLibraryUsageDescription`：随机回顾并在确认后删除。  
删除走 `PHAssetChangeRequest.deleteAssets`，组末二次确认。
