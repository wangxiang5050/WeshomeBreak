# 12 — Staff Melody Scene（Verovio 展示 + 空态）

**What to build:** 休息遮罩中央以 Staff Melody Scene 展示当前选中的 User Melody：用 Verovio 将已接受的 MusicXML 镌刻为 SVG，供哼唱放松；Melody Library 为空时显示可行动空态（提示去设置导入）。角落倒计时保留。本 issue 不做飞入动画、深色主题打磨、App 内识图、发声。

**Blocked by:** 04 — 全屏休息遮罩、06 — 展示模式协议 + 注册/选择、11 — MusicXML 导入门禁 + Melody Library / Selection 核心模型

**Status:** ready-for-agent

**参考:** `CONTEXT.md`；`docs/adr/0001-musicxml-verovio-for-staff-melody.md`

- [ ] 实现 Staff Melody Scene 并注册到模式注册表:用 Verovio 将当前选中的 User Melody（MusicXML）镌刻为 SVG，在遮罩中央展示
- [ ] Melody Library 为空时:遮罩显示可行动空态（提示去设置导入）,倒计时照常
- [ ] 有当前旋律时:展示可读正确的单声部谱面（谱号、拍号等由 Verovio 镌刻）
- [ ] 本 issue 明确不做: App 内识图/OMR、谱面元素飞入动画、深色主题打磨、旋律随机等非手工 Melody Selection、发声/节拍器
