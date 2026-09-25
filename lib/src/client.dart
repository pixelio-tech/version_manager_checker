import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import 'log.dart';
import 'models/check_result.dart';

/// Ответ `check-version` вместе с ETag: его возвращают в следующем запросе,
/// чтобы сервер мог ответить 304 и не гонять конфиг лишний раз.
class CheckResponse {
  /// null — сервер ответил 304: конфиг не менялся с прошлой проверки.
  final CheckResult? result;

  /// Значение заголовка `ETag` (оно же `configHash`).
  final String? etag;

  /// Тело ответа как есть. Его кладут в хранилище, чтобы пережить перезапуск:
  /// разбирать обратно дешевле, чем описывать сериализацию всего дерева
  /// моделей и потом следить, чтобы она не разошлась с разбором.
  final String? raw;

  const CheckResponse({this.result, this.etag, this.raw});

  bool get notModified => result == null;
}

/// Тонкий клиент мобильного API Version Manager v3
/// (`/api/mobile/v2/*`, авторизация по ключу приложения — см.
/// `version_manager_v3_back/internal/check/handler.go`).
///
/// Форма ответов — `version_manager_v3_back/api/RESPONSES.md`: полезная
/// нагрузка на верхнем уровне, ошибки в `application/problem+json`, отказ по
/// ключу — 403. Версия v1 заморожена и здесь не используется.
///
/// Сетевые сбои и 5xx повторяются с нарастающей паузой: мобильная сеть рвётся
/// часто, а проверка версии не должна ронять запуск приложения.
class VmV3Client {
  final String baseUrl;
  final String apiKey;
  final Duration timeout;
  final int maxRetries;
  final http.Client _http;
  final VmLog _log;

  VmV3Client({
    required this.baseUrl,
    required this.apiKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
    this.maxRetries = 2,
    VmLogSink? onLog,
  }) : _http = httpClient ?? http.Client(),
       _log = VmLog(onLog);

  Uri _uri(String path) => Uri.parse('$baseUrl/api/mobile/v2$path');

  Map<String, String> get _headers => {'Content-Type': 'application/json', 'X-API-Key': apiKey};

