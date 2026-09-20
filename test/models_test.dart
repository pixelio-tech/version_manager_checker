import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

void main() {
  test('CheckResult разбирает ответ целиком', () {
    final result = CheckResult.fromJson({
      'status': 'update_available',
      'isBlocked': false,
      'blockReason': null,
      'updatePriority': 'recommended',
      'recommendedVersion': {
        'versionNumber': '4.2.0',
        'buildNumber': 420,
        'changelog': 'Правки',
        'frequency': 'once',
        'storeLinks': [
          {'platform': 'ios', 'storeName': 'App Store', 'url': 'https://apps.apple.com/app/id1'},
        ],
      },
      'notifications': [
        {
          'id': 'n1',
          'type': 'banner',
          'title': 'Привет',
          'body': 'Текст',
          'action': {'kind': 'dismiss'},
          'style': {
            'cornerRadius': 40,
            'position': 'bottom',
            'colors': {'background': '#101418', 'surface': '#1a1e24', 'text': '#ffffff', 'accent': '#5b8cff'},
          },
        },
      ],
      'nextCheckInterval': 900,
      'configHash': 'hash',
      'message': 'ok',
      'serverTimestamp': '2026-09-20T10:00:00Z',
    });

    expect(result.status, 'update_available');
    expect(result.recommendedVersion!.storeLinks.single.storeName, 'App Store');
    expect(result.notifications.single.style.cornerRadius, 40);
    expect(result.notifications.single.style.position, NotificationPosition.bottom);
    expect(result.nextCheckInterval, 900);
  });

  test('стиль карточки читает точную геометрию и тайминг', () {
    final style = NotificationStyle.fromJson({
      'paddingSides': {'top': 4, 'right': 8, 'bottom': 12, 'left': 16},
      'corners': {'tl': 28, 'tr': 0, 'br': 4, 'bl': 0},
      'screenMargin': 20,
      'maxWidth': 420,
      'shadowCustom': {'x': 0, 'y': 12, 'blur': 30, 'spread': 2, 'color': '#000000'},
      'animationMs': 400,
      'animationCurve': 'bounce',
      'closeButtonPosition': 'left',
      'closeButtonStyle': 'circle',
      'sheetHandle': false,
      'handleColor': '#ffffff55',
    });

    expect(style.paddingInsets, const EdgeInsets.only(top: 4, right: 8, bottom: 12, left: 16));
    expect(style.cardRadius.topLeft.x, 28);
    expect(style.cardRadius.topRight.x, 0);
    expect(style.screenMargin, 20);
    expect(style.maxWidth, 420);
    expect(style.shadowCustom!.blurRadius, 30);
    expect(style.animationMs, 400);
    expect(style.curve, isNotNull);
    expect(style.closeButtonPosition, 'left');
    expect(style.closeButtonStyle, 'circle');
    expect(style.sheetHandle, isFalse);
    expect(style.handleColor, isNotNull);
  });

  test('дерево блоков читает коробку, текст, картинку и кнопки', () {
    final style = NotificationStyle.fromJson({
      'blocks': [
        {
          'id': 'text',
          'type': 'text',
          'text': {'ru': 'привет', 'en': 'hi'},
          'size': 18,
          'weight': 700,
          'align': 'justify',
          'opacity': 0.9,
          'lineHeight': 1.4,
          'font': 'mono',
          'letterSpacing': 1.5,
          'transform': 'upper',
          'italic': true,
          'underline': true,
          'box': {
            'padding': {'top': 6, 'right': 8, 'bottom': 6, 'left': 8},
            'margin': 4,
            'background': '#112233',
            'radius': {'tl': 10, 'tr': 10, 'br': 0, 'bl': 0},
            'border': {'width': 2, 'color': '#ffffff'},
            'shadow': 'soft',
            'opacity': 0.8,
            'align': 'center',
            'width': 'full',
            'maxWidth': 300,
            'bleed': true,
          },
        },
        {
          'id': 'img',
          'type': 'image',
          'url': 'https://x/1.png',
          'height': 120,
          'fit': 'contain',
          'radius': 8,
          'width': 200,
          'aspect': 1.5,
          'opacity': 0.7,
          'overlay': '#00000055',
          'align': 'center',
        },
        {
          'id': 'btns',
          'type': 'buttons',
          'layout': 'stack',
          'gap': 14,
          'shape': {'radius': 12, 'height': 44, 'fullWidth': false},
          'buttons': [
            {
              'id': 'b1',
              'label': {'ru': 'Обновить'},
              'style': 'primary',
              'icon': '↑',
              'fullWidth': true,
              'colors': {'background': '#112233', 'text': '#ffffff', 'border': '#445566'},
              'action': {'kind': 'url', 'value': 'https://example.com'},
            },
          ],
        },
        {'id': 'div', 'type': 'divider', 'thickness': 2, 'style': 'dashed', 'inset': 12},
        {'id': 'sp', 'type': 'spacer', 'size': 10, 'grow': true},
        {
          'id': 'row',
          'type': 'row',
          'wrap': true,
          'gap': 6,
          'align': 'center',
          'justify': 'between',
          'padding': 4,
          'radius': 8,
          'children': [
            {'id': 'icon', 'type': 'icon', 'source': 'custom', 'url': 'https://x/i.png', 'size': 40, 'shape': 'circle'},
          ],
        },
      ],
    });

    final text = style.blocks[0] as TextBlock;
    expect(text.textFor('en'), 'hi');
    expect(text.font, 'mono');
    expect(text.transform, 'upper');
    expect(text.italic && text.underline, isTrue);
    expect(text.box!.bleed, isTrue);
    expect(text.box!.width, -1); // 'full'
    expect(text.box!.maxWidth, 300);
    expect(text.box!.borderWidth, 2);
    expect(text.box!.radius!.topLeft.x, 10);

    final image = style.blocks[1] as ImageBlock;
    expect(image.width, 200);
    expect(image.aspect, 1.5);
    expect(image.overlay, isNotNull);
    expect(image.align, 'center');

    final buttons = style.blocks[2] as ButtonsBlock;
    expect(buttons.gap, 14);
    expect(buttons.layout, ButtonsLayout.stack);
    expect(buttons.buttons.single.icon, '↑');
    expect(buttons.buttons.single.fullWidth, isTrue);
    expect(buttons.buttons.single.background, isNotNull);
    expect(buttons.buttons.single.actionValue, 'https://example.com');

    final divider = style.blocks[3] as DividerBlock;
    expect(divider.dashed, isTrue);
    expect(divider.inset, 12);

    expect((style.blocks[4] as SpacerBlock).grow, isTrue);

    final row = style.blocks[5] as ContainerBlock;
    expect(row.isRow && row.wrap, isTrue);
    expect((row.children.single as IconBlock).shape, 'circle');
  });

  test('неизвестный тип блока пропускается, старое сообщение остаётся валидным', () {
    final style = NotificationStyle.fromJson({
      'blocks': [
        {'id': 'x', 'type': 'video', 'url': 'https://x/v.mp4'},
        {
          'id': 't',
          'type': 'text',
          'text': {'ru': 'ок'},
        },
      ],
    });

    expect(style.blocks, hasLength(1));
    expect((style.blocks.single as TextBlock).textFor('ru'), 'ок');
  });
}
