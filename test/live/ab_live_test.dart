// Живой прогон SDK против настоящего бэкенда (version_manager_back#61,
// checker#12).
//
// Юнит-тесты SDK ходят в MockClient и контракт с сервером не проверяют:
// переименуй сервер поле experimentFlags или формат occurredAt, тесты
// останутся зелёными, а отчёт A/B в проде — пустым. Здесь настоящий
// VersionManager проходит путь приложения: проверка версии → флаг под
// экспериментом → экспозиция → покупка в очереди событий → отчёт на сервере.
//
// Нужен бэкенд в режиме development (регистрация по devCode):
//
//   VM_LIVE_URL=http://localhost:8080 flutter test test/live/
//
// Без VM_LIVE_URL тест пропускается.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

final _base = Platform.environment['VM_LIVE_URL'] ?? '';

/// Админский API от имени свежего пользователя.
class _Admin {
  _Admin(this.token);
  final String token;

  static Future<dynamic> _call(String method, String path, {String? token, Object? body}) async {
    final req = http.Request(method, Uri.parse('$_base/api/admin/v1$path'))
      ..headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode >= 300) throw StateError('$method $path: ${res.statusCode} ${res.body}');
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  static Future<_Admin> register() async {
    final email = 'live-${DateTime.now().microsecondsSinceEpoch}@example.com';
    final sent = await _call('POST', '/auth/send-code', body: {'email': email, 'purpose': 'register'});
    final code = sent['devCode'] as String?;
    if (code == null) throw StateError('нет devCode — бэкенд не в режиме development');
    final reg = await _call(
      'POST',
      '/auth/register',
      body: {'email': email, 'code': code, 'password': 'Sup3rSecret!42', 'firstName': 'Live'},
    );
    return _Admin(reg['accessToken'] as String);
  }

  Future<dynamic> call(String method, String path, [Object? body]) => _call(method, path, token: token, body: body);
}

void main() {
  test(
    'флаг под A/B тестом: вариант, экспозиция и покупка доезжают до отчёта',
    () async {
      final admin = await _Admin.register();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final app = await admin.call('POST', '/apps', {
        'name': 'Live SDK',
        'platforms': ['ios'],
        'iosBundleId': 'tech.pixelio.live$stamp',
      });
      final appId = app['id'] as String;
      final envs = await admin.call('GET', '/apps/$appId/environments');
      final envId = (envs['items'] as List).first['id'] as String;
      final key = (await admin.call('GET', '/apps/$appId/environments/$envId/key'))['key'] as String;

      final flag = await admin.call('POST', '/flags?application_id=$appId', {
        'key': 'paywall',
        'type': 'string',
        'defaultValue': 'classic',
      });
      final exp = await admin.call('POST', '/experiments?application_id=$appId', {
        'key': 'paywall_v2',
        'name': 'Пейвол',
        'kind': 'flag',
        'flagId': flag['id'],
        'metrics': [
          {'kind': 'event', 'eventName': 'purchase', 'role': 'primary'},
          {'kind': 'event', 'eventName': 'purchase', 'aggregate': 'sum', 'role': 'secondary'},
        ],
        'variants': [
          {'key': 'control', 'weight': 50, 'value': 'classic'},
          {'key': 'compact', 'weight': 50, 'value': 'compact'},
        ],
      });
      final expId = exp['id'] as String;
      await admin.call('POST', '/experiments/$expId/start');

      // Восемь установок. Каждая — отдельное хранилище, как отдельный телефон.
      final bought = <String, int>{'control': 0, 'compact': 0};
      final assigned = <String, int>{'control': 0, 'compact': 0};
      for (var i = 0; i < 8; i++) {
        final vm = await VersionManager.init(
          baseUrl: _base,
          apiKey: key,
          namespace: 'tech.pixelio.live$stamp',
          version: '1.0.0',
          buildNumber: 42,
          platform: 'ios',
          locale: 'ru-RU',
          storage: VmMemoryStorage(),
          maxRetries: 0,
        );
        // До ответа сервера — значение из кода, вне теста.
        expect(vm.flag('paywall', 'classic'), 'classic');
        expect(vm.experiment('paywall_v2'), isNull);

        await vm.check();
        final variant = vm.experiments['paywall_v2'];
        expect(variant, isIn(['control', 'compact']), reason: 'установка $i не попала в тест со 100% аудитории');
        assigned[variant!] = assigned[variant]! + 1;
        // Экран пейвола читает флаг — не вариант. SDK сам отмечает экспозицию.
        expect(vm.flag('paywall', 'classic'), variant == 'compact' ? 'compact' : 'classic');

        if (i.isEven) {
          expect(vm.track('purchase', value: 4.99), isTrue);
          bought[variant] = bought[variant]! + 1;
        }
        expect(vm.track('paywall.close'), isTrue);
        await vm.flushEvents();
        // Экспозиция уходит без ожидания — дадим ей доехать.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        vm.dispose();
      }

      final rep = await admin.call('GET', '/experiments/$expId/report');
      final primary = (rep['metrics'] as List).first['variants'] as List;
      for (final v in primary.cast<Map<String, dynamic>>()) {
        final k = v['key'] as String;
        expect(v['assigned'], assigned[k], reason: '$k: назначено');
        expect(v['exposed'], assigned[k], reason: '$k: экспозиция от vm.flag не дошла');
        expect(v['conversions'], bought[k], reason: '$k: покупки из очереди SDK не засчитаны');
      }
      final revenue = (rep['metrics'] as List)[1]['variants'] as List;
      for (final v in revenue.cast<Map<String, dynamic>>()) {
        final k = v['key'] as String;
        final n = assigned[k]!;
        if (n == 0) continue;
        expect((v['value'] as num).toDouble(), closeTo(bought[k]! * 4.99 / n, 1e-6), reason: '$k: выручка на участника');
      }

      // Подсказка событий в админке видит то, что прислал SDK.
      final names = await admin.call('GET', '/experiments/event-names?application_id=$appId');
      expect((names['items'] as List).map((e) => e['name']), containsAll(['purchase', 'paywall.close']));
    },
    skip: _base.isEmpty ? 'нужен VM_LIVE_URL — адрес бэкенда в режиме development' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
