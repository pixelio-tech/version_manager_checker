import 'package:flutter/material.dart';

import '../models/check_result.dart';
import '../models/notification_style.dart';
import 'block_renderer.dart';
import 'notification_visuals.dart';

/// Bottom sheet (`type: "bottomSheet"`) — anchored to the bottom, only the top
/// corners take the configured radius, same content layout as the admin
/// preview's bottomSheet branch (drag handle, icon+title+body row, buttons).
class BottomSheetNotification extends StatelessWidget {
  final NotificationPayload payload;
  final String locale;
  final void Function(NotificationButtonConfig button) onButtonTap;
  final VoidCallback onDismiss;

  const BottomSheetNotification({
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
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: payload.style.colors.overlay ?? const Color(0x73141821),
      builder: (ctx) => BottomSheetNotification(
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
    return SafeArea(
      // Широкий экран (планшет, веб): шторка не расползается на всю ширину,
      // если в стиле задан maxWidth.
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: style.maxWidth ?? double.infinity),
          child: Container(
            decoration: notificationCardDecoration(
              style,
              onSurface: true,
              radius: BorderRadius.only(topLeft: Radius.circular(radius), topRight: Radius.circular(radius)),
            ),
            padding: style.blocks.isEmpty ? style.paddingInsets : EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            // Ручка лежит ПОВЕРХ содержимого: так под неё можно завести картинку
            // во всю ширину — ровно как показывает конструктор.
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (style.blocks.isNotEmpty) ...[
                      NotificationBlocks(
                        style: style,
                        locale: locale,
                        onButtonTap: (b) {
                          onButtonTap(b);
                          onDismiss();
                        },
                      ),
                    ] else ...[
                      Container(
                        width: 36,
                        height: 4,
                        margin: EdgeInsets.only(bottom: style.gap),
                        decoration: BoxDecoration(
                          color: style.colors.text.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      if (style.image?.position == 'top' && style.image != null) ...[
                        notificationImage(style, radius: 12)!,
                        SizedBox(height: style.gap),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (style.icon.source != 'none') ...[NotificationIconBadge(style: style), SizedBox(width: style.gap)],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: notificationCrossAlign(style),
                              children: [
                                Text(
                                  payload.title,
                                  textAlign: notificationTextAlign(style),
                                  style: notificationTitleStyle(style, bump: 1),
                                ),
                                SizedBox(height: style.gap * 0.35),
                                Text(payload.body, textAlign: notificationTextAlign(style), style: notificationBodyStyle(style)),
                              ],
                            ),
                          ),
                          if (style.buttons.isEmpty && !style.closeButton)
                            Icon(Icons.chevron_right, color: style.colors.text.withValues(alpha: 0.4)),
                          if (style.closeButton) NotificationCloseButton(style: style, onTap: onDismiss),
                        ],
                      ),
                      if (style.image?.position == 'bottom' && style.image != null) ...[
                        SizedBox(height: style.gap),
                        notificationImage(style, radius: 12)!,
                      ],
                      NotificationButtonsRow(
                        style: style,
                        locale: locale,
                        onTap: (b) {
                          onButtonTap(b);
                          onDismiss();
                        },
                      ),
                    ],
                  ],
                ),
                if (style.sheetHandle)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: style.handleColor ?? style.colors.text.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
