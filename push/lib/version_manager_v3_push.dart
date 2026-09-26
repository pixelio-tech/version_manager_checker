/// Remote push для Version Manager v3 (checker#9, checker#19, back#53, back#84).
///
/// Связывает `firebase_messaging` с [VersionManager]: получает токен FCM и
/// передаёт его серверу вместе с каналами Android, следит за его обновлением,
/// показывает рассылку при открытом приложении и разбирает открытие пуша —
/// отмечает его в статистике и отдаёт приложению действие сообщения.
library;

import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

export 'package:firebase_messaging/firebase_messaging.dart' show BackgroundMessageHandler, RemoteMessage;
export 'package:version_manager_v3_checker/version_manager_v3_checker.dart'
    show VmPushOpen, VmPushChannel, VmPushImportance;

/// Обработчик открытого пуша: выполнить действие сообщения
/// (`open.action['kind']`: `url`, `deeplink`, `event`, `dismiss`).
typedef VmPushOpenHandler = FutureOr<void> Function(VmPushOpen open);

/// Чем закончился [VmPush.start].
enum VmPushStatus {
  /// Сервер знает токен: рассылки дойдут.
  registered,

  /// Токен не дошёл — сервер недоступен или FCM ещё не выдал токен. SDK
  /// повторит сам: при следующем старте и при `onTokenRefresh`.
  pending,

  /// Человек запретил уведомления: токен снят с сервера.
  denied,

  /// Сервер отказал (например, отозван ключ окружения).
  rejected,
}

/// Фоновый обработчик SDK по умолчанию. Регистрируется, когда приложение не
/// передало свой: без обработчика Firebase не доносит сообщение до Dart,
/// пока приложение свёрнуто или выгружено. Рассылки Version Manager приходят
/// с заголовком и текстом — их показывает система, поэтому здесь нечего
/// делать, кроме как принять сообщение.
@pragma('vm:entry-point')
Future<void> vmPushBackgroundHandler(RemoteMessage message) async {
  debugPrint('VmPush: background message ${message.messageId}');
}

/// Подключение пушей. Вызывается один раз после `Firebase.initializeApp()` и
/// `VersionManager.init()`.
class VmPush {
  VmPush._();

  /// Канал, который SDK заводит, если приложение не передало своих.
  static VmPushChannel get fallbackChannel => VmPushChannel(
    'vm_default',
    PlatformDispatcher.instance.locale.languageCode == 'ru' ? 'Уведомления' : 'Notifications',
  );

  /// Метка в payload локального уведомления: по ней [handleLocalNotificationTap]
  /// отличает наши уведомления от уведомлений приложения.
  static const _payloadTag = 'vm_push:';

  static StreamSubscription<String>? _refresh;
  static StreamSubscription<RemoteMessage>? _opened;
  static StreamSubscription<RemoteMessage>? _foreground;
  static VersionManager? _vm;
  static VmPushOpenHandler? _onOpen;
  static List<VmPushChannel> _channels = const [];
  static String? _defaultChannel;
  static int _nextId = 0;

  /// Запрашивает разрешение (iOS, Android 13+), заводит каналы Android,
  /// передаёт токен и каналы серверу и начинает слушать обновления токена,
  /// пуши при открытом приложении и открытия.
  ///
  /// - [channels] — каналы Android (back#84). Пусто — один канал SDK
  ///   ([fallbackChannel]). [defaultChannel] — канал рассылки без выбранного
  ///   канала; по умолчанию первый.
  /// - [showInForeground] — показывать рассылку, пока приложение открыто
  ///   (по умолчанию да). Иначе она приходит только в [onMessage].
  /// - Фоновый обработчик: по умолчанию SDK регистрирует
  ///   [vmPushBackgroundHandler]. Firebase держит **один** обработчик на
  ///   приложение: свой передайте в [onBackgroundMessage] (top-level или
  ///   static функция с `@pragma('vm:entry-point')`), а если приложение
  ///   регистрирует его само — [handleBackground] = false.
  /// - [localNotifications] и [initializeLocalNotifications]: если приложение
  ///   само пользуется `flutter_local_notifications`, у плагина один
  ///   обработчик тапов на всё приложение. Тогда передайте свой экземпляр,
  ///   `initializeLocalNotifications: false` и в своём
  ///   `onDidReceiveNotificationResponse` зовите [handleLocalNotificationTap].
  ///
  /// Отказ в разрешении — токен снимается с сервера: рассылка на эту
  /// установку всё равно не покажется. [onOpen] получает и пуш, которым
  /// приложение запустили из закрытого состояния.
  static Future<VmPushStatus> start(
    VersionManager vm, {
    VmPushOpenHandler? onOpen,
    List<VmPushChannel> channels = const [],
    String? defaultChannel,
    bool showInForeground = true,
    void Function(RemoteMessage message)? onMessage,
    bool handleBackground = true,
    BackgroundMessageHandler? onBackgroundMessage,
    bool requestPermission = true,
    String androidIcon = '@mipmap/ic_launcher',
    FlutterLocalNotificationsPlugin? localNotifications,
    bool initializeLocalNotifications = true,
    FirebaseMessaging? messaging,
  }) async {
    final m = messaging ?? FirebaseMessaging.instance;
    await _cancel();
    _vm = vm;
    _onOpen = onOpen;
    _channels = channels.isEmpty ? [fallbackChannel] : channels;
    _defaultChannel = defaultChannel ?? _channels.first.id;
    _local = localNotifications ?? _local ?? FlutterLocalNotificationsPlugin();

    if (handleBackground) {
      FirebaseMessaging.onBackgroundMessage(onBackgroundMessage ?? vmPushBackgroundHandler);
    }

    if (requestPermission) {
      final settings = await m.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        await vm.setPushToken(null);
        return VmPushStatus.denied;
      }
    }

