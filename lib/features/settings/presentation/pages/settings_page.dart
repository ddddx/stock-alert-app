import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../data/models/stock_quote_snapshot.dart';
import '../../../../data/models/webdav_config.dart';
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

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<int> _commonPollIntervals = [5, 10, 15, 30, 60];

  late final TextEditingController _intervalController;
  late final TextEditingController _webDavEndpointController;
  late final TextEditingController _webDavUsernameController;
  late final TextEditingController _webDavPasswordController;
  late WebDavConfig _lastSyncedWebDavConfig;

  bool _webDavBusy = false;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController(
      text: widget.repository.getStatus().pollIntervalSeconds.toString(),
    );
    final webDavConfig = widget.repository.getStatus().webDavConfig;
    _webDavEndpointController =
        TextEditingController(text: webDavConfig.endpoint);
    _webDavUsernameController =
        TextEditingController(text: webDavConfig.username);
    _webDavPasswordController = TextEditingController();
    _lastSyncedWebDavConfig = webDavConfig;
  }

  @override
  void dispose() {
    _intervalController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final status = widget.repository.getStatus();
    _syncIntervalController(status.pollIntervalSeconds);
    _syncWebDavControllersIfNeeded(status.webDavConfig);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOverviewSection(status),
        const SizedBox(height: 12),
        _buildMonitoringSection(status),
        const SizedBox(height: 12),
        _buildMarketDataSection(status),
        const SizedBox(height: 12),
        _buildAudioSection(status),
        const SizedBox(height: 12),
        _buildWebDavSection(),
        const SizedBox(height: 12),
        _buildStatusSection(status),
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
                label: Text('$seconds 秒'),
                selected: isSelected,
                onSelected: (_) async {
                  _syncIntervalController(seconds);
                  await _applyPollInterval();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _applyPollInterval,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('应用间隔'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  final ready = await widget.audioService.preload();
                  final message = ready
                      ? '语音播报能力已预热，可以直接试播真实提醒文案。'
                      : '预热失败：${widget.audioService.lastErrorMessage ?? '语音插件未完成初始化。'}';
                  _showFeedback(message);
                  widget.onChanged();
                },
                icon: const Icon(Icons.precision_manufacturing_outlined),
                label: const Text('预热播报'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await widget.onRefresh();
                  if (status.serviceEnabled) {
                    _showFeedback('已执行一次前台刷新；后台轮询仍会按既定间隔持续运行。');
                  } else {
                    _showFeedback('已执行一次前台刷新；如需持续后台轮询，请先开启后台监控。');
                  }
                  widget.onChanged();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('立即刷新'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final granted = await widget.platformBridgeService
                      .requestNotificationPermission();
                  if (!granted) {
                    await widget.platformBridgeService.openNotificationSettings();
                  }
                  _showFeedback(
                    granted ? '通知权限已授予。' : '未能直接获取通知权限，已打开系统通知设置，请确认允许通知。',
                  );
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('通知权限'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await widget.platformBridgeService
                      .openBatteryOptimizationSettings();
                  _showFeedback('已打开电池优化设置，建议将本应用加入白名单。');
                },
                icon: const Icon(Icons.battery_saver_outlined),
                label: const Text('电池白名单'),
              ),
            ],
          ),
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
                        : OutlinedButton(
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () async {
                final text = widget.messageBuilder.buildPreviewText(
                  widget.previewQuote,
                );
                final played = await widget.audioService.speak(text);
                final message = played
                    ? '已试播：$text'
                    : '试播失败：${widget.audioService.lastErrorMessage ?? '语音插件未完成初始化、设备缺少可用语音服务，或当前媒体音量过低。'} 文案为：$text';
                _showFeedback(message);
              },
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('试播真实文案'),
            ),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _webDavBusy
                    ? null
                    : () async {
                        await _rememberWebDavConfig();
                        _showFeedback('已保存 WebDAV 地址和用户名。');
                      },
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存连接信息'),
              ),
              FilledButton.icon(
                onPressed: _webDavBusy
                    ? null
                    : () => _runWebDavAction(
                          action: widget.onExportToWebDav,
                        ),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(_webDavBusy ? '处理中...' : '导出到 WebDAV'),
              ),
              FilledButton.tonalIcon(
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
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('从 WebDAV 导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection(dynamic status) {
    return SectionCard(
      title: '当前状态',
      subtitle: '集中查看最近一次监控结果、刷新来源和后台运行限制。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsStatusLine(
            label: '最近说明',
            value: status.lastMessage,
          ),
          _SettingsStatusLine(
            label: '最近检查',
            value: Formatters.compactDateTime(status.lastCheckAt),
          ),
          _SettingsStatusLine(
            label: '后台监控',
            value:
                '${status.serviceEnabled ? '已开启' : '未开启'} · 轮询 ${status.pollIntervalSeconds} 秒',
          ),
          _SettingsStatusLine(
            label: '行情数据源',
            value: _providerNameFor(status.marketDataProviderId),
          ),
          const Text('本地数据已持久化，重启应用后会保留自选、规则、历史和设置。'),
          const SizedBox(height: 8),
          const Text('监控仅在A股交易时段运行：工作日 09:30-11:30、13:00-15:00；午休和收市后会暂停。'),
          const SizedBox(height: 8),
          const Text('如果系统强杀进程，前台服务会尽量维持；设备重启或应用更新后，需要重新打开应用并确认权限。'),
          if (_toast != null) ...[
            const SizedBox(height: 8),
            Text('操作反馈：$_toast'),
          ],
        ],
      ),
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
        borderRadius: BorderRadius.circular(14),
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
        borderRadius: BorderRadius.circular(12),
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

class _SettingsStatusLine extends StatelessWidget {
  const _SettingsStatusLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label：',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
