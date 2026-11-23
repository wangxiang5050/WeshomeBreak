# Agent pointers

- 术语：`GLOSSARY.md`
- 产品约定：`spec.md`、`docs/adr/`
- 评审：`CODING_STANDARDS.md`
- 检查：在 `GrillBreakCore` 跑 `swift test`；在 `WeshomeBreak` 跑 `xcodegen generate`，再 `xcodebuild -project WeshomeBreak.xcodeproj -scheme WeshomeBreak -configuration Debug build` 编一次应用
- Issue tracker：本地工单在 `.scratch/weshome-break/issues/`，一份工单一文件
