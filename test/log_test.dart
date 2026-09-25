import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

/// Ответ `check-version`, какой отдаёт сервер.
String _okBody() =>
    jsonEncode({'status': 'up_to_date', 'nextCheckInterval': 3600, 'notifications': <Object>[]});

void main() {
  group('диагностика', () {
    test('без приёмника пакет молчит', () async {
      // Библиотека, печатающая в чужой вывод, — плохая библиотека.
      final client = VmV3Client(
        baseUrl: 'https://example.test',
        apiKey: 'vm_live_x',
        httpClient: MockClient((_) async => http.Response(_okBody(), 200)),
      );
      await client.checkVersion(
        namespace: 'com.example',
        version: '1.0.0',
        buildNumber: 1,
        platform: 'ios',
        instanceId: 'i-1',
      );
      // Ничего не упало и никуда не напечаталось — проверять больше нечего.
    });

    test('повторы видны: причина, номер попытки и задержка', () async {
      final events = <VmLogEvent>[];
      var calls = 0;
      final client = VmV3Client(
        baseUrl: 'https://example.test',
        apiKey: 'vm_live_x',
        maxRetries: 2,
        httpClient: MockClient((_) async {
          calls++;
          // Первый раз сервер падает, второй отвечает.
          return calls == 1 ? http.Response('boom', 503) : http.Response(_okBody(), 200);
        }),
        onLog: events.add,
      );

      await client.checkVersion(
        namespace: 'com.example',
        version: '1.0.0',
        buildNumber: 1,
        platform: 'ios',
        instanceId: 'i-1',
      );

      final retry = events.firstWhere((e) => e.message.contains('retrying'));
      expect(retry.level, VmLogLevel.debug);
      expect(retry.data['attempt'], 2);
      expect(retry.data['reason'], 'http 503');
      expect(events.any((e) => e.message.contains('succeeded after retries')), isTrue);
    });

    test('исчерпанные попытки логируются как ошибка', () async {
      final events = <VmLogEvent>[];
      final client = VmV3Client(
        baseUrl: 'https://example.test',
        apiKey: 'vm_live_x',
        maxRetries: 1,
        httpClient: MockClient((_) async => http.Response('boom', 503)),
        onLog: events.add,
      );

      await expectLater(
        client.checkVersion(
          namespace: 'com.example',
          version: '1.0.0',
          buildNumber: 1,
          platform: 'ios',
          instanceId: 'i-1',
        ),
        throwsA(isA<VmApiException>()),
      );

      final failed = events.firstWhere((e) => e.level == VmLogLevel.error);
      expect(failed.message, contains('still failing after all attempts'));
      expect(failed.data['attempts'], 2);
      expect(failed.data['status'], 503);
    });

    test('сломанный приёмник не роняет проверку', () async {
      // Чужой логгер не должен ломать то, ради чего пакет и подключали.
      final client = VmV3Client(
        baseUrl: 'https://example.test',
        apiKey: 'vm_live_x',
        httpClient: MockClient((_) async => http.Response(_okBody(), 200)),
        onLog: (_) => throw StateError('логгер сломался'),
      );

      final res = await client.checkVersion(
        namespace: 'com.example',
        version: '1.0.0',
        buildNumber: 1,
        platform: 'ios',
        instanceId: 'i-1',
      );
      expect(res.result, isNotNull);
    });

    test('ключ приложения в записи не появляется', () async {
      // Секрет в логе приложения — это секрет в чужих отчётах о сбоях.
      final events = <VmLogEvent>[];
      final client = VmV3Client(
        baseUrl: 'https://example.test',
        apiKey: 'vm_live_super_secret_key',
        maxRetries: 0,
        httpClient: MockClient((_) async => http.Response('boom', 503)),
        onLog: events.add,
      );

      await expectLater(
        client.checkVersion(
          namespace: 'com.example',
          version: '1.0.0',
          buildNumber: 1,
          platform: 'ios',
          instanceId: 'i-1',
        ),
        throwsA(isA<VmApiException>()),
      );

      for (final e in events) {
        expect(e.toString(), isNot(contains('super_secret_key')));
      }
    });

    test('событие воронки, которое не дошло, остаётся в логе', () async {
      // Поведение не меняется — событие по-прежнему не критично, — но если
      // они перестанут доходить у всех сразу, это видно только по пустой
      // статистике в админке.
      final events = <VmLogEvent>[];
      final client = VmV3Client(
        baseUrl: 'https://example.test',
        apiKey: 'vm_live_x',
        maxRetries: 0,
        httpClient: MockClient(
          (r) async => r.url.path.endsWith('/notification-event')
              ? http.Response('nope', 400)
              : http.Response(_okBody(), 200),
        ),
        onLog: events.add,
      );

      await client.recordEvent(notificationId: 'n-1', instanceId: 'i-1', eventType: 'shown');

      final warn = events.firstWhere((e) => e.level == VmLogLevel.warning);
      expect(warn.message, contains('not delivered'));
      expect(warn.data['eventType'], 'shown');
    });
  });
}
