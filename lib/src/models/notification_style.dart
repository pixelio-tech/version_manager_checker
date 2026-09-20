import 'package:flutter/widgets.dart' show BorderRadius, BoxShadow, Color, Curve, Curves, EdgeInsets, Offset, Radius;

import 'notification_blocks.dart';

/// Presentation config for an in-app notification — corner rounding, colors,
/// icon/image, buttons. Mirrors the `style` JSON the admin configurator
/// writes (`version_manager_v3_front/src/lib/api/notifications.ts`) field for
/// field, so a notification looks the same in the admin preview and
/// on-device. There's no separate "shape" enum: a pill look is just a large
/// [cornerRadius], and a fullscreen takeover is [fullscreen] (only
/// meaningful when the payload's `type` is `modal`).
class NotificationStyle {
  final double cornerRadius;
  final bool fullscreen;
  final NotificationColors colors;
  final NotificationGradient? gradient;
  final NotificationBorder? border;
  final NotificationShadow shadow;
  final double padding;
  final double gap;
  final NotificationTypography typography;
  final NotificationIcon icon;
  final NotificationImage? image;
  final NotificationPosition position;
  final List<NotificationButtonConfig> buttons;
  final ButtonsLayout buttonsLayout;
  final NotificationButtonShape buttonShape;
  final bool closeButton;

  /// Поля карточки по сторонам; null — используется [padding].
  final EdgeInsets? paddingSides;

  /// Скругление по углам; null — используется [cornerRadius].
  final BorderRadius? corners;

  /// Отступ карточки от краёв экрана.
  final double? screenMargin;

  /// Ограничение ширины карточки.
  final double? maxWidth;

  /// Своя тень вместо пресета [shadow].
  final BoxShadow? shadowCustom;

  /// Длительность появления, мс.
  final int? animationMs;

  /// Кривая появления: standard | accelerate | decelerate | bounce.
  final String? animationCurve;

  /// Сторона крестика: right (по умолчанию) | left.
  final String? closeButtonPosition;

  /// Вид крестика: plain (по умолчанию) | circle.
  final String? closeButtonStyle;

  /// Полоска-ручка у шторки; false — не рисовать.
  final bool sheetHandle;

  /// Цвет ручки; null — полупрозрачный цвет текста.
  final Color? handleColor;

  /// Дерево содержимого из конструктора. Пусто — рисуется прежняя
  /// фиксированная раскладка (иконка → текст → кнопки).
  final List<NotificationBlock> blocks;

  const NotificationStyle({
    this.cornerRadius = 16,
    this.fullscreen = false,
    this.colors = const NotificationColors(),
    this.gradient,
    this.border,
    this.shadow = NotificationShadow.soft,
    this.padding = 16,
    this.gap = 12,
    this.typography = const NotificationTypography(),
    this.icon = const NotificationIcon(),
    this.image,
    this.position = NotificationPosition.top,
    this.buttons = const [],
    this.buttonsLayout = ButtonsLayout.row,
    this.buttonShape = const NotificationButtonShape(),
    this.closeButton = false,
    this.paddingSides,
    this.corners,
    this.screenMargin,
    this.maxWidth,
    this.shadowCustom,
    this.animationMs,
    this.animationCurve,
    this.closeButtonPosition,
    this.closeButtonStyle,
    this.sheetHandle = true,
    this.handleColor,
    this.blocks = const [],
  });

  /// Поля карточки с учётом настройки по сторонам.
  EdgeInsets get paddingInsets => paddingSides ?? EdgeInsets.all(padding);

  /// Скругление карточки с учётом настройки по углам.
  BorderRadius get cardRadius => corners ?? BorderRadius.circular(cornerRadius);

  /// Кривая появления как Flutter-ная.
  Curve get curve => switch (animationCurve) {
    'accelerate' => Curves.easeIn,
    'decelerate' => Curves.easeOut,
    'bounce' => Curves.elasticOut,
    _ => Curves.easeOutCubic,
  };

