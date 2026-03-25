import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../data/models/stock_quote_snapshot.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../services/alerts/alert_message_builder.dart';
import '../../../../services/audio/audio_alert_service.dart';
import '../../../../services/background/monitor_service.dart';
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
  });

  final SettingsRepository repository;
  final MonitorService monitorService;
  final AudioAlertService audioService;
  final AlertMessageBuilder messageBuilder;
  final PlatformBridgeService platformBridgeService;
  final StockQuoteSnapshot? previewQuote;
  final Future<void> Function() onRefresh;
  final VoidCallback onChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _toast;

  @override
  Widget build(BuildContext context) {
    final status = widget.repository.getStatus();
    final pollIntervalOptions = const [15, 20, 30, 45, 60, 120, 300];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: '后台监控',
          subtitle: '已接入 Android 前台服务常驻通知、原生后台轮询、开机恢复入口和系统设置跳转，后台可用性比单纯应用内扫描更稳。',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用后台监控守护'),
                subtitle: const Text('开启后会拉起常驻通知，并由原生前台服务持续后台轮询 A 股行情。'),
                value: status.serviceEnabled,
                onChanged: (value) async {
                  await widget.repository.updateService(value);
                  if (value) {
                    await widget.monitorService.start();
                    await widget.monitorService.requestBackgroundRefresh();
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _toast = '已启用后台守护，原生前台服务会按设定间隔持续轮询。';
                    });
                  } else {
                    await widget.monitorService.stop();
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _toast = '已关闭后台监控守护。';
                    });
                  }
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: status.pollIntervalSeconds,
                decoration: const InputDecoration(
                  labelText: '后台轮询间隔',
                  border: OutlineInputBorder(),
                  helperText: '建议 15~30 秒；越短越实时，但更耗电。',
                ),
                items: pollIntervalOptions
                    .map(
                      (seconds) => DropdownMenuItem<int>(
                        value: seconds,
                        child: Text('$seconds 秒'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) async {
                  if (value == null) {
                    return;
                  }
                  await widget.repository.updatePollIntervalSeconds(value);
                  if (status.serviceEnabled) {
                    await widget.monitorService.reload();
                  }
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _toast = '后台轮询间隔已更新为 $value 秒。';
                  });
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await widget.monitorService.prepare();
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _toast = '语音播报能力已预热，可以直接试播真实文案。';
                      });
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
                      await widget.platformBridgeService.openNotificationSettings();
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _toast = '已打开通知设置，请确认允许通知与常驻提醒。';
                      });
                    },
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('通知权限'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await widget.platformBridgeService.openBatteryOptimizationSettings();
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _toast = '已打开电池优化设置，建议将本应用加入白名单。';
                      });
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
          subtitle: '播报股票名称、代码、波动金额与涨跌幅，不再使用占位提示。后台原生轮询触发时也会走系统 TTS。',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用语音播报'),
                value: status.soundEnabled,
                onChanged: (value) async {
                  await widget.repository.updateSound(value);
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _toast = value ? '已开启语音播报。' : '已关闭语音播报。';
                  });
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () async {
                    final text = widget.messageBuilder.buildPreviewText(widget.previewQuote);
                    final played = await widget.audioService.speak(text);
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _toast = played ? '已试播：$text' : '平台未返回播报成功，文案为：$text';
                    });
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
              Text(status.serviceEnabled ? '后台守护：已开启常驻通知 + 原生后台轮询' : '后台守护：未开启'),
              const SizedBox(height: 8),
              Text('轮询间隔：${status.pollIntervalSeconds} 秒'),
              const SizedBox(height: 8),
              const Text('本地数据已持久化，重启应用后会保留自选、规则、历史与设置。'),
              const SizedBox(height: 8),
              const Text('若系统强杀进程，前台服务会尽量粘性重启；开机/应用更新后也会尝试自动恢复。'),
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
