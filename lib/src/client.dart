import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import 'models/check_result.dart';

/// Ответ `check-version` вместе с ETag: его возвращают в следующем запросе,
/// чтобы сервер мог ответить 304 и не гонять конфиг лишний раз.
class CheckResponse {
  /// null — сервер ответил 304: конфиг не менялся с прошлой проверки.
  final CheckResult? result;

  /// Значение заголовка `ETag` (оно же `configHash`).
  final String? etag;

  const CheckResponse({this.result, this.etag});

  bool get notModified => result == null;
}

/// Тонкий клиент мобильного API Version Manager v3
/// (`/api/mobile/v1/*`, авторизация по ключу приложения — см.
/// `version_manager_v3_back/internal/check/handler.go`).
///
/// Сетевые сбои и 5xx повторяются с нарастающей паузой: мобильная сеть рвётся
/// часто, а проверка версии не должна ронять запуск приложения.
class VmV3Client {
  final String baseUrl;
  final String apiKey;
  final Duration timeout;
  final int maxRetries;
  final http.Client _http;

  VmV3Client({
    required this.baseUrl,
    required this.apiKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
    this.maxRetries = 2,
  }) : _http = httpClient ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl/api/mobile/v1$path');

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
      throw VmApiException(res.statusCode, res.body);
    }
    final envelope = jsonDecode(res.body) as Map<String, dynamic>;
    final result = CheckResult.fromJson(envelope['data'] as Map<String, dynamic>);
    return CheckResponse(result: result, etag: res.headers['etag'] ?? result.configHash);
  }

  /// Отправляет событие воронки: `shown` | `clicked` | `dismissed`.
  /// Ошибки глотает: статистика не должна ломать пользовательский сценарий.
  Future<void> recordEvent({required String notificationId, required String instanceId, required String eventType}) async {
    try {
      await _send(
        () => _http.post(
          _uri('/notification-event'),
          headers: _headers,
          body: jsonEncode({'notificationId': notificationId, 'instanceId': instanceId, 'eventType': eventType}),
        ),
      );
    } on VmApiException {
      // Событие не дошло — переживём, воронка не критична для работы приложения.
    }
  }

  /// Запрос с таймаутом и повтором на сетевых сбоях и 5xx.
  Future<http.Response> _send(Future<http.Response> Function() run) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 300 * (1 << (attempt - 1))));
      }
      try {
        final res = await run().timeout(timeout);
        if (res.statusCode >= 500 && attempt < maxRetries) {
          lastError = VmApiException(res.statusCode, res.body);
          continue;
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
    if (lastError is VmApiException) throw lastError;
    throw VmNetworkException(lastError.toString());
  }

  void close() => _http.close();
}

/// Сервер ответил ошибкой.
class VmApiException implements Exception {
  final int statusCode;
  final String body;
  VmApiException(this.statusCode, this.body);

  @override
  String toString() => 'VmApiException($statusCode): $body';
}

/// До сервера не достучались: нет сети, таймаут, оборванное соединение.
class VmNetworkException implements Exception {
  final String reason;
  VmNetworkException(this.reason);

  @override
  String toString() => 'VmNetworkException: $reason';
}