  /// Maximum number of buttons the backend accepts (`maxStyleButtons`).
  static const int maxButtons = 5;

  factory NotificationStyle.fromJson(Map<String, dynamic> json) {
    final iconJson = json['icon'] as Map<String, dynamic>?;
    final imageJson = json['image'] as Map<String, dynamic>?;
    final gradientJson = json['gradient'] as Map<String, dynamic>?;
    final borderJson = json['border'] as Map<String, dynamic>?;
    final typographyJson = json['typography'] as Map<String, dynamic>?;
    final buttonShapeJson = json['buttonShape'] as Map<String, dynamic>?;
    return NotificationStyle(
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 16,
      fullscreen: json['fullscreen'] as bool? ?? false,
      colors: json['colors'] is Map<String, dynamic>
          ? NotificationColors.fromJson(json['colors'] as Map<String, dynamic>)
          : const NotificationColors(),
      gradient: gradientJson != null ? NotificationGradient.fromJson(gradientJson) : null,
      border: borderJson != null ? NotificationBorder.fromJson(borderJson) : null,
      shadow: NotificationShadow.fromJson(json['shadow'] as String?),
      padding: (json['padding'] as num?)?.toDouble() ?? 16,
      gap: (json['gap'] as num?)?.toDouble() ?? 12,
      typography: typographyJson != null ? NotificationTypography.fromJson(typographyJson) : const NotificationTypography(),
      icon: iconJson != null ? NotificationIcon.fromJson(iconJson) : const NotificationIcon(),
      image: imageJson != null && imageJson['url'] != null ? NotificationImage.fromJson(imageJson) : null,
      position: NotificationPosition.fromJson(json['position'] as String?),
      buttons: (json['buttons'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .take(maxButtons)
          .map(NotificationButtonConfig.fromJson)
          .toList(),
      buttonsLayout: ButtonsLayout.fromJson(json['buttonsLayout'] as String?),
      buttonShape: buttonShapeJson != null ? NotificationButtonShape.fromJson(buttonShapeJson) : const NotificationButtonShape(),
      closeButton: json['closeButton'] as bool? ?? false,
      paddingSides: _insets(json['paddingSides']),
      corners: _corners(json['corners']),
      screenMargin: (json['screenMargin'] as num?)?.toDouble(),
      maxWidth: (json['maxWidth'] as num?)?.toDouble(),
      shadowCustom: _shadow(json['shadowCustom']),
      animationMs: (json['animationMs'] as num?)?.toInt(),
      animationCurve: json['animationCurve'] as String?,
      closeButtonPosition: json['closeButtonPosition'] as String?,
      closeButtonStyle: json['closeButtonStyle'] as String?,
      sheetHandle: json['sheetHandle'] as bool? ?? true,
      handleColor: _colorOr(json['handleColor'], null),
      blocks: (json['blocks'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(NotificationBlock.fromJson)
          .whereType<NotificationBlock>()
          .toList(),
    );
  }
}

/// Type scale and alignment of the card's text.
class NotificationTypography {
  final double titleSize;
  final double bodySize;
  final int titleWeight;
  final String align; // 'left' | 'center'
  final double lineHeight;

  const NotificationTypography({
    this.titleSize = 15,
    this.bodySize = 13,
    this.titleWeight = 700,
    this.align = 'left',
    this.lineHeight = 1.35,
  });

  factory NotificationTypography.fromJson(Map<String, dynamic> json) => NotificationTypography(
    titleSize: (json['titleSize'] as num?)?.toDouble() ?? 15,
    bodySize: (json['bodySize'] as num?)?.toDouble() ?? 13,
    titleWeight: (json['titleWeight'] as num?)?.toInt() ?? 700,
    align: json['align'] as String? ?? 'left',
    lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.35,
  );
}

/// Two-stop linear gradient behind the card; when absent the card is a flat
/// colour from [NotificationColors].
class NotificationGradient {
  final Color from;
  final Color to;
  final double angle;

  const NotificationGradient({required this.from, required this.to, this.angle = 135});

  factory NotificationGradient.fromJson(Map<String, dynamic> json) => NotificationGradient(
    from: _colorOr(json['from'], const Color(0xFF141821))!,
    to: _colorOr(json['to'], const Color(0xFF5B8CFF))!,
    angle: (json['angle'] as num?)?.toDouble() ?? 135,
  );
}

class NotificationBorder {
  final double width;
  final Color color;

  const NotificationBorder({this.width = 1, required this.color});

  factory NotificationBorder.fromJson(Map<String, dynamic> json) => NotificationBorder(
    width: (json['width'] as num?)?.toDouble() ?? 1,
    color: _colorOr(json['color'], const Color(0x33FFFFFF))!,
  );
}

enum NotificationShadow {
  none,
  soft,
  strong;

  factory NotificationShadow.fromJson(String? v) =>
      NotificationShadow.values.firstWhere((e) => e.name == v, orElse: () => NotificationShadow.soft);
}

class NotificationButtonShape {
  final double radius;
  final double height;
  final bool fullWidth;

  const NotificationButtonShape({this.radius = 10, this.height = 38, this.fullWidth = true});

  factory NotificationButtonShape.fromJson(Map<String, dynamic> json) => NotificationButtonShape(
    radius: (json['radius'] as num?)?.toDouble() ?? 10,
    height: (json['height'] as num?)?.toDouble() ?? 38,
    fullWidth: json['fullWidth'] as bool? ?? true,
  );
}

/// Where a banner appears on screen. Only meaningful when `type` is
/// `banner` — a modal is always centered (or fullscreen), a bottomSheet is
/// always anchored to the bottom.
enum NotificationPosition {
  top,
  bottom;

  factory NotificationPosition.fromJson(String? v) =>
      NotificationPosition.values.firstWhere((e) => e.name == v, orElse: () => NotificationPosition.top);
}

enum ButtonsLayout {
  row,
  stack;

  factory ButtonsLayout.fromJson(String? v) =>
      ButtonsLayout.values.firstWhere((e) => e.name == v, orElse: () => ButtonsLayout.row);
}

enum NotificationButtonStyle {
  primary,
  secondary,
  text,
  destructive;

  factory NotificationButtonStyle.fromJson(String? v) =>
      NotificationButtonStyle.values.firstWhere((e) => e.name == v, orElse: () => NotificationButtonStyle.secondary);
}

class NotificationColors {
  final Color background;
  final Color surface;
  final Color text;
  final Color accent;
  final Color? overlay;

  const NotificationColors({
    this.background = const Color(0xFF141821),
    this.surface = const Color(0xFF1C212C),
    this.text = const Color(0xFFF4F6F8),
    this.accent = const Color(0xFF5B8CFF),
    this.overlay,
  });

  factory NotificationColors.fromJson(Map<String, dynamic> json) => NotificationColors(
    background: _colorOr(json['background'], const Color(0xFF141821))!,
    surface: _colorOr(json['surface'], const Color(0xFF1C212C))!,
    text: _colorOr(json['text'], const Color(0xFFF4F6F8))!,
    accent: _colorOr(json['accent'], const Color(0xFF5B8CFF))!,
    overlay: _colorOr(json['overlay'], null),
  );
}

class NotificationIcon {
  final String source; // 'app' | 'custom' | 'none'
  final String? url;
  final double size;
  final String shape; // 'squircle' | 'circle' | 'square'

  const NotificationIcon({this.source = 'app', this.url, this.size = 32, this.shape = 'squircle'});

  factory NotificationIcon.fromJson(Map<String, dynamic> json) => NotificationIcon(
    source: json['source'] as String? ?? 'app',
    url: json['url'] as String?,
    size: (json['size'] as num?)?.toDouble() ?? 32,
    shape: json['shape'] as String? ?? 'squircle',
  );
}

class NotificationImage {
  final String url;
  final String position; // 'top' | 'bottom' | 'background'
  final double height;
  final String fit; // 'cover' | 'contain'

  const NotificationImage({required this.url, this.position = 'top', this.height = 140, this.fit = 'cover'});

  factory NotificationImage.fromJson(Map<String, dynamic> json) => NotificationImage(
    url: json['url'] as String,
    position: json['position'] as String? ?? 'top',
    height: (json['height'] as num?)?.toDouble() ?? 140,
    fit: json['fit'] as String? ?? 'cover',
  );
}

class NotificationButtonConfig {
  final String id;
  final Map<String, String> label;
  final NotificationButtonStyle style;
  final String actionKind; // 'url' | 'deeplink' | 'dismiss' | 'store'
  final String? actionValue;

  /// Свои цвета поверх пресета [style].
  final Color? background;
  final Color? textColor;
  final Color? borderColor;

  /// Символ слева от подписи.
  final String? icon;

  /// Растянуть именно эту кнопку; null — как у блока.
  final bool? fullWidth;

  const NotificationButtonConfig({
    required this.id,
    required this.label,
    required this.style,
    required this.actionKind,
    this.actionValue,
    this.background,
    this.textColor,
    this.borderColor,
    this.icon,
    this.fullWidth,
  });

  factory NotificationButtonConfig.fromJson(Map<String, dynamic> json) {
    final action = json['action'] as Map<String, dynamic>? ?? const {};
    final label = json['label'] as Map<String, dynamic>? ?? const {};
    final colors = json['colors'];
    return NotificationButtonConfig(
      id: json['id'] as String? ?? label.toString(),
      label: label.map((k, v) => MapEntry(k, v as String)),
      style: NotificationButtonStyle.fromJson(json['style'] as String?),
      actionKind: action['kind'] as String? ?? 'dismiss',
      actionValue: action['value'] as String?,
      background: colors is Map ? _colorOr(colors['background'], null) : null,
      textColor: colors is Map ? _colorOr(colors['text'], null) : null,
      borderColor: colors is Map ? _colorOr(colors['border'], null) : null,
      icon: json['icon'] as String?,
      fullWidth: json['fullWidth'] as bool?,
    );
  }

  String labelFor(String locale) => label[locale] ?? label['ru'] ?? label['en'] ?? label.values.firstOrNull ?? '';
}

EdgeInsets? _insets(dynamic raw) {
  if (raw is! Map) return null;
  final fallback = 0.0;
  return EdgeInsets.only(
    top: (raw['top'] as num?)?.toDouble() ?? fallback,
    right: (raw['right'] as num?)?.toDouble() ?? fallback,
    bottom: (raw['bottom'] as num?)?.toDouble() ?? fallback,
    left: (raw['left'] as num?)?.toDouble() ?? fallback,
  );
}

BorderRadius? _corners(dynamic raw) {
  if (raw is! Map) return null;
  return BorderRadius.only(
    topLeft: Radius.circular((raw['tl'] as num?)?.toDouble() ?? 0),
    topRight: Radius.circular((raw['tr'] as num?)?.toDouble() ?? 0),
    bottomRight: Radius.circular((raw['br'] as num?)?.toDouble() ?? 0),
    bottomLeft: Radius.circular((raw['bl'] as num?)?.toDouble() ?? 0),
  );
}

BoxShadow? _shadow(dynamic raw) {
  if (raw is! Map) return null;
  final color = _colorOr(raw['color'], const Color(0x59000000));
  return BoxShadow(
    color: color ?? const Color(0x59000000),
    offset: Offset((raw['x'] as num?)?.toDouble() ?? 0, (raw['y'] as num?)?.toDouble() ?? 0),
    blurRadius: (raw['blur'] as num?)?.toDouble() ?? 0,
    spreadRadius: (raw['spread'] as num?)?.toDouble() ?? 0,
  );
}

Color? _colorOr(dynamic hex, Color? fallback) {
  if (hex is! String) return fallback;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v != null ? Color(v) : fallback;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
