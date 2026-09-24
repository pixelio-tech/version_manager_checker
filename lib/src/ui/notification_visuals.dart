import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/notification_style.dart';

/// Fill of the card: gradient when configured, flat colour otherwise. The
/// admin constructor uses `colors.surface` for modal/bottomSheet and
/// `colors.background` everywhere else — [onSurface] picks the same one.
BoxDecoration notificationCardDecoration(NotificationStyle style, {required bool onSurface, BorderRadius? radius}) {
  final gradient = style.gradient;
  final rads = (gradient?.angle ?? 0) * math.pi / 180;
  return BoxDecoration(
    color: gradient != null ? null : (onSurface ? style.colors.surface : style.colors.background),
    gradient: gradient != null
        ? LinearGradient(
            colors: [gradient.from, gradient.to],
            begin: Alignment(-math.cos(rads), -math.sin(rads)),
            end: Alignment(math.cos(rads), math.sin(rads)),
          )
        : null,
    borderRadius: radius ?? style.cardRadius,
    border: style.border != null ? Border.all(color: style.border!.color, width: style.border!.width) : null,
    // Своя тень из конструктора перебивает пресет.
    boxShadow: style.shadowCustom != null
        ? [style.shadowCustom!]
        : switch (style.shadow) {
            NotificationShadow.none => null,
            NotificationShadow.soft => const [BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8))],
            NotificationShadow.strong => const [BoxShadow(color: Color(0x73000000), blurRadius: 44, offset: Offset(0, 18))],
          },
  );
}

/// Картинка уведомления по её адресу. Конструктор умеет отдавать не только
/// ссылку, но и `data:` — встроенный base64 (так в админку попадают
/// загруженные файлы). `Image.network` такие адреса не понимает и молча
/// показывает пустоту, поэтому разбираем их сами.
Widget notificationNetworkImage(String url, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
  if (url.startsWith('data:')) {
    final comma = url.indexOf(',');
    final meta = comma == -1 ? '' : url.substring(0, comma);
    if (comma == -1 || !meta.contains(';base64')) return const SizedBox.shrink();
    try {
      final bytes = base64Decode(url.substring(comma + 1));
      return Image.memory(bytes, width: width, height: height, fit: fit, errorBuilder: (_, _, _) => const SizedBox.shrink());
    } on FormatException {
      return const SizedBox.shrink();
    }
  }
  return Image.network(url, width: width, height: height, fit: fit, errorBuilder: (_, _, _) => const SizedBox.shrink());
}


/// Dismiss affordance drawn in the card's corner when `style.closeButton`.
class NotificationCloseButton extends StatelessWidget {
  final NotificationStyle style;
  final VoidCallback onTap;

  const NotificationCloseButton({super.key, required this.style, required this.onTap});

  /// Крестик, приклеенный к верхнему углу карточки. Именно [Positioned]:
  /// обычный [Align] внутри [Stack] растягивается на все доступные размеры и
  /// раздувает карточку до высоты экрана.
  static Widget positioned(NotificationStyle style, VoidCallback onTap, {double inset = 8}) => Positioned(
    top: inset,
    left: style.closeButtonPosition == 'left' ? inset : null,
    right: style.closeButtonPosition == 'left' ? null : inset,
    child: NotificationCloseButton(style: style, onTap: onTap),
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: style.closeButtonStyle == 'circle'
            ? BoxDecoration(color: style.colors.text.withValues(alpha: 0.12), shape: BoxShape.circle)
            : null,
        child: Icon(Icons.close, size: 16, color: style.colors.text.withValues(alpha: 0.55)),
      ),
    );
  }
}

/// Shared visual pieces used by every notification surface (banner, modal,
/// bottom sheet) so the button/icon look stays identical across types — the
/// same rule the admin's `ButtonsRow`/`NotificationIcon` follow.
class NotificationButtonsRow extends StatelessWidget {
  final NotificationStyle style;
  final String locale;
  final void Function(NotificationButtonConfig button) onTap;
  final bool compact;

  /// Кнопки узла: у карточки своих кнопок нет.
  final List<NotificationButtonConfig> buttons;
  final ButtonsLayout layout;
  final NotificationButtonShape shape;

  /// Отступ сверху: у блочной раскладки его задаёт промежуток контейнера.
  final double? topPadding;

  /// Промежуток между кнопками; null — доля от `style.gap`.
  final double? gap;

