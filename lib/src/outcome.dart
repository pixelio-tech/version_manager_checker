import 'models/check_result.dart';

/// Чем закончилась проверка версии.
///
/// Отдельный тип вместо `CheckResult?` и исключения нужен по одной причине:
/// ошибка обращения к Version Manager не должна влиять на работу приложения.
/// Бросок из [VersionManager.check] уходил бы в код хоста — чаще всего в
/// `main()` перед `runApp` — и отозванный ключ или недоступный сервер роняли бы
/// чужое приложение на старте.
///
/// ```dart
/// final outcome = await VersionManager.instance.check();
/// if (outcome case VmFresh(:final result) when result.isBlocked) {
///   // показать экран блокировки
/// }
/// // VmUnavailable можно молча игнорировать: приложение работает как раньше
/// ```
sealed class VmCheckOutcome {
  const VmCheckOutcome();

  /// Конфиг, с которым стоит работать, или null, если его нет вовсе.
  ///
  /// У [VmUnavailable] здесь оказывается сохранённый ответ — но только пока он
  /// не просрочен (см. `cacheTtl`).
  CheckResult? get result;
}

/// Сервер ответил новым конфигом.
class VmFresh extends VmCheckOutcome {
  @override
  final CheckResult result;

  const VmFresh(this.result);
}

/// Сервер ответил «не менялось» (304). [result] — прежний конфиг, если он был.
///
/// Это полноценный свежий ответ, а не запасной вариант: сервер подтвердил, что
/// конфиг актуален.
class VmUnchanged extends VmCheckOutcome {
  @override
  final CheckResult? result;

  const VmUnchanged(this.result);
}

/// Спросить не получилось: сеть, таймаут, отказ сервера, неверный ключ.
///
/// [result] — последний сохранённый конфиг, если он ещё не просрочен; иначе
/// null, и приложение работает так, будто проверки не было.
class VmUnavailable extends VmCheckOutcome {
  /// Причина — для логов и телеметрии, не для решений в интерфейсе.
  final Object cause;

  @override
  final CheckResult? result;

  /// Сколько прошло с момента, когда сохранённый конфиг получили с сервера.
  /// null — сохранённого конфига нет.
  final Duration? cacheAge;

  const VmUnavailable(this.cause, {this.result, this.cacheAge});
}
