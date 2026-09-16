# Melody Entry（外置录入路径）

Staff Melody 的 Phase 1 不在 App 内识图。用户把谱面变成可导入的 MusicXML，再写入 Melody Library。

## 推荐路径（图 → MusicXML）

1. **准备谱面图**（扫描件或清晰照片）。
2. **Audiveris** 做 OMR：图 → MusicXML（`.mxl` / `.musicxml`）。
3. **MuseScore** 打开结果，校对音高、时值、谱号/拍号/调号、连梁、延音线、三连音等。
4. 从 MuseScore **导出** `.musicxml`（优先）或 `.mxl`。
5. 在 App **设置 → Melody Library** 导入该文件（导入 UI 见 issue 07；门禁与库模型见 issue 11）。

亦可跳过 Audiveris，在 MuseScore 中直接手工录入后导出。

## 导入门禁（摘要）

- 仅单 Part、单 Voice；越界内容整份拒绝并说明原因。
- 允许：高低音谱号（含中途更换）、拍号、调号、音高/临时升降、时值（含附点）、休止、小节线、Beam、Tie、常见三连音。
- 拒绝：多声部/和弦、歌词、Slur、非三连音 / 嵌套 tuplet 等。
- 小节数目标约 4–8；少于 4 允许；多于 8 警告仍可导入。

## 常见失败与怎么改

App 会提示**原因**和**建议**。门禁拒绝（如多 Part）按提示改谱即可。底层读档问题可参考：

| 现象 | 怎么改 |
|------|--------|
| 压缩包内文件名含非英文字符 | 在 Audiveris 把工程名改成英文后重新导出，或导出为 `.musicxml` 再导入。 |
| 不是有效的 MXL 压缩包 | 文件损坏或根本不是 zip；用 MuseScore 或 Audiveris **重新导出** `.musicxml` / `.mxl`。 |
| 其它解压失败 | 按提示导出 `.musicxml`；界面「详情」一行是解压工具原文，便于对照。 |
| MXL 内没有谱面 | 压缩包不完整或非标准；在 MuseScore 中重新导出 `.musicxml` / `.mxl`。 |
| 无法读取文件 | 确认文件未损坏、编码正常；改用 MuseScore 导出 `.musicxml`。界面可能附带一行「详情」。 |
| 不支持的扩展名 | 只接受 `.musicxml` / `.mxl`（及 `.xml`）；先从 MuseScore / Audiveris 导出正确格式。 |

格式与镌刻决策见 `docs/adr/0001-musicxml-verovio-for-staff-melody.md`；术语见根目录 `CONTEXT.md`。
