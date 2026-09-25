import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'client.dart';
import 'events.dart';
import 'log.dart';
import 'models/check_result.dart';
import 'outcome.dart';
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
/// final outcome = await VersionManager.instance.check();
/// ```
///
/// **Ошибки не влияют на приложение.** Ни один вызов не бросает: недоступный
/// сервер, отозванный ключ и таймаут возвращают [VmUnavailable] и уходят в
/// [failures]. Проверка версии не должна ронять чужой запуск.
///
/// Хранилище по умолчанию живёт в памяти: `instanceId` тогда новый на каждый
/// запуск, и частотные ограничения показов считаются заново. Для продакшена
/// передайте [storage] поверх `shared_preferences` — см. README.
class VersionManager {
  static VersionManager? _instance;

  /// Инициализированный менеджер.
  ///
  /// Если [init] ещё не звали, возвращается пустышка: её [check] отвечает
  /// [VmUnavailable], показы ничего не рисуют. Забытая инициализация — ошибка
  /// интеграции, но ронять из-за неё чужой экран пакет не вправе.
  static VersionManager get instance => _instance ?? _uninitialized();

  static VersionManager? _stub;

  static VersionManager _uninitialized() {
    final stub = _stub ??= VersionManager._(
      client: VmV3Client(baseUrl: '', apiKey: ''),
      namespace: '',
      version: '',
      buildNumber: 0,
      platform: '',
      osVersion: '',
      deviceModel: '',
      locale: 'ru',
      storage: VmMemoryStorage(),
      budget: const Duration(seconds: 5),
      cacheTtl: Duration.zero,
      onLog: null,
    );
    stub._log.error('VersionManager.init() не вызван — проверка версии пропущена');
    return stub;
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

  /// Потолок времени на всю проверку — вместе с повторами.
  ///
  /// Таймаут одной попытки ничего не обещает вызывающему: три попытки по
  /// десять секунд держат `await check()` полминуты, и запуск приложения всё
  /// это время не двигается. Бюджет — то, на что можно рассчитывать.
  final Duration budget;

  /// Сколько живёт сохранённый ответ, когда сервер недоступен.
  ///
  /// [Duration.zero] выключает кэш: нет свежего ответа — нет ограничений.
  /// Иначе сохранённый конфиг продолжает действовать этот срок, а потом
  /// перестаёт сам: лежащий неделями сервер не должен держать людей
  /// заблокированными, но и авиарежим не должен снимать блокировку мгновенно.
  final Duration cacheTtl;

  final VmLog _log;

  String? _instanceId;
  String? _etag;
  CheckResult? _last;
  DateTime? _lastAt;
  Timer? _poll;
  Timer? _eventsTimer;
  late final VmEventQueue _events;

  /// Как часто отправлять накопленные события, если очередь не заполнилась.
  static const eventsInterval = Duration(seconds: 30);
  bool _disposed = false;

  int _launch = 1;

  /// Что уже показано для конфига [_presentedHash] — по одному показу на
  /// уведомление, пока сервер не пришлёт другой конфиг.
  final Set<String> _presented = {};
  String? _presentedHash;

  final _results = StreamController<CheckResult>.broadcast();
  final _flagChanges = StreamController<Map<String, Object?>>.broadcast();
  final Set<String> _flagTypeWarned = {};

  /// Тесты, экспозиция которых уже отправлена в этом запуске: параметры
  /// читают на каждом кадре, а серверу нужна только первая.
  final Set<String> _exposed = {};
  final _failures = StreamController<Object>.broadcast();

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
    required this.budget,
    required this.cacheTtl,
    required VmLogSink? onLog,
  }) : _log = VmLog(onLog);

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
    Duration budget = const Duration(seconds: 5),
    Duration cacheTtl = const Duration(days: 7),
    VmLogSink? onLog,
  }) async {
    final store = storage ?? VmMemoryStorage();
    if (storage == null) {
      // Без постоянного хранилища instanceId новый на каждый запуск. Это не
      // мелочь: сервер считает установки по нему, и статистика приложения
      // превращается в поток «новых установок», а частотные ограничения
      // показов считаются заново — человек видит одно и то же сообщение.
      VmLog(onLog).error(
        'storage not provided: every launch looks like a new install — '
        'statistics and impression caps will be wrong; pass VmStorage backed by shared_preferences',
      );
    }
    final it = VersionManager._(
      client:
          client ??
          VmV3Client(baseUrl: baseUrl, apiKey: apiKey, timeout: timeout, maxRetries: maxRetries, onLog: onLog),
      namespace: namespace,
      version: version,
      buildNumber: buildNumber,
      platform: platform,
      osVersion: osVersion,
      deviceModel: deviceModel,
      locale: locale,
      storage: store,
      budget: budget,
      cacheTtl: cacheTtl,
      onLog: onLog,
    );
    // Сбой хранилища не должен мешать проверке версии: она важнее, чем
    // память между запусками. Но заметить его надо — без хранилища
    // instanceId новый на каждый старт, и частотные ограничения показов
    // считаются заново, то есть человек видит одно и то же уведомление.
    try {
      it._instanceId = await store.read(_kInstanceId) ?? await it._newInstanceId();
      it._etag = await store.read(_kEtag);
      await it._loadCache();
      await it._countLaunch();
    } catch (e, st) {
      it._log.error('storage is unavailable, continuing without it', error: e, stackTrace: st);
      it._instanceId ??= await it._newInstanceId();
    }
    it._events = VmEventQueue(client: it.client, storage: store, instanceId: () => it.instanceId, log: it._log);
    await it._events.restore();
    it._eventsTimer = Timer.periodic(eventsInterval, (_) => unawaited(it._events.flush()));
    _instance = it;
    it._log.info(
      'initialized',
      data: {
        'version': version,
        'buildNumber': buildNumber,
        'platform': platform,
        'hasStoredEtag': it._etag != null,
        'hasCachedConfig': it._last != null,
        'cacheTtlDays': cacheTtl.inDays,
        'launch': it._launch,
      },
    );
    return it;
  }

  static const _kInstanceId = 'vm.instanceId';
  static const _kEtag = 'vm.etag';
  static const _kConfig = 'vm.config';
  static const _kConfigAt = 'vm.configAt';
  static const _kLaunch = 'vm.launch';

  /// Идентификатор установки: по нему сервер считает частоту показов.
  String get instanceId => _instanceId ?? '';

  /// Последний полученный результат (null, пока не проверяли).
  CheckResult? get lastResult => _last;

  /// Каждая проверка, вернувшая новый конфиг. 304 сюда не попадает.
  Stream<CheckResult> get results => _results.stream;

  /// Текущие значения feature flags (#51): из последнего ответа или из
  /// сохранённого, пока он не просрочен. Пусто — сервер ещё не отвечал и
  /// сохранённого нет; тогда [flag] отдаёт значения по умолчанию из кода.
  Map<String, Object?> get flags => _last?.flags ?? const {};

  /// Значения флагов после каждой проверки, в которой они изменились.
  /// Подписка не обязательна — [flag] всегда читает текущее.
  Stream<Map<String, Object?>> get flagChanges => _flagChanges.stream;

  /// Значение флага [key] нужного типа или [defaultValue].
  ///
  /// Значение по умолчанию — то, с чем приложение работает без сервера:
  /// до первого ответа, офлайн без сохранённого конфига, если флаг удалили
  /// или его тип не совпал с ожидаемым. Числа приводятся между int и double.
  ///
  /// ```dart
  /// if (vm.flag('new_checkout', false)) { ... }
  /// final limit = vm.flag('upload_limit_mb', 50);
  /// ```
  ///
  /// Флаги — выключатели фич. A/B тесты их не подменяют: у теста свои
  /// параметры, см. [experiment].
  T flag<T>(String key, T defaultValue) => _typed(flags[key], defaultValue, 'feature flag', key);

  /// Значение нужного типа или [defaultValue]. Числа приводятся между int и
  /// double; несовпадение типа — ошибка настройки, пишется в лог раз на ключ.
  T _typed<T>(Object? raw, T defaultValue, String what, String key) {
    if (raw == null) return defaultValue;
    if (raw is T) return raw as T;
    if (raw is num) {
      if (defaultValue is double) return raw.toDouble() as T;
      if (defaultValue is int && raw == raw.roundToDouble()) return raw.toInt() as T;
    }
    // Один раз на ключ: читают на каждом кадре.
    if (_flagTypeWarned.add('$what|$key')) {
      _log.warning(
        '$what has an unexpected type, using the default',
        data: {'key': key, 'expected': '$T', 'got': raw.runtimeType.toString()},
      );
    }
    return defaultValue;
  }

  /// Короткая форма для булевых флагов.
  bool isEnabled(String key, {bool defaultValue = false}) => flag<bool>(key, defaultValue);

  /// Варианты A/B тестов, в которые попало устройство:
  /// `{ключ теста: ключ варианта}`. Экспозицию не отмечает — для этого
  /// [experiment].
  Map<String, String> get experiments => {
    for (final e in (_last?.experiments ?? const <String, VmAssignment>{}).entries) e.key: e.value.variant,
  };

  /// A/B тест [key] (version_manager_back#54, #66). Тест не связан с флагами:
  /// у него свои параметры, их значения задаёт вариант устройства.
  ///
  /// ```dart
  /// final paywall = vm.experiment('paywall_design_test');
  /// final layout = paywall.getString('layout', 'classic');
  /// final trialDays = paywall.getInt('trial_days', 3);
  /// ```
  ///
  /// Устройство не в тесте (не подошло, тест не запущен, на паузе, сервер ещё
  /// не отвечал) — [VmExperiment.variant] равен `null`, а `get…` отдают
  /// значения по умолчанию из кода. Значения по умолчанию в коде должны быть
  /// значениями контроля.
  ///
  /// Первое чтение варианта или параметра за запуск отправляет экспозицию:
  /// так отчёт отличает тех, кто дошёл до экрана с тестом, от всех
  /// назначенных. Зовите `get…` там, где значение действительно влияет на
  /// то, что видит человек. Выкаченный тест экспозицию не шлёт.
  VmExperiment experiment(String key) => VmExperiment._(this, key);

  void _expose(String experimentKey) {
    final a = _last?.experiments[experimentKey];
    if (a == null || a.shipped) return;
    if (!_exposed.add(experimentKey)) return;
    unawaited(client.recordExposure(experimentKey: experimentKey, instanceId: instanceId));
  }

  /// Каждая неудавшаяся проверка. Подписка не обязательна: пакет уже пишет их
  /// в [VmLog]. Нужна тем, кто шлёт такое в свою телеметрию.
  Stream<Object> get failures => _failures.stream;

  /// Возраст сохранённого конфига, или null, если его нет.
  Duration? get cacheAge => _lastAt == null ? null : DateTime.now().difference(_lastAt!);

  /// Сохранённый конфиг ещё действует.
  bool get hasFreshCache {
    final age = cacheAge;
    return _last != null && age != null && cacheTtl > Duration.zero && age <= cacheTtl;
  }

  /// Номер текущего запуска приложения, считая с первой установки.
  ///
  /// Растёт один раз за [init], а не за проверку: за один старт проверок
  /// бывает несколько (поллинг, возврат из фона).
  int get launchCount => _launch;

  /// Увеличивает счётчик запусков.
  Future<void> _countLaunch() async {
    final stored = int.tryParse(await storage.read(_kLaunch) ?? '') ?? 0;
    _launch = stored + 1;
    await storage.write(_kLaunch, '$_launch');
  }

  Future<String> _newInstanceId() async {
    final rnd = Random.secure();
    final id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await storage.write(_kInstanceId, id);
    return id;
  }

  /// Спрашивает сервер о версии.
  ///
  /// Не бросает никогда. Сеть, таймаут, отказ сервера и неверный ключ дают
  /// [VmUnavailable]: приложение продолжает работать так же, как до вызова.
  ///
  /// Свежий ответ всегда важнее сохранённого: кэш подставляется только когда
  /// сервер не ответил, и только пока не истёк [cacheTtl].
  ///
  /// [force] сбрасывает ETag — сервер ответит полным конфигом.
  Future<VmCheckOutcome> check({bool force = false}) async {
    try {
      final res = await client
          .checkVersion(
            namespace: namespace,
            version: version,
            buildNumber: buildNumber,
            platform: platform,
            instanceId: instanceId,
            osVersion: osVersion,
            deviceModel: deviceModel,
            locale: locale,
            etag: force ? null : _etag,
          )
          // Потолок на всю проверку: иначе повторы держат запуск приложения
          // дольше, чем кто-либо ожидает от проверки версии.
          .timeout(budget);

      await _rememberEtag(res.etag);
      // Сервер ответил — сеть есть: самое время отправить события, которые
      // копились офлайн.
      if (_events.length > 0) unawaited(_events.flush());

      if (res.result == null) {
        // 304: сервер подтвердил, что конфиг актуален. Это свежий ответ, а не
        // запасной вариант, поэтому срок хранения отсчитывается заново.
        _log.debug('config unchanged (304)');
        await _touchCache();
        return VmUnchanged(_last);
      }

      final before = flags;
      _last = res.result;
      _lastAt = DateTime.now();
      await _saveCache(res.raw);
      _results.add(res.result!);
      if (!_sameFlags(before, res.result!.flags)) _flagChanges.add(res.result!.flags);
      _log.info(
        'check completed',
        data: {
          'status': res.result!.status,
          'notifications': res.result!.notifications.length,
          'nextCheckInSec': res.result!.nextCheckInterval,
        },
      );
      return VmFresh(res.result!);
    } catch (e, st) {
      return _unavailable(e, st);
    }
  }

  /// Готовит исход для неудавшейся проверки и сообщает о ней наружу.
  VmUnavailable _unavailable(Object e, StackTrace st) {
    final fresh = hasFreshCache;
    _log.error(
      'check failed, the app continues as before',
      error: e,
      stackTrace: st,
      data: {'usingCachedConfig': fresh, 'cacheAgeSec': cacheAge?.inSeconds},
    );
    if (_failures.hasListener) _failures.add(e);
    return VmUnavailable(e, result: fresh ? _last : null, cacheAge: cacheAge);
  }

  static bool _sameFlags(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || jsonEncode(e.value) != jsonEncode(b[e.key])) return false;
    }
    return true;
  }

  Future<void> _rememberEtag(String? etag) async {
    if (etag == null || etag == _etag) return;
    _etag = etag;
    try {
      await storage.write(_kEtag, etag);
    } catch (e, st) {
      // Без сохранённого ETag каждый запуск снова тянет конфиг целиком:
      // работать будет, но лишний трафик на каждом старте.
      _log.error('failed to store the ETag', error: e, stackTrace: st);
    }
  }

  /// Кладёт ответ в хранилище, чтобы он пережил перезапуск приложения.
  Future<void> _saveCache(String? raw) async {
    if (cacheTtl <= Duration.zero || raw == null) return;
    try {
      await storage.write(_kConfig, raw);
      await storage.write(_kConfigAt, _lastAt!.toUtc().toIso8601String());
    } catch (e, st) {
      // Не смертельно: следующий запуск просто начнёт без сохранённого
      // конфига, как при первой установке.
      _log.warning('failed to store the config', error: e, data: {'trace': st.toString()});
    }
  }

  /// Отмечает, что сервер подтвердил актуальность сохранённого конфига.
  Future<void> _touchCache() async {
    if (cacheTtl <= Duration.zero || _last == null) return;
    _lastAt = DateTime.now();
    try {
      await storage.write(_kConfigAt, _lastAt!.toUtc().toIso8601String());
    } catch (e, st) {
      _log.warning('failed to refresh the config timestamp', error: e, data: {'trace': st.toString()});
    }
  }

  /// Поднимает сохранённый конфиг. Просроченный не восстанавливается: держать
  /// его в памяти значило бы применить его позже, уже после срока.
  Future<void> _loadCache() async {
    if (cacheTtl <= Duration.zero) return;
    final raw = await storage.read(_kConfig);
    final at = await storage.read(_kConfigAt);
    if (raw == null || at == null) return;

    final savedAt = DateTime.tryParse(at);
    if (savedAt == null) return;
    final age = DateTime.now().difference(savedAt.toLocal());
    if (age > cacheTtl) {
      _log.info('stored config expired', data: {'ageDays': age.inDays, 'ttlDays': cacheTtl.inDays});
      return;
    }
    try {
      _last = CheckResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _lastAt = savedAt.toLocal();
    } catch (e, st) {
      // Формат ответа мог измениться между версиями пакета — это не повод
      // мешать проверке.
      _log.warning('stored config could not be read', error: e, data: {'trace': st.toString()});
    }
  }

  /// Периодическая проверка: интервал берётся из `nextCheckInterval` ответа.
  /// Повторный вызов перезапускает таймер, [stopPolling] его снимает.
  void startPolling({void Function(Object error)? onError, Duration? minInterval}) {
    stopPolling();
    void schedule(Duration d) {
      _log.debug('next check scheduled', data: {'inSec': d.inSeconds});
      _poll = Timer(d, () async {
        final outcome = await check();
        if (outcome is VmUnavailable) {
          onError?.call(outcome.cause);
          // После отказа проверять чаще обычного незачем: сервер, который не
          // ответил, не ответит и через минуту, а батарею это тратит.
          final fallback = minInterval ?? const Duration(minutes: 15);
          _log.debug('backing off after a failed check', data: {'nextInSec': fallback.inSeconds});
          schedule(fallback);
          return;
        }
        schedule(_interval(outcome.result, minInterval));
      });
    }

    _log.info('polling started');
    schedule(_interval(_last, minInterval));
  }

  Duration _interval(CheckResult? r, Duration? minInterval) {
    final fromServer = Duration(seconds: r?.nextCheckInterval ?? 3600);
    final floor = minInterval ?? const Duration(minutes: 1);
    return fromServer < floor ? floor : fromServer;
  }

  void stopPolling() {
    if (_poll != null) _log.debug('polling stopped');
    _poll?.cancel();
    _poll = null;
  }

  /// Отправляет событие воронки за текущую установку.
  Future<void> recordEvent(String notificationId, String eventType) =>
      client.recordEvent(notificationId: notificationId, instanceId: instanceId, eventType: eventType);

  /// Показывает все уведомления из результата по очереди и сам отчитывается
  /// о событиях воронки.
  ///
  /// [context] должен быть **ниже** `Navigator` — баннеры и шторки рисуются
  /// через `Overlay`, который живёт внутри него. Из `builder` у `MaterialApp`
  /// звать нельзя: там `Overlay` ещё не создан и падает
  /// `No Overlay widget found`. Подойдёт контекст любого экрана.
  ///
  /// `localPush` пакет не рисует сам: системное уведомление требует плагина,
  /// нативную часть которого (манифест, разрешения) владеет хост. Подпишитесь
  /// на [onLocalPush] и запланируйте показ сами — готовый сниппет в README.
  Future<void> presentAll(
    BuildContext context, {
    CheckResult? result,
    required VmNotificationAction onAction,
    void Function(NotificationPayload payload)? onLocalPush,
    Duration bannerDuration = const Duration(seconds: 5),
    bool repeat = false,
  }) async {
    final data = result ?? _last;
    if (data == null) return;
    // Новый конфиг — новые показы: отметки прошлого конфига больше ни о чём
    // не говорят.
    if (data.configHash != _presentedHash) {
      _presentedHash = data.configHash;
      _presented.clear();
    }
    for (final n in data.notifications) {
      if (!context.mounted) return;
      // Одно и то же уведомление из одного и того же конфига показывается
      // один раз. Хост зовёт этот метод откуда угодно — с экрана, из
      // слушателя, после возврата из фона, — и человек не должен видеть
      // карточку дважды подряд только потому, что экран пересобрался.
      // [repeat] для тех, кто показывает намеренно (кнопка «показать ещё раз»).
      if (!repeat && !_presented.add(n.id)) {
        _log.debug('notification already shown for this config', data: {'id': n.id});
        continue;
      }
      // Показ обёрнут по одному: кривое оформление, пришедшее из админки,
      // должно гасить себя, а не остальные сообщения и не экран вокруг.
      try {
        await _present(context, n, onAction: onAction, onLocalPush: onLocalPush, bannerDuration: bannerDuration);
      } catch (e, st) {
        _log.error('notification was not shown', error: e, stackTrace: st, data: {'type': n.type});
      }
    }
  }

  Future<void> _present(
    BuildContext context,
    NotificationPayload n, {
    required VmNotificationAction onAction,
    void Function(NotificationPayload payload)? onLocalPush,
    required Duration bannerDuration,
  }) async {
    presentVmNotification(
      context,
      payload: n,
      locale: locale,
      onAction: onAction,
      onLocalPush: onLocalPush,
      bannerDuration: bannerDuration,
      onEvent: (id, type) => recordEvent(id, type),
      // Пустая карточка не показывается: под ней осталось бы одно затемнение,
      // и экран выглядел бы зависшим. Сообщение, у которого нечего рисовать, —
      // ошибка в админке, поэтому её видно в логе.
      onEmpty: (p) =>
          _log.warning('notification has nothing to draw and was skipped', data: {'id': p.id, 'type': p.type}),
    );
    // Модалка и шторка перекрывают друг друга, поэтому следующий показ
    // ждёт, пока пользователь закроет предыдущий.
    if (n.type == 'modal' || n.type == 'bottomSheet') {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Событие приложения — цель A/B теста (#58): покупка, завершённый
  /// онбординг, отправленное сообщение. [value] — необязательное число для
  /// метрики «сумма на участника»: выручка, длительность.
  ///
  /// ```dart
  /// vm.track('purchase', value: 9.99);
  /// vm.track('onboarding.done');
  /// ```
  ///
  /// Не ждёт сети: событие ложится в очередь, очередь переживает перезапуск
  /// и офлайн и уходит пачками. Возвращает false, если имя или значение
  /// кривые — такое событие отброшено и записано в лог.
  bool track(String name, {num? value}) => _events.add(name, value: value);

  /// Отправить накопленные события сейчас — например, перед тем как
  /// приложение уйдёт в фон. Не бросает.
  Future<void> flushEvents() => _events.flush();

  /// Закрывает клиент и таймеры. После этого нужен новый [init].
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _eventsTimer?.cancel();
    stopPolling();
    _results.close();
    _failures.close();
    _flagChanges.close();
    client.close();
    if (identical(_instance, this)) _instance = null;
  }
}

/// A/B тест с точки зрения приложения: вариант и параметры устройства.
/// Получается через [VersionManager.experiment]; дёшев, держать не нужно.
class VmExperiment {
  VmExperiment._(this._vm, this.key);

  final VersionManager _vm;

  /// Ключ теста, как в админке.
  final String key;

  VmAssignment? get _assignment => _vm._last?.experiments[key];

  /// Устройство участвует в тесте (или получает выкаченного победителя).
  /// Экспозицию не отмечает.
  bool get isActive => _assignment != null;

  /// Победитель выкачен: значения больше не делятся по вариантам.
  bool get isShipped => _assignment?.shipped ?? false;

  /// Ключ варианта или `null`, если устройство не в тесте. Отмечает
  /// экспозицию.
  String? get variant {
    final a = _assignment;
    if (a == null) return null;
    _vm._expose(key);
    return a.variant;
  }

  /// Параметр [param] нужного типа или [defaultValue]. Отмечает экспозицию,
  /// если устройство в тесте.
  T get<T>(String param, T defaultValue) {
    final a = _assignment;
    if (a == null) return defaultValue;
    _vm._expose(key);
    return _vm._typed(a.params[param], defaultValue, 'experiment param', '$key.$param');
  }

  bool getBool(String param, bool defaultValue) => get<bool>(param, defaultValue);
  int getInt(String param, int defaultValue) => get<int>(param, defaultValue);
  double getDouble(String param, double defaultValue) => get<double>(param, defaultValue);
  num getNum(String param, num defaultValue) => get<num>(param, defaultValue);
  String getString(String param, String defaultValue) => get<String>(param, defaultValue);

  /// JSON-параметр: объект или список, как пришёл с сервера.
  Map<String, Object?> getJson(String param, Map<String, Object?> defaultValue) {
    final raw = get<Object?>(param, null);
    return raw is Map ? Map<String, Object?>.from(raw) : defaultValue;
  }

  /// Отметить экспозицию вручную — когда значения читаются заранее, а экран
  /// с тестом показывается позже.
  void logExposure() {
    if (_assignment != null) _vm._expose(key);
  }
}
