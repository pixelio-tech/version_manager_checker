import 'dart:async';
import 'dart:convert';

import 'client.dart';
import 'log.dart';
import 'storage.dart';

/// Очередь событий приложения для целей A/B тестов (version_manager_back#58).
///
/// Событие не должно теряться из-за того, что человек купил подписку в
/// метро: очередь лежит в [VmStorage] и переживает перезапуск и офлайн.
/// Отправляется пачками по [batchSize] — при заполнении, по таймеру и после
/// каждой проверки версии. Ошибки не бросает: трекинг не должен ломать
/// приложение.
class VmEventQueue {
  VmEventQueue({
    required this.client,
    required this.storage,
    required this.instanceId,
    required this.log,
    this.maxQueued = 500,
    this.batchSize = 50,
    this.flushAt = 20,
  });

  final VmV3Client client;
  final VmStorage storage;
  final String Function() instanceId;
  final VmLog log;

  /// Потолок очереди: дальше выбрасываются самые старые. Месяц офлайна не
  /// должен съесть память и хранилище приложения.
  final int maxQueued;
  final int batchSize;

  /// При скольких событиях в очереди отправлять, не дожидаясь таймера.
  final int flushAt;

  static const storageKey = 'vm.events';
  static final _name = RegExp(r'^[a-z][a-z0-9_.]{0,63}$');

  final List<Map<String, Object?>> _queue = [];
  Future<void>? _flushing;
  Future<void> _saving = Future.value();
  bool _dropWarned = false;

  int get length => _queue.length;

  Future<void> restore() async {
    try {
      final raw = await storage.read(storageKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).whereType<Map>().map((m) => Map<String, Object?>.from(m));
      _queue.insertAll(0, list);
      _trim();
    } catch (e) {
      // Испорченная очередь не должна мешать новой: начинаем с чистой.
      log.warning('stored event queue is unreadable, starting empty', error: e);
    }
  }

  /// Ставит событие в очередь. Имя — как у цели в админке: латиница в
  /// нижнем регистре, цифры, «_» и «.». Кривое имя сервер отверг бы вместе
  /// со всей пачкой, поэтому оно отбрасывается здесь, с записью в лог.
  bool add(String name, {num? value}) {
    if (!_name.hasMatch(name)) {
      log.error('event name is invalid and was dropped', data: {'name': name});
      return false;
    }
    if (value != null && (value.isNaN || value.isInfinite)) {
      log.error('event value is not a finite number and was dropped', data: {'name': name});
      return false;
    }
    _queue.add({'name': name, 'value': ?value, 'occurredAt': DateTime.now().toUtc().toIso8601String()});
    _trim();
    _save();
    if (_queue.length >= flushAt) unawaited(flush());
    return true;
  }

  void _trim() {
    if (_queue.length <= maxQueued) return;
    _queue.removeRange(0, _queue.length - maxQueued);
    if (!_dropWarned) {
      _dropWarned = true;
      log.warning('event queue is full, oldest events were dropped', data: {'max': maxQueued});
    }
  }

  void _save() {
    final snapshot = jsonEncode(_queue);
    _saving = _saving.then((_) => storage.write(storageKey, snapshot)).catchError((Object e) {
      log.warning('event queue was not saved', error: e);
    });
  }

  /// Отправляет всё, что накопилось. Параллельный вызов ждёт идущую отправку,
  /// а не шлёт те же события второй раз.
  Future<void> flush() => _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<void> _flush() async {
    while (_queue.isNotEmpty) {
      final batch = _queue.take(batchSize).toList();
      final result = await client.sendEvents(instanceId: instanceId(), events: batch);
      if (result == VmSendResult.retry) break;
      // Отправлено или отвергнуто — из очереди в любом случае: отвергнутое
      // повтор не исправит.
      _queue.removeRange(0, batch.length);
      _save();
    }
    await _saving;
  }
}
