# Melody Entry（外置录入路径）

Staff Melody 的 Phase 1 不在 App 内识图。用户把谱面变成可导入的 MusicXML，再写入 Melody Library。

## 推荐路径（图 → MusicXML）

1. **准备谱面图**（扫描件或清晰照片）。
2. **Audiveris** 做 OMR：图 → MusicXML（`.mxl` / `.musicxml`）。
3. **MuseScore** 打开结果，校对音高、时值、谱号/拍号/调号、连梁、延音线、三连音等。
4. 从 MuseScore **导出** `.mxl` 或 `.musicxml`。
5. 在 App **设置 → Melody Library** 导入该文件（导入 UI 见 issue 07；门禁与库模型见 issue 11）。

亦可跳过 Audiveris，在 MuseScore 中直接手工录入后导出。

## 导入门禁（摘要）

- 仅单 Part、单 Voice；越界内容整份拒绝并说明原因。
- 允许：高低音谱号（含中途更换）、拍号、调号、音高/临时升降、时值（含附点）、休止、小节线、Beam、Tie、常见三连音。
- 拒绝：多声部/和弦、歌词、Slur、非三连音 / 嵌套 tuplet 等。
- 小节数目标约 4–8；少于 4 允许；多于 8 警告仍可导入。

格式与镌刻决策见 `docs/adr/0001-musicxml-verovio-for-staff-melody.md`；术语见根目录 `CONTEXT.md`。
