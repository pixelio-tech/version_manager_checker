import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'client.dart';
import 'models/check_result.dart';
import 'storage.dart';
import 'ui/notification_presenter.dart';

/// Точка входа пакета: помнит ключ и параметры сборки, сам держит
/// `instanceId` и ETag, ходит на сервер и отдаёт результат.
///
/// ```dart
/// await VersionManager.init(
///   baseUrl: 'https://api.example.com',
///   apiKey: 'vm_live_…',
///   namespace: 'com.example.app',
///   version: '1.2.0',
///   buildNumber: 42,
///   platform: 'ios',
/// );
/// final result = await VersionManager.instance.check();
/// ```
///
/// Хранилище по умолчанию живёт в памяти: `instanceId` тогда новый на каждый
/// запуск, и частотные ограничения показов считаются заново. Для продакшена
/// передайте [storage] поверх `shared_preferences` — см. README.
class VersionManager {
  static VersionManager? _instance;

  /// Инициализированный менеджер. Бросает, если [init] ещё не звали.
  static VersionManager get instance {
    final it = _instance;
    if (it == null) {
      throw StateError('VersionManager.init() не вызван — сделайте это до первой проверки версии');
    }
    return it;
  }

  static bool get isInitialized => _instance != null;

  final VmV3Client client;
  final String namespace;
  final String version;
  final int buildNumber;
  final String platform;
  final String osVersion;
  final String deviceModel;
  final String locale;
  final VmStorage storage;

  String? _instanceId;
  String? _etag;
  CheckResult? _last;
  Timer? _poll;

  final _results = StreamController<CheckResult>.broadcast();

  VersionManager._({
    required this.client,
    required this.namespace,
    required this.version,
    required this.buildNumber,
    required this.platform,
    required this.osVersion,
    required this.deviceModel,
    required this.locale,
    required this.storage,
  });

  /// Создаёт менеджер и восстанавливает `instanceId` из хранилища.
  static Future<VersionManager> init({
    required String baseUrl,
    required String apiKey,
    required String namespace,
    required String version,
    required int buildNumber,
    required String platform,
    String osVersion = '',
    String deviceModel = '',
    String locale = 'ru',
    VmStorage? storage,
    VmV3Client? client,
    Duration timeout = const Duration(seconds: 10),
    int maxRetries = 2,
  }) async {
    final store = storage ?? VmMemoryStorage();
    final it = VersionManager._(
      client: client ?? VmV3Client(baseUrl: baseUrl, apiKey: apiKey, timeout: timeout, maxRetries: maxRetries),
      namespace: namespace,
      version: version,
      buildNumber: buildNumber,
      platform: platform,
      osVersion: osVersion,
      deviceModel: deviceModel,
      locale: locale,
      storage: store,
    );
    it._instanceId = await store.read(_kInstanceId) ?? await it._newInstanceId();
    it._etag = await store.read(_kEtag);
    _instance = it;
    return it;
  }

  static const _kInstanceId = 'vm.instanceId';
  static const _kEtag = 'vm.etag';

  /// Идентификатор установки: по нему сервер считает частоту показов.
  String get instanceId => _instanceId ?? '';

  /// Последний полученный результат (null, пока не проверяли).
  CheckResult? get lastResult => _last;

  /// Каждая проверка, вернувшая новый конфиг. 304 сюда не попадает.
  Stream<CheckResult> get results => _results.stream;

  Future<String> _newInstanceId() async {
    final rnd = Random.secure();
    final id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await storage.write(_kInstanceId, id);
    return id;
  }

  /// Спрашивает сервер о версии. При 304 возвращает предыдущий результат.
  ///
  /// [force] сбрасывает ETag — сервер ответит полным конфигом.
  Future<CheckResult?> check({bool force = false}) async {
    final res = await client.checkVersion(
      namespace: namespace,
      version: version,
      buildNumber: buildNumber,
      platform: platform,
      instanceId: instanceId,
      osVersion: osVersion,
      deviceModel: deviceModel,
      locale: locale,
      etag: force ? null : _etag,
    );
    if (res.etag != null && res.etag != _etag) {
      _etag = res.etag;
      await storage.write(_kEtag, res.etag!);
    }
    if (res.result == null) return _last;
    _last = res.result;
    _results.add(res.result!);
    return res.result;
  }

  /// Периодическая проверка: интервал берётся из `nextCheckInterval` ответа.
  /// Повторный вызов перезапускает таймер, [stopPolling] его снимает.
  void startPolling({void Function(Object error)? onError, Duration? minInterval}) {
    stopPolling();
    void schedule(Duration d) {
      _poll = Timer(d, () async {
        try {
          final r = await check();
          schedule(_interval(r, minInterval));
        } catch (e) {
          onError?.call(e);
          schedule(minInterval ?? const Duration(minutes: 15));
        }
      });
    }

    schedule(_interval(_last, minInterval));
  }

  Duration _interval(CheckResult? r, Duration? minInterval) {
    final fromServer = Duration(seconds: r?.nextCheckInterval ?? 3600);
    final floor = minInterval ?? const Duration(minutes: 1);
    return fromServer < floor ? floor : fromServer;
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// Отправляет событие воронки за текущую установку.
  Future<void> recordEvent(String notificationId, String eventType) =>
      client.recordEvent(notificationId: notificationId, instanceId: instanceId, eventType: eventType);

  /// Показывает все уведомления из результата по очереди и сам отчитывается
  /// о событиях воронки. `silent` не рисуется — его отдают в [onSilent].
  ///
  /// `localPush` пакет не рисует сам: системное уведомление требует плагина,
  /// нативную часть которого (манифест, разрешения) владеет хост. Подпишитесь
  /// на [onLocalPush] и запланируйте показ сами — готовый сниппет в README.
  Future<void> presentAll(
    BuildContext context, {
    CheckResult? result,
    required VmNotificationAction onAction,
    void Function(NotificationPayload payload)? onLocalPush,
    void Function(NotificationPayload payload)? onSilent,
    Duration bannerDuration = const Duration(seconds: 5),
  }) async {
    final data = result ?? _last;
    if (data == null) return;
    for (final n in data.notifications) {
      if (!context.mounted) return;
      if (n.type == 'silent') {
        onSilent?.call(n);
        await recordEvent(n.id, 'shown');
        continue;
      }
      presentVmNotification(
        context,
        payload: n,
        locale: locale,
        onAction: onAction,
        onLocalPush: onLocalPush,
        bannerDuration: bannerDuration,
        onEvent: (id, type) => recordEvent(id, type),
      );
      // Модалка и шторка перекрывают друг друга, поэтому следующий показ
      // ждёт, пока пользователь закроет предыдущий.
      if (n.type == 'modal' || n.type == 'bottomSheet') {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  /// Закрывает клиент и таймеры. После этого нужен новый [init].
  void dispose() {
    stopPolling();
    _results.close();
    client.close();
    if (identical(_instance, this)) _instance = null;
  }
}
