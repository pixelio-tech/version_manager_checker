import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

/// Правило: любое уведомление пользователь может закрыть. Запереть интерфейс
/// имеет право только экран обязательного обновления (`VmUpdateGate`).
Map<String, dynamic> _text(String id, String text) => {
  'id': id,
  'type': 'text',
  'text': {'ru': text, 'en': text},
  'size': 14,
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
  'style': {
    'cornerRadius': 16,
    'padding': 16,
    'gap': 12,
    'colors': {'background': '#141821', 'surface': '#1c212c', 'text': '#f4f6f8', 'accent': '#5b8cff'},
    'icon': {'source': 'none'},
    // Специально выключено: крестик обязан появиться всё равно.
    'closeButton': false,
    'blocks': blocks,
    ...style,
  },
});

Widget _host(NotificationPayload payload) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => presentVmNotification(context, payload: payload, onAction: (_, _) {}),
          child: const Text('показать'),
        ),
      ),
    ),
  ),
);

Future<void> _show(WidgetTester tester, NotificationPayload payload) async {
  await tester.pumpWidget(_host(payload));
  await tester.tap(find.text('показать'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Картинка из конструктора может приехать как `data:` — раньше она молча
/// пропадала, потому что `Image.network` такие адреса не понимает.
const _pngDataUri =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  for (final type in ['banner', 'modal', 'bottomSheet']) {
    testWidgets('$type закрывается крестиком, даже если closeButton выключен', (tester) async {
      final payload = _payload(type: type, blocks: [_text('t', 'Привет')]);
      await _show(tester, payload);
      expect(find.text('Привет'), findsOneWidget);

      expect(find.byIcon(Icons.close), findsWidgets);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(find.text('Привет'), findsNothing);
    });
  }

  testWidgets('полноэкранное рисует блоки и закрывается крестиком', (tester) async {
    final payload = _payload(
      type: 'modal',
      style: {'fullscreen': true},
      blocks: [
        {'id': 'sp', 'type': 'spacer', 'size': 12, 'grow': true},
        _text('t', 'Полный экран'),
        {
          'id': 'bt',
          'type': 'buttons',
          'layout': 'column',
          'buttons': [
            {
              'id': 'b1',
              'label': {'ru': 'Обновить', 'en': 'Update'},
              'style': 'primary',
              'action': {'kind': 'store'},
            },
          ],
        },
      ],
    );
    await _show(tester, payload);

    // Блоки раньше игнорировались — кнопки из конструктора не доезжали.
    expect(find.text('Полный экран'), findsOneWidget);
    expect(find.text('Обновить'), findsOneWidget);
    // `column` — то же, что `stack`: кнопки идут друг под другом.
    expect(ButtonsLayout.fromJson('column'), ButtonsLayout.stack);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Полный экран'), findsNothing);
  });

  testWidgets('шторка прилегает к нижнему краю, без полосы под карточкой', (tester) async {
    // Домашний индикатор iPhone: раньше SafeArea отодвигала шторку вверх, и
    // под ней оставалась полоса фона.
    tester.view.viewPadding = const FakeViewPadding(bottom: 34 * 3);
    tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
    addTearDown(tester.view.reset);

    await _show(tester, _payload(type: 'bottomSheet', blocks: [_text('t', 'Шторка')]));

    final card = tester.getRect(find.byType(NotificationBlocks));
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    // Содержимое отодвинуто от индикатора, а сама карточка доходит до края.
    expect(screenHeight - card.bottom, greaterThanOrEqualTo(34));
    final sheet = tester.getRect(
      find.ancestor(of: find.byType(NotificationBlocks), matching: find.byType(Container)).last,
    );
    expect(sheet.bottom, closeTo(screenHeight, 0.5));
  });

  testWidgets('модалка закрывается тапом по затемнению', (tester) async {
    await _show(tester, _payload(type: 'modal', blocks: [_text('t', 'Тап мимо')]));
    expect(find.text('Тап мимо'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Тап мимо'), findsNothing);
  });

  testWidgets('растяжимый отступ не раздувает обычную карточку', (tester) async {
    final payload = _payload(
      type: 'modal',
      blocks: [
        _text('t', 'Коротко'),
        {'id': 'sp', 'type': 'spacer', 'size': 10, 'grow': true},
      ],
    );
    await _show(tester, payload);

    final card = tester.getSize(find.byType(NotificationBlocks));
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    // Карточка считает высоту по содержимому, а не занимает весь экран.
    expect(card.height, lessThan(screen * 0.5));
  });

  testWidgets('короткая модалка не растягивается на весь экран', (tester) async {
    await _show(tester, _payload(type: 'modal', blocks: [_text('t', 'Коротко')]));

    final card = tester.getSize(find.byType(NotificationBlocks));
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    // Крестик рисуется в Stack: раньше он был Align и раздувал карточку до
    // высоты экрана.
    expect(card.height, lessThan(screen * 0.35));
  });

  testWidgets('картинка из data: URI рисуется', (tester) async {
    final payload = _payload(
      type: 'modal',
      blocks: [
        {'id': 'img', 'type': 'image', 'url': _pngDataUri, 'height': 80},
        _text('t', 'С картинкой'),
      ],
    );
    await _show(tester, payload);

    expect(find.byType(Image), findsWidgets);
    expect(tester.widget<Image>(find.byType(Image).first).image, isA<MemoryImage>());
  });

  testWidgets('техработы не запирают приложение, но опознаются', (tester) async {
    final maintenance = CheckResult.fromJson({
      'status': 'maintenance',
      'isBlocked': false,
      'updatePriority': 'none',
      'notifications': [],
      'nextCheckInterval': 60,
      'configHash': 'h',
      'message': 'Вернёмся через час',
      'serverTimestamp': '',
    });

    expect(vmIsMaintenance(maintenance), isTrue);
    // Запирать интерфейс имеет право только блокировка версии.
    expect(vmVerdictFor(maintenance), VmGateVerdict.pass);

    await tester.pumpWidget(MaterialApp(home: VmMaintenanceScreen(result: maintenance, onRetry: () {})));
    expect(find.text('Идут технические работы'), findsOneWidget);
    expect(find.text('Вернёмся через час'), findsOneWidget);
    expect(find.text('Проверить ещё раз'), findsOneWidget);
  });

  testWidgets('длинное содержимое прокручивается, а не переполняет карточку', (tester) async {
    final payload = _payload(
      type: 'modal',
      blocks: [for (var i = 0; i < 40; i++) _text('t$i', 'Строка $i, довольно длинная, чтобы карточка не влезла в экран')],
    );
    await _show(tester, payload);

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });
}
