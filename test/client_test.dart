import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

/// Форма ответа v2: полезная нагрузка на верхнем уровне, без конверта.
Map<String, dynamic> _okBody({String status = 'active', List<Map<String, dynamic>> notifications = const []}) => {
  'status': status,
  'isBlocked': false,
  'blockReason': null,
  'updatePriority': 'none',
  'recommendedVersion': null,
  'notifications': notifications,
  'nextCheckInterval': 1800,
  'configHash': 'hash-1',
  'message': '',
  'serverTimestamp': '2026-09-20T10:00:00Z',
};

VmV3Client _client(MockClient mock, {int maxRetries = 2}) =>
    VmV3Client(baseUrl: 'https://api.test', apiKey: 'vm_live_x', httpClient: mock, maxRetries: maxRetries);

Future<CheckResponse> _check(VmV3Client c, {String? etag}) => c.checkVersion(
  namespace: 'com.example.app',
  version: '1.0.0',
  buildNumber: 1,
  platform: 'ios',
  instanceId: 'inst-1',
  etag: etag,
);

void main() {
  test('шлёт ключ приложения и параметры сборки, возвращает ETag', () async {
    late http.Request seen;
    final c = _client(
      MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode(_okBody()),
          200,
          headers: {'etag': 'hash-1', 'content-type': 'application/json'},
        );
      }),
    );

    final res = await _check(c);

    expect(seen.headers['X-API-Key'], 'vm_live_x');
    expect(seen.url.path, '/api/mobile/v2/check-version');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['namespace'], 'com.example.app');
    expect(body['buildNumber'], 1);
    expect(res.notModified, isFalse);
    expect(res.result!.nextCheckInterval, 1800);
    expect(res.etag, 'hash-1');
  });

  test('304 отдаёт пустой результат и сохраняет ETag', () async {
    final c = _client(
      MockClient((req) async {
        expect(req.headers['If-None-Match'], 'hash-1');
        return http.Response('', 304, headers: {'etag': 'hash-1'});
      }),
    );

    final res = await _check(c, etag: 'hash-1');

    expect(res.notModified, isTrue);
    expect(res.result, isNull);
    expect(res.etag, 'hash-1');
  });

  test('4xx поднимает VmApiException и не повторяется', () async {
    var calls = 0;
    final c = _client(
      MockClient((_) async {
        calls++;
        return http.Response('{"error":{"code":"INVALID_API_KEY"}}', 401);
      }),
    );

    await expectLater(_check(c), throwsA(isA<VmApiException>()));
    expect(calls, 1);
  });

  test('5xx повторяется и проходит со второй попытки', () async {
    var calls = 0;
    final c = _client(
      MockClient((_) async {
        calls++;
        if (calls == 1) return http.Response('boom', 503);
        return http.Response(jsonEncode(_okBody(status: 'update_available')), 200);
      }),
    );

    final res = await _check(c);

    expect(calls, 2);
    expect(res.result!.status, 'update_available');
  });

  test('сетевой сбой после всех попыток — VmNetworkException', () async {
    var calls = 0;
    final c = _client(
      MockClient((_) async {
        calls++;
        throw http.ClientException('connection reset');
      }),
      maxRetries: 1,
    );

    await expectLater(_check(c), throwsA(isA<VmNetworkException>()));
    expect(calls, 2);
  });

  test('событие воронки уходит с типом и не падает на ошибке сервера', () async {
    final seen = <Map<String, dynamic>>[];
    final c = _client(
      MockClient((req) async {
        seen.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('nope', 500);
      }),
      maxRetries: 0,
    );

    await c.recordEvent(notificationId: 'n1', instanceId: 'inst-1', eventType: 'clicked');

    expect(seen.single['notificationId'], 'n1');
    expect(seen.single['eventType'], 'clicked');
  });
}
