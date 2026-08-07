# 11 — MusicXML 导入门禁 + Melody Library / Selection 核心模型

**What to build:** 用户可将符合子集的 MusicXML（`.musicxml` / `.mxl`）导入为 User Melody；越界内容整份拒绝并说明原因。Melody Library 持久化多首旋律；Melody Selection v1 为手工选中一首（策略可扩展，本 issue 不实现随机选曲）。无设置 UI 也可用测试验收；导入 UI 见 issue 07。外置录入路径写入产品/开发说明。

**Blocked by:** None — can start immediately

**Status:** done

**参考:** `CONTEXT.md`；`docs/adr/0001-musicxml-verovio-for-staff-melody.md`；`docs/melody-entry.md`

- [x] MusicXML 导入门禁（整份拒绝并说明原因，不静默丢元素）:
  - 仅单 Part、单 Voice
  - 允许:高低音谱号（含中途更换）、拍号、调号（含中途更换）、音高/临时升降、时值（含附点）、休止、小节线、Beam、Tie、常见三连音
  - 拒绝:多声部/和弦、歌词、Slur、非三连音 tuplet、嵌套 tuplet，以及其他超出子集的元素
  - 小节数:目标约 4–8；少于 4 允许；多于 8 警告仍可导入
- [x] Melody Library：持久化已导入的 User Melody；支持多首；支持删除
- [x] Melody Selection v1：手工选中当前旋律（接口预留后续策略扩展）
- [x] 外置录入路径写入产品/开发说明:图 → Audiveris → MuseScore 校对 → 导出 `.mxl`/`.musicxml` → App 导入（亦可纯 MuseScore 手录）
