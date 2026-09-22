import 'package:flutter/material.dart';

import '../models/notification_blocks.dart';
import '../models/notification_style.dart';
import 'notification_visuals.dart';

/// Рисует дерево блоков, собранное в конструкторе. Раскладка потоковая
/// (колонки и ряды), без абсолютных координат — поэтому длинный текст и
/// узкий экран не ломают карточку.
class NotificationBlocks extends StatelessWidget {
  final NotificationStyle style;
  final String locale;
  final void Function(NotificationButtonConfig button) onButtonTap;

  /// Карточка занимает всю доступную высоту (полноэкранное уведомление).
  /// Только тогда растяжимый отступ может растягиваться: в обычной карточке
  /// высота считается по содержимому, и `Expanded` растянул бы её на весь
  /// экран — уведомление выглядело бы «раздутым».
  final bool fill;

  const NotificationBlocks({super.key, required this.style, required this.locale, required this.onButtonTap, this.fill = false});

  @override
  Widget build(BuildContext context) {
    // Поля карточки держат сами блоки: блок «край в край» их не получает и
    // упирается в границы карточки — так картинка занимает верх целиком.
    final pad = style.paddingInsets;
    final last = style.blocks.length - 1;
    final children = <Widget>[];
    for (var i = 0; i < style.blocks.length; i++) {
      if (i > 0) children.add(SizedBox(height: style.gap));
      final block = style.blocks[i];
      final bleed = block.box?.bleed ?? false;
      final padded = Padding(
        padding: EdgeInsets.only(
          top: i == 0 ? (bleed ? 0 : pad.top) : 0,
          bottom: i == last ? (bleed ? 0 : pad.bottom) : 0,
          left: bleed ? 0 : pad.left,
          right: bleed ? 0 : pad.right,
        ),
        child: _render(block, isRow: false),
      );
      // Растяжимый отступ обязан быть ПРЯМЫМ ребёнком Column: Expanded внутри
      // Padding — ошибка раскладки (ParentDataWidget), из-за которой
      // полноэкранное уведомление падало вместо отрисовки.
      final grows = fill && block is SpacerBlock && block.grow;
      children.add(grows ? Expanded(child: padded) : padded);
    }
    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  List<Widget> _withGaps(List<NotificationBlock> blocks, double gap, {required bool isRow}) {
    final out = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) out.add(SizedBox(width: isRow ? gap : 0, height: isRow ? 0 : gap));
      out.add(_render(blocks[i], isRow: isRow));
    }
    return out;
  }

  Widget _render(NotificationBlock block, {required bool isRow}) {
    var child = switch (block) {
      TextBlock b => Text(
        _transformed(b),
        maxLines: b.maxLines,
        overflow: b.maxLines != null ? TextOverflow.ellipsis : null,
        textAlign: switch (b.align) {
          'center' => TextAlign.center,
          'right' => TextAlign.end,
          'justify' => TextAlign.justify,
          _ => TextAlign.start,
        },
        style: TextStyle(
          color: (b.color ?? style.colors.text).withValues(alpha: b.opacity),
          fontSize: b.size,
          height: b.lineHeight,
          fontWeight: FontWeight.values[(b.weight ~/ 100).clamp(1, 9) - 1],
          letterSpacing: b.letterSpacing,
          fontStyle: b.italic ? FontStyle.italic : null,
          decoration: b.underline ? TextDecoration.underline : null,
          fontFamily: b.font == 'mono' ? 'monospace' : null,
        ),
      ),
      ImageBlock b => _image(b),
      IconBlock b => NotificationIconBadge(
        style: style,
        size: b.size,
        overrideSource: b.source,
        overrideUrl: b.url,
        overrideShape: b.shape,
      ),
      ButtonsBlock b => NotificationButtonsRow(
        style: style,
        locale: locale,
        onTap: onButtonTap,
        buttons: b.buttons,
        layout: b.layout,
        shape: b.shape,
        gap: b.gap,
        topPadding: 0,
      ),
      SpacerBlock b => b.grow ? const SizedBox.shrink() : SizedBox(height: b.size, width: b.size),
      DividerBlock b => _divider(b),
      ContainerBlock b => _container(b),
    };

    child = _boxed(block, child);

    // Растяжимый отступ занимает свободное место вдоль оси. В колонке это
    // возможно, только когда карточка тянется на всю высоту ([fill]); иначе
    // отступ остаётся фиксированным, а карточка — по содержимому.
    if (block is SpacerBlock && block.grow) {
      if (isRow) return const Spacer();
      // В колонке растяжение включает сам [build] (Expanded снаружи полей);
      // здесь остаётся обычный отступ.
      return SizedBox(height: block.size);
    }
    // flex работает только внутри ряда: иначе Expanded ломает высоту колонки.
    if (isRow && block.flex != null) return Expanded(flex: block.flex!.round().clamp(1, 12), child: child);
    // Остальные дети ряда не растягиваются, но обязаны сжиматься — иначе
    // соседи выталкивают друг друга за край карточки.
    if (isRow) return Flexible(fit: FlexFit.loose, child: child);
    return child;
  }

  String _transformed(TextBlock b) {
    final raw = b.textFor(locale);
    return switch (b.transform) {
      'upper' => raw.toUpperCase(),
      'lower' => raw.toLowerCase(),
      _ => raw,
    };
  }

  Widget _image(ImageBlock b) {
    if (b.url.isEmpty) return const SizedBox.shrink();
    Widget picture = notificationNetworkImage(
      b.url,
      height: b.aspect != null ? null : b.height,
      width: double.infinity,
      fit: b.fit == 'contain' ? BoxFit.contain : BoxFit.cover,
    );
    // Заданная ширина работает как максимум: шире карточки картинка не станет.
    if (b.width != null) {
      picture = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: b.width!),
        child: picture,
      );
    }
    if (b.aspect != null) picture = AspectRatio(aspectRatio: b.aspect!, child: picture);
    if (b.opacity != null) picture = Opacity(opacity: b.opacity!, child: picture);
    if (b.overlay != null) {
      picture = Stack(
        children: [
          picture,
          Positioned.fill(child: ColoredBox(color: b.overlay!)),
        ],
      );
    }
    Widget clipped = ClipRRect(borderRadius: BorderRadius.circular(b.radius), child: picture);
    if (b.width != null) {
      clipped = Align(
        alignment: switch (b.align) {
          'center' => Alignment.center,
          'end' => Alignment.centerRight,
          _ => Alignment.centerLeft,
        },
        child: clipped,
      );
    }
    return clipped;
  }

  Widget _divider(DividerBlock b) {
    final color = b.color ?? style.colors.text.withValues(alpha: 0.15);
    final line = b.dashed
        ? CustomPaint(
            painter: _DashedLinePainter(color: color, thickness: b.thickness),
            size: Size(double.infinity, b.thickness),
          )
        : Container(height: b.thickness, color: color);
    return b.inset == 0
        ? line
        : Padding(
            padding: EdgeInsets.symmetric(horizontal: b.inset),
            child: line,
          );
  }

  /// Поля, фон, рамка, тень, размеры и выравнивание блока.
  Widget _boxed(NotificationBlock block, Widget child) {
    final box = block.box;
    if (box == null) return child;

    var out = child;
    final hasDecoration = box.background != null || box.radius != null || box.borderWidth != null || box.shadow != null;
    if (box.padding != null || hasDecoration) {
      out = Container(
        padding: box.padding,
        decoration: hasDecoration
            ? BoxDecoration(
                color: box.background,
                borderRadius: box.radius,
                border: box.borderWidth != null
                    ? Border.all(color: box.borderColor ?? style.colors.text, width: box.borderWidth!)
                    : null,
                boxShadow: switch (box.shadow) {
                  'soft' => const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6))],
                  'strong' => const [BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 12))],
                  _ => null,
                },
              )
            : null,
        child: out,
      );
    }
    if (box.width != null || box.maxWidth != null) {
      // width == -1 — «во всю строку»: ограничение по ширине не нужно.
      out = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: box.width != null && box.width! > 0 ? box.width! : 0,
          maxWidth: box.width != null && box.width! > 0 ? box.width! : (box.maxWidth ?? double.infinity),
        ),
        child: out,
      );
    }
    if (box.opacity != null) out = Opacity(opacity: box.opacity!, child: out);
    if (box.margin != null) out = Padding(padding: box.margin!, child: out);
    if (box.align != null && box.align != 'stretch') {
      out = Align(
        alignment: switch (box.align) {
          'center' => Alignment.center,
          'end' => Alignment.centerRight,
          _ => Alignment.centerLeft,
        },
        child: out,
      );
    }
    return out;
  }

  Widget _container(ContainerBlock b) {
    final children = _withGaps(b.children, b.gap, isRow: b.isRow);
    final mainAxis = switch (b.justify) {
      'center' => MainAxisAlignment.center,
      'end' => MainAxisAlignment.end,
      'between' => MainAxisAlignment.spaceBetween,
      _ => MainAxisAlignment.start,
    };
    final crossAxis = switch (b.align) {
      'center' => CrossAxisAlignment.center,
      'end' => CrossAxisAlignment.end,
      'stretch' => CrossAxisAlignment.stretch,
      _ => CrossAxisAlignment.start,
    };

    final Widget inner;
    if (b.isRow && b.wrap) {
      // Перенос: промежутки задаёт сам Wrap, поэтому дети идут без прокладок.
      inner = Wrap(
        spacing: b.gap,
        runSpacing: b.gap,
        alignment: switch (b.justify) {
          'center' => WrapAlignment.center,
          'end' => WrapAlignment.end,
          'between' => WrapAlignment.spaceBetween,
          _ => WrapAlignment.start,
        },
        crossAxisAlignment: b.align == 'center' ? WrapCrossAlignment.center : WrapCrossAlignment.start,
        children: [for (final child in b.children) _render(child, isRow: false)],
      );
    } else if (b.isRow) {
      inner = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: mainAxis, crossAxisAlignment: crossAxis, children: children);
    } else {
      inner = Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: mainAxis,
        crossAxisAlignment: crossAxis,
        children: children,
      );
    }

    // Коробка блока перебивает старые поля контейнера.
    if (b.box != null) return inner;
    if (b.padding == 0 && b.background == null && b.radius == 0) return inner;
    return Container(
      padding: EdgeInsets.all(b.padding),
      decoration: BoxDecoration(color: b.background, borderRadius: BorderRadius.circular(b.radius)),
      child: inner,
    );
  }
}

/// Пунктирная линия разделителя — во Flutter её нет из коробки.
class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double thickness;

  _DashedLinePainter({required this.color, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    const dash = 5.0;
    const gap = 4.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, thickness / 2), Offset((x + dash).clamp(0, size.width), thickness / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color || old.thickness != thickness;
}
