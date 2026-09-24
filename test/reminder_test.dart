import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

Map<String, dynamic> _body({
  required String frequency,
  int? everyNth,
  int? periodHours,
  int build = 412,
  String priority = 'recommended',
}) => {
  'status': 'update_available',
  'isBlocked': false,
  'updatePriority': priority,
  'recommendedVersion': {
    'versionNumber': '2.4.0',
    'buildNumber': build,
    'changelog': '',
    'frequency': frequency,
    'everyNth': ?everyNth,
    'periodHours': ?periodHours,
    'storeLinks': const [],
  },
  'notifications': const [],
  'nextCheckInterval': 1800,
  'configHash': 'hash-$build-$frequency',
  'message': '',
  'serverTimestamp': '2026-09-20T10:00:00Z',
};

/// Запуск приложения: каждый init — новый старт поверх того же хранилища.
Future<VersionManager> _launch(Map<String, dynamic> body, VmStorage storage) => VersionManager.init(
  baseUrl: 'https://api.test',
  apiKey: 'vm_live_x',
  namespace: 'com.example.app',
  version: '1.0.0',
  buildNumber: 1,
  platform: 'ios',
  storage: storage,
  client: VmV3Client(
    baseUrl: 'https://api.test',
    apiKey: 'vm_live_x',
    httpClient: MockClient((_) async => http.Response(jsonEncode(body), 200)),
  ),
);

RecommendedVersion _version({required String frequency, int? everyNth, int? periodHours, int build = 412}) =>
    RecommendedVersion.fromJson(
      _body(frequency: frequency, everyNth: everyNth, periodHours: periodHours, build: build)['recommendedVersion']
          as Map<String, dynamic>,
    );

void main() {
  test('every_launch напоминает на каждом запуске', () {
    final v = _version(frequency: 'every_launch');
    for (var launch = 1; launch <= 3; launch++) {
      final shown = VmReminderState(target: 412, shownAtLaunch: launch - 1, shownAt: DateTime.now());
      expect(vmShouldRemind(version: v, state: shown, launch: launch, now: DateTime.now()), isTrue);
    }
  });

  test('one_time напоминает ровно один раз', () {
    final v = _version(frequency: 'one_time');
    const fresh = VmReminderState();
    expect(vmShouldRemind(version: v, state: fresh, launch: 1, now: DateTime.now()), isTrue);

    final shown = VmReminderState(target: 412, shownAtLaunch: 1, shownAt: DateTime.now());
    expect(vmShouldRemind(version: v, state: shown, launch: 9, now: DateTime.now()), isFalse);
  });

  test('every_nth напоминает на первом запуске и потом через N', () {
    final v = _version(frequency: 'every_nth', everyNth: 3);
    const fresh = VmReminderState();
    expect(vmShouldRemind(version: v, state: fresh, launch: 1, now: DateTime.now()), isTrue);

    const shown = VmReminderState(target: 412, shownAtLaunch: 1);
    expect(vmShouldRemind(version: v, state: shown, launch: 2, now: DateTime.now()), isFalse);
    expect(vmShouldRemind(version: v, state: shown, launch: 3, now: DateTime.now()), isFalse);
    expect(vmShouldRemind(version: v, state: shown, launch: 4, now: DateTime.now()), isTrue);
  });

  test('every_x_hours выдерживает паузу', () {
    final v = _version(frequency: 'every_x_hours', periodHours: 24);
    final now = DateTime(2026, 9, 24, 12);
    final state = VmReminderState(target: 412, shownAtLaunch: 1, shownAt: now.subtract(const Duration(hours: 23)));
    expect(vmShouldRemind(version: v, state: state, launch: 5, now: now), isFalse);
    expect(vmShouldRemind(version: v, state: state, launch: 5, now: now.add(const Duration(hours: 2))), isTrue);
  });

  test('новая рекомендованная сборка сбрасывает счётчики', () {
    // Человек, пропустивший два запуска из трёх, при новом релизе не должен
    // ждать ещё столько же: это уже другое обновление.
    final v = _version(frequency: 'every_nth', everyNth: 3, build: 500);
    const shown = VmReminderState(target: 412, shownAtLaunch: 7);
    expect(vmShouldRemind(version: v, state: shown, launch: 8, now: DateTime.now()), isTrue);
  });

  test('незнакомый режим ведёт себя как every_launch', () {
    final v = _version(frequency: 'every_full_moon');
    final shown = VmReminderState(target: 412, shownAtLaunch: 1, shownAt: DateTime.now());
    expect(vmShouldRemind(version: v, state: shown, launch: 2, now: DateTime.now()), isTrue);
  });

  test('счётчик запусков растёт раз в init и переживает перезапуск', () async {
    final storage = VmMemoryStorage();
    final body = _body(frequency: 'every_launch');

    final first = await _launch(body, storage);
    expect(first.launchCount, 1);
    await first.check();
    await first.check();
    // Проверок две, а запуск один: «каждый N-й запуск» не должен считаться по
    // проверкам — их за старт бывает несколько.
    expect(first.launchCount, 1);
    first.dispose();

    final second = await _launch(body, storage);
    expect(second.launchCount, 2);
    second.dispose();
  });

  test('one_time: отметка о показе переживает перезапуск', () async {
    final storage = VmMemoryStorage();
    final body = _body(frequency: 'one_time');

    final first = await _launch(body, storage);
    await first.check();
    expect(first.shouldRemindAboutUpdate(), isTrue);
    await first.markUpdateReminderShown();
    expect(first.shouldRemindAboutUpdate(), isFalse);
    first.dispose();

    final second = await _launch(body, storage);
    await second.check();
    expect(second.shouldRemindAboutUpdate(), isFalse);
    second.dispose();
  });

  test('every_nth: пауза считается по запускам из хранилища', () async {
    final storage = VmMemoryStorage();
    final body = _body(frequency: 'every_nth', everyNth: 2);

    final first = await _launch(body, storage);
    await first.check();
    expect(first.shouldRemindAboutUpdate(), isTrue);
    await first.markUpdateReminderShown();
    first.dispose();

    final second = await _launch(body, storage);
    await second.check();
    expect(second.shouldRemindAboutUpdate(), isFalse);
    second.dispose();

    final third = await _launch(body, storage);
    await third.check();
    expect(third.shouldRemindAboutUpdate(), isTrue);
    third.dispose();
  });

  test('обязательное обновление показывается независимо от частоты', () async {
    final storage = VmMemoryStorage();
    final body = _body(frequency: 'one_time', priority: 'forced');

    final vm = await _launch(body, storage);
    await vm.check();
    await vm.markUpdateReminderShown();
    // Частота — про вежливое напоминание. Запереть приложение она не мешает.
    expect(vm.shouldRemindAboutUpdate(), isTrue);
    vm.dispose();
  });

  test('без рекомендации напоминать нечего', () async {
    final storage = VmMemoryStorage();
    final vm = await _launch({
      'status': 'active',
      'isBlocked': false,
      'updatePriority': 'none',
      'notifications': const [],
      'nextCheckInterval': 1800,
      'configHash': 'h',
      'message': '',
      'serverTimestamp': '2026-09-20T10:00:00Z',
    }, storage);
    await vm.check();
    expect(vm.shouldRemindAboutUpdate(), isFalse);
    vm.dispose();
  });
}
