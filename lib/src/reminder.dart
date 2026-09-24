import 'models/check_result.dart';

/// Частота напоминания об обновлении.
///
/// Считает её клиент, а не сервер: сервер видит проверки, а запуск приложения
/// от проверки отличается — за один старт проверок бывает несколько (поллинг,
/// возврат из фона). «Каждый третий запуск» и «каждая третья проверка» — это
/// разные величины, и вторую нечестно называть запуском.
///
/// Режимы приходят в `recommendedVersion.frequency` из админки:
///
/// | Режим | Когда показывать |
/// | --- | --- |
/// | `every_launch` | всегда |
/// | `one_time` | один раз на установку |
/// | `every_nth` | на каждом N-м запуске (`everyNth`) |
/// | `every_x_hours` | не чаще раза в N часов (`periodHours`) |
///
/// **Обязательного обновления это не касается.** Блокировка версии и
/// `updatePriority: forced|required` показываются всегда: частота — про
/// вежливое напоминание, а не про право запереть приложение. Решение об этом
/// принимает [vmVerdictFor], и правило не должно раздвоиться.
class VmReminderState {
  /// Номер сборки, о которой напоминали. Смена цели сбрасывает счётчики:
  /// иначе человек, пропустивший два запуска из трёх, при новом релизе ждал бы
  /// ещё столько же.
  final int? target;

  /// Номер запуска, на котором напоминание показали в последний раз.
  final int? shownAtLaunch;

  /// Время последнего показа.
  final DateTime? shownAt;

  const VmReminderState({this.target, this.shownAtLaunch, this.shownAt});

  /// Показывали ли напоминание об этой сборке хоть раз.
  bool get shown => shownAtLaunch != null || shownAt != null;

  VmReminderState forTarget(int build) => target == build ? this : VmReminderState(target: build);
}

/// Решает, показывать ли напоминание о [version] на запуске номер [launch].
///
/// [now] и [launch] передаются снаружи, чтобы решение было проверяемым: та же
/// пара входных данных всегда даёт тот же ответ.
bool vmShouldRemind({
  required RecommendedVersion version,
  required VmReminderState state,
  required int launch,
  required DateTime now,
}) {
  final s = state.forTarget(version.buildNumber);
  switch (version.frequency) {
    case 'one_time':
      return !s.shown;
    case 'every_nth':
      final n = version.everyNth ?? 1;
      if (n <= 1) return true;
      final last = s.shownAtLaunch;
      // Первый запуск после появления рекомендации — показ: ждать N запусков
      // до первого напоминания никто не просил, N — это пауза между ними.
      return last == null || launch - last >= n;
    case 'every_x_hours':
      final hours = version.periodHours ?? 0;
      if (hours <= 0) return true;
      final last = s.shownAt;
      return last == null || now.difference(last) >= Duration(hours: hours);
    case 'every_launch':
    default:
      // Незнакомый режим — режим по умолчанию. Админка новее этой сборки SDK
      // не повод замолчать о вышедшем обновлении.
      return true;
  }
}
