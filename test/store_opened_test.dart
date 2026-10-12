import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

/// Сервер, который записывает отметки перехода в магазин. [gate] держит
/// ответ, пока его не завершат: так видно, что магазин открывается, не
/// дожидаясь сети.
({MockClient client, List<(String, Map<String, dynamic>)> calls}) _server({int status = 204, Completer<void>? gate}) {
  final calls = <(String, Map<String, dynamic>)>[];
  final client = MockClient((req) async {
    calls.add((req.url.path, jsonDecode(req.body) as Map<String, dynamic>));
    if (gate != null) await gate.future;
    return http.Response('', status);
  });
  return (client: client, calls: calls);
}

Future<VersionManager> _manager(MockClient mock, {String platform = 'android'}) => VersionManager.init(
  baseUrl: 'https://api.test',
  apiKey: 'vm_live_x',
  namespace: 'com.example.app',
  version: '1.0.0',
  buildNumber: 41,
  platform: platform,
  storage: VmMemoryStorage(),
  client: VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: mock, maxRetries: 0),
);

CheckResult _blocked() => CheckResult.fromJson({
  'status': 'blocked',
  'isBlocked': true,
  'blockReason': 'Версия снята с поддержки',
  'updatePriority': 'forced',
  'recommendedVersion': {
    'versionNumber': '4.2.0',
    'buildNumber': 420,
    'storeLinks': [
      {'platform': 'android', 'storeName': 'Google Play', 'url': 'https://play.google.com/x'},
    ],
  },
  'notifications': const <Map<String, dynamic>>[],
  'nextCheckInterval': 3600,
  'configHash': 'h',
  'message': '',
  'serverTimestamp': '2026-10-12T10:00:00Z',
});

void main() {
  test('клиент: store-opened уходит с установкой и платформой', () async {
    final s = _server();
    final c = VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: s.client, maxRetries: 0);
    expect(await c.recordStoreOpened(instanceId: 'i-1', platform: 'ios'), VmSendResult.sent);
    expect(s.calls.single.$1, '/api/mobile/v2/store-opened');
    expect(s.calls.single.$2, {'instanceId': 'i-1', 'platform': 'ios'});
  });

  test('клиент: 5xx и 403 — повторить, 400 — отвергнуто; не бросает', () async {
    for (final (status, want) in [(503, VmSendResult.retry), (403, VmSendResult.retry), (400, VmSendResult.rejected)]) {
      final s = _server(status: status);
      final c = VmV3Client(baseUrl: 'https://api.test', apiKey: 'k', httpClient: s.client, maxRetries: 0);
      expect(
        await c.recordStoreOpened(instanceId: 'i', platform: 'android'),
        want,
        reason: 'HTTP $status',
      );
    }
    final down = VmV3Client(
      baseUrl: 'https://api.test',
      apiKey: 'k',
      httpClient: MockClient((_) async => throw http.ClientException('нет сети')),
      maxRetries: 0,
    );
    expect(await down.recordStoreOpened(instanceId: 'i', platform: 'android'), VmSendResult.retry);
  });

  test('фасад: отметка за текущую установку и платформу', () async {
    final s = _server();
    final vm = await _manager(s.client);
    expect(await vm.recordStoreOpened(), VmSendResult.sent);
    expect(s.calls.single.$2, {'instanceId': vm.instanceId, 'platform': 'android'});
    vm.dispose();
  });

  test('фасад: чужая платформа и пустышка без init в сеть не ходят', () async {
    final s = _server();
    final vm = await _manager(s.client, platform: 'macos');
    expect(await vm.recordStoreOpened(), isNull);
    vm.dispose();
    expect(VersionManager.isInitialized, isFalse);
    expect(await VersionManager.instance.recordStoreOpened(), isNull);
    expect(s.calls, isEmpty);
  });

  testWidgets('экран блокировки отмечает переход и открывает магазин, не дожидаясь сети', (tester) async {
    final gate = Completer<void>();
    final s = _server(gate: gate);
    final vm = await tester.runAsync(() => _manager(s.client));
    StoreLink? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: VmUpdateGate(
          result: _blocked(),
          platform: 'android',
          onOpenStore: (l) => opened = l,
          child: const SizedBox(),
        ),
      ),
    );

    await tester.tap(find.text('Обновить в Google Play'));
    // Сервер ещё не ответил, а ссылка уже открыта.
    expect(opened?.url, 'https://play.google.com/x');
    await tester.pump();
    expect(s.calls.single.$1, '/api/mobile/v2/store-opened');
    expect(s.calls.single.$2['platform'], 'android');

    gate.complete();
    await tester.pump();
    vm!.dispose();
  });

  testWidgets('reportStoreOpen: false — приложение отмечает само, экран молчит', (tester) async {
    final s = _server();
    final vm = await tester.runAsync(() => _manager(s.client));
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VmBlockedScreen(
          result: _blocked(),
          platform: 'android',
          reportStoreOpen: false,
          onOpenStore: (_) => opened++,
        ),
      ),
    );
    await tester.tap(find.text('Обновить в Google Play'));
    await tester.pump();
    expect(opened, 1);
    expect(s.calls, isEmpty);
    vm!.dispose();
  });

  testWidgets('без init экран блокировки просто открывает магазин', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VmBlockedScreen(result: _blocked(), platform: 'android', onOpenStore: (_) => opened++),
      ),
    );
    await tester.tap(find.text('Обновить в Google Play'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('presentAll: кнопка «в магазин» отмечает переход и отдаёт действие', (tester) async {
    final calls = <String>[];
    final config = {
      'status': 'active',
      'isBlocked': false,
      'updatePriority': 'none',
      'notifications': [
        {
          'id': 'n1',
          'type': 'modal',
          'title': 'Обновитесь',
          'body': '',
          'action': {'kind': 'dismiss'},
          'ui': {
            'v': 1,
            'type': 'card',
            'children': [
              {
                'id': 'b1',
                'type': 'buttons',
                'layout': 'row',
                'buttons': [
                  {
                    'id': 'store',
                    'label': {'ru': 'В магазин'},
                    'style': 'primary',
                    'action': {'kind': 'store'},
                  },
                ],
              },
            ],
          },
        },
      ],
      'nextCheckInterval': 1800,
      'configHash': 'h',
      'message': '',
      'serverTimestamp': '2026-10-12T10:00:00Z',
    };
    final mock = MockClient((req) async {
      calls.add(req.url.path);
      if (req.url.path.endsWith('/check-version')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode(config)),
          200,
          headers: {'etag': 'h', 'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('', 204);
    });
    final vm = (await tester.runAsync(() => _manager(mock)))!;
    await tester.runAsync(vm.check);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    final actions = <String>[];
    unawaited(vm.presentAll(ctx, onAction: (kind, _) => actions.add(kind)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('В магазин'));
    await tester.pumpAndSettle();

    expect(actions, ['store']);
    expect(calls.where((p) => p.endsWith('/store-opened')), hasLength(1));
    vm.dispose();
  });
}
