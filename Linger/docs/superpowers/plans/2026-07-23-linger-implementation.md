# Linger Implementation Plan

> **For agentic workers:** 按 Phase 逐步推进；checkbox 用于跟踪。

**Goal:** 本地相册随机回顾 + 顺手整理的 iOS App（不含付费）。

**Architecture:** SwiftUI + MVVM + PhotoKit Services。

**Tech Stack:** iOS 17+、SwiftUI、Photos、AVKit、XCTest。

## Global Constraints

- 最低 iOS 17
- 不做 StoreKit / 付费
- 删除必须组末二次确认
- 不展示待办积压数量
- 真机验证删除与实况

---

## Phase 0 — 工程脚手架

- [x] 创建 `~/Projects/Linger`，git init，SwiftUI App（iOS 17）
- [x] 配置相册用途文案
- [x] 写入 specs / plans 文档

## Phase 1 — P0 数据层

- [x] Domain 模型与 Protocol
- [x] PhotoLibraryService / ImageLoader / StatsStore / PreferencesStore
- [x] 单测：抽组、空库、去重

## Phase 2 — P0 回顾 UI

- [x] Permission + Review + ConfirmDelete + Settings
- [x] 手势、预加载、统计更新

## Phase 3 — P1

- [x] DayTimeline + 双指捏合
- [x] Live Photo

## Phase 4 — P2

- [x] MediaKind 筛选
- [x] 视频预览进入随机池

## Phase 5 — 打磨

- [x] 错误处理与动效
- [x] README

## Phase 6 — 规格缺口补齐（2026-07-23）

- [x] 删除部分失败：留在确认页并可重试
- [x] iCloud / 加载失败：浏览侧可跳过
- [x] GIF 动画播放 + 视频短预览（3 秒循环）
- [x] 近期已看跨启动持久化
- [x] App Icon；大相册随机索引抽样；Signing 说明（Team 本机自选）