  /// Проверка версии. Возвращает результат и ETag; при 304 результат пустой.
  /// Бросает [VmApiException] на 4xx и на исчерпанные попытки.
  Future<CheckResponse> checkVersion({
    required String namespace,
    required String version,
    required int buildNumber,
    required String platform,
    required String instanceId,
    String osVersion = '',
    String deviceModel = '',
    String locale = 'ru',
    String? etag,
  }) async {
    final res = await _send(
      () => _http.post(
        _uri('/check-version'),
        headers: {..._headers, if (etag != null && etag.isNotEmpty) 'If-None-Match': etag},
        body: jsonEncode({
          'namespace': namespace,
          'version': version,
          'buildNumber': buildNumber,
          'platform': platform,
          'instanceId': instanceId,
          'osVersion': osVersion,
          'deviceModel': deviceModel,
          'locale': locale,
        }),
      ),
    );

    if (res.statusCode == 304) return CheckResponse(etag: res.headers['etag'] ?? etag);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw VmApiException.fromResponse(res.statusCode, res.body);
    }
    final result = CheckResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    return CheckResponse(result: result, etag: res.headers['etag'] ?? result.configHash, raw: res.body);
  }

  /// Отправляет событие воронки: `shown` | `clicked` | `dismissed`.
  ///
  /// Ошибки не пробрасывает: статистика не должна ломать пользовательский
  /// сценарий. Но и не теряет их молча — раньше статус ответа здесь вообще не
  /// проверялся, и отказ сервера считался успехом.
  Future<void> recordEvent({
    required String notificationId,
    required String instanceId,
    required String eventType,
  }) async {
    try {
      final res = await _send(
        () => _http.post(
          _uri('/notification-event'),
          headers: _headers,
          body: jsonEncode({
            'notificationId': notificationId,
            'instanceId': instanceId,
            'eventType': eventType,
          }),
        ),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _log.warning(
          'notification event was not delivered',
          error: VmApiException.fromResponse(res.statusCode, res.body),
          data: {'eventType': eventType},
        );
      }
    } on VmNetworkException catch (e) {
      // Сеть не дала отправить. Если события перестанут доходить у всех
      // сразу, это проявится только пустой статистикой в админке.
      _log.warning('notification event was not delivered', error: e, data: {'eventType': eventType});
    } on VmApiException catch (e) {
      _log.warning('notification event was not delivered', error: e, data: {'eventType': eventType});
    }
  }

  /// Отмечает, что приложение прочитало вариант эксперимента [experimentKey].
  ///
  /// Как и [recordEvent], не бросает: экспозиция уточняет отчёт, но
  /// эксперимент считается и без неё — по назначениям на сервере.
  Future<void> recordExposure({required String experimentKey, required String instanceId}) async {
    try {
      final res = await _send(
        () => _http.post(
          _uri('/experiment-exposure'),
          headers: _headers,
          body: jsonEncode({'experimentKey': experimentKey, 'instanceId': instanceId}),
        ),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _log.warning(
          'experiment exposure was not delivered',
          error: VmApiException.fromResponse(res.statusCode, res.body),
          data: {'experiment': experimentKey},
        );
      }
    } on VmNetworkException catch (e) {
      _log.warning('experiment exposure was not delivered', error: e, data: {'experiment': experimentKey});
    } catch (e) {
      // Экспозицию отправляют не дожидаясь ответа, поэтому любое исключение
      // отсюда стало бы необработанной ошибкой в зоне приложения.
      _log.warning('experiment exposure was not delivered', error: e, data: {'experiment': experimentKey});
    }
  }

  /// Отправляет пачку событий приложения (цели A/B тестов).
  ///
  /// Не бросает — говорит, что делать с пачкой: [VmSendResult.sent] —
  /// принята, [VmSendResult.retry] — сеть или сервер, отправить позже,
  /// [VmSendResult.rejected] — сервер отверг содержимое (4xx): повтор не
  /// поможет, пачку надо выбросить, иначе она застрянет в очереди навсегда.
  Future<VmSendResult> sendEvents({required String instanceId, required List<Map<String, Object?>> events}) async {
    try {
      final res = await _send(
        () => _http.post(
          _uri('/events'),
          headers: _headers,
          body: jsonEncode({'instanceId': instanceId, 'events': events}),
        ),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) return VmSendResult.sent;
      final err = VmApiException.fromResponse(res.statusCode, res.body);
      // 429 и 403 — не про содержимое: лимит пройдёт, ключ перевыпустят.
      if (res.statusCode >= 500 || res.statusCode == 429 || res.statusCode == 403) {
        _log.warning('events were not delivered, will retry', error: err, data: {'count': events.length});
        return VmSendResult.retry;
      }
      _log.error('events were rejected and dropped', error: err, data: {'count': events.length});
      return VmSendResult.rejected;
    } catch (e) {
      _log.warning('events were not delivered, will retry', error: e, data: {'count': events.length});
      return VmSendResult.retry;
    }
  }

  /// Запрос с таймаутом и повтором на сетевых сбоях и 5xx.
  Future<http.Response> _send(Future<http.Response> Function() run) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        final delay = Duration(milliseconds: 300 * (1 << (attempt - 1)));
        // Причина повтора и задержка: снаружи иначе виден только итог, и
        // «работает медленно» не отличить от «не работает».
        _log.debug(
          'retrying check',
          data: {
            'attempt': attempt + 1,
            'of': maxRetries + 1,
            'afterMs': delay.inMilliseconds,
            'reason': _reasonOf(lastError),
          },
        );
        await Future<void>.delayed(delay);
      }
      try {
        final res = await run().timeout(timeout);
        if (res.statusCode >= 500 && attempt < maxRetries) {
          lastError = VmApiException(res.statusCode, res.body);
          continue;
        }
        if (res.statusCode >= 500) {
          // Попытки кончились, а сервер всё ещё отвечает ошибкой. Ответ
          // возвращаем как есть — его разбирает вызывающий, — но это отказ,
          // и в логе он должен быть отказом.
          _log.error(
            'server still failing after all attempts',
            data: {'attempts': attempt + 1, 'status': res.statusCode},
          );
        } else if (attempt > 0) {
          _log.info('request succeeded after retries', data: {'attempts': attempt + 1});
        }
        return res;
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
    }
    _log.error(
      'request failed after all attempts',
      error: lastError,
      data: {'attempts': maxRetries + 1, 'reason': _reasonOf(lastError)},
    );
    if (lastError is VmApiException) throw lastError;
    throw VmNetworkException(lastError.toString());
  }

  /// Короткое имя причины: по нему видно, сеть это, таймаут или сервер.
  static String _reasonOf(Object? error) {
    if (error is TimeoutException) return 'timeout';
    if (error is SocketException) return 'network';
    if (error is http.ClientException) return 'client';
    if (error is VmApiException) return 'http ${error.statusCode}';
    return 'unknown';
  }

  void close() => _http.close();
}

/// Сервер ответил ошибкой.
///
/// Тело приходит как `application/problem+json`: машинный [code], человеческий
/// [detail] и [requestId], по которому владелец приложения находит этот самый
/// вызов в логах Version Manager. Для неверного ключа сервер отвечает 403, а не
/// 401: ключ опознаёт приложение, а не пользователя, и 401 в хост-приложении
/// обычно означает «сессия истекла».
class VmApiException implements Exception {
  final int statusCode;
  final String body;
  final String? code;
  final String? detail;
  final String? requestId;

  VmApiException(this.statusCode, this.body, {this.code, this.detail, this.requestId});

  /// Разбирает problem+json. Тело, которое разобрать не удалось (например,
  /// HTML от прокси), сохраняется как есть — пустая ошибка хуже любого текста.
  factory VmApiException.fromResponse(int statusCode, String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return VmApiException(
        statusCode,
        body,
        code: map['code'] as String?,
        detail: map['detail'] as String?,
        requestId: map['requestId'] as String?,
      );
    } catch (_) {
      return VmApiException(statusCode, body);
    }
  }

  /// Ключ приложения не принят: не передан, неизвестен или отозван.
  bool get isBadKey => code == 'INVALID_API_KEY';

  @override
  String toString() {
    final what = detail ?? body;
    final id = requestId != null ? ', requestId $requestId' : '';
    return 'VmApiException(${code ?? statusCode}): $what (HTTP $statusCode$id)';
  }
}

/// До сервера не достучались: нет сети, таймаут, оборванное соединение.
class VmNetworkException implements Exception {
  final String reason;
  VmNetworkException(this.reason);

  @override
  String toString() => 'VmNetworkException: $reason';
}

/// Что стало с пачкой событий, см. [VmV3Client.sendEvents].
enum VmSendResult { sent, retry, rejected }