    // iOS: пока приложение открыто, FCM показывает уведомление, только если
    // попросить явно. Android — локальным уведомлением ниже.
    await m.setForegroundNotificationPresentationOptions(alert: showInForeground, badge: true, sound: showInForeground);
    if (_isAndroid) await _prepareAndroid(androidIcon, initializeLocalNotifications);

    _foreground = FirebaseMessaging.onMessage.listen((msg) {
      if (showInForeground && _isAndroid) unawaited(_showLocal(msg));
      onMessage?.call(msg);
    });

    var status = VmPushStatus.pending;
    try {
      status = _statusOf(
        await vm.setPushToken(await m.getToken(), channels: _channels, defaultChannel: _defaultChannel),
      );
    } catch (e) {
      // На iOS токен FCM бывает недоступен, пока APNs не выдал свой: тогда
      // он придёт через onTokenRefresh.
      debugPrint('VmPush: token is not ready yet: $e');
    }
    _refresh = m.onTokenRefresh.listen(
      (t) => unawaited(vm.setPushToken(t, channels: _channels, defaultChannel: _defaultChannel)),
    );

    final initial = await m.getInitialMessage();
    if (initial != null) await _handle(initial.data);
    _opened = FirebaseMessaging.onMessageOpenedApp.listen((msg) => unawaited(_handle(msg.data)));
    return status;
  }

  /// Тап по локальному уведомлению, если приложение инициализирует
  /// `flutter_local_notifications` само (`initializeLocalNotifications:
  /// false`). Возвращает true, если уведомление наше и обработано.
  static Future<bool> handleLocalNotificationTap(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || !payload.startsWith(_payloadTag)) return false;
    try {
      final data = jsonDecode(payload.substring(_payloadTag.length));
      if (data is Map) await _handle(Map<String, Object?>.from(data));
    } catch (e) {
      debugPrint('VmPush: bad local notification payload: $e');
    }
    return true;
  }

  /// Выключает пуши для установки: снимает токен с сервера и удаляет его в
  /// Firebase. Например, при выходе из аккаунта или по переключателю в
  /// настройках приложения.
  static Future<void> stop(VersionManager vm, {FirebaseMessaging? messaging}) async {
    await _cancel();
    await vm.setPushToken(null);
    try {
      await (messaging ?? FirebaseMessaging.instance).deleteToken();
    } catch (e) {
      debugPrint('VmPush: token was not deleted: $e');
    }
  }

  static FlutterLocalNotificationsPlugin? _local;

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> _cancel() async {
    await _refresh?.cancel();
    await _opened?.cancel();
    await _foreground?.cancel();
    _refresh = null;
    _opened = null;
    _foreground = null;
  }

  static VmPushStatus _statusOf(VmSendResult r) => switch (r) {
    VmSendResult.sent => VmPushStatus.registered,
    VmSendResult.retry => VmPushStatus.pending,
    VmSendResult.rejected => VmPushStatus.rejected,
  };

  /// Заводит каналы и, если разрешено, инициализирует плагин с обработчиком
  /// тапов. Пуш, показанный при открытом приложении, может открыть и уже
  /// закрытое приложение — такой тап приходит через launch details.
  static Future<void> _prepareAndroid(String icon, bool initialize) async {
    final local = _local!;
    if (initialize) {
      await local.initialize(
        settings: InitializationSettings(android: AndroidInitializationSettings(icon)),
        onDidReceiveNotificationResponse: (r) => unawaited(handleLocalNotificationTap(r)),
      );
      final launch = await local.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
        await handleLocalNotificationTap(response);
      }
    }
    final android = local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final c in _channels.where((c) => c.isValid)) {
      await android?.createNotificationChannel(
        AndroidNotificationChannel(c.id, c.name, description: c.description, importance: _importance(c.importance)),
      );
    }
  }

  /// Показывает рассылку, пришедшую при открытом приложении, в её канале.
  static Future<void> _showLocal(RemoteMessage msg) async {
    final n = msg.notification;
    if (n == null) return;
    final wanted = n.android?.channelId;
    final channel = _channels.firstWhere(
      (c) => c.id == wanted,
      orElse: () => _channels.firstWhere((c) => c.id == _defaultChannel, orElse: () => _channels.first),
    );
    await _local!.show(
      id: _nextId++,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: _importance(channel.importance),
          priority: channel.importance == VmPushImportance.high ? Priority.high : Priority.defaultPriority,
        ),
      ),
      payload: _payloadTag + jsonEncode(msg.data),
    );
  }

  static Importance _importance(VmPushImportance i) => switch (i) {
    VmPushImportance.min => Importance.min,
    VmPushImportance.low => Importance.low,
    VmPushImportance.normal => Importance.defaultImportance,
    VmPushImportance.high => Importance.high,
  };

  static Future<void> _handle(Map<String, Object?> data) async {
    final vm = _vm;
    if (vm == null) return;
    final open = await vm.pushOpened(data);
    if (open != null && _onOpen != null) await _onOpen!(open);
  }
}
