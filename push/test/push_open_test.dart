import 'package:flutter_test/flutter_test.dart';
import 'package:version_manager_v3_push/version_manager_v3_push.dart';

void main() {
  // Разбор data живёт в ядре (VmPushOpen.fromData); здесь — что пакет
  // отдаёт его наружу и data от FCM (Map<String, dynamic>) разбирается.
  test('data пуша рассылки разбирается через экспорт пакета', () {
    final Map<String, dynamic> data = {
      'vm_campaign_id': 'c-1',
      'vm_notification_id': 'n-1',
      'vm_action': '{"kind":"url","url":"https://example.com"}',
    };
    final open = VmPushOpen.fromData(data);
    expect(open?.campaignId, 'c-1');
    expect(open?.action['url'], 'https://example.com');
  });
}
