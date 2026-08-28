# EasyMacBord

EasyMacBord 是 EasyInput V2.0 的 macOS 日常效率工具。它负责配置档、按键映射、本机动作登记、设备同步和权限状态；开发板只保存键位配置并发送稳定的 HID 事件。

## 当前范围

- macOS 26 及以上，Apple Silicon (`arm64`)。
- 菜单栏和 Dock 均可恢复同一个主窗口；主窗口提供状态总览、配置档、动作库、设备与同步、权限，以及侧栏底部的设置和关于入口。
- 配置档编辑：8 键与单枚旋钮的左转、按下、右转事件；编辑区采用固定尺寸的 `4 x 2` 宏键盘和旋钮外观。
- USB 与蓝牙配置通道同步；仅在收到设备保存确认后显示成功，并保留上次确认记录。
- 本机动作：打开用户选择的应用、网址、macOS 快捷指令和少量系统动作；动作库还维护可复用的固定文本与键盘组合键预设。界面不显示 UUID、绝对路径或安全书签。
- 使用现有 EasyInput V2.0 协议，不改动 Maker 固件、GPIO、设备身份、HID/GATT 描述符和 Flash 分区。

T05“动作与场景”已在功能分支实现：前台应用规则只按 Bundle ID 切换既有配置档；状态读取以现有 `0x13 / S3R v1` 与 `0x11 / kind 0x04` 合同校验状态；语义动作按能力与各自的 PTT 字段门控。动作库新增五个内建组合键预设、可配置喝水提醒、清洁屏幕遮罩和废纸篓本机确认；灯光和音乐律动仍未接入。关于页只检查公开 GitHub Releases，Beta 包含预发布，只展示 Release 信息、`arm64` DMG 与 SHA-256 外部链接，不提供自动更新。

当前工作树的 `swift test --jobs 4` 为 114/114，arm64 Release 构建通过。内部候选 `0.1.0-beta.4` 由干净提交 `51f4c4c` 生成，DMG SHA-256 为 `1fa2af4b6411cddb92a140dbb782a97eb9fb9849990a01222bafbd0bb33f7e79`，签名为 ad-hoc，未公证。USB Status HID 已在兼容设备上完成请求、分片、长度、CRC、schema 与能力字段的只读验证；这不代表配置写入、BLE 配置通道、实体输入或 Host Action 已验收。`1280 x 800` 与 `1120 x 720` 的 Debug 界面观察见 [T05 UI 证据](flow/evidence/t05-actions-scenes/UI-验收-2026-08-27.md)。Dock 重新打开、本机工具、应用内成功更新检查和真机矩阵仍待实际验证，详见 [T05 任务卡](flow/tasks/T05-动作与场景.md)。

AI、TTS、板端录音、Wi-Fi 音频、音乐律动和外接显示器 DDC 不属于 v0.1。

## 本地构建

需要与当前 macOS 对应的完整 Xcode。当前已使用 Xcode 27.0 beta 6 和 Swift 6.4 验证构建；Command Line Tools 不能单独作为构建结论。

```bash
swift test --jobs 4
scripts/package-app.sh 0.1.0-beta.4
```

脚本生成 `.app`、DMG、SHA-256 摘要和候选包 manifest。应用使用 ad-hoc 签名，不含开发团队标识、Developer ID 或公证。其他 Mac 首次打开时可能需要在系统设置中手动放行。

## 文档

- [SRS](docs/产品/SRS.md)
- [架构与协议](docs/技术/架构与协议.md)
- [构建与发布](docs/开发/构建与发布.md)
- [测试计划](docs/测试/测试计划.md)
- [硬件联调边界](docs/硬件/联调与边界.md)
- [设计原型](设计/v0.1-EasyMacBord桌面端/主界面.html)
- [全状态设计参考](设计/v0.1-EasyMacBord桌面端/全状态设计参考.html)
- [UI 改造实施方案](设计/v0.1-EasyMacBord桌面端/UI改造实施方案.md)
- [T04 桌面体验与动作中心设计说明](设计/v0.1-EasyMacBord桌面端/T04桌面体验与动作中心设计说明.md)
- [课程门禁记录](flow/course-gates.md)
- [内部 Beta 验收清单](flow/内部Beta验收清单.md)
- [T04 桌面体验与动作中心任务卡](flow/tasks/T04-桌面体验与动作中心.md)
- [T05 动作与场景设计稿](设计/v0.2-动作与场景/动作与场景-设计稿.html)
- [T05 动作与场景全状态设计参考](设计/v0.2-动作与场景/动作与场景-全状态设计参考.html)
- [T05 动作与场景任务卡](flow/tasks/T05-动作与场景.md)

## 版本管理

远程仓库：`https://github.com/Jiangshuo1109/EasyMacBord.git`

提交前不得加入构建产物、DMG、设备信息、本机绝对路径、权限诊断或用户动作记录。详细规则见 [CONTRIBUTING.md](CONTRIBUTING.md)。
