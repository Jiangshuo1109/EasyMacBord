# EasyMacBord

EasyMacBord 是 EasyInput V2.0 的 macOS 日常效率工具。它负责配置档、按键映射、本机动作登记、设备同步和权限状态；开发板只保存键位配置并发送稳定的 HID 事件。

## 当前范围

- macOS 26 及以上，Apple Silicon (`arm64`)。
- 菜单栏入口，以及状态总览、配置档、设备与同步、权限四页主导航。
- 配置档三栏编辑：8 键与单枚旋钮的左转、按下、右转事件；动作登记嵌入右侧检查器。
- USB 与蓝牙配置通道同步；仅在收到设备保存确认后显示成功，并保留上次确认记录。
- 本机动作：打开用户选择的应用、网址、macOS 快捷指令和少量系统动作。界面不显示 UUID、绝对路径或安全书签。
- 使用现有 EasyInput V2.0 协议，不改动 Maker 固件、GPIO、设备身份、HID/GATT 描述符和 Flash 分区。

T03 已补充动作库：从本机应用目录选择应用，以及截图与录屏界面、锁定屏幕、保持亮屏、壁纸、音量、隐藏当前应用和 Apple Music 基础控制。深色模式、屏保、键盘清洁、隐藏桌面文件/Dock、分屏和亮度控制只经用户自己的 macOS 快捷指令接入。该阶段已完成 41 项单元测试和 arm64 内部 DMG 构建；人工界面、本机工具和真机验收仍待执行，详见 [T03 任务卡](flow/tasks/T03-可配置工具目录.md)。

AI、TTS、板端录音、Wi-Fi 音频、音乐律动和外接显示器 DDC 不属于 v0.1。

## 本地构建

需要与当前 macOS 对应的完整 Xcode。当前已使用 Xcode 27.0 beta 6 和 Swift 6.4 验证构建；Command Line Tools 不能单独作为构建结论。

```bash
swift test --jobs 4
scripts/package-app.sh 0.1.0-beta.1
```

脚本生成 `.app`、DMG 和对应 SHA-256 摘要。应用使用 ad-hoc 签名，不含开发团队标识、Developer ID 或公证。其他 Mac 首次打开时可能需要在系统设置中手动放行。

## 文档

- [SRS](docs/产品/SRS.md)
- [架构与协议](docs/技术/架构与协议.md)
- [构建与发布](docs/开发/构建与发布.md)
- [测试计划](docs/测试/测试计划.md)
- [硬件联调边界](docs/硬件/联调与边界.md)
- [设计原型](设计/v0.1-EasyMacBord桌面端/主界面.html)
- [全状态设计参考](设计/v0.1-EasyMacBord桌面端/全状态设计参考.html)
- [UI 改造实施方案](设计/v0.1-EasyMacBord桌面端/UI改造实施方案.md)
- [课程门禁记录](flow/course-gates.md)

## 版本管理

远程仓库：`https://github.com/Jiangshuo1109/EasyMacBord.git`

提交前不得加入构建产物、DMG、设备信息、本机绝对路径、权限诊断或用户动作记录。详细规则见 [CONTRIBUTING.md](CONTRIBUTING.md)。
