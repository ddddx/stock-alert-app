# 股票异动雷达

面向 A 股市场的 Android 股票监控应用，聚焦“自选股管理 -> 行情刷新 -> 异动提醒 -> 中文语音播报”这条核心链路。

## 核心能力

- 自选股搜索、添加、删除与行情刷新
- 短时波动提醒与价格阈值提醒
- 中文语音播报与提醒预览
- 提醒历史记录查看
- Android 后台监控与轮询设置
- 面向真机使用场景的行情容错策略

## 当前状态

当前仓库提供的是一个可运行、可继续迭代的 Android 应用版本，已经覆盖以下主要能力：

- 自选股与规则管理
- 行情刷新与提醒触发
- 提醒历史与设置页面
- 中文语音播报链路

## 页面截图

当前仓库包含 4 个主要页面的实际截图：自选、提醒历史、设置、提醒列表。

| 自选 | 提醒历史 |
| --- | --- |
| ![自选页](docs/images/app-watchlist.jpg) | ![历史页](docs/images/app-history.jpg) |

| 设置 | 提醒列表 |
| --- | --- |
| ![设置页](docs/images/app-settings.jpg) | ![提醒页](docs/images/app-alerts.jpg) |

## 提醒规则

- **短时大幅波动**：在指定分钟窗口内监测涨跌幅变化
- **价格阈值提醒**：按价格条件触发提醒

## 数据来源

- 搜索：东方财富 `suggest` 接口
- 行情：东方财富 `push2` 行情接口
- 当前版本增加了多数据源容错思路，用于降低单一行情源异常时的整体失败概率

> 本项目使用公开数据接口，仅用于学习、研究与产品原型验证。

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
tool/
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

- 当前版本主要面向 Android
- 搜索和行情能力依赖第三方公开接口
- 第三方接口限流、变更或不可用时，会影响搜索和行情刷新
- 截图素材仍在持续整理中

## AI 开发说明

这是一个由 AI 完成实现、由人工负责需求提出与验收把关的项目。
