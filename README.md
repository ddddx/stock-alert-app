# 股票异动雷达

面向 A 股市场的 Android 股票异动监控应用，提供自选股管理、规则提醒、历史记录和监控设置。

## 功能

- 自选股搜索、添加、删除与行情刷新
- 短时波动提醒与台阶提醒
- 中文语音播报与提醒预览
- 提醒历史记录查看
- Android 后台监控与轮询设置

## 截图

当前仓库只包含设置页实拍图，其余页面使用明确标注的占位图，避免误导。

| 自选 | 规则 |
|---|---|
| ![自选页占位图](docs/images/watchlist-placeholder.svg) | ![规则页占位图](docs/images/alerts-placeholder.svg) |

| 历史 | 设置 |
|---|---|
| ![历史页占位图](docs/images/history-placeholder.svg) | ![设置页](docs/images/app-settings.jpg) |

## 提醒规则

- 短时大幅波动：在指定分钟窗口内监测涨跌幅变化
- 台阶提醒：按价格或涨跌幅台阶触发提醒

## 数据来源

- 搜索：东方财富 `suggest` 接口
- 行情：东方财富 `push2` 行情接口

本项目使用公开数据接口，仅用于学习、研究与产品原型验证。

## 项目结构

```text
lib/
  app/
  core/
  data/
  features/
  services/
android/
docs/
test/
```

## 环境要求

- Flutter 3.x
- Dart SDK
- Android SDK

## 开发

```bash
flutter pub get
flutter run
```

## 测试

```bash
flutter analyze
flutter test
```

## 构建

```bash
flutter build apk --release
```

## 已知限制

- 当前版本面向 Android
- 搜索和行情能力依赖第三方公开接口
- 第三方接口限流、变更或不可用时会影响搜索和行情刷新
