import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/services/platform/platform_bridge_service.dart';

void main() {
  test('fake platform bridge records pause and resume calls', () async {
    final bridge = _FakePlatformBridgeService();

    expect(await bridge.pauseForegroundMonitorService(), isTrue);
    expect(await bridge.resumeForegroundMonitorService(), isTrue);

    expect(bridge.pauseCalls, 1);
    expect(bridge.resumeCalls, 1);
  });
}

class _FakePlatformBridgeService extends PlatformBridgeService {
  int pauseCalls = 0;
  int resumeCalls = 0;

  @override
  Future<bool> pauseForegroundMonitorService() async {
    pauseCalls += 1;
    return true;
  }

  @override
  Future<bool> resumeForegroundMonitorService() async {
    resumeCalls += 1;
    return true;
  }
}
