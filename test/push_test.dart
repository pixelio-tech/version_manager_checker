import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

/// Сервер, который записывает запросы push и отвечает [status].
({MockClient client, List<(String, Map<String, dynamic>)> calls}) _server({int status = 204}) {
  final calls = <(String, Map<String, dynamic>)>[];
  final client = MockClient((req) async {
    calls.add((req.url.path, jsonDecode(req.body) as Map<String, dynamic>));
    return http.Response('', status);
  });
  return (client: client, calls: calls);
}

Future<VersionManager> _manager(MockClient mock, VmStorage storage, {int build = 41, String locale = 'ru-RU'}) =>
    VersionManager.init(
      baseUrl: 'https://api.test',
      apiKey: 'vm_live_x',
      namespace: 'com.example.app',
      version: '1.0.0',
      buildNumber: build,
      platform: 'android',
      locale: locale,
      storage: storage,
      client: VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: mock, maxRetries: 0),
    );

void main() {
  test('токен push уходит один раз, пока не изменились токен, сборка или язык', () async {
    final s = _server();
    final storage = VmMemoryStorage();
    final vm = await _manager(s.client, storage);

    await vm.setPushToken('tok-1');
    await vm.setPushToken('tok-1');
    expect(s.calls, hasLength(1));
    final (path, body) = s.calls.single;
    expect(path, '/api/mobile/v2/push-token');
    expect(body, {
      'instanceId': vm.instanceId,
      'platform': 'android',
      'token': 'tok-1',
      'buildNumber': 41,
      'locale': 'ru-RU',
    });

    await vm.setPushToken('tok-2');
    expect(s.calls, hasLength(2));

    // Обновление приложения: та же установка, новая сборка — сервер должен
    // узнать, иначе таргетинг по сборкам промахнётся.
    final updated = await _manager(s.client, storage, build: 42);
    await updated.setPushToken('tok-2');
    expect(s.calls, hasLength(3));
    expect(s.calls.last.$2['buildNumber'], 42);

    await updated.setPushToken(null);
    expect(s.calls.last.$2['token'], '', reason: 'отказ от уведомлений — пустой токен');
  });

  test('не дошедший токен уходит при следующем вызове', () async {
    var fail = true;
    final calls = <String>[];
    final mock = MockClient((req) async {
      calls.add(req.url.path);
      return http.Response('', fail ? 503 : 204);
    });
    final vm = await _manager(mock, VmMemoryStorage());
    await vm.setPushToken('tok');
    fail = false;
    await vm.setPushToken('tok');
    await vm.setPushToken('tok');
    expect(calls, hasLength(2));
  });

  test('открытие пуша рассылки отмечается и отдаёт действие', () async {
    final s = _server();
    final vm = await _manager(s.client, VmMemoryStorage());

    final open = await vm.pushOpened({
      'vm_campaign_id': 'c-1',
      'vm_notification_id': 'n-1',
      'vm_action': '{"kind":"deeplink","deeplink":"app://sale"}',
    });
    await Future<void>.delayed(Duration.zero);
    expect(open?.campaignId, 'c-1');
    expect(open?.action, {'kind': 'deeplink', 'deeplink': 'app://sale'});
    expect(s.calls.single.$1, '/api/mobile/v2/push-opened');
    expect(s.calls.single.$2, {'campaignId': 'c-1', 'instanceId': vm.instanceId});

    // Тестовая отправка из админки — без рассылки: открытие не считается.
    final test = await vm.pushOpened({'vm_notification_id': 'n-1'});
    expect(test?.campaignId, isNull);
    expect(test?.action, isEmpty);
    expect(s.calls, hasLength(1));

    // Чужой пуш не трогаем.
    expect(await vm.pushOpened({'from': 'другой сервис'}), isNull);
    expect(await vm.pushOpened({'vm_notification_id': 'n', 'vm_action': '{битый'}), isA<VmPushOpen>());
  });
}