  const NotificationButtonsRow({
    super.key,
    required this.style,
    required this.locale,
    required this.onTap,
    this.compact = false,
    required this.buttons,
    this.layout = ButtonsLayout.row,
    this.shape = const NotificationButtonShape(),
    this.topPadding,
    this.gap,
  });

  @override
  Widget build(BuildContext context) {
    final list = buttons;
    if (list.isEmpty) return const SizedBox.shrink();
    final gap = this.gap ?? math.max(6.0, style.gap * 0.6);
    final effectiveShape = shape;
    final stacked = layout == ButtonsLayout.stack;
    final buttonWidgets = [
      for (final b in list)
        _NotificationButton(
          button: b,
          style: style,
          shape: effectiveShape,
          compact: compact,
          onTap: () => onTap(b),
          locale: locale,
        ),
    ];

    return Padding(
      padding: EdgeInsets.only(top: topPadding ?? style.gap),
      child: stacked
          ? Column(
              children: [
                for (var i = 0; i < buttonWidgets.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == buttonWidgets.length - 1 ? 0 : gap),
                    child: SizedBox(width: double.infinity, child: buttonWidgets[i]),
                  ),
              ],
            )
          : Row(
              children: [
                for (var i = 0; i < buttonWidgets.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  // Кнопка может перебить растяжение блока своим fullWidth.
                  (list[i].fullWidth ?? effectiveShape.fullWidth)
                      ? Expanded(child: buttonWidgets[i])
                      : Flexible(fit: FlexFit.loose, child: buttonWidgets[i]),
                ],
              ],
            ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final NotificationButtonConfig button;
  final NotificationStyle style;
  final NotificationButtonShape shape;
  final bool compact;
  final String locale;
  final VoidCallback onTap;

  const _NotificationButton({
    required this.button,
    required this.style,
    required this.shape,
    required this.compact,
    required this.locale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = style.colors;
    final (presetBg, presetFg, presetBorder) = switch (button.style) {
      NotificationButtonStyle.primary => (colors.accent, _onColor(colors.accent), null),
      NotificationButtonStyle.destructive => (const Color(0xFFE5484D), Colors.white, null),
      NotificationButtonStyle.text => (Colors.transparent, colors.accent, null),
      NotificationButtonStyle.secondary => (
        Colors.transparent,
        colors.text,
        Border.all(color: colors.text.withValues(alpha: 0.2)),
      ),
    };
    // Персональные цвета кнопки перебивают пресет.
    final bg = button.background ?? presetBg;
    final fg = button.textColor ?? presetFg;
    final border = button.borderColor != null ? Border.all(color: button.borderColor!) : presetBorder;
    final radius = BorderRadius.circular(shape.radius);
    final height = compact ? math.max(26.0, shape.height - 8) : shape.height;
    return Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          height: height,
          decoration: BoxDecoration(border: border, borderRadius: radius),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (button.icon != null && button.icon!.isNotEmpty) ...[
                Text(
                  button.icon!,
                  style: TextStyle(color: fg, fontSize: compact ? 11.5 : 13),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  button.labelFor(locale),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: compact ? 11.5 : 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _onColor(Color bg) => ThemeData.estimateBrightnessForColor(bg) == Brightness.light ? const Color(0xFF141821) : Colors.white;

/// App/custom icon badge, or nothing when `icon.source == none`.
/// Иконка узла `icon`. Все свойства приходят из узла: у карточки своей
/// иконки больше нет — она сама узел дерева.
class NotificationIconBadge extends StatelessWidget {
  final NotificationStyle style;
  final double size;
  final String source;
  final String? url;
  final String shape;

  const NotificationIconBadge({
    super.key,
    required this.style,
    required this.size,
    required this.source,
    this.url,
    this.shape = 'squircle',
  });

  @override
  Widget build(BuildContext context) {
    if (source == 'none') return const SizedBox.shrink();
    final radius = BorderRadius.circular(switch (shape) {
      'circle' => size,
      'square' => 4,
      _ => size * 0.28,
    });
    final url = this.url;
    if (source == 'custom' && url != null) {
      return ClipRRect(
        borderRadius: radius,
        child: notificationNetworkImage(url, width: size, height: size),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: style.colors.accent.withValues(alpha: 0.13), borderRadius: radius),
      alignment: Alignment.center,
      child: Text(
        'A',
        style: TextStyle(color: style.colors.accent, fontWeight: FontWeight.bold, fontSize: size * 0.4),
      ),
    );
  }
}
