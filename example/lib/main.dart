import 'package:flutter/material.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

import 'demo_payloads.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Version Manager — песочница',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF5B4BDD), useMaterial3: true),
    darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF5B4BDD), brightness: Brightness.dark, useMaterial3: true),
    home: const DemoHome(),
  );
}

/// Песочница пакета: слева — уведомления без сервера, справа — живой запрос
/// к `check-version` и экран блокировки.
class DemoHome extends StatefulWidget {
  const DemoHome({super.key});

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  final _baseUrl = TextEditingController(text: 'http://localhost:8080');
  final _apiKey = TextEditingController();
  final _namespace = TextEditingController(text: 'com.pixelio.demo');
  final _version = TextEditingController(text: '1.0.0');
  final _build = TextEditingController(text: '1');
  String _platform = 'ios';

  final _log = <String>[];
  CheckResult? _result;
  CheckResult? _gateOverride;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_baseUrl, _apiKey, _namespace, _version, _build]) {
      c.dispose();
    }
    if (VersionManager.isInitialized) VersionManager.instance.dispose();
    super.dispose();
  }

  void _say(String line) {
    setState(() => _log.insert(0, '${TimeOfDay.now().format(context)}  $line'));
  }

  void _action(String kind, String? value) => _say('действие: $kind${value == null ? '' : ' → $value'}');

  Future<void> _connect() async {
    if (_apiKey.text.trim().isEmpty) {
      _say('нужен ключ приложения (X-API-Key)');
      return;
    }
    setState(() => _busy = true);
    try {
      if (VersionManager.isInitialized) VersionManager.instance.dispose();
      final vm = await VersionManager.init(
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim(),
        namespace: _namespace.text.trim(),
        version: _version.text.trim(),
        buildNumber: int.tryParse(_build.text.trim()) ?? 1,
        platform: _platform,
        deviceModel: 'sandbox',
      );
      _say('подключились, instanceId ${vm.instanceId.substring(0, 8)}…');
      final res = await vm.check();
      setState(() => _result = res);
      _say(
        res == null
            ? 'ответ пустой'
            : 'статус ${res.status}, приоритет ${res.updatePriority}, уведомлений ${res.notifications.length}',
      );
      if (res != null && mounted) {
        await vm.presentAll(
          context,
          onAction: _action,
          onLocalPush: (p) => _say('локальный push: ${p.title}'),
          onSilent: (p) => _say('тихое сообщение: ${p.id}'),
        );
      }
    } catch (e) {
      _say('ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recheck() async {
    if (!VersionManager.isInitialized) return _say('сначала подключитесь');
    setState(() => _busy = true);
    try {
      final res = await VersionManager.instance.check();
      setState(() => _result = res);
      _say('перепроверили: статус ${res?.status ?? '—'} (304 отдаёт прежний результат)');
    } catch (e) {
      _say('ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String name) {
    final payload = demoNotifications[name]!;
    presentVmNotification(
      context,
      payload: payload,
      onAction: _action,
      onLocalPush: (p) => _say('локальный push: ${p.title} — рисует ОС, не пакет'),
      onEvent: (id, type) => _say('событие $type · $id'),
    );
    if (payload.type == 'silent') _say('тихое сообщение: ничего не рисуем');
  }

  @override
  Widget build(BuildContext context) {
    // Экран блокировки перекрывает всё приложение — как в бою.
    return VmUpdateGate(
      result: _gateOverride,
      platform: _platform,
      onOpenStore: (l) {
        _say('открыть стор: ${l.url}');
        setState(() => _gateOverride = null);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Version Manager — песочница')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section(
              title: 'Уведомления без сервера',
              subtitle: 'Те же данные, что присылает check-version.',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in demoNotifications.keys) OutlinedButton(onPressed: () => _show(name), child: Text(name)),
                ],
              ),
            ),
            _Section(
              title: 'Экран обновления',
              subtitle: 'Проверка блокировки и обязательного обновления.',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => setState(() => _gateOverride = demoBlockedResult(blocked: true)),
                    child: const Text('Версия заблокирована'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => setState(() => _gateOverride = demoBlockedResult(blocked: false)),
                    child: const Text('Обновление обязательно'),
                  ),
                ],
              ),
            ),
            _Section(
              title: 'Живой сервер',
              subtitle: 'POST /api/mobile/v1/check-version с ключом приложения.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(_baseUrl, 'Адрес сервера'),
                  _field(_apiKey, 'Ключ приложения (vm_live_…)'),
                  _field(_namespace, 'Namespace / bundle id'),
                  Row(
                    children: [
                      Expanded(child: _field(_version, 'Версия')),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_build, 'Билд')),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: _platform,
                        onChanged: (v) => setState(() => _platform = v ?? 'ios'),
                        items: const [
                          DropdownMenuItem(value: 'ios', child: Text('ios')),
                          DropdownMenuItem(value: 'android', child: Text('android')),
                          DropdownMenuItem(value: 'web', child: Text('web')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton(onPressed: _busy ? null : _connect, child: const Text('Проверить версию')),
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: _busy ? null : _recheck, child: const Text('Ещё раз (ETag)')),
                      const SizedBox(width: 8),
                      if (_result != null)
                        OutlinedButton(
                          onPressed: () => setState(() => _gateOverride = _result),
                          child: const Text('Применить как блокировку'),
                        ),
                    ],
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'статус ${_result!.status} · приоритет ${_result!.updatePriority} · '
                      'следующая проверка через ${_result!.nextCheckInterval} с',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            _Section(
              title: 'Журнал',
              subtitle: 'События воронки и действия кнопок.',
              child: _log.isEmpty
                  ? const Text('пока пусто')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final l in _log.take(40)) Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: c,
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
    ),
  );
}

class _Section extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _Section({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}
