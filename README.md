# Weshome Break

macOS 菜单栏应用：按可配置的工作/休息节奏强制全屏休息，并在休息遮罩中展示可哼唱的五线谱（Staff Melody Scene）。

[English](README.en.md)

## 功能概览

- 纯菜单栏常驻（无 Dock 图标、无独立主窗口）
- 可配置工作时长 / 休息时长的简单循环调度（默认 20 / 5 分钟）
- 休息到点时在所有已连接屏幕上弹出全屏遮罩
- **Staff Melody Scene**：导入 MusicXML，以 Verovio 镌刻可读单声部谱供休息时哼唱（纯视觉，不发声）
- 遮罩上可跳过本次休息或延迟休息；菜单栏可暂停/继续、手动触发休息、打开设置
- 可选登录时启动；设置项持久化（计时状态不跨进程恢复）

## 要求

- macOS **14.0+**（以 `WeshomeBreak/project.yml` / `GrillBreakCore/Package.swift` 为准）
- [Xcode](https://developer.apple.com/xcode/)（Swift 6 工具链）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（由 `project.yml` 生成 `xcodeproj`；工程文件不入库）

可选（仅录入旋律时需要，非构建依赖）：

- [Audiveris](https://github.com/Audiveris/audiveris)（识图 → MusicXML）和/或 [MuseScore](https://musescore.org/)（校对 / 手录 / 导出）

## 构建与运行

```bash
# 生成 Xcode 工程并运行 App
cd WeshomeBreak
xcodegen generate
open WeshomeBreak.xcodeproj
# 在 Xcode 中选择 Weshome Break target → Run
```

签名：关闭 App Sandbox，使用本机 Apple ID、Xcode 自动管理签名；定位为个人自用直接分发（非 App Store / 不做 notarization）。首次 Run 前请在 Xcode 中确认 Signing Team。

```bash
# 运行 GrillBreakCore 单元测试
cd GrillBreakCore
swift test
```

## 使用要点

1. 启动后菜单栏出现图标：可打开设置、立即休息、暂停/继续、退出。
2. 工作时长结束后，全屏遮罩覆盖所有屏幕；中央为 Staff Melody，角落为休息倒计时。
3. 鼠标在遮罩上移动时浮现控制条：可跳过或延迟本次休息。
4. 在设置中导入 MusicXML（`.musicxml` / `.mxl`）到 Melody Library，并手工选中当前旋律。

外置录入步骤详见 [`docs/melody-entry.md`](docs/melody-entry.md)。

## 文档索引

| 文档 | 说明 |
|------|------|
| [`spec.md`](spec.md) | 产品规格与实现决策 |
| [`CONTEXT.md`](CONTEXT.md) | 领域术语（Staff Melody、MusicXML 等） |
| [`docs/melody-entry.md`](docs/melody-entry.md) | 旋律外置录入路径 |
| [`docs/adr/0001-musicxml-verovio-for-staff-melody.md`](docs/adr/0001-musicxml-verovio-for-staff-melody.md) | MusicXML + Verovio 决策 |

## 许可

[Apache License 2.0](LICENSE)

## 附注

本仓库亦用于演示 [grill-me](.agents/skills/grill-me/) 等工作流技能（见 [`.agents/skills/`](.agents/skills/)）：从 grilling 访谈到 `spec.md`、tickets 与实现。产品代码与文档以上方章节为准；技能本身不是运行 App 的依赖。
