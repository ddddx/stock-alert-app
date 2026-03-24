# Stock Alert App

面向 A 股的 Flutter 监控 MVP，提供自选股、模糊搜索加股、实时行情刷新、短时波动提醒、台阶提醒、提醒历史和中文语音播报。

## 当前实现

- 自选页通过东方财富公开接口拉取 A 股实时行情。
- 新增股票支持按代码、名称或拼音缩写模糊搜索，只展示沪深 A 股候选。
- 提醒规则已替换为两类：
  - 短时大幅波动：在 N 分钟窗口内涨跌超过 X%。
  - 台阶提醒：每跨过固定价格台阶或固定涨跌幅台阶播报一次。
- 语音文案会播报股票名称、代码、价格变化和涨跌幅，不再是占位提示音。
- Android 端已通过 `MethodChannel` 接入系统 `TextToSpeech`。
- 历史页会记录规则类型、触发行情、播报文案和是否成功播报。

## 主要目录

```text
lib/
  app/
  core/
  data/
    models/
    repositories/
  features/
    alerts/
    history/
    settings/
    watchlist/
  services/
    alerts/
    audio/
    background/
    market/
android/
test/
```

## 数据来源

- 搜索：东方财富 suggest 接口
- 行情：东方财富 `push2` 个股行情接口

## 工具说明

当前终端环境没有可执行的 `flutter` 命令，因此无法在本次任务中完成 `flutter pub get`、`flutter analyze`、`flutter test` 或 `flutter build apk`。如本机补齐 Flutter SDK 并加入 `PATH`，建议按顺序执行：

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk
```
