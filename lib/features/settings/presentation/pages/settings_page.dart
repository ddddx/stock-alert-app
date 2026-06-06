import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../data/models/diagnostic_log_entry.dart';
import '../../../../data/models/stock_quote_snapshot.dart';
import '../../../../data/models/webdav_config.dart';
import '../../../../data/repositories/diagnostic_log_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../services/alerts/alert_message_builder.dart';
import '../../../../services/audio/audio_alert_service.dart';
import '../../../../services/background/monitor_service.dart';
import '../../../../services/background/monitoring_policy.dart';
import '../../../../services/market/market_data_provider.dart';
import '../../../../services/platform/platform_bridge_service.dart';
import '../../../../services/webdav/webdav_backup_service.dart';
import '../../../../shared/widgets/section_card.dart';

Future<void> _noopMarketDataProviderChanged(String providerId) async {}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    required this.monitorService,
    required this.audioService,
    required this.messageBuilder,
    required this.platformBridgeService,
    required this.previewQuote,
    required this.onRefresh,
    required this.onChanged,
    required this.onRequestAndroidBackgroundAccess,
    required this.onExportToWebDav,
    required this.onImportFromWebDav,
    this.currentMarketDataProviderId = 'ashare',
    this.availableMarketDataProviders = const [],
    this.onMarketDataProviderChanged = _noopMarketDataProviderChanged,
    this.diagnosticLogRepository = const NoopDiagnosticLogRepository(),
  });

  final SettingsRepository repository;
  final MonitorService monitorService;
  final AudioAlertService audioService;
  final AlertMessageBuilder messageBuilder;
  final PlatformBridgeService platformBridgeService;
  final StockQuoteSnapshot? previewQuote;
  final Future<void> Function() onRefresh;
  final VoidCallback onChanged;
  final Future<bool> Function({required bool onboarding})
      onRequestAndroidBackgroundAccess;
  final Future<String> Function(WebDavCredentials credentials) onExportToWebDav;
  final Future<String> Function(WebDavCredentials credentials)
      onImportFromWebDav;
  final String currentMarketDataProviderId;
  final List<MarketDataProvider> availableMarketDataProviders;
  final Future<void> Function(String providerId) onMarketDataProviderChanged;
  final DiagnosticLogRepository diagnosticLogRepository;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<int> _commonPollIntervals = [5, 10, 15, 30, 60];
  static const List<int> _commonCooldownSeconds = [0, 30, 60, 120, 300];

  late final TextEditingController _intervalController;
  late final TextEditingController _cooldownController;
  late final TextEditingController _webDavEndpointController;
  late final TextEditingController _webDavUsernameController;
  late final TextEditingController _webDavPasswordController;
  late WebDavConfig _lastSyncedWebDavConfig;
  late Future<AndroidBackgroundAccessStatus> _backgroundAccessFuture;

  bool _webDavBusy = false;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController(
      text: widget.repository.getStatus().pollIntervalSeconds.toString(),
    );
    _cooldownController = TextEditingController(
      text: widget.repository.getStatus().alertCooldownSeconds.toString(),
    );
    final webDavConfig = widget.repository.getStatus().webDavConfig;
    _webDavEndpointController =
        TextEditingController(text: webDavConfig.endpoint);
    _webDavUsernameController =
        TextEditingController(text: webDavConfig.username);
    _webDavPasswordController = TextEditingController();
    _lastSyncedWebDavConfig = webDavConfig;
    _backgroundAccessFuture =
        widget.platformBridgeService.getAndroidBackgroundAccessStatus();
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _cooldownController.dispose();
    _webDavEndpointController.dispose();
    _webDavUsernameController.dispose();
    _webDavPasswordController.dispose();
    super.dispose();
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    setState(() {
      _toast = message;
    });
  }

  void _refreshBackgroundAccessStatus() {
    setState(() {
      _backgroundAccessFuture =
          widget.platformBridgeService.getAndroidBackgroundAccessStatus();
    });
  }

  void _syncIntervalController(int seconds) {
    final text = seconds.toString();
    if (_intervalController.text == text) {
      return;
    }
    _intervalController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _syncCooldownController(int seconds) {
    final text = seconds.toString();
    if (_cooldownController.text == text) {
      return;
    }
    _cooldownController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _syncWebDavControllers(WebDavConfig config) {
    if (_webDavEndpointController.text != config.endpoint) {
      _webDavEndpointController.value = TextEditingValue(
        text: config.endpoint,
        selection: TextSelection.collapsed(offset: config.endpoint.length),
      );
    }
    if (_webDavUsernameController.text != config.username) {
      _webDavUsernameController.value = TextEditingValue(
        text: config.username,
        selection: TextSelection.collapsed(offset: config.username.length),
      );
    }
    _lastSyncedWebDavConfig = config;
  }

  bool _sameWebDavConfig(WebDavConfig left, WebDavConfig right) {
    return left.endpoint == right.endpoint && left.username == right.username;
  }

  void _syncWebDavControllersIfNeeded(WebDavConfig config) {
    if (_sameWebDavConfig(_lastSyncedWebDavConfig, config)) {
      return;
    }
    _syncWebDavControllers(config);
  }

  Future<void> _rememberWebDavConfig() async {
    final config = WebDavConfig(
      endpoint: _webDavEndpointController.text.trim(),
      username: _webDavUsernameController.text.trim(),
    );
    await widget.repository.updateWebDavConfig(config);
    _lastSyncedWebDavConfig = config;
    widget.onChanged();
  }

  WebDavCredentials? _buildWebDavCredentials() {
    final endpoint = _webDavEndpointController.text.trim();
    final username = _webDavUsernameController.text.trim();
    final password = _webDavPasswordController.text;
    if (endpoint.isEmpty || username.isEmpty || password.isEmpty) {
      _showFeedback('请完整填写 WebDAV 地址、用户名和密码。');
      return null;
    }
    return WebDavCredentials(
      endpoint: endpoint,
      username: username,
      password: password,
    );
  }

  Future<void> _runWebDavAction({
    required Future<String> Function(WebDavCredentials credentials) action,
  }) async {
    final credentials = _buildWebDavCredentials();
    if (credentials == null) {
      return;
    }

    await _rememberWebDavConfig();
    setState(() {
      _webDavBusy = true;
    });
    try {
      final message = await action(credentials);
      _showFeedback(message);
      widget.onChanged();
    } catch (error) {
      _showFeedback('WebDAV 操作失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _webDavBusy = false;
        });
      }
    }
  }

  Future<bool> _confirmImport() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认导入配置'),
          content: const Text('导入会覆盖当前自选、规则和核心偏好设置，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续导入'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _applyPollInterval() async {
    final rawValue = _intervalController.text.trim();
    final parsed = int.tryParse(rawValue);
    final statusBeforeUpdate = widget.repository.getStatus();
    if (parsed == null) {
      _syncIntervalController(statusBeforeUpdate.pollIntervalSeconds);
      _showFeedback(
        '请输入 $minMonitorPollIntervalSeconds 到 $maxMonitorPollIntervalSeconds 秒之间的整数。',
      );
      return;
    }

    final normalized = parsed
        .clamp(minMonitorPollIntervalSeconds, maxMonitorPollIntervalSeconds)
        .toInt();
    await widget.repository.updatePollIntervalSeconds(normalized);
    if (statusBeforeUpdate.serviceEnabled) {
      await widget.monitorService.reload();
    }
    _syncIntervalController(normalized);

    final intervalText =
        parsed == normalized ? '$normalized 秒' : '$normalized 秒（已自动校正）';
    final feedback = statusBeforeUpdate.serviceEnabled
        ? '后台轮询间隔已更新为 $intervalText，后台监控会按新间隔继续执行。'
        : '轮询间隔已保存为 $intervalText，开启后台监控后会按该频率执行。';
    _showFeedback(feedback);
    widget.onChanged();
  }

  Future<void> _applyAlertCooldown() async {
    final rawValue = _cooldownController.text.trim();
    final parsed = int.tryParse(rawValue);
    final statusBeforeUpdate = widget.repository.getStatus();
    if (parsed == null) {
      _syncCooldownController(statusBeforeUpdate.alertCooldownSeconds);
      _showFeedback(
        '请输入 $minAlertCooldownSeconds 到 $maxAlertCooldownSeconds 秒之间的整数。',
      );
      return;
    }

    final normalized =
        parsed.clamp(minAlertCooldownSeconds, maxAlertCooldownSeconds).toInt();
    await widget.repository.updateAlertCooldownSeconds(normalized);
    if (statusBeforeUpdate.serviceEnabled) {
      await widget.monitorService.reload();
    }
    _syncCooldownController(normalized);

    final cooldownText = normalized == 0 ? '关闭冷却' : '$normalized 秒冷却';
    final feedback = statusBeforeUpdate.serviceEnabled
        ? '提醒冷却已更新为 $cooldownText，后台监控会按新策略继续执行。'
        : '提醒冷却已保存为 $cooldownText，开启后台监控后会按该策略执行。';
    _showFeedback(feedback);
    widget.onChanged();
  }

  Future<void> _handleServiceToggle(bool enabled) async {
    if (enabled) {
      final allowed = await widget.onRequestAndroidBackgroundAccess(
        onboarding: false,
      );
      if (!allowed) {
        _showFeedback('后台监控未开启：请先允许通知，并按提示完成电池优化设置。');
        widget.onChanged();
        return;
      }
      await widget.repository.updateService(true);
      await widget.monitorService.start();
      final enabledAfterStart = widget.repository.getStatus().serviceEnabled;
      _showFeedback(
        enabledAfterStart
            ? '后台监控守护已启用，原生前台服务会按设定间隔持续轮询。'
            : widget.repository.getStatus().lastMessage,
      );
      widget.onChanged();
      return;
    }

    await widget.repository.updateService(false);
    await widget.monitorService.stop();
    _showFeedback('后台监控守护已关闭。');
    widget.onChanged();
  }

  Future<void> _handleAudioPreload() async {
    final ready = await widget.audioService.preload();
    final message = ready
        ? '语音播报能力已预热，可以直接试播真实提醒文案。'
        : '预热失败：${widget.audioService.lastErrorMessage ?? '语音插件未完成初始化。'}';
    _showFeedback(message);
    widget.onChanged();
  }

  Future<void> _handleImmediateRefresh(bool serviceEnabled) async {
    await widget.onRefresh();
    if (serviceEnabled) {
      _showFeedback('已执行一次前台刷新；后台轮询仍会按既定间隔持续运行。');
    } else {
      _showFeedback('已执行一次前台刷新；如需持续后台轮询，请先开启后台监控。');
    }
    widget.onChanged();
  }

  Future<void> _handleNotificationPermission() async {
    final granted =
        await widget.platformBridgeService.requestNotificationPermission();
    if (!granted) {
      await widget.platformBridgeService.openNotificationSettings();
    }
    _showFeedback(
      granted ? '通知权限已授予。' : '未能直接获取通知权限，已打开系统通知设置，请确认允许通知。',
    );
    _refreshBackgroundAccessStatus();
  }

  Future<void> _handleBatteryWhitelist() async {
    await widget.platformBridgeService.openBatteryOptimizationSettings();
    _showFeedback('已打开电池优化设置，建议将本应用加入白名单。');
    _refreshBackgroundAccessStatus();
  }

  Future<void> _handlePreviewSpeech() async {
    final text = widget.messageBuilder.buildPreviewText(widget.previewQuote);
    final played = await widget.audioService.speak(text);
    final message = played
        ? '已试播：$text'
        : '试播失败：${widget.audioService.lastErrorMessage ?? '语音插件未完成初始化、设备缺少可用语音服务，或当前媒体音量过低。'} 文案为：$text';
    _showFeedback(message);
  }

  Future<void> _handleOpeningBriefingToggle(bool enabled) async {
    await widget.repository.updateOpeningBriefing(enabled);
    _showFeedback(enabled ? '开盘简报已开启，每个交易日 9:30 自动播报。' : '开盘简报已关闭。');
    widget.onChanged();
  }

  Future<void> _handleClosingReviewToggle(bool enabled) async {
    await widget.repository.updateClosingReview(enabled);
    _showFeedback(enabled ? '收盘复盘已开启，每个交易日 15:05 自动播报。' : '收盘复盘已关闭。');
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.repository.getStatus();
    _syncIntervalController(status.pollIntervalSeconds);
    _syncCooldownController(status.alertCooldownSeconds);
    _syncWebDavControllersIfNeeded(status.webDavConfig);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOverviewSection(status),
        const SizedBox(height: 12),
        _buildBackgroundHealthSection(status),
        const SizedBox(height: 12),
        _buildMonitoringSection(status),
        const SizedBox(height: 12),
        _buildDiagnosticsSection(),
        const SizedBox(height: 12),
        _buildBriefingSection(status),
        const SizedBox(height: 12),
        _buildMarketDataSection(status),
        const SizedBox(height: 12),
        _buildAudioSection(status),
        const SizedBox(height: 12),
        _buildWebDavSection(),
        const SizedBox(height: 12),
        if (status.lastMessage.isNotEmpty)
          _SettingsSubpanel(
            icon: Icons.info_outline,
            title: '最近说明',
            body: status.lastMessage,
          ),
        if (_toast != null) ...[
          const SizedBox(height: 12),
          _SettingsSubpanel(
            icon: Icons.task_alt_outlined,
            title: '最近操作',
            body: _toast!,
          ),
        ],
      ],
    );
  }

  Widget _buildOverviewSection(dynamic status) {
    final providerLabel = _providerNameFor(status.marketDataProviderId);
    return SectionCard(
      title: '设置概览',
      subtitle: '把监控、数据源、语音和备份分开管理，便于快速确认当前运行状态。',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _SettingsQuickStat(
            icon: status.serviceEnabled
                ? Icons.shield_outlined
                : Icons.shield_moon_outlined,
            label: '后台守护',
            value: status.serviceEnabled ? '运行中' : '未开启',
            tone: status.serviceEnabled
                ? const Color(0xFF1565C0)
                : const Color(0xFF546E7A),
          ),
          _SettingsQuickStat(
            icon: Icons.data_thresholding_outlined,
            label: '数据源',
            value: providerLabel,
            tone: const Color(0xFF6A1B9A),
          ),
          _SettingsQuickStat(
            icon: Icons.timer_outlined,
            label: '轮询间隔',
            value: '${status.pollIntervalSeconds} 秒',
            tone: const Color(0xFFEF6C00),
          ),
          _SettingsQuickStat(
            icon: Icons.alarm_on_outlined,
            label: '提醒冷却',
            value: status.alertCooldownSeconds == 0
                ? '已关闭'
                : '${status.alertCooldownSeconds} 秒',
            tone: const Color(0xFF5E35B1),
          ),
          _SettingsQuickStat(
            icon: Icons.history_toggle_off_outlined,
            label: '最近检查',
            value: Formatters.compactDateTime(status.lastCheckAt),
            tone: const Color(0xFF00838F),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitoringSection(dynamic status) {
    return SectionCard(
      title: '后台监控',
      subtitle: '先确认守护是否开启，再调整轮询频率和系统权限入口。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用后台监控守护'),
            subtitle: const Text(
              '开启后会拉起常驻通知，并由原生前台服务按设定间隔持续在后台轮询。',
            ),
            value: status.serviceEnabled,
            onChanged: _handleServiceToggle,
          ),
          _SettingsSubpanel(
            icon: status.serviceEnabled
                ? Icons.shield_outlined
                : Icons.shield_moon_outlined,
            title: status.serviceEnabled ? '后台监控已开启' : '后台监控未开启',
            body: status.serviceEnabled
                ? '当前会按 ${status.pollIntervalSeconds} 秒的节奏持续轮询，并同步更新前台服务通知。'
                : '当前只保存监控配置；应用退到后台后不会持续轮询，开启后台监控后才会按当前间隔执行。',
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('poll-interval-input'),
            controller: _intervalController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '后台轮询间隔',
              border: OutlineInputBorder(),
              helperText: '允许 1 到 300 秒。低于 15 秒也可用，但会更耗电；仅在A股交易时段监控。',
              suffixIcon: Icon(Icons.timer_outlined),
            ),
            onFieldSubmitted: (_) async => _applyPollInterval(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _commonPollIntervals.map((seconds) {
              final isSelected = status.pollIntervalSeconds == seconds;
              return ChoiceChip(
                key: Key('poll-interval-chip-$seconds'),
                label: Text('$seconds 秒'),
                selected: isSelected,
                onSelected: (_) async {
                  _syncIntervalController(seconds);
                  await _applyPollInterval();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('alert-cooldown-input'),
            controller: _cooldownController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '提醒冷却时间',
              border: OutlineInputBorder(),
              helperText: '允许 0 到 3600 秒。0 表示关闭冷却；用于减少重复轰炸。',
              suffixIcon: Icon(Icons.alarm_on_outlined),
            ),
            onFieldSubmitted: (_) async => _applyAlertCooldown(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _commonCooldownSeconds.map((seconds) {
              final isSelected = status.alertCooldownSeconds == seconds;
              final label = seconds == 0 ? '关闭冷却' : '$seconds 秒';
              return ChoiceChip(
                key: Key('alert-cooldown-chip-$seconds'),
                label: Text(label),
                selected: isSelected,
                onSelected: (_) async {
                  _syncCooldownController(seconds);
                  await _applyAlertCooldown();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            '监控操作',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _buildActionGrid(
            children: [
              _SettingsActionButton(
                key: const Key('apply-poll-interval-button'),
                onPressed: _applyPollInterval,
                icon: Icons.check_circle_outline,
                label: '应用间隔',
                emphasis: _SettingsActionEmphasis.primary,
              ),
              _SettingsActionButton(
                key: const Key('apply-alert-cooldown-button'),
                onPressed: _applyAlertCooldown,
                icon: Icons.alarm_on_outlined,
                label: '应用冷却',
                emphasis: _SettingsActionEmphasis.primary,
              ),
              _SettingsActionButton(
                key: const Key('manual-refresh-button'),
                onPressed: () => _handleImmediateRefresh(status.serviceEnabled),
                icon: Icons.refresh,
                label: '立即刷新',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '系统权限',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _buildActionGrid(
            children: [
              _SettingsActionButton(
                onPressed: _handleNotificationPermission,
                icon: Icons.notifications_active_outlined,
                label: '通知权限',
              ),
              _SettingsActionButton(
                onPressed: _handleBatteryWhitelist,
                icon: Icons.battery_saver_outlined,
                label: '电池白名单',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundHealthSection(dynamic status) {
    return SectionCard(
      title: '后台健康检查',
      subtitle: '集中查看通知、电池优化、服务配置和实际运行状态。',
      trailing: TextButton.icon(
        onPressed: _refreshBackgroundAccessStatus,
        icon: const Icon(Icons.refresh),
        label: const Text('重新检查'),
      ),
      child: FutureBuilder<AndroidBackgroundAccessStatus>(
        future: _backgroundAccessFuture,
        builder: (context, snapshot) {
          final access = snapshot.data;
          if (snapshot.connectionState == ConnectionState.waiting &&
              access == null) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            );
          }
          final isAndroid = access?.isAndroid ?? false;
          final canPostNotifications = access?.canPostNotifications ?? true;
          final ignoringBattery = access?.ignoringBatteryOptimizations ?? true;
          return Column(
            children: [
              _HealthCheckRow(
                icon: Icons.notifications_active_outlined,
                title: '通知权限',
                detail: isAndroid
                    ? (canPostNotifications
                        ? '已允许通知，前台服务和提醒通知可显示。'
                        : '通知未完全开启，后台监控无法稳定常驻。')
                    : '当前不是 Android 环境，跳过系统通知检查。',
                healthy: canPostNotifications,
              ),
              const SizedBox(height: 8),
              _HealthCheckRow(
                icon: Icons.battery_saver_outlined,
                title: '电池优化',
                detail: isAndroid
                    ? (ignoringBattery
                        ? '已忽略电池优化，后台服务更不容易被系统回收。'
                        : '尚未加入电池白名单，部分 ROM 可能杀死后台服务。')
                    : '当前不是 Android 环境，跳过电池白名单检查。',
                healthy: ignoringBattery,
              ),
              const SizedBox(height: 8),
              _HealthCheckRow(
                icon: Icons.tune_outlined,
                title: '后台配置',
                detail: status.serviceEnabled
                    ? '后台守护配置已开启，应用会尝试恢复原生前台服务。'
                    : '后台守护未开启，应用退到后台后不会持续轮询。',
                healthy: status.serviceEnabled,
              ),
              const SizedBox(height: 8),
              _HealthCheckRow(
                icon: Icons.shield_outlined,
                title: '服务运行',
                detail: widget.monitorService.isRunning
                    ? '当前 Flutter 侧确认原生前台服务已启动。'
                    : (status.serviceEnabled
                        ? '配置已开启，但当前会话还未确认服务运行；可重新开启或查看诊断日志。'
                        : '服务未运行。'),
                healthy: widget.monitorService.isRunning,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDiagnosticsSection() {
    final logs = widget.diagnosticLogRepository.getAll();
    final latest = logs.take(5).toList(growable: false);
    return SectionCard(
      title: '运行诊断',
      subtitle: '记录刷新、后台服务、通知和语音播报的关键事件。',
      trailing: TextButton.icon(
        onPressed: logs.isEmpty
            ? null
            : () async {
                await widget.diagnosticLogRepository.clear();
                _showFeedback('诊断日志已清空。');
                widget.onChanged();
              },
        icon: const Icon(Icons.delete_outline),
        label: const Text('清空'),
      ),
      child: latest.isEmpty
          ? const Text('暂无诊断日志。完成一次刷新或启动后台监控后会在这里记录关键事件。')
          : Column(
              children: [
                for (final entry in latest) ...[
                  _DiagnosticLogTile(entry: entry),
                  if (entry != latest.last) const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }

  Widget _buildMarketDataSection(dynamic status) {
    final providers = widget.availableMarketDataProviders;
    final selectedProviderId = status.marketDataProviderId;

    return SectionCard(
      title: '数据源',
      subtitle: '支持在前台和后台统一切换行情来源，便于交叉核对报价。',
      child: providers.isEmpty
          ? const Text('当前暂无可切换的数据源。')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final provider in providers) ...[
                  _SettingsSubpanel(
                    icon: provider.providerId == selectedProviderId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    title: provider.providerName,
                    body: _providerDescription(provider),
                    trailing: provider.providerId == selectedProviderId
                        ? const Chip(label: Text('当前'))
                        : FilledButton.tonal(
                            onPressed: () async {
                              final wasServiceEnabled = status.serviceEnabled;
                              await widget.onMarketDataProviderChanged(
                                provider.providerId,
                              );
                              _showFeedback(
                                wasServiceEnabled
                                    ? '已切换为 ${provider.providerName}，后台监控和前台刷新都会使用新数据源。'
                                    : '已切换为 ${provider.providerName}，下次刷新会使用新数据源。',
                              );
                            },
                            child: const Text('切换'),
                          ),
                  ),
                  if (provider != providers.last) const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }

  Widget _buildBriefingSection(dynamic status) {
    return SectionCard(
      title: '定时简报',
      subtitle: '按交易日关键时点自动播报开盘和收盘摘要，并写入提醒历史。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开盘简报'),
            subtitle: const Text('每个交易日 9:30 播报自选开盘表现与全市场情绪。'),
            value: status.openingBriefingEnabled,
            onChanged: _handleOpeningBriefingToggle,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('收盘复盘'),
            subtitle: const Text('每个交易日 15:05 播报自选收盘表现与当日提醒统计。'),
            value: status.closingReviewEnabled,
            onChanged: _handleClosingReviewToggle,
          ),
          _SettingsSubpanel(
            icon: Icons.record_voice_over_outlined,
            title: '播报说明',
            body: '定时简报遵循A股交易日判断；关闭“启用语音播报”后仍会写入历史，但不会发声。',
          ),
        ],
      ),
    );
  }

  Widget _buildAudioSection(dynamic status) {
    return SectionCard(
      title: '语音提醒',
      subtitle: '控制提醒是否播报，并可直接试播一条当前会使用的真实文案。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用语音播报'),
            value: status.soundEnabled,
            onChanged: (value) async {
              await widget.repository.updateSound(value);
              _showFeedback(value ? '语音播报已开启。' : '语音播报已关闭。');
              widget.onChanged();
            },
          ),
          _SettingsSubpanel(
            icon: Icons.record_voice_over_outlined,
            title: status.soundEnabled ? '播报链路已启用' : '播报链路已关闭',
            body: '前台提醒、试播按钮和后台触发的语音都共享这套播报配置。',
          ),
          const SizedBox(height: 12),
          _buildActionGrid(
            children: [
              _SettingsActionButton(
                onPressed: _handlePreviewSpeech,
                icon: Icons.volume_up_outlined,
                label: '试播真实文案',
                emphasis: _SettingsActionEmphasis.primary,
              ),
              _SettingsActionButton(
                onPressed: _handleAudioPreload,
                icon: Icons.precision_manufacturing_outlined,
                label: '预热播报',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebDavSection() {
    return SectionCard(
      title: 'WebDAV 导入导出',
      subtitle: '用于备份自选、规则和核心偏好。密码只用于本次连接，不会写入本地配置。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsSubpanel(
            icon: Icons.cloud_sync_outlined,
            title: '备份覆盖范围',
            body: '当前包含自选、提醒规则、语音开关、轮询间隔、自选排序和行情数据源偏好。',
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('webdav-endpoint-input'),
            controller: _webDavEndpointController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'WebDAV 文件地址',
              border: OutlineInputBorder(),
              hintText: 'https://dav.example.com/stock-alert-app/backup.json',
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('webdav-username-input'),
            controller: _webDavUsernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('webdav-password-input'),
            controller: _webDavPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码',
              border: OutlineInputBorder(),
              helperText: '密码仅本次使用，不会保存在本地。',
            ),
          ),
          const SizedBox(height: 12),
          _buildActionGrid(
            children: [
              _SettingsActionButton(
                onPressed: _webDavBusy
                    ? null
                    : () async {
                        await _rememberWebDavConfig();
                        _showFeedback('已保存 WebDAV 地址和用户名。');
                      },
                icon: Icons.save_outlined,
                label: '保存连接信息',
              ),
              _SettingsActionButton(
                onPressed: _webDavBusy
                    ? null
                    : () => _runWebDavAction(
                          action: widget.onExportToWebDav,
                        ),
                icon: Icons.cloud_upload_outlined,
                label: _webDavBusy ? '处理中...' : '导出到 WebDAV',
                emphasis: _SettingsActionEmphasis.primary,
              ),
              _SettingsActionButton(
                onPressed: _webDavBusy
                    ? null
                    : () async {
                        final confirmed = await _confirmImport();
                        if (!confirmed) {
                          return;
                        }
                        await _runWebDavAction(
                          action: widget.onImportFromWebDav,
                        );
                      },
                icon: Icons.cloud_download_outlined,
                label: '从 WebDAV 导入',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid({
    required List<Widget> children,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final maxWidth = constraints.maxWidth;
        final useTwoColumns = maxWidth >= 520;
        final itemWidth = useTwoColumns ? (maxWidth - spacing) / 2 : maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }

  String _providerNameFor(String providerId) {
    for (final provider in widget.availableMarketDataProviders) {
      if (provider.providerId == providerId) {
        return provider.providerName;
      }
    }
    return providerId == 'sina' ? '新浪财经' : '聚合 A 股';
  }

  String _providerDescription(MarketDataProvider provider) {
    switch (provider.providerId) {
      case 'sina':
        return '使用新浪财经行情接口和建议接口，适合作为第二信源交叉比对。';
      default:
        return '优先走 Eastmoney 批量行情，必要时回退到单只接口与 Tencent 兜底。';
    }
  }
}

class _SettingsQuickStat extends StatelessWidget {
  const _SettingsQuickStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 152,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(height: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

enum _SettingsActionEmphasis {
  primary,
  secondary,
}

class _SettingsActionButton extends StatelessWidget {
  const _SettingsActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.emphasis = _SettingsActionEmphasis.secondary,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final _SettingsActionEmphasis emphasis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final isPrimary = emphasis == _SettingsActionEmphasis.primary;
    final backgroundColor = enabled
        ? (isPrimary ? scheme.primaryContainer : const Color(0xFFF5F7FB))
        : const Color(0xFFF2F4F7);
    final borderColor = enabled
        ? (isPrimary
            ? scheme.primary.withValues(alpha: 0.20)
            : const Color(0xFFD6DEE8))
        : const Color(0xFFE3E8EF);
    final iconColor = enabled
        ? (isPrimary ? scheme.primary : const Color(0xFF1E3A5F))
        : const Color(0xFF9AA6B2);
    final titleColor = enabled
        ? (isPrimary ? scheme.onPrimaryContainer : const Color(0xFF102A43))
        : const Color(0xFF7B8794);
    final subtitleColor =
        enabled ? const Color(0xFF52606D) : const Color(0xFF9AA5B1);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: titleColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled ? '点击执行' : '当前不可用',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: subtitleColor,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                color: subtitleColor,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSubpanel extends StatelessWidget {
  const _SettingsSubpanel({
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(body),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _HealthCheckRow extends StatelessWidget {
  const _HealthCheckRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.healthy,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    final color = healthy ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(detail),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            healthy ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _DiagnosticLogTile extends StatelessWidget {
  const _DiagnosticLogTile({required this.entry});

  final DiagnosticLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      DiagnosticLogLevel.info => const Color(0xFF1565C0),
      DiagnosticLogLevel.warning => const Color(0xFFEF6C00),
      DiagnosticLogLevel.error => const Color(0xFFC62828),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE3EAF3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.receipt_long_outlined, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.levelLabel} · ${entry.category} · ${Formatters.compactDateTime(entry.timestamp)}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(entry.message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
