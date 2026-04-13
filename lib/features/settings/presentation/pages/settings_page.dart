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
        SectionCard(
          title: '后台监控',
          subtitle: '后台监控开关、轮询间隔和系统权限入口统一集中在这里。首次使用前，建议先完成通知授权与电池优化设置。',
          child: Column(
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.serviceEnabled ? '后台监控已开启' : '后台监控未开启',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text('轮询间隔：${status.pollIntervalSeconds} 秒'),
                    const SizedBox(height: 4),
                    Text(
                      status.serviceEnabled
                          ? '原生前台服务会按当前间隔持续轮询，并同步更新常驻通知。'
                          : '当前仅保存监控配置；应用退到后台后不会持续轮询，开启后台监控后才会按当前间隔执行。',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
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
                        await widget.platformBridgeService
                            .openNotificationSettings();
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
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '语音提醒',
          subtitle: '试播与前台可见时的播报共用同一条应用内语音播报链路；后台原生轮询阶段暂保留前台服务和通知能力。',
          child: Column(
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
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'WebDAV 导入导出',
          subtitle: '用于备份自选、规则和核心偏好。密码只用于本次连接，不会写入本地配置。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const Key('webdav-endpoint-input'),
                controller: _webDavEndpointController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'WebDAV 文件地址',
                  border: OutlineInputBorder(),
                  hintText:
                      'https://dav.example.com/stock-alert-app/backup.json',
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
              const SizedBox(height: 8),
              const Text('MVP 当前覆盖：自选、提醒规则、语音开关、轮询间隔和自选排序偏好。'),
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
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '当前状态',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('最近说明：${status.lastMessage}'),
              const SizedBox(height: 8),
              Text('最近检查：${Formatters.compactDateTime(status.lastCheckAt)}'),
              const SizedBox(height: 8),
              Text(
                '后台监控：${status.serviceEnabled ? '已开启' : '未开启'} · 轮询 ${status.pollIntervalSeconds} 秒',
              ),
              const SizedBox(height: 8),
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
        ),
      ],
    );
  }
}
