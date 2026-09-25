import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

CheckResult _result({
  String status = 'active',
  bool blocked = false,
  String priority = 'none',
  bool withStore = true,
}) => CheckResult.fromJson({
  'status': status,
  'isBlocked': blocked,
  'blockReason': blocked ? 'Версия снята с поддержки' : null,
  'updatePriority': priority,
  'recommendedVersion': {
    'versionNumber': '4.2.0',
    'buildNumber': 420,
    'changelog': 'Починили синхронизацию',
    'storeLinks': withStore
        ? [
            {'platform': 'ios', 'storeName': 'App Store', 'url': 'https://apps.apple.com/app/id1'},
            {'platform': 'android', 'storeName': 'Google Play', 'url': 'https://play.google.com/x'},
          ]
        : <Map<String, dynamic>>[],
  },
  'notifications': const <Map<String, dynamic>>[],
  'nextCheckInterval': 3600,
  'configHash': 'h',
  'message': 'Обновите приложение',
  'serverTimestamp': '2026-09-20T10:00:00Z',
});

void main() {
  test('вердикт: блокировка и обязательное обновление закрывают приложение', () {
    expect(vmVerdictFor(null), VmGateVerdict.pass);
    expect(vmVerdictFor(_result()), VmGateVerdict.pass);
    expect(vmVerdictFor(_result(priority: 'recommended')), VmGateVerdict.pass);
    expect(vmVerdictFor(_result(status: 'blocked', blocked: true)), VmGateVerdict.block);
    expect(vmVerdictFor(_result(priority: 'forced')), VmGateVerdict.block);
    expect(vmVerdictFor(_result(priority: 'required')), VmGateVerdict.block);
  });

  testWidgets('пока всё в порядке — показывает приложение', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VmUpdateGate(result: _result(), platform: 'ios', child: const Text('домашний экран')),
      ),
    );
    expect(find.text('домашний экран'), findsOneWidget);
  });

  testWidgets('блокировка накрывает экраном с причиной и ссылкой на стор', (tester) async {
    StoreLink? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: VmUpdateGate(
          result: _result(status: 'blocked', blocked: true),
          platform: 'android',
          onOpenStore: (l) => opened = l,
          child: const Text('домашний экран'),
        ),
      ),
    );

    expect(find.text('домашний экран'), findsNothing);
    expect(find.text('Версия больше не поддерживается'), findsOneWidget);
    expect(find.text('Версия снята с поддержки'), findsOneWidget);
    expect(find.text('Актуальная версия 4.2.0'), findsOneWidget);

    // Ссылка выбирается под платформу установки.
    await tester.tap(find.text('Обновить в Google Play'));
    expect(opened?.platform, 'android');
  });

  testWidgets('без ссылок на стор подсказывает настроить их в админке', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VmUpdateGate(
          result: _result(priority: 'forced', withStore: false),
          platform: 'ios',
          child: const SizedBox(),
        ),
      ),
    );

    expect(find.textContaining('Ссылка на магазин не настроена'), findsOneWidget);
  });
}
