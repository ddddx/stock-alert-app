import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../data/models/stock_quote_snapshot.dart';
import '../../../../data/repositories/in_memory_settings_repository.dart';
import '../../../../services/alerts/alert_message_builder.dart';
import '../../../../services/audio/audio_alert_service.dart';
import '../../../../services/background/monitor_service.dart';
import '../../../../shared/widgets/section_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    required this.monitorService,
    required this.audioService,
    required this.messageBuilder,
    required this.previewQuote,
    required this.onRefresh,
    required this.onChanged,
  });

  final InMemorySettingsRepository repository;
  final MonitorService monitorService;
  final AudioAlertService audioService;
  final AlertMessageBuilder messageBuilder;
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: '监控服务',
          subtitle: '当前为应用内扫描流程，可手动刷新并执行规则评估。',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用监控'),
                subtitle: const Text('开启后保留监控状态，便于后续接入后台轮询。'),
                value: status.serviceEnabled,
                onChanged: (value) async {
                  widget.repository.updateService(value);
                  if (value) {
                    await widget.monitorService.start();
                  } else {
                    await widget.monitorService.stop();
                  }
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 8),
              Row(
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
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('立即刷新'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '语音提醒',
          subtitle: '播报股票名称、代码、价格变动和涨跌幅。',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用语音播报'),
                value: status.soundEnabled,
                onChanged: (value) {
                  widget.repository.updateSound(value);
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
