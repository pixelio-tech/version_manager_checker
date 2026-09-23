import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

Map<String, dynamic> _body({String hash = 'hash-1', int interval = 1800}) => {
  'status': 'active',
  'isBlocked': false,
  'updatePriority': 'none',
  'notifications': const [],
  'nextCheckInterval': interval,
  'configHash': hash,
  'message': '',
  'serverTimestamp': '2026-09-20T10:00:00Z',
};

Future<VersionManager> _manager(MockClient mock, {VmStorage? storage}) => VersionManager.init(
  baseUrl: 'https://api.test',
  apiKey: 'vm_live_x',
  namespace: 'com.example.app',
  version: '1.0.0',
  buildNumber: 1,
  platform: 'ios',
  storage: storage,
  client: VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: mock),
);

void main() {
  test('instanceId генерируется один раз и переживает переинициализацию', () async {
    final storage = VmMemoryStorage();
    final mock = MockClient(
      (_) async => http.Response(jsonEncode(_body()), 200, headers: {'etag': 'hash-1'}),
    );

    final first = await _manager(mock, storage: storage);
    final id = first.instanceId;
    expect(id, hasLength(32));
    first.dispose();

    final second = await _manager(mock, storage: storage);
    expect(second.instanceId, id);
    second.dispose();
  });

  test('ETag подставляется в следующий запрос, а 304 отдаёт прежний результат', () async {
    final sentEtags = <String?>[];
    var call = 0;
    final mock = MockClient((req) async {
      sentEtags.add(req.headers['If-None-Match']);
      call++;
      if (call == 1) return http.Response(jsonEncode(_body()), 200, headers: {'etag': 'hash-1'});
      return http.Response('', 304, headers: {'etag': 'hash-1'});
    });

    final vm = await _manager(mock);
    final first = await vm.check();
    final second = await vm.check();

    expect(sentEtags, [null, 'hash-1']);
    expect(first, isA<VmFresh>());
    expect(first.result!.configHash, 'hash-1');
    // 304 — конфиг не менялся, менеджер возвращает то, что уже знает.
    expect(second, isA<VmUnchanged>());
    expect(identical(second.result, first.result), isTrue);
    vm.dispose();
  });

  test('force сбрасывает ETag', () async {
    final sentEtags = <String?>[];
    final mock = MockClient((req) async {
      sentEtags.add(req.headers['If-None-Match']);
      return http.Response(jsonEncode(_body()), 200, headers: {'etag': 'hash-1'});
    });

    final vm = await _manager(mock);
    await vm.check();
    await vm.check(force: true);

    expect(sentEtags, [null, null]);
    vm.dispose();
  });

  test('новый конфиг попадает в поток results', () async {
    var call = 0;
    final mock = MockClient((_) async {
      call++;
      return http.Response(jsonEncode(_body(hash: 'hash-$call')), 200, headers: {'etag': 'hash-$call'});
    });

    final vm = await _manager(mock);
    final seen = <String>[];
    final sub = vm.results.listen((r) => seen.add(r.configHash));

    await vm.check();
    await vm.check();
    await Future<void>.delayed(Duration.zero);

    expect(seen, ['hash-1', 'hash-2']);
    await sub.cancel();
    vm.dispose();
  });

  test('instance до init не бросает и не проверяет версию', () async {
    // Забытая инициализация — ошибка интеграции, но ронять из-за неё чужой
    // экран пакет не вправе: у хоста этот вызов стоит в build или в main.
    final logged = <VmLogEvent>[];
    final outcome = await VersionManager.instance.check();

    expect(outcome, isA<VmUnavailable>());
    expect(outcome.result, isNull);
    expect(logged, isEmpty);
  });

  test('кэш переживает перезапуск и действует, пока сервер молчит', () async {
    final storage = VmMemoryStorage();
    var answer = true;
    final mock = MockClient((_) async {
      if (!answer) throw const SocketException('сеть недоступна');
      return http.Response(jsonEncode(_body(hash: 'cached')), 200, headers: {'etag': 'cached'});
    });

    final first = await _manager(mock, storage: storage);
    expect(await first.check(), isA<VmFresh>());
    first.dispose();

    // Новый запуск приложения: сервер не отвечает, но конфиг уже знаком.
    answer = false;
    final second = await _manager(mock, storage: storage);
    final outcome = await second.check();

    expect(outcome, isA<VmUnavailable>());
    expect(outcome.result?.configHash, 'cached');
    second.dispose();
  });

  test('просроченный кэш не применяется', () async {
    final storage = VmMemoryStorage();
    final mock = MockClient((_) async => throw const SocketException('сеть недоступна'));
    await storage.write('vm.config', jsonEncode(_body(hash: 'old')));
    await storage.write(
      'vm.configAt',
      DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String(),
    );

    final vm = await VersionManager.init(
      baseUrl: 'https://api.test',
      apiKey: 'vm_live_x',
      namespace: 'com.example.app',
      version: '1.0.0',
      buildNumber: 1,
      platform: 'ios',
      storage: storage,
      cacheTtl: const Duration(days: 7),
      client: VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: mock),
    );

    final outcome = await vm.check();
    expect(outcome, isA<VmUnavailable>());
    expect(outcome.result, isNull, reason: 'конфиг старше срока хранения не должен действовать');
    vm.dispose();
  });

  test('cacheTtl: zero выключает кэш совсем', () async {
    final storage = VmMemoryStorage();
    var answer = true;
    final mock = MockClient((_) async {
      if (!answer) throw const SocketException('сеть недоступна');
      return http.Response(jsonEncode(_body()), 200, headers: {'etag': 'hash-1'});
    });

    final vm = await VersionManager.init(
      baseUrl: 'https://api.test',
      apiKey: 'vm_live_x',
      namespace: 'com.example.app',
      version: '1.0.0',
      buildNumber: 1,
      platform: 'ios',
      storage: storage,
      cacheTtl: Duration.zero,
      client: VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: mock),
    );
    await vm.check();
    answer = false;
    final outcome = await vm.check();

    expect(outcome.result, isNull);
    expect(await storage.read('vm.config'), isNull);
    vm.dispose();
  });

  test('свежий ответ важнее сохранённого', () async {
    final storage = VmMemoryStorage();
    await storage.write('vm.config', jsonEncode(_body(hash: 'stale')));
    await storage.write('vm.configAt', DateTime.now().toUtc().toIso8601String());
    final mock = MockClient(
      (_) async => http.Response(jsonEncode(_body(hash: 'fresh')), 200, headers: {'etag': 'fresh'}),
    );

    final vm = await _manager(mock, storage: storage);
    final outcome = await vm.check();

    expect(outcome, isA<VmFresh>());
    expect(outcome.result!.configHash, 'fresh');
    vm.dispose();
  });

  test('отказ сервера не бросает и уходит в failures', () async {
    final mock = MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(jsonEncode({'status': 403, 'code': 'INVALID_API_KEY', 'detail': 'ключ отозван'})),
        403,
        headers: {'content-type': 'application/problem+json; charset=utf-8'},
      ),
    );

    final vm = await _manager(mock);
    final seen = <Object>[];
    final sub = vm.failures.listen(seen.add);

    final outcome = await vm.check();
    await Future<void>.delayed(Duration.zero);

    expect(outcome, isA<VmUnavailable>());
    expect((outcome as VmUnavailable).cause, isA<VmApiException>());
    expect((outcome.cause as VmApiException).isBadKey, isTrue);
    expect(seen, hasLength(1));
    await sub.cancel();
    vm.dispose();
  });

  test('проверка укладывается в бюджет времени', () async {
    // Три попытки по десять секунд держали бы запуск приложения полминуты.
    final mock = MockClient((_) async {
      await Future<void>.delayed(const Duration(seconds: 5));
      return http.Response(jsonEncode(_body()), 200);
    });

    final vm = await VersionManager.init(
      baseUrl: 'https://api.test',
      apiKey: 'vm_live_x',
      namespace: 'com.example.app',
      version: '1.0.0',
      buildNumber: 1,
      platform: 'ios',
      budget: const Duration(milliseconds: 200),
      client: VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: mock),
    );

    final started = DateTime.now();
    final outcome = await vm.check();
    final spent = DateTime.now().difference(started);

    expect(outcome, isA<VmUnavailable>());
    expect(spent, lessThan(const Duration(seconds: 2)));
    vm.dispose();
  });
}
