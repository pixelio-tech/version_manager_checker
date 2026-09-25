import 'dart:async';

import 'package:flutter/material.dart';

import '../models/check_result.dart';
import '../models/notification_style.dart';
import 'block_renderer.dart';
import 'notification_visuals.dart';

/// In-app banner (`type: "banner"` or `"localPush"` while the app is
/// foregrounded) — a self-dismissing card positioned per `style.position`.
/// Mirrors the admin preview's banner/localPush branch pixel-for-pixel:
/// same background/text colors, same icon, same compact buttons row.
class BannerNotification extends StatefulWidget {
  final NotificationPayload payload;
  final String locale;
  final Duration duration;
  final VoidCallback onDismissed;
  final void Function(NotificationButtonConfig button) onButtonTap;
  final VoidCallback onTap;

  const BannerNotification({
    super.key,
    required this.payload,
    required this.locale,
    required this.onDismissed,
    required this.onButtonTap,
    required this.onTap,
    this.duration = const Duration(seconds: 5),
  });

  /// Inserts the banner into the nearest [Overlay]. Returns a handle that
  /// removes it early if the caller needs to (e.g. a newer notification
  /// arrives).
  static VoidCallback show(
    BuildContext context, {
    required NotificationPayload payload,
    required String locale,
    required void Function(NotificationButtonConfig button) onButtonTap,
    required VoidCallback onTap,
    required VoidCallback onDismissed,
    Duration duration = const Duration(seconds: 5),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => BannerNotification(
        payload: payload,
        locale: locale,
        duration: duration,
        onButtonTap: onButtonTap,
        onTap: onTap,
        onDismissed: () {
          entry.remove();
          onDismissed();
        },
      ),
    );
    overlay.insert(entry);
    return entry.remove;
  }

  @override
  State<BannerNotification> createState() => _BannerNotificationState();
}

class _BannerNotificationState extends State<BannerNotification> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  NotificationStyle get _style => widget.payload.style;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.payload.style.animationMs ?? 260),
    )..forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _timer?.cancel();
    _controller.reverse().then((_) => widget.onDismissed());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final position = _style.position;
    final beginOffset = position == NotificationPosition.bottom ? const Offset(0, 1) : const Offset(0, -1);

    final card = SlideTransition(
      position: Tween(
        begin: beginOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _controller, curve: _style.curve)),
      child: FadeTransition(
        opacity: _controller,
        child: GestureDetector(
          onTap: () {
            widget.onTap();
            _dismiss();
          },
          onVerticalDragEnd: (d) {
            if (d.primaryVelocity != null && d.primaryVelocity!.abs() > 100) _dismiss();
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              // Поля раздают сами блоки (см. NotificationBlocks), поэтому у
              // карточки их нет: блок «край в край» упирается в её границу.
              padding: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              decoration: notificationCardDecoration(_style, onSurface: false),
              constraints: _style.maxWidth != null ? BoxConstraints(maxWidth: _style.maxWidth!) : null,
              child: Stack(
                children: [
                  NotificationBlocks(style: _style, locale: widget.locale, onButtonTap: widget.onButtonTap),
                  NotificationCloseButton.positioned(_style, _dismiss, inset: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Positioned.fill(
      child: Align(
        alignment: position == NotificationPosition.bottom ? Alignment.bottomCenter : Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(
            top: position == NotificationPosition.top ? media.padding.top + 12 : 0,
            bottom: position == NotificationPosition.bottom ? media.padding.bottom + 12 : 0,
            left: _style.screenMargin ?? 16,
            right: _style.screenMargin ?? 16,
          ),
          child: card,
        ),
      ),
    );
  }
}
