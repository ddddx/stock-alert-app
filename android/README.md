# Android 平台占位

当前目录只是占位说明，**不是真正的 Flutter Android 原生工程**。

由于本机当前未检测到 Flutter / Java / Android SDK，暂未执行：

```powershell
flutter create . --platforms=android
```

等工具链补齐后，在 `stock-alert-app/` 根目录执行上面的命令，Flutter 会补生成真实的 Android 工程文件。

生成后建议立即执行：

```powershell
flutter doctor
flutter pub get
flutter run
```

如果后续要做“后台持续监控 + 声音提醒 + 本地通知”，Android 侧通常还需要继续补：

- 前台服务/后台任务能力
- 通知渠道（Notification Channel）
- 自定义音频资源
- 省电白名单/厂商后台限制说明
