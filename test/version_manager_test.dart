import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

Map<String, dynamic> _body({String hash = 'hash-1', int interval = 1800}) => {
  'success': true,
  'data': {
    'status': 'active',
    'isBlocked': false,
    'updatePriority': 'none',
    'notifications': const [],
    'nextCheckInterval': interval,
    'configHash': hash,
    'message': '',
    'serverTimestamp': '2026-09-20T10:00:00Z',
  },
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
    final mock = MockClient((_) async => http.Response(jsonEncode(_body()), 200, headers: {'etag': 'hash-1'}));

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
    expect(first!.configHash, 'hash-1');
    // 304 — конфиг не менялся, менеджер возвращает то, что уже знает.
    expect(identical(second, first), isTrue);
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

  test('instance до init бросает понятную ошибку', () {
    expect(() => VersionManager.instance, throwsA(isA<StateError>()));
  });
}
