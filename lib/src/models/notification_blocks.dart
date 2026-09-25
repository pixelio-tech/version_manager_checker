import 'package:flutter/widgets.dart' show BorderRadius, Color, EdgeInsets, Radius;

import 'notification_style.dart';

/// Поля, фон, рамка, тень и размеры блока — одинаковый набор у всех типов.
/// Пришло из конструктора пустым — блок рисуется как раньше.
class BlockBox {
  final EdgeInsets? margin;
  final EdgeInsets? padding;
  final Color? background;
  final BorderRadius? radius;
  final double? borderWidth;
  final Color? borderColor;
  final String? shadow; // none | soft | strong
  final double? opacity;
  final String? align; // start | center | end | stretch
  final double? width; // null — авто, -1 — на всю строку
  final double? maxWidth;

  /// Край в край: блок не получает внутренних полей карточки.
  final bool bleed;

  const BlockBox({
    this.margin,
    this.padding,
    this.background,
    this.radius,
    this.borderWidth,
    this.borderColor,
    this.shadow,
    this.opacity,
    this.align,
    this.width,
    this.maxWidth,
    this.bleed = false,
  });

  bool get isEmpty =>
      margin == null &&
      padding == null &&
      background == null &&
      radius == null &&
      borderWidth == null &&
      shadow == null &&
      opacity == null &&
      align == null &&
      width == null &&
      maxWidth == null &&
      !bleed;

  static BlockBox? fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final width = raw['width'];
    final box = BlockBox(
      margin: _edges(raw['margin']),
      padding: _edges(raw['padding']),
      background: _colorOrNull(raw['background']),
      radius: _radius(raw['radius']),
      borderWidth: (raw['border'] is Map ? (raw['border']['width'] as num?)?.toDouble() : null),
      borderColor: (raw['border'] is Map ? _colorOrNull(raw['border']['color']) : null),
      shadow: raw['shadow'] as String?,
      opacity: (raw['opacity'] as num?)?.toDouble(),
      align: raw['align'] as String?,
      width: width == 'full' ? -1 : (width as num?)?.toDouble(),
      maxWidth: (raw['maxWidth'] as num?)?.toDouble(),
      bleed: raw['bleed'] as bool? ?? false,
    );
    return box.isEmpty ? null : box;
  }
}

/// Отступы: число на все стороны либо по сторонам.
EdgeInsets? _edges(dynamic raw) {
  if (raw is num) return EdgeInsets.all(raw.toDouble());
  if (raw is Map) {
    return EdgeInsets.only(
      top: (raw['top'] as num?)?.toDouble() ?? 0,
      right: (raw['right'] as num?)?.toDouble() ?? 0,
      bottom: (raw['bottom'] as num?)?.toDouble() ?? 0,
      left: (raw['left'] as num?)?.toDouble() ?? 0,
    );
  }
  return null;
}

/// Скругление: число на все углы либо по углам.
BorderRadius? _radius(dynamic raw) {
  if (raw is num) return BorderRadius.circular(raw.toDouble());
  if (raw is Map) {
    return BorderRadius.only(
      topLeft: Radius.circular((raw['tl'] as num?)?.toDouble() ?? 0),
      topRight: Radius.circular((raw['tr'] as num?)?.toDouble() ?? 0),
      bottomRight: Radius.circular((raw['br'] as num?)?.toDouble() ?? 0),
      bottomLeft: Radius.circular((raw['bl'] as num?)?.toDouble() ?? 0),
    );
  }
  return null;
}

/// Дерево содержимого уведомления — то, что собрал конструктор в админке.
/// Карточка (цвет, форма, отступы) остаётся в [NotificationStyle], а что
/// внутри неё, описывают блоки: текст, картинка, иконка, кнопки, отступ,
/// разделитель и контейнеры row/column.
///
/// Сообщения, собранные до появления блоков, приходят без `blocks` — их рисует
/// прежняя фиксированная раскладка, поэтому старые клиенты и старые данные
/// продолжают работать.
sealed class NotificationBlock {
  final String id;

  /// Доля ширины внутри ряда: null — по содержимому.
  final double? flex;

  /// Общее оформление коробки блока.
  final BlockBox? box;

  const NotificationBlock({required this.id, this.flex, this.box});

