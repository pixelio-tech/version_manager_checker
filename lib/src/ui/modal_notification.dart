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
      barrierColor: payload.style.colors.overlay ?? const Color(0x73141821),
      builder: (ctx) =>
          ModalNotification(payload: payload, locale: locale, onButtonTap: onButtonTap, onDismiss: () => Navigator.of(ctx).pop()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = payload.style;
    final radius = style.cornerRadius;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: style.screenMargin ?? 28),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: notificationCardDecoration(style, onSurface: true, radius: style.corners ?? BorderRadius.circular(radius)),
        padding: style.blocks.isEmpty ? style.paddingInsets : EdgeInsets.zero,
        constraints: style.maxWidth != null ? BoxConstraints(maxWidth: style.maxWidth!) : null,
        child: Stack(
          children: [
            if (style.blocks.isNotEmpty)
              NotificationBlocks(
                style: style,
                locale: locale,
                onButtonTap: (b) {
                  onButtonTap(b);
                  onDismiss();
                },
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: notificationCrossAlign(style),
                children: [
                  if (style.image?.position == 'top' && style.image != null) ...[
                    notificationImage(style, radius: 10)!,
                    SizedBox(height: style.gap),
                  ],
                  if (style.icon.source != 'none') ...[
                    Align(
                      alignment: style.typography.align == 'center' ? Alignment.center : Alignment.centerLeft,
                      child: NotificationIconBadge(style: style),
                    ),
                    SizedBox(height: style.gap),
                  ],
                  Text(payload.title, textAlign: notificationTextAlign(style), style: notificationTitleStyle(style, bump: 2)),
                  SizedBox(height: style.gap * 0.4),
                  Text(payload.body, textAlign: notificationTextAlign(style), style: notificationBodyStyle(style)),
                  if (style.image?.position == 'bottom' && style.image != null) ...[
                    SizedBox(height: style.gap),
                    notificationImage(style, radius: 10)!,
                  ],
                  if (style.buttons.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: style.gap),
                      child: SizedBox(
                        width: double.infinity,
                        height: style.buttonShape.height,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: style.colors.accent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(style.buttonShape.radius)),
                          ),
                          onPressed: onDismiss,
                          child: const Text('Понятно'),
                        ),
                      ),
                    )
                  else
                    NotificationButtonsRow(
                      style: style,
                      locale: locale,
                      onTap: (b) {
                        onButtonTap(b);
                        onDismiss();
                      },
                    ),
                ],
              ),
            if (style.closeButton) NotificationCloseButton(style: style, onTap: onDismiss),
          ],
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
    final isBackgroundImage = style.image?.url != null && style.image!.position == 'background';
    final gradient = style.gradient;
    return Scaffold(
      backgroundColor: isBackgroundImage || gradient != null ? null : style.colors.background,
      body: Container(
        decoration: !isBackgroundImage && gradient != null
            ? notificationCardDecoration(style, onSurface: false, radius: BorderRadius.zero)
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isBackgroundImage)
              Image.network(
                style.image!.url,
                fit: style.image!.fit == 'contain' ? BoxFit.contain : BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: style.padding + 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (style.image?.url != null && !isBackgroundImage)
                      Padding(
                        padding: EdgeInsets.only(bottom: style.gap),
                        child: notificationImage(style, radius: 20),
                      ),
                    if (style.icon.source != 'none') ...[
                      NotificationIconBadge(style: style, size: style.icon.size + 8),
                      SizedBox(height: style.gap),
                    ],
                    Text(payload.title, textAlign: TextAlign.center, style: notificationTitleStyle(style, bump: 4)),
                    SizedBox(height: style.gap * 0.5),
                    Text(payload.body, textAlign: TextAlign.center, style: notificationBodyStyle(style, bump: 1)),
                    if (style.buttons.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: style.gap),
                        child: NotificationButtonsRow(
                          style: style,
                          locale: locale,
                          onTap: (b) {
                            onButtonTap(b);
                            onDismiss();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (style.closeButton)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: NotificationCloseButton(style: style, onTap: onDismiss),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
