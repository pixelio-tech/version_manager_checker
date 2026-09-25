import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

Map<String, dynamic> _body({Map<String, Object?>? experiments, Map<String, Object?>? flags}) => {
  'status': 'active',
  'isBlocked': false,
  'updatePriority': 'none',
  'notifications': const [],
  'nextCheckInterval': 1800,
  'configHash': 'h',
  'message': '',
  'serverTimestamp': '2026-09-25T10:00:00Z',
  'flags': ?flags,
  'experiments': ?experiments,
};

/// Сервер, который отвечает на проверку [body] и записывает экспозиции.
({MockClient client, List<Map<String, dynamic>> exposures}) _server(
  Map<String, dynamic> body, {
  int exposureStatus = 204,
}) {
  final exposures = <Map<String, dynamic>>[];
  final client = MockClient((req) async {
    if (req.url.path.endsWith('/experiment-exposure')) {
      exposures.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('', exposureStatus);
    }
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'etag': 'h', 'content-type': 'application/json; charset=utf-8'},
    );
  });
  return (client: client, exposures: exposures);
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
  test('experiment отдаёт вариант и отправляет экспозицию один раз', () async {
    final s = _server(_body(experiments: {'paywall': 'compact', 'onboarding': 'control'}));
    final vm = await _manager(s.client);
    expect(vm.experiment('paywall'), isNull, reason: 'до ответа сервера — вне эксперимента');
    expect(s.exposures, isEmpty, reason: 'без варианта экспозиции нет');

    await vm.check();
    expect(vm.experiment('paywall'), 'compact');
    expect(vm.experiment('paywall'), 'compact');
    expect(vm.experiment('onboarding'), 'control');
    expect(vm.experiment('missing'), isNull);
    await Future<void>.delayed(Duration.zero);

    expect(s.exposures.map((e) => e['experimentKey']), ['paywall', 'onboarding']);
    expect(s.exposures.first['instanceId'], vm.instanceId);
    expect(vm.experiments, {'paywall': 'compact', 'onboarding': 'control'});
    vm.dispose();
  });

  test('отказ сервера на экспозиции не ломает чтение варианта', () async {
    final s = _server(_body(experiments: {'paywall': 'compact'}), exposureStatus: 500);
    final vm = await _manager(s.client);
    await vm.check();
    expect(vm.experiment('paywall'), 'compact');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(s.exposures, hasLength(1));
    vm.dispose();
  });

  test('варианты переживают перезапуск вместе с сохранённым конфигом', () async {
    final storage = VmMemoryStorage();
    final first = await _manager(_server(_body(experiments: {'paywall': 'compact'})).client, storage: storage);
    await first.check();
    first.dispose();

    final offline = MockClient((_) async => throw const FormatException('нет сети'));
    final second = await _manager(offline, storage: storage);
    expect(second.experiment('paywall'), 'compact');
    second.dispose();
  });

  test('чтение флага под экспериментом отмечает экспозицию', () async {
    final s = _server({
      ..._body(experiments: {'checkout': 'green'}, flags: {'button_color': 'green', 'plain': true}),
      'experimentFlags': {'button_color': 'checkout'},
    });
    final vm = await _manager(s.client);
    await vm.check();
    expect(vm.flag('plain', false), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(s.exposures, isEmpty, reason: 'флаг вне эксперимента экспозицию не шлёт');

    expect(vm.flag('button_color', 'blue'), 'green');
    expect(vm.flag('button_color', 'blue'), 'green');
    expect(vm.experiment('checkout'), 'green');
    await Future<void>.delayed(Duration.zero);
    expect(s.exposures.map((e) => e['experimentKey']), ['checkout'], reason: 'одна экспозиция на эксперимент за запуск');
    vm.dispose();
  });

  test('разбор: без поля и с мусором — пустой набор', () {
    expect(CheckResult.fromJson(_body()).experiments, isEmpty);
    final r = CheckResult.fromJson(_body(experiments: {'ok': 'b', 'bad': 5}));
    expect(r.experiments, {'ok': 'b'});
  });
}
