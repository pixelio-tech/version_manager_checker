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
/// A `localPush` payload is not drawn here: an OS notification needs a plugin
/// like `flutter_local_notifications`, whose native side (manifest entries,
/// permissions, entitlements) only the host app can own. Depending on it here
/// would push that native weight onto every consumer, including the ones that
/// never send `localPush`. Wire [onLocalPush] and schedule it yourself — the
/// README has a ready snippet.
void presentVmNotification(
  BuildContext context, {
  required NotificationPayload payload,
  String locale = 'ru',
  required VmNotificationAction onAction,
  VmNotificationEvent? onEvent,
  void Function(NotificationPayload payload)? onLocalPush,
  /// Вызывается вместо показа, когда в оформлении не осталось ни одного узла.
  void Function(NotificationPayload payload)? onEmpty,
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

  // Карточка без детей рисуется в ничто, а затемнение под ней остаётся:
  // экран выглядит зависшим, и закрыть его можно только тапом мимо. Пустым
  // дерево приходит и само по себе, и когда все узлы оказались незнакомы
  // этой сборке SDK и отпали при деградации. Показывать нечего — не
  // показываем и говорим об этом вслух.
  final drawsItself = payload.type == 'banner' || payload.type == 'modal' || payload.type == 'bottomSheet';
  if (drawsItself && payload.style.blocks.isEmpty) {
    onEmpty?.call(payload);
    return;
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
