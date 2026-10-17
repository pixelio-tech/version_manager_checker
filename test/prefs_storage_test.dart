import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('VmPrefsStorage пишет и читает строки через shared_preferences', () async {
    const storage = VmPrefsStorage();
    expect(await storage.read('vm.instanceId'), isNull);

    await storage.write('vm.instanceId', 'abc');
    expect(await storage.read('vm.instanceId'), 'abc');
    expect((await SharedPreferences.getInstance()).getString('vm.instanceId'), 'abc');

    await storage.write('vm.instanceId', 'def');
    expect(await const VmPrefsStorage().read('vm.instanceId'), 'def');
  });

  test('VmPrefsStorage видит значения, записанные прежним PrefsStorage из README', () async {
    SharedPreferences.setMockInitialValues({'vm.instanceId': 'legacy-id'});
    expect(await const VmPrefsStorage().read('vm.instanceId'), 'legacy-id');
  });

  test('init без storage хранит instanceId в shared_preferences', () async {
    final mock = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'status': 'active',
          'isBlocked': false,
          'updatePriority': 'none',
          'notifications': const [],
          'nextCheckInterval': 1800,
          'configHash': 'hash-1',
          'message': '',
          'serverTimestamp': '2026-09-20T10:00:00Z',
        }),
        200,
      ),
    );
    Future<VersionManager> init() => VersionManager.init(
      baseUrl: 'https://api.test',
      apiKey: 'vm_live_x',
      namespace: 'com.example.app',
      version: '1.0.0',
      buildNumber: 1,
      platform: 'ios',
      client: VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: mock),
    );

    final first = await init();
    final id = first.instanceId;
    expect((await SharedPreferences.getInstance()).getString('vm.instanceId'), id);
    first.dispose();

    final second = await init();
    expect(second.instanceId, id);
    second.dispose();
  });
  test('сломанное хранилище не роняет init: instanceId живёт до конца запуска', () async {
    final vm = await VersionManager.init(
      baseUrl: 'https://api.test',
      apiKey: 'vm_live_x',
      namespace: 'com.example.app',
      version: '1.0.0',
      buildNumber: 1,
      platform: 'ios',
      storage: _BrokenStorage(),
      client: VmV3Client(
        baseUrl: 'https://api.test',
        apiKey: 'vm_live_x',
        httpClient: MockClient((_) async => http.Response('', 503)),
      ),
    );
    expect(vm.instanceId, hasLength(32));
    vm.dispose();
  });
}

class _BrokenStorage implements VmStorage {
  @override
  Future<String?> read(String key) async => throw StateError('нет хранилища');

  @override
  Future<void> write(String key, String value) async => throw StateError('нет хранилища');
}