  static NotificationBlock? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final flex = (json['flex'] as num?)?.toDouble();
    final box = BlockBox.fromJson(json['box']);
    switch (json['type'] as String?) {
      case 'text':
        return TextBlock(
          id: id,
          flex: flex,
          box: box,
          text: _i18n(json['text']),
          size: (json['size'] as num?)?.toDouble() ?? 13,
          weight: (json['weight'] as num?)?.toInt() ?? 400,
          align: json['align'] as String? ?? 'left',
          color: _colorOrNull(json['color']),
          opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
          lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.35,
          maxLines: (json['maxLines'] as num?)?.toInt(),
          font: json['font'] as String?,
          letterSpacing: (json['letterSpacing'] as num?)?.toDouble(),
          transform: json['transform'] as String?,
          italic: json['italic'] as bool? ?? false,
          underline: json['underline'] as bool? ?? false,
        );
      case 'image':
        final imageWidth = json['width'];
        return ImageBlock(
          id: id,
          flex: flex,
          box: box,
          url: json['url'] as String? ?? '',
          height: (json['height'] as num?)?.toDouble() ?? 140,
          fit: json['fit'] as String? ?? 'cover',
          radius: (json['radius'] as num?)?.toDouble() ?? 10,
          width: imageWidth == 'full' ? null : (imageWidth as num?)?.toDouble(),
          align: json['align'] as String?,
          aspect: (json['aspect'] as num?)?.toDouble(),
          opacity: (json['opacity'] as num?)?.toDouble(),
          overlay: _colorOrNull(json['overlay']),
        );
      case 'icon':
        return IconBlock(
          id: id,
          flex: flex,
          box: box,
          source: json['source'] as String? ?? 'app',
          url: json['url'] as String?,
          size: (json['size'] as num?)?.toDouble() ?? 32,
          shape: json['shape'] as String? ?? 'squircle',
        );
      case 'buttons':
        return ButtonsBlock(
          id: id,
          flex: flex,
          box: box,
          buttons: (json['buttons'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .take(NotificationStyle.maxButtons)
              .map(NotificationButtonConfig.fromJson)
              .toList(),
          layout: ButtonsLayout.fromJson(json['layout'] as String?),
          shape: json['shape'] is Map<String, dynamic>
              ? NotificationButtonShape.fromJson(json['shape'] as Map<String, dynamic>)
              : const NotificationButtonShape(),
          gap: (json['gap'] as num?)?.toDouble(),
        );
      case 'spacer':
        return SpacerBlock(
          id: id,
          flex: flex,
          box: box,
          size: (json['size'] as num?)?.toDouble() ?? 12,
          grow: json['grow'] as bool? ?? false,
        );
      case 'divider':
        return DividerBlock(
          id: id,
          flex: flex,
          box: box,
          thickness: (json['thickness'] as num?)?.toDouble() ?? 1,
          color: _colorOrNull(json['color']),
          dashed: json['style'] == 'dashed',
          inset: (json['inset'] as num?)?.toDouble() ?? 0,
        );
      case 'stack':
        return StackBlock(
          id: id,
          flex: flex,
          box: box,
          children: (json['children'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(NotificationBlock.fromJson)
              .whereType<NotificationBlock>()
              .toList(),
          alignment: json['alignment'] as String? ?? 'topLeft',
        );
      case 'row':
      case 'column':
        return ContainerBlock(
          id: id,
          flex: flex,
          box: box,
          isRow: json['type'] == 'row',
          children: (json['children'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(NotificationBlock.fromJson)
              .whereType<NotificationBlock>()
              .toList(),
          gap: (json['gap'] as num?)?.toDouble() ?? 10,
          align: json['align'] as String? ?? 'start',
          justify: json['justify'] as String? ?? 'start',
          padding: (json['padding'] as num?)?.toDouble() ?? 0,
          background: _colorOrNull(json['background']),
          radius: (json['radius'] as num?)?.toDouble() ?? 0,
          wrap: json['wrap'] as bool? ?? false,
        );
      default:
        // Клиент старее админки. Лист пропускаем — рисовать нечем; а вот
        // контейнер пропускать нельзя: вместе с ним исчезло бы поддерево, и
        // добавление нового типа узла выключало бы половину карточки на всех
        // прежних сборках. Поэтому незнакомый узел с детьми становится
        // колонкой — раскладка беднее, содержимое на месте.
        final children = (json['children'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(NotificationBlock.fromJson)
            .whereType<NotificationBlock>()
            .toList();
        if (children.isEmpty) return null;
        return ContainerBlock(
          id: id,
          flex: flex,
          box: box,
          isRow: false,
          children: children,
          gap: 10,
          align: 'start',
          justify: 'start',
          padding: 0,
          radius: 0,
        );
    }
  }
}

/// Наложение: дети рисуются друг поверх друга.
///
/// Нужно там, где иначе пришлось бы городить обёртки: бейдж на картинке,
/// текст поверх изображения. Позицию ребёнка задаёт его `box`.
class StackBlock extends NotificationBlock {
  final List<NotificationBlock> children;

  /// topLeft | topRight | bottomLeft | bottomRight | center
  final String alignment;

  const StackBlock({
    required super.id,
    super.flex,
    super.box,
    required this.children,
    this.alignment = 'topLeft',
  });
}

class TextBlock extends NotificationBlock {
  final Map<String, String> text;
  final double size;
  final int weight;
  final String align; // left | center | right
  final Color? color;
  final double opacity;
  final double lineHeight;
  final int? maxLines;
  final String? font; // ui | display | mono
  final double? letterSpacing;
  final String? transform; // upper | lower
  final bool italic;
  final bool underline;

  const TextBlock({
    required super.id,
    super.flex,
    super.box,
    required this.text,
    required this.size,
    required this.weight,
    required this.align,
    this.color,
    required this.opacity,
    required this.lineHeight,
    this.maxLines,
    this.font,
    this.letterSpacing,
    this.transform,
    this.italic = false,
    this.underline = false,
  });

  String textFor(String locale) => vmPickLocalized(text, locale);
}

class ImageBlock extends NotificationBlock {
  final String url;
  final double height;
  final String fit; // cover | contain
  final double radius;

  /// null — во всю ширину.
  final double? width;
  final String? align; // start | center | end
  final double? aspect;
  final double? opacity;
  final Color? overlay;

  const ImageBlock({
    required super.id,
    super.flex,
    super.box,
    required this.url,
    required this.height,
    required this.fit,
    required this.radius,
    this.width,
    this.align,
    this.aspect,
    this.opacity,
    this.overlay,
  });
}

class IconBlock extends NotificationBlock {
  final String source; // app | custom
  final String? url;
  final double size;
  final String shape; // squircle | circle | square

  const IconBlock({
    required super.id,
    super.flex,
    super.box,
    required this.source,
    this.url,
    required this.size,
    required this.shape,
  });
}

class ButtonsBlock extends NotificationBlock {
  final List<NotificationButtonConfig> buttons;
  final ButtonsLayout layout;
  final NotificationButtonShape shape;

  /// Промежуток между кнопками; null — берётся из стиля карточки.
  final double? gap;

  const ButtonsBlock({
    required super.id,
    super.flex,
    super.box,
    required this.buttons,
    required this.layout,
    required this.shape,
    this.gap,
  });
}

class SpacerBlock extends NotificationBlock {
  final double size;

  /// Занять всё свободное место вместо фиксированного размера.
  final bool grow;

  const SpacerBlock({required super.id, super.flex, super.box, required this.size, this.grow = false});
}

class DividerBlock extends NotificationBlock {
  final double thickness;
  final Color? color;
  final bool dashed;
  final double inset;

  const DividerBlock({
    required super.id,
    super.flex,
    super.box,
    required this.thickness,
    this.color,
    this.dashed = false,
    this.inset = 0,
  });
}

class ContainerBlock extends NotificationBlock {
  final bool isRow;
  final List<NotificationBlock> children;
  final double gap;
  final String align; // start | center | end | stretch
  final String justify; // start | center | end | between
  final double padding;
  final Color? background;
  final double radius;

  /// Переносить детей на новую строку (только для ряда).
  final bool wrap;

  const ContainerBlock({
    required super.id,
    super.flex,
    super.box,
    required this.isRow,
    required this.children,
    required this.gap,
    required this.align,
    required this.justify,
    required this.padding,
    this.background,
    required this.radius,
    this.wrap = false,
  });
}

Map<String, String> _i18n(dynamic value) {
  if (value is! Map) return const {};
  return value.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
}

Color? _colorOrNull(dynamic hex) {
  if (hex is! String) return null;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v != null ? Color(v) : null;
}

/// Выбирает перевод под [locale], пропуская пустые значения.
///
/// Конструктор в админке заводит ключ на каждую известную локаль, даже если
/// текст в неё не вписали, — поэтому проверять на `null` мало: приходит пустая
/// строка, и без этой отбраковки уведомление рисуется с пустым местом вместо
/// текста. Любой непустой перевод лучше пустоты.
String vmPickLocalized(Map<String, String> values, String locale) {
  for (final key in [locale, 'ru', 'en']) {
    final v = values[key];
    if (v != null && v.trim().isNotEmpty) return v;
  }
  for (final v in values.values) {
    if (v.trim().isNotEmpty) return v;
  }
  return '';
}
