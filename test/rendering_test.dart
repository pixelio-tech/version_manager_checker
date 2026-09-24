import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

Map<String, dynamic> _text(String id, String text) => {
  'id': id,
  'type': 'text',
  'text': {'ru': text, 'en': 'EN $text'},
  'size': 14,
  'weight': 600,
  'align': 'left',
  'opacity': 1,
  'lineHeight': 1.35,
};

NotificationPayload _payload({
  required String type,
  List<Map<String, dynamic>> blocks = const [],
  Map<String, dynamic> style = const {},
}) => NotificationPayload.fromJson({
  'id': 'n1',
  'type': type,
  'title': 'Заголовок',
  'body': 'Текст',
  'action': {'kind': 'dismiss'},
  // Оформление — дерево: корень card, дети — узлы.
  'ui': {
    'v': 1,
    'type': 'card',
    'corners': 16,
    'padding': 16,
    'gap': 12,
    'background': '#141821',
    'children': blocks,
    ...style,
  },
});

/// Прокликиваемая обёртка: показывает уведомление и копит события воронки.
Widget _host({required NotificationPayload payload, required List<String> events, List<String>? actions, String locale = 'ru'}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => presentVmNotification(
                context,
                payload: payload,
                locale: locale,
                onAction: (kind, value) => actions?.add('$kind:${value ?? ''}'),
                onEvent: (id, type) => events.add('$id:$type'),
              ),
              child: const Text('показать'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('баннер рисует блоки и шлёт shown', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      _host(
        payload: _payload(type: 'banner', blocks: [_text('t1', 'Привет из баннера')]),
        events: events,
      ),
    );

    await tester.tap(find.text('показать'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Привет из баннера'), findsOneWidget);
    expect(events, contains('n1:shown'));
  });

  testWidgets('модалка показывает кнопку и отдаёт её действие', (tester) async {
    final events = <String>[];
    final actions = <String>[];
    await tester.pumpWidget(
      _host(
        payload: _payload(
          type: 'modal',
          blocks: [
            _text('t1', 'Обновитесь'),
            {
              'id': 'b1',
              'type': 'buttons',
              'layout': 'row',
              'shape': {'radius': 10, 'height': 38, 'fullWidth': true},
              'buttons': [
                {
                  'id': 'btn',
                  'label': {'ru': 'Обновить'},
                  'style': 'primary',
                  'action': {'kind': 'store'},
                },
              ],
            },
          ],
        ),
        events: events,
        actions: actions,
      ),
    );

    await tester.tap(find.text('показать'));
    await tester.pumpAndSettle();

    expect(find.text('Обновитесь'), findsOneWidget);
    await tester.tap(find.text('Обновить'));
    await tester.pumpAndSettle();

    expect(actions, contains('store:'));
    expect(events, contains('n1:clicked'));
  });

  testWidgets('шторка рисует ручку, а с sheetHandle: false — нет', (tester) async {
    Future<int> handles(Map<String, dynamic> style) async {
      await tester.pumpWidget(
        _host(
          payload: _payload(type: 'bottomSheet', blocks: [_text('t', 'Шторка')], style: style),
          events: [],
        ),
      );
      await tester.tap(find.text('показать'));
      await tester.pumpAndSettle();
      // Ручка — единственный Container шириной 36 и высотой 4.
      final found = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.constraints?.maxWidth == 36 && c.constraints?.maxHeight == 4)
          .length;
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      return found;
    }

    expect(await handles(const {}), 1);
    expect(await handles(const {'sheetHandle': false}), 0);
  });

  testWidgets('локаль переключает язык текста', (tester) async {
    await tester.pumpWidget(
      _host(
        payload: _payload(type: 'banner', blocks: [_text('t1', 'Русский')]),
        events: [],
        locale: 'en',
      ),
    );

    await tester.tap(find.text('показать'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('EN Русский'), findsOneWidget);
  });

  testWidgets('silent ничего не рисует, но считается показанным', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      _host(
        payload: _payload(type: 'silent'),
        events: events,
      ),
    );

    await tester.tap(find.text('показать'));
    await tester.pumpAndSettle();

    expect(find.text('Заголовок'), findsNothing);
    expect(events, ['n1:shown']);
  });

  testWidgets('блок «край в край» шире соседнего с полями', (tester) async {
    final payload = _payload(
      type: 'modal',
      blocks: [
        {
          'id': 'edge',
          'type': 'divider',
          'thickness': 4,
          'color': '#ff0000',
          'box': {'bleed': true},
        },
        {'id': 'inset', 'type': 'divider', 'thickness': 4, 'color': '#00ff00'},
      ],
    );
    await tester.pumpWidget(_host(payload: payload, events: []));
    await tester.tap(find.text('показать'));
    await tester.pumpAndSettle();

    final rects = tester.widgetList<Container>(find.byType(Container)).where((c) => c.constraints?.maxHeight == 4).toList();
    expect(rects, hasLength(2));
    final sizes = find
        .byType(Container)
        .evaluate()
        .where((e) {
          final w = e.widget as Container;
          return w.constraints?.maxHeight == 4;
        })
        .map((e) => e.size!.width)
        .toList();

    // Верхний идёт край в край, нижний — внутри полей карточки (16 + 16).
    expect(sizes.first - sizes.last, closeTo(32, 0.5));
  });
}
