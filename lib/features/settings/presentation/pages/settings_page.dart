import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../data/models/stock_quote_snapshot.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../services/alerts/alert_message_builder.dart';
import '../../../../services/audio/audio_alert_service.dart';
import '../../../../services/background/monitor_service.dart';
import '../../../../services/background/monitoring_policy.dart';
import '../../../../services/platform/platform_bridge_service.dart';
import '../../../../shared/widgets/section_card.dart';

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

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _intervalController;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController(
      text: widget.repository.getStatus().pollIntervalSeconds.toString(),
    );
  }

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _applyPollInterval() async {
    final rawValue = _intervalController.text.trim();
    final parsed = int.tryParse(rawValue);
    if (parsed == null) {
      final current = widget.repository.getStatus().pollIntervalSeconds;
      _syncIntervalController(current);
      _showFeedback(
        '请输入 $minMonitorPollIntervalSeconds 到 $maxMonitorPollIntervalSeconds 秒之间的整数。',
      );
      return;
    }

    final normalized = parsed
        .clamp(minMonitorPollIntervalSeconds, maxMonitorPollIntervalSeconds)
        .toInt();
    await widget.repository.updatePollIntervalSeconds(normalized);
    if (widget.repository.getStatus().serviceEnabled) {
      await widget.monitorService.reload();
    }
    _syncIntervalController(normalized);
    final feedback = parsed == normalized
        ? '后台轮询间隔已更新为 $normalized 秒。'
        : '输入值超出允许范围，已自动调整为 $normalized 秒。';
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: '后台监控',
          subtitle:
              '安卓端已接入前台服务、常驻通知和系统设置跳转。首次使用前，请先完成通知授权和电池优化引导。',
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
                        await widget.monitorService.requestBackgroundRefresh();
                      }
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
                        granted
                            ? '通知权限已授予。'
                            : '未能直接获取通知权限，已打开系统通知设置，请确认允许通知。',
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
          subtitle:
              '试播与前台可见时的播报共用同一条应用内语音播报链路；后台原生轮询阶段暂保留前台服务和通知能力。',
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
          title: '当前状态',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('最近说明：${status.lastMessage}'),
              const SizedBox(height: 8),
              Text('最近检查：${Formatters.compactDateTime(status.lastCheckAt)}'),
              const SizedBox(height: 8),
              Text(
                status.serviceEnabled
                    ? '后台守护：已开启常驻通知和原生后台轮询'
                    : '后台守护：未开启',
              ),
              const SizedBox(height: 8),
              Text('轮询间隔：${status.pollIntervalSeconds} 秒'),
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
