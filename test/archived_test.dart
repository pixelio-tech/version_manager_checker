import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

/// Ответ v2 архивному приложению — ровно как его сериализует бэкенд
/// (`archivedResult` в version_manager_v3_back/internal/check/compute.go):
/// пустые `flags`, `experiments` и `pushChannels` уходят по `omitempty`,
/// `blockReason` и `recommendedVersion` — null, `configHash` — `archived`.
const _archived = {
  'status': 'active',
  'isBlocked': false,
  'blockReason': null,
  'updatePriority': 'none',
  'recommendedVersion': null,
  'notifications': <Object>[],
  'nextCheckInterval': 3600,
  'configHash': 'archived',
  'message': '',
  'serverTimestamp': '2026-10-12T10:00:00Z',
};

/// Конфиг до архивации: блокировка, флаг, тест и уведомление.
final _live = {
  'status': 'blocked',
  'isBlocked': true,
  'blockReason': 'Версия снята с поддержки',
  'updatePriority': 'forced',
  'recommendedVersion': {
    'versionNumber': '4.2.0',
    'buildNumber': 420,
    'storeLinks': [
      {'platform': 'ios', 'storeName': 'App Store', 'url': 'https://apps.apple.com/app/id1'},
    ],
  },
  'notifications': [
    {'id': 'n1', 'type': 'localPush', 'title': 'Привет', 'body': '', 'action': <String, Object>{}},
  ],
  'flags': {'new_checkout': true},
  'experiments': {
    'paywall': {
      'variant': 'b',
      'params': {'layout': 'grid'},
    },
  },
  'nextCheckInterval': 1800,
  'configHash': 'live',
  'message': 'Обновите приложение',
  'serverTimestamp': '2026-10-11T10:00:00Z',
};

/// Сервер: проверка отвечает тем, что лежит в [body] на момент запроса;
/// на `If-None-Match`, совпавший с `configHash`, — 304, как бэкенд.
({MockClient client, List<String> calls}) _server(Map<String, Object?> Function() body) {
  final calls = <String>[];
  final client = MockClient((req) async {
    calls.add(req.url.path);
    if (!req.url.path.endsWith('/check-version')) return http.Response('', 204);
    final b = body();
    if (req.headers['If-None-Match'] == b['configHash']) return http.Response('', 304);
    return http.Response.bytes(
      utf8.encode(jsonEncode(b)),
      200,
      headers: {'etag': b['configHash'] as String, 'content-type': 'application/json; charset=utf-8'},
    );
  });
  return (client: client, calls: calls);
}

Future<VersionManager> _manager(MockClient mock, {VmStorage? storage}) => VersionManager.init(
  baseUrl: 'https://api.test',
  apiKey: 'vm_live_x',
  namespace: 'com.example.app',
  version: '1.0.0',
  buildNumber: 41,
  platform: 'ios',
  storage: storage ?? VmMemoryStorage(),
  client: VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: mock, maxRetries: 0),
);

void main() {
  test('разбор: архивный ответ — «всё в порядке, показывать нечего»', () {
    final r = CheckResult.fromJson(jsonDecode(jsonEncode(_archived)) as Map<String, dynamic>);
    expect(r.status, 'active');
    expect(r.isBlocked, isFalse);
    expect(r.blockReason, isNull);
    expect(r.updateTarget, isNull);
    expect(r.notifications, isEmpty);
    expect(r.flags, isEmpty);
    expect(r.experiments, isEmpty);
    expect(r.pushChannels, isEmpty);
    expect(r.configHash, 'archived');
    expect(vmVerdictFor(r), VmGateVerdict.pass);
    expect(vmIsMaintenance(r), isFalse);
  });

  test('приложение ушло в архив: флаги — по умолчанию, тесты — контроль, блокировка снята', () async {
    Map<String, Object?> current = _live;
    final s = _server(() => current);
    final vm = await _manager(s.client);

    await vm.check();
    expect(vm.flag('new_checkout', false), isTrue);
    expect(vmVerdictFor(vm.lastResult), VmGateVerdict.block);

    current = _archived;
    final changes = <Map<String, Object?>>[];
    final sub = vm.flagChanges.listen(changes.add);
    final outcome = await vm.check();
    await Future<void>.delayed(Duration.zero);

    expect(outcome, isA<VmFresh>());
    expect(vmVerdictFor(outcome.result), VmGateVerdict.pass);
    expect(vm.flags, isEmpty);
    expect(vm.flag('new_checkout', false), isFalse);
    expect(vm.isEnabled('new_checkout'), isFalse);
    expect(changes, [isEmpty], reason: 'флаги пропали — подписчики должны узнать');

    final paywall = vm.experiment('paywall');
    expect(paywall.isActive, isFalse);
    expect(paywall.variant, isNull);
    expect(paywall.getString('layout', 'classic'), 'classic');
    expect(vm.experiments, isEmpty);
    await vm.flushEvents();
    expect(s.calls.where((p) => p.endsWith('/experiment-exposure')), isEmpty, reason: 'вне теста экспозиции нет');

    // Каналы из админки пропали вместе с конфигом.
    expect((await vm.planPushChannels()).create, isEmpty);

    // Повторная проверка — 304 по ETag `archived`: ответ остаётся тем же.
    final again = await vm.check();
    expect(again, isA<VmUnchanged>());
    expect(again.result?.configHash, 'archived');

    await sub.cancel();
    vm.dispose();
  });

  test('архивный ответ из кэша переживает перезапуск', () async {
    final storage = VmMemoryStorage();
    final s = _server(() => _archived);
    final vm = await _manager(s.client, storage: storage);
    await vm.check();
    vm.dispose();

    final restarted = await _manager(s.client, storage: storage);
    expect(restarted.lastResult?.configHash, 'archived');
    expect(restarted.flag('upload_limit_mb', 50), 50);
    restarted.dispose();
  });

  testWidgets('архив: ни экрана обновления, ни уведомлений', (tester) async {
    final s = _server(() => _archived);
    final vm = (await tester.runAsync(() => _manager(s.client)))!;
    await tester.runAsync(vm.check);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: VmUpdateGate(
          result: vm.lastResult,
          platform: 'ios',
          child: Builder(
            builder: (context) {
              ctx = context;
              return const Text('домашний экран');
            },
          ),
        ),
      ),
    );
    expect(find.text('домашний экран'), findsOneWidget);

    final shown = <String>[];
    await vm.presentAll(ctx, onAction: (k, _) => shown.add(k), onLocalPush: (p) => shown.add(p.id));
    await tester.pumpAndSettle();
    expect(shown, isEmpty);
    expect(find.byType(Dialog), findsNothing);
    vm.dispose();
  });
}
