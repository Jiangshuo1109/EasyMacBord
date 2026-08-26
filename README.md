# EasyMacBord

EasyMacBord 是 EasyInput V2.0 的 macOS 日常效率工具。它负责配置档、按键映射、本机动作映射、设备同步和权限状态；开发板只保存键位配置并发送稳定的 HID 事件。

## 当前范围

- macOS 26 及以上，Apple Silicon (`arm64`)。
- 菜单栏入口、状态总览、配置档、8 键与旋钮编辑、USB/BLE 配置同步。
- 本机动作：打开用户选择的应用、网址、macOS 快捷指令和少量系统动作。
- 使用现有 EasyInput V2.0 协议，不改动 Maker 固件、GPIO、设备身份、HID/GATT 描述符和 Flash 分区。

AI、TTS、板端录音、Wi-Fi 音频、音乐律动和外接显示器 DDC 不属于 v0.1。

## 本地构建

需要与当前 macOS 对应的完整 Xcode。当前工作机只有 Command Line Tools，不能作为构建结论。

```bash
swift test
scripts/package-app.sh 0.1.0
```

脚本生成 `dist/EasyMacBord.app` 和 `dist/EasyMacBord-0.1.0-arm64.dmg`。应用使用 ad-hoc 签名，不含开发团队标识、Developer ID 或公证。其他 Mac 首次打开时可能需要在系统设置中手动放行。

## 文档

- [SRS](docs/产品/SRS.md)
- [架构与协议](docs/技术/架构与协议.md)
- [构建与发布](docs/开发/构建与发布.md)
- [测试计划](docs/测试/测试计划.md)
- [硬件联调边界](docs/硬件/联调与边界.md)
- [设计原型](设计/v0.1-EasyMacBord桌面端/主界面.html)
- [课程门禁记录](flow/course-gates.md)

## 版本管理

远程仓库：`https://github.com/Jiangshuo1109/EasyMacBord.git`

提交前不得加入构建产物、DMG、设备信息、本机绝对路径、权限诊断或用户动作记录。详细规则见 [CONTRIBUTING.md](CONTRIBUTING.md)。
