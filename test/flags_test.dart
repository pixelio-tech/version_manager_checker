import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

Map<String, dynamic> _body(Map<String, Object?>? flags, {String hash = 'h'}) => {
  'status': 'active',
  'isBlocked': false,
  'updatePriority': 'none',
  'notifications': const [],
  'nextCheckInterval': 1800,
  'configHash': hash,
  'message': '',
  'serverTimestamp': '2026-09-25T10:00:00Z',
  'flags': ?flags,
};

Future<VersionManager> _manager(MockClient mock, {VmStorage? storage}) => VersionManager.init(
  baseUrl: 'https://api.test',
  apiKey: 'vm_live_x',
  namespace: 'com.example.app',
  version: '1.0.0',
  buildNumber: 41,
  platform: 'ios',
  storage: storage,
  client: VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: mock, maxRetries: 0),
);

MockClient _serving(List<Map<String, dynamic>> bodies) {
  var i = 0;
  return MockClient((_) async {
    final b = bodies[i < bodies.length ? i : bodies.length - 1];
    i++;
    return http.Response.bytes(
      utf8.encode(jsonEncode(b)),
      200,
      headers: {'etag': b['configHash'] as String, 'content-type': 'application/json; charset=utf-8'},
    );
  });
}

void main() {
  test('flag отдаёт значение нужного типа или значение по умолчанию', () async {
    final vm = await _manager(_serving([
      _body({'new_checkout': false, 'limit_mb': 25, 'ratio': 1, 'title': 'Привет', 'cfg': {'a': 1}, 'wrong': 'yes'}),
    ]));
    // До первого ответа — значения из кода.
    expect(vm.flag('new_checkout', true), isTrue);

    expect(await vm.check(), isA<VmFresh>());
    expect(vm.flag('new_checkout', true), isFalse);
    expect(vm.isEnabled('new_checkout', defaultValue: true), isFalse);
    expect(vm.flag('limit_mb', 50), 25);
    expect(vm.flag('ratio', 0.5), 1.0);
    expect(vm.flag('title', ''), 'Привет');
    expect(vm.flag<Map<String, Object?>>('cfg', const {})['a'], 1);
    expect(vm.flag('missing', 7), 7);
    // Тип в админке не совпал с кодом — значение по умолчанию, не падение.
    expect(vm.flag('wrong', false), isFalse);
    vm.dispose();
  });

  test('флаги переживают перезапуск и работают без сети', () async {
    final storage = VmMemoryStorage();
    final first = await _manager(_serving([_body({'kill': true})]), storage: storage);
    await first.check();
    first.dispose();

    final offline = MockClient((_) async => throw const FormatException('нет сети'));
    final second = await _manager(offline, storage: storage);
    expect(second.flag('kill', false), isTrue, reason: 'сохранённый конфиг до ответа сервера');
    await second.check();
    expect(second.flag('kill', false), isTrue, reason: 'сервер недоступен — работаем на сохранённом');
    second.dispose();
  });

  test('flagChanges срабатывает только когда значения поменялись', () async {
    final vm = await _manager(_serving([
      _body({'a': true}, hash: 'h1'),
      _body({'a': true}, hash: 'h2'),
      _body({'a': false}, hash: 'h3'),
    ]));
    final seen = <Map<String, Object?>>[];
    final sub = vm.flagChanges.listen(seen.add);
    await vm.check(force: true);
    await vm.check(force: true);
    await vm.check(force: true);
    await Future<void>.delayed(Duration.zero);
    expect(seen.map((m) => m['a']).toList(), [true, false]);
    await sub.cancel();
    vm.dispose();
  });

  test('ответ без флагов — пустой набор', () {
    final r = CheckResult.fromJson(_body(null));
    expect(r.flags, isEmpty);
  });
}
