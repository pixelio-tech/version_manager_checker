import 'dart:convert';
import 'dart:io';

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

Map<String, Object?> _a(String variant, [Map<String, Object?> params = const {}, bool shipped = false]) => {
  'variant': variant,
  'params': params,
  if (shipped) 'shipped': true,
};

void main() {
  test('experiment отдаёт вариант и параметры, экспозиция — одна за запуск', () async {
    final s = _server(
      _body(
        experiments: {
          'paywall': _a('compact', {
            'layout': 'compact',
            'trial_days': 7,
            'config': {'plans': 2},
          }),
          'onboarding': _a('control', {'steps': 4}),
        },
      ),
    );
    final vm = await _manager(s.client);
    final before = vm.experiment('paywall');
    expect(before.variant, isNull, reason: 'до ответа сервера — вне теста');
    expect(before.getString('layout', 'classic'), 'classic', reason: 'значение из кода');
    expect(s.exposures, isEmpty, reason: 'без варианта экспозиции нет');

    await vm.check();
    final paywall = vm.experiment('paywall');
    expect(paywall.isActive, isTrue);
    expect(paywall.getString('layout', 'classic'), 'compact');
    expect(paywall.getInt('trial_days', 3), 7);
    expect(paywall.getDouble('trial_days', 3.0), 7.0);
    expect(paywall.getJson('config', const {}), {'plans': 2});
    expect(paywall.getBool('missing', true), isTrue, reason: 'параметра нет — значение из кода');
    expect(paywall.getInt('layout', 1), 1, reason: 'тип не совпал — значение из кода');
    expect(vm.experiment('onboarding').variant, 'control');
    expect(vm.experiment('missing').variant, isNull);
    await Future<void>.delayed(Duration.zero);

    expect(s.exposures.map((e) => e['experimentKey']), ['paywall', 'onboarding']);
    expect(s.exposures.first['instanceId'], vm.instanceId);
    expect(vm.experiments, {'paywall': 'compact', 'onboarding': 'control'});
    vm.dispose();
  });

  test('isActive и карта experiments экспозицию не отмечают', () async {
    final s = _server(_body(experiments: {'paywall': _a('compact')}));
    final vm = await _manager(s.client);
    await vm.check();
    expect(vm.experiment('paywall').isActive, isTrue);
    expect(vm.experiments['paywall'], 'compact');
    await Future<void>.delayed(Duration.zero);
    expect(s.exposures, isEmpty);
    vm.experiment('paywall').logExposure();
    await Future<void>.delayed(Duration.zero);
    expect(s.exposures, hasLength(1));
    vm.dispose();
  });

  test('выкаченный тест отдаёт параметры победителя без экспозиции', () async {
    final s = _server(
      _body(
        experiments: {
          'paywall': _a('compact', {'layout': 'compact'}, true),
        },
      ),
    );
    final vm = await _manager(s.client);
    await vm.check();
    final e = vm.experiment('paywall');
    expect(e.isShipped, isTrue);
    expect(e.variant, 'compact');
    expect(e.getString('layout', 'classic'), 'compact');
    await Future<void>.delayed(Duration.zero);
    expect(s.exposures, isEmpty);
    vm.dispose();
  });

  test('отказ сервера на экспозиции не ломает чтение варианта', () async {
    final s = _server(_body(experiments: {'paywall': _a('compact')}), exposureStatus: 500);
    final vm = await _manager(s.client);
    await vm.check();
    expect(vm.experiment('paywall').variant, 'compact');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(s.exposures, hasLength(1));
    vm.dispose();
  });

  test('экспозиция переживает сбой сети и перезапуск (checker#16)', () async {
    final storage = VmMemoryStorage();
    final body = _body(experiments: {'paywall': _a('compact', {'layout': 'compact'})});
    // Проверка проходит, а экспозиция — нет: человек увидел пейвол и закрыл
    // приложение, пока запрос шёл.
    var exposureTries = 0;
    final flaky = MockClient((req) async {
      if (req.url.path.endsWith('/experiment-exposure')) {
        exposureTries++;
        throw const SocketException('нет сети');
      }
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'etag': 'h', 'content-type': 'application/json; charset=utf-8'});
    });
    final first = await _manager(flaky, storage: storage);
    await first.check();
    expect(first.experiment('paywall').getString('layout', 'classic'), 'compact');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(exposureTries, 1);
    first.dispose();

    final s = _server(body);
    final second = await _manager(s.client, storage: storage);
    await second.flushEvents();
    expect(s.exposures.map((e) => e['experimentKey']), ['paywall'], reason: 'экспозиция из очереди прошлого запуска');
    second.dispose();
  });

  test('варианты и параметры переживают перезапуск вместе с сохранённым конфигом', () async {
    final storage = VmMemoryStorage();
    final first = await _manager(
      _server(
        _body(
          experiments: {
            'paywall': _a('compact', {'layout': 'compact'}),
          },
        ),
      ).client,
      storage: storage,
    );
    await first.check();
    first.dispose();

    final offline = MockClient((_) async => throw const FormatException('нет сети'));
    final second = await _manager(offline, storage: storage);
    expect(second.experiment('paywall').getString('layout', 'classic'), 'compact');
    second.dispose();
  });

  test('флаги и тесты независимы: чтение флага экспозицию не шлёт', () async {
    final s = _server(
      _body(
        experiments: {
          'checkout': _a('green', {'button_color': 'green'}),
        },
        flags: {'button_color': 'blue'},
      ),
    );
    final vm = await _manager(s.client);
    await vm.check();
    expect(vm.flag('button_color', 'red'), 'blue', reason: 'тест не подменяет флаг');
    await Future<void>.delayed(Duration.zero);
    expect(s.exposures, isEmpty);
    expect(vm.experiment('checkout').getString('button_color', 'red'), 'green');
    vm.dispose();
  });

  test('разбор: без поля, с мусором и в старом формате', () {
    expect(CheckResult.fromJson(_body()).experiments, isEmpty);
    final r = CheckResult.fromJson(
      _body(
        experiments: {
          'ok': _a('b', {'x': 1}),
          'bad': 5,
          'old': 'c',
        },
      ),
    );
    expect(r.experiments.keys, unorderedEquals(['ok', 'old']));
    expect(r.experiments['ok']!.params, {'x': 1});
    expect(r.experiments['old']!.variant, 'c', reason: 'сохранённый конфиг до #66');
    expect(r.experiments['old']!.params, isEmpty);
  });
}
