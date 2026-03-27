# Android 交付状态

当前目录已经是可构建的 Flutter Android 原生工程，并补齐了本次交付所需的关键链路：

- 正式包名：`com.stockpulse.radar`
- 应用名：`股票异动雷达`
- Android `TextToSpeech` 中文语音播报
- 前台服务常驻通知 `MonitorForegroundService`
- 开机/升级后恢复入口 `BootCompletedReceiver`
- 通知权限、电池优化设置跳转
- release 仍使用 debug 签名，仅供内部测试

建议验证顺序：

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release
```
