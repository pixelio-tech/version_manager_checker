import 'package:flutter/material.dart';

import '../models/check_result.dart';
import '../models/notification_style.dart';
import 'block_renderer.dart';
import 'notification_visuals.dart';

/// Centered modal card (`type: "modal"`) — full custom styling: corner
/// rounding, colors, optional hero image, icon, buttons. Mirrors the admin
/// preview's modal branch: image on top, icon, title, body, then either the
/// button list or a single default "Понятно" action when no buttons are
/// configured. `style.fullscreen` swaps the centered card for a full-screen
/// takeover (see [FullscreenNotification]) — same content, no card/overlay.
class ModalNotification extends StatelessWidget {
  final NotificationPayload payload;
  final String locale;
  final void Function(NotificationButtonConfig button) onButtonTap;
  final VoidCallback onDismiss;

  const ModalNotification({
    super.key,
    required this.payload,
    required this.locale,
    required this.onButtonTap,
    required this.onDismiss,
  });

  static Future<void> show(
    BuildContext context, {
    required NotificationPayload payload,
    required String locale,
    required void Function(NotificationButtonConfig button) onButtonTap,
  }) {
    if (payload.style.fullscreen) {
      return Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) => FullscreenNotification(
            payload: payload,
            locale: locale,
            onButtonTap: onButtonTap,
            onDismiss: () => Navigator.of(ctx).pop(),
          ),
        ),
      );
    }
    return showDialog(
      context: context,
      // Уведомление не имеет права запирать приложение: тап по затемнению
      // закрывает его всегда. Заблокировать интерфейс может только экран
      // обязательного обновления (VmUpdateGate).
      barrierDismissible: true,
      barrierColor: payload.style.colors.overlay ?? const Color(0x73141821),
      builder: (ctx) => ModalNotification(
        payload: payload,
        locale: locale,
        onButtonTap: onButtonTap,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = payload.style;
    final radius = style.cornerRadius;
    final media = MediaQuery.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: style.screenMargin ?? 28, vertical: 40),
      child: ConstrainedBox(
        // Длинное содержимое не растягивает карточку до краёв экрана и не
        // переполняет её — дальше оно прокручивается.
        constraints: BoxConstraints(maxHeight: media.size.height * 0.8, maxWidth: style.maxWidth ?? double.infinity),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: notificationCardDecoration(
            style,
            onSurface: true,
            radius: style.corners ?? BorderRadius.circular(radius),
          ),
          child: Stack(
            children: [
              // Column + Flexible: высота карточки считается по содержимому,
              // но не больше ограничения — дальше содержимое прокручивается.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.zero,
                      child: NotificationBlocks(
                        style: style,
                        locale: locale,
                        onButtonTap: (b) {
                          onButtonTap(b);
                          onDismiss();
                        },
                      ),
                    ),
                  ),
                ],
              ),
              // Крестик рисуется всегда: закрыть уведомление можно в любом
              // случае, даже если в конструкторе его выключили.
              NotificationCloseButton.positioned(style, onDismiss),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen takeover — `type: "modal"` with `style.fullscreen: true`.
/// Same content as [ModalNotification] but fills the whole screen instead of
/// a centered card, with an optional full-bleed background image.
class FullscreenNotification extends StatelessWidget {
  final NotificationPayload payload;
  final String locale;
  final void Function(NotificationButtonConfig button) onButtonTap;
  final VoidCallback onDismiss;

  const FullscreenNotification({
    super.key,
    required this.payload,
    required this.locale,
    required this.onButtonTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final style = payload.style;
    final gradient = style.gradient;
    // Картинка на фоне — это узел image «край в край» внутри stack: у карточки
    // своей картинки больше нет, её описывает дерево.
    return Scaffold(
      backgroundColor: gradient != null ? null : style.colors.background,
      body: Container(
        decoration: gradient != null
            ? notificationCardDecoration(style, onSurface: false, radius: BorderRadius.zero)
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              child: LayoutBuilder(
                // Содержимое занимает весь экран (растяжимые отступы работают),
                // но если его больше, чем помещается, — прокручивается.
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: NotificationBlocks(
                        style: style,
                        locale: locale,
                        fill: true,
                        onButtonTap: (b) {
                          onButtonTap(b);
                          onDismiss();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Полный экран тоже обязан закрываться: на iOS системного «назад»
            // нет, поэтому крестик рисуется всегда.
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: style.closeButtonPosition == 'left' ? null : 8,
              left: style.closeButtonPosition == 'left' ? 8 : null,
              child: NotificationCloseButton(style: style, onTap: onDismiss),
            ),
          ],
        ),
      ),
    );
  }
}
