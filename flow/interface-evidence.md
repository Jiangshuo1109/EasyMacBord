# 接口证据

## 已采用的上游事实

- 配置：`0x10`、S3C v1、最大 2048 字节、CRC16-CCITT、每片 52 字节数据。
- 确认：`0x11 / kind 0x03`，数据长度 7，保存确认需要 bytes/CRC 匹配。
- 本机动作：`0x11 / kind 0x05`，单片 36 字节小写 UUID。
- 状态：`0x04` 独立于确认和 Host Action。
- 状态读取：既有 HID Feature Report `0x13` 使用 16 字节 `S3R v1` 请求；`0x11 / kind 0x04` 以分片承载 `ai_keyboard.config_status.v1` JSON。消费端需校验 request ID、分片、完整 JSON 长度和 CRC16。
- 状态能力：`capabilities.semantic_actions` 由状态 JSON 声明；该字段不改变既有 `host_action:<uuid>` 格式。当前合同没有灯光或音乐律动控制字段。
- 路由：USB 优先，失败不跨通道补发。

这些事实来自本机保存的 EasyInput Maker 验证参考。记录仅保留协议字段，不包含设备唯一标识、私有日志或用户内容。
