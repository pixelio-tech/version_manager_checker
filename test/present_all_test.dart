import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

/// За одну проверку сервер присылает до трёх уведомлений. Их показывают
/// подряд, и каждое должно быть реально видно — баннер не имеет права
/// остаться под шторкой или модалкой.
Map<String, dynamic> _payload(String type, String title) => {
  'id': 'n-$type',
  'type': type,
  'title': title,
  'body': 'Текст',
  'action': {'kind': 'dismiss'},
  'ui': {
    'v': 1,
    'type': 'card',
    'corners': 16,
    'padding': 16,
    'gap': 12,
    'background': '#141821',
    'children': [
      {
        'id': 't',
        'type': 'text',
        'text': {'ru': title, 'en': title},
        'size': 14,
      },
    ],
  },
};

void main() {
  testWidgets('баннер виден поверх шторки, показанной раньше', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    for (final p in [_payload('bottomSheet', 'Шторка'), _payload('banner', 'Баннер')]) {
      presentVmNotification(ctx, payload: NotificationPayload.fromJson(p), onAction: (_, _) {});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Шторка'), findsOneWidget);
    expect(find.text('Баннер'), findsOneWidget);

    // Баннер должен принимать тап: если он под затемнением шторки, тап уйдёт
    // в затемнение и закроет шторку вместо баннера.
    await tester.tap(find.text('Баннер'), warnIfMissed: true);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Шторка'), findsOneWidget, reason: 'тап по баннеру не должен закрывать шторку');
  });

  testWidgets('повторный presentAll не показывает то же уведомление второй раз', (tester) async {
    // Хост зовёт presentAll откуда угодно: с экрана, из слушателя, после
    // возврата из фона. Карточка не должна открываться второй раз сразу за
    // первой, когда ответ сервера тот же самый.
    final vm = await _vm(_config('hash-1'));
    final outcome = await vm.check();
    expect(outcome, isA<VmFresh>(),
        reason: 'проверка не дошла: ${outcome is VmUnavailable ? outcome.cause : outcome}');

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    await vm.presentAll(ctx, onAction: (_, _) {});
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Одно и то же'), findsOneWidget);

    await vm.presentAll(ctx, onAction: (_, _) {});
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Одно и то же'), findsOneWidget, reason: 'показано дважды из одного конфига');

    // Показать намеренно — можно: это другая кнопка, а не случайный повтор.
    await vm.presentAll(ctx, onAction: (_, _) {}, repeat: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Одно и то же'), findsNWidgets(2));

    vm.dispose();
  });
}

Map<String, dynamic> _config(String hash) => {
  'status': 'active',
  'isBlocked': false,
  'updatePriority': 'none',
  'notifications': [_payload('banner', 'Одно и то же')],
  'nextCheckInterval': 1800,
  'configHash': hash,
  'message': '',
  'serverTimestamp': '2026-09-20T10:00:00Z',
};

Future<VersionManager> _vm(Map<String, dynamic> body) => VersionManager.init(
  baseUrl: 'https://api.test',
  apiKey: 'vm_live_x',
  namespace: 'com.example.app',
  version: '1.0.0',
  buildNumber: 1,
  platform: 'ios',
  storage: VmMemoryStorage(),
  client: VmV3Client(
    baseUrl: 'https://api.test',
    apiKey: 'vm_live_x',
    // Response.bytes, а не Response(String): в теле кириллица, а строковый
    // конструктор кодирует latin1 и запрос падает на «invalid characters».
    httpClient: MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        200,
        headers: {'etag': body['configHash'] as String, 'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  ),
);
