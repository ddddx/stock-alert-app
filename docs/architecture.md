# Architecture

## 目标

这是一个面向 Android 的股票监控 APP 骨架，当前优先解决：

- 自选股票管理
- 价格提醒规则管理
- 提醒历史展示
- 后台监控服务预留
- 声音提醒能力预留

## 分层思路

### `lib/data`

负责本地数据模型和仓库接口，当前先用内存仓库，后续可替换为：

- Hive
- Isar
- Drift

### `lib/features`

按业务模块拆分页面：

- `watchlist`：自选列表
- `alerts`：提醒规则
- `history`：提醒历史
- `settings`：监控与声音设置

### `lib/services`

平台能力与系统能力占位：

- `background`：后台监控服务
- `audio`：声音提醒

后续这里可以继续拆：

- `notification`
- `market`
- `storage`
- `permissions`

### `lib/core`

全局能力：

- 主题
- 路由壳
- 通用格式化

### `lib/shared`

共享 UI 组件，例如空状态、公共卡片、标签组件等。

## 当前实现策略

### 1. 先静态，再接真实数据

当前页面先使用本地示例数据 + 内存仓库，方便快速把页面结构和交互骨架搭起来。

### 2. 先保留后台服务接口，不假装已经可用

后台监控和声音提醒只做了占位服务，不伪装成已经接通系统后台能力。

### 3. 让后续扩展点清晰

后续真实开发时，建议按下面路线推进：

1. 接入本地数据库
2. 接入行情抓取/聚合层
3. 落地规则引擎
4. 接入 Android 后台任务能力
5. 接入本地通知和声音播放
6. 做权限、异常、重试、日志

## 未来建议模块

可继续扩展这些目录：

```text
lib/
├─ services/
│  ├─ market/
│  ├─ notification/
│  ├─ storage/
│  └─ permissions/
├─ features/
│  ├─ dashboard/
│  ├─ screener/
│  └─ onboarding/
└─ data/
   ├─ sources/
   └─ mappers/
```

## 安卓实现提醒时要重点注意

如果后续要做“App 退到后台也持续盯盘”，常见做法不是单纯定时器，而是组合：

- 前台服务（Foreground Service）
- WorkManager / AlarmManager
- 本地通知
- 厂商 ROM 后台存活适配

这部分属于后续 Android 工程补齐后的重点。
