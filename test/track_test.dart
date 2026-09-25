import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/src/log.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

/// Сервер событий: отвечает [status] и запоминает пачки.
class _EventsServer {
  _EventsServer(this.status);
  int status;
  final batches = <List<dynamic>>[];

  late final client = MockClient((req) async {
    if (req.url.path.endsWith('/events')) {
      if (status >= 200 && status < 300) {
        batches.add((jsonDecode(req.body) as Map)['events'] as List);
      }
      return http.Response('', status);
    }
    return http.Response(
      jsonEncode({
        'status': 'active',
        'isBlocked': false,
        'updatePriority': 'none',
        'notifications': [],
        'nextCheckInterval': 1800,
        'configHash': 'h',
        'message': '',
        'serverTimestamp': '2026-09-25T10:00:00Z',
      }),
      200,
      headers: {'etag': 'h'},
    );
  });
}

Future<VersionManager> _manager(MockClient mock, VmStorage storage) => VersionManager.init(
  baseUrl: 'https://api.test',
  apiKey: 'vm_live_x',
  namespace: 'com.example.app',
  version: '1.0.0',
  buildNumber: 41,
  platform: 'ios',
  storage: storage,
  client: VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: mock, maxRetries: 0),
);

void main() {
  test('track кладёт в очередь, flushEvents отправляет пачкой', () async {
    final server = _EventsServer(204);
    final vm = await _manager(server.client, VmMemoryStorage());
    expect(vm.track('purchase', value: 9.99), isTrue);
    expect(vm.track('onboarding.done'), isTrue);
    await vm.flushEvents();

    expect(server.batches, hasLength(1));
    final sent = server.batches.single;
    expect(sent.map((e) => e['name']), ['purchase', 'onboarding.done']);
    expect(sent.first['value'], 9.99);
    expect(sent.last.containsKey('value'), isFalse);
    expect(DateTime.tryParse(sent.first['occurredAt'] as String), isNotNull);
    vm.dispose();
  });

  test('кривое имя и NaN отбрасываются до отправки', () async {
    final server = _EventsServer(204);
    final vm = await _manager(server.client, VmMemoryStorage());
    expect(vm.track('Purchase'), isFalse);
    expect(vm.track('a b'), isFalse);
    expect(vm.track('x', value: double.nan), isFalse);
    await vm.flushEvents();
    expect(server.batches, isEmpty);
    vm.dispose();
  });

  test('офлайн: события переживают перезапуск и уходят, когда сеть вернулась', () async {
    final storage = VmMemoryStorage();
    final server = _EventsServer(503);
    final first = await _manager(server.client, storage);
    first.track('purchase', value: 5);
    await first.flushEvents();
    expect(server.batches, isEmpty, reason: 'сервер недоступен — события остаются');
    first.dispose();

    server.status = 204;
    final second = await _manager(server.client, storage);
    await second.check();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(server.batches, hasLength(1), reason: 'после ответа сервера очередь уходит сама');
    expect(server.batches.single.single['name'], 'purchase');
    await second.flushEvents();
    expect(server.batches, hasLength(1), reason: 'отправленное не уходит второй раз');
    second.dispose();
  });

  test('отвергнутая пачка выбрасывается, а не застревает', () async {
    final server = _EventsServer(400);
    final vm = await _manager(server.client, VmMemoryStorage());
    vm.track('purchase');
    await vm.flushEvents();
    server.status = 204;
    await vm.flushEvents();
    expect(server.batches, isEmpty);
    vm.dispose();
  });

  test('пачки по 50, очередь не больше 500', () async {
    final server = _EventsServer(503);
    final storage = VmMemoryStorage();
    final queue = VmEventQueue(
      client: VmV3Client(baseUrl: 'https://api.test', apiKey: 'k', httpClient: server.client, maxRetries: 0),
      storage: storage,
      instanceId: () => 'i',
      log: VmLog(null),
      flushAt: 100000,
    );
    for (var i = 0; i < 520; i++) {
      queue.add('e$i');
    }
    expect(queue.length, 500);
    server.status = 204;
    await queue.flush();
    expect(server.batches.map((b) => b.length), List.filled(10, 50));
    expect(server.batches.first.first['name'], 'e20', reason: 'выброшены самые старые');
  });
}
