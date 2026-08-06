# 10 — 登录时自动启动

**What to build:** 用户开机登录后,Weshome Break 会自动启动并开始工作,不需要每次手动打开。用户可以在设置面板中关闭这个行为。

**Blocked by:** 07 — 设置面板(时长、跳过/延迟、模式策略,持久化)

**Status:** ready-for-agent

- [ ] 使用 `SMAppService` 实现登录时自动启动
- [ ] 设置面板新增「登录时启动」开关,默认开启
- [ ] 关闭该开关后,下次登录不再自动启动;重新开启后恢复自动启动
- [ ] 关闭 App Sandbox,使用本机 Apple ID 签名(Xcode 自动管理签名),不做 notarization
