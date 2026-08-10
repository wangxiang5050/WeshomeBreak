# 01 — 项目脚手架 + 菜单栏最小骨架

**What to build:** 用户可以打开一个纯菜单栏的 macOS App「Weshome Break」——没有 Dock 图标、没有独立主窗口。菜单栏上出现一个图标,点击后弹出菜单,里面有「退出 App」入口,点击后应用正常退出。此时应用还没有任何计时/休息逻辑,只是一个能启动、显示、退出的空壳。

**Blocked by:** None — can start immediately

**Status:** ready-for-agent

- [x] `git init` 初始化仓库版本管理
- [x] 用 Xcode 创建标准 macOS App 项目,Bundle ID 为 `com.weshome.break`,App 名称为 Weshome Break
- [x] App 不显示 Dock 图标、不打开任何独立窗口(纯菜单栏形态)
- [x] 用 SwiftUI `MenuBarExtra` 实现菜单栏图标与下拉菜单
- [x] 创建本地 Swift Package `GrillBreakCore`(当前为空骨架,不依赖 SwiftUI/AppKit),并通过 Add Local Package 方式被 App target 引用
- [x] 菜单栏菜单中包含「退出 App」入口,点击后应用正常终止
