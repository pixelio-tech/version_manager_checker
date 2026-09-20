import 'package:flutter/widgets.dart';

import '../models/check_result.dart';
import '../models/notification_style.dart';
import 'banner_notification.dart';
import 'bottom_sheet_notification.dart';
import 'modal_notification.dart';

/// Fired when the notification's default tap action or a button's action
/// should run. `kind` is `url`/`deeplink`/`store`/`dismiss`; `value` is the
/// URL/deeplink/store id for the first three. The host app owns actually
/// opening it (`url_launcher`, router, etc.) — this package stays UI-only.
typedef VmNotificationAction = void Function(String kind, String? value);

/// `shown` | `clicked` | `dismissed` — feed straight into
/// [VmV3Client.recordEvent] to keep the admin funnel accurate.
typedef VmNotificationEvent = void Function(String notificationId, String eventType);

/// Renders one delivered [NotificationPayload] on the right surface for its
/// `type`, using its `style` verbatim — this is the client-side half of the
/// admin configurator's live preview; the two must stay visually identical.
///
/// `localPush` is intentionally not drawn here: a real local/OS push needs a
/// plugin like `flutter_local_notifications`, which this package does not
/// depend on. Wire [onLocalPush] to schedule it yourself; `style.icon` and
/// `style.buttons` map onto that plugin's icon/actions.
void presentVmNotification(
  BuildContext context, {
  required NotificationPayload payload,
  String locale = 'ru',
  required VmNotificationAction onAction,
  VmNotificationEvent? onEvent,
  void Function(NotificationPayload payload)? onLocalPush,
  Duration bannerDuration = const Duration(seconds: 5),
}) {
  void handleButton(NotificationButtonConfig button) {
    onEvent?.call(payload.id, 'clicked');
    onAction(button.actionKind, button.actionValue);
  }

  void handleDefaultTap() {
    onEvent?.call(payload.id, 'clicked');
    final kind = payload.action['kind'] as String?;
    final value = (payload.action['url'] ?? payload.action['deeplink'] ?? payload.action['value']) as String?;
    if (kind != null) onAction(kind, value);
  }

  switch (payload.type) {
    case 'silent':
      onEvent?.call(payload.id, 'shown');
      return;
    case 'localPush':
      onEvent?.call(payload.id, 'shown');
      onLocalPush?.call(payload);
      return;
    case 'banner':
      onEvent?.call(payload.id, 'shown');
      BannerNotification.show(
        context,
        payload: payload,
        locale: locale,
        duration: bannerDuration,
        onButtonTap: handleButton,
        onTap: handleDefaultTap,
        onDismissed: () => onEvent?.call(payload.id, 'dismissed'),
      );
      return;
    case 'modal':
      onEvent?.call(payload.id, 'shown');
      ModalNotification.show(
        context,
        payload: payload,
        locale: locale,
        onButtonTap: handleButton,
      ).then((_) => onEvent?.call(payload.id, 'dismissed'));
      return;
    case 'bottomSheet':
      onEvent?.call(payload.id, 'shown');
      BottomSheetNotification.show(
        context,
        payload: payload,
        locale: locale,
        onButtonTap: handleButton,
      ).then((_) => onEvent?.call(payload.id, 'dismissed'));
      return;
  }
}
