# 应用图标资产

- `image-20260826-173822-5cbb8358.png` 是图标的原始位图来源，仅用于重新生成图标尺寸。
- `AppIcon.xcassets` 保存各尺寸 PNG；`EasyMacBord.icns` 是当前打包脚本复制到 `.app` 的图标。

原始位图不会由 SwiftPM 或打包脚本直接装入应用。替换图标时，应同时更新 `.xcassets`、`.icns` 和 `Sources/EasyMacBord/Resources/EasyMacBordLogo.png`，再运行完整打包校验。
