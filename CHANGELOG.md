# 变更记录

本项目按 Keep a Changelog 的思路维护。只有已合并的代码、已确认的文档决策和已发布的构建产物进入本文件。

## [0.1.0] - 未发布

### 新增

- SwiftUI 菜单栏应用和状态总览界面。
- 8 键、旋钮和配置档模型。
- S3C v1 配置帧、CRC16-CCITT、配置确认和 Host Action 解码。
- USB 优先、BLE 备用的配置路由与相应测试。
- v0.1 的 SRS、原型、联调和发布文档。
- 菜单栏入口可显式创建并打开主窗口。

### 已验证

- Xcode 27.0 beta 6 的 `arm64` 编译和 18 项单元测试。
- ad-hoc 签名、无 Team Identifier 的 `.app` 和 DMG 完整性。

### 未验证

- USB/BLE 真机配置确认与 Host Action 实际执行。
