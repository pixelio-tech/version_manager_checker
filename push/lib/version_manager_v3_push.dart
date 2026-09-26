/// Remote push для Version Manager v3 (checker#9, back#53).
///
/// Связывает `firebase_messaging` с [VersionManager]: получает токен FCM и
/// передаёт его серверу, следит за его обновлением и разбирает открытие пуша
/// рассылки — отмечает его в статистике и отдаёт приложению действие
/// сообщения. Сами уведомления показывает система: FCM присылает их с
/// заголовком и текстом, приложение для этого не нужно.
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

export 'package:version_manager_v3_checker/version_manager_v3_checker.dart' show VmPushOpen;

/// Обработчик открытого пуша: выполнить действие сообщения
/// (`open.action['kind']`: `url`, `deeplink`, `event`, `dismiss`).
typedef VmPushOpenHandler = FutureOr<void> Function(VmPushOpen open);

/// Подключение пушей. Вызывается один раз после `Firebase.initializeApp()` и
/// `VersionManager.init()`.
class VmPush {
  VmPush._();

  static StreamSubscription<String>? _refresh;
  static StreamSubscription<RemoteMessage>? _opened;

  /// Запрашивает разрешение (iOS, Android 13+), передаёт токен серверу и
  /// начинает слушать его обновления и открытия пушей.
  ///
  /// Отказ в разрешении — токен снимается с сервера: рассылка на эту
  /// установку всё равно не покажется. [onOpen] получает и пуш, которым
  /// приложение запустили из закрытого состояния.
  static Future<void> start(
    VersionManager vm, {
    VmPushOpenHandler? onOpen,
    bool requestPermission = true,
    FirebaseMessaging? messaging,
  }) async {
    final m = messaging ?? FirebaseMessaging.instance;
    await _refresh?.cancel();
    await _opened?.cancel();

    if (requestPermission) {
      final settings = await m.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        await vm.setPushToken(null);
        return;
      }
    }
    // На iOS FCM не показывает уведомление, пока приложение открыто, если
    // не попросить явно; рассылка должна выглядеть одинаково всегда.
    await m.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    try {
      await vm.setPushToken(await m.getToken());
    } catch (e) {
      // На iOS токен FCM бывает недоступен, пока APNs не выдал свой: тогда
      // он придёт через onTokenRefresh.
      debugPrint('VmPush: token is not ready yet: $e');
    }
    _refresh = m.onTokenRefresh.listen((t) => unawaited(vm.setPushToken(t)));

    final initial = await m.getInitialMessage();
    if (initial != null) await _handle(vm, initial, onOpen);
    _opened = FirebaseMessaging.onMessageOpenedApp.listen((msg) => unawaited(_handle(vm, msg, onOpen)));
  }

  /// Выключает пуши для установки: снимает токен с сервера и удаляет его в
  /// Firebase. Например, при выходе из аккаунта или по переключателю в
  /// настройках приложения.
  static Future<void> stop(VersionManager vm, {FirebaseMessaging? messaging}) async {
    await _refresh?.cancel();
    await _opened?.cancel();
    _refresh = null;
    _opened = null;
    await vm.setPushToken(null);
    try {
      await (messaging ?? FirebaseMessaging.instance).deleteToken();
    } catch (e) {
      debugPrint('VmPush: token was not deleted: $e');
    }
  }

  static Future<void> _handle(VersionManager vm, RemoteMessage msg, VmPushOpenHandler? onOpen) async {
    final open = await vm.pushOpened(msg.data);
    if (open != null && onOpen != null) await onOpen(open);
  }
}
