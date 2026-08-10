# 14 — 菜单栏悬停高亮与鼠标行对齐

**What to build:** 打开菜单栏下拉菜单后，鼠标悬停在某一可点项上时，系统高亮条覆盖的就是那一行（例如悬停「设置…」时高亮「设置…」），而不再偏到上一行。状态文案仍留在菜单第一行，观感仍是状态头而非灰掉的操作项；暂停/立即休息/设置/退出的顺序与分隔线不变。优先保持 `.menu` 下拉。

**Root cause:** `BreakSchedulerController` 每秒把 `remaining` 写进 `@Published`，`MenuBarExtra` + `.menu` 在菜单打开时被 SwiftUI 整菜单重建，导致 NSMenu 悬停高亮与 hit-test 错位。与首行用 `Text` 还是 `Button` 无关；倒计时跨秒即可稳定复现。

**Fix:** 将每秒剩余时间挪到独立的 `BreakCountdown`（仅遮罩用 SwiftUI 观察）；controller 只在 `phase` / `isPaused` 实际变化时 `objectWillChange`。菜单打开时由 `MenuBarLiveStatusTitleUpdater` 直接改 `NSMenuItem.title`，倒计时继续走且不重建 SwiftUI 菜单。

**Blocked by:** None — can start immediately

**Status:** done

- [x] 悬停各菜单项时高亮与鼠标行一致（打开菜单后跨过至少一秒仍不偏）
- [x] 菜单打开期间状态行倒计时仍每秒变化
- [x] 点击各入口行为不变
- [x] 状态信息仍在菜单第一行，观感为状态头
- [x] 其它菜单项顺序与分隔线保持现状
- [x] 休息遮罩倒计时仍每秒刷新
- [x] 仍使用 `MenuBarExtra` + `.menu`
