import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
