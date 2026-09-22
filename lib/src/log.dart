/// Диагностика пакета.
///
/// Пакет ничего не пишет сам: библиотека, печатающая в чужой вывод, — плохая
/// библиотека. Вместо этого он отдаёт события, а приложение решает, куда их
/// девать: `debugPrint`, Crashlytics, свой логгер или никуда.
///
/// ```dart
/// await VersionManager.init(
///   // …
///   onLog: (e) => debugPrint('[vm] ${e.level.name} ${e.message}'),
/// );
/// ```
library;

/// Важность записи.
enum VmLogLevel {
  /// Подробности сетевого обмена: попытки, ETag, интервалы.
  debug,

  /// Обычные события: проверка прошла, показ уведомления.
  info,

  /// Что-то пошло не так, но работа продолжается: повтор запроса, отказ
  /// записать событие воронки.
  warning,

  /// Проверка не удалась.
  error,
}

/// Одна запись диагностики.
class VmLogEvent {
  const VmLogEvent({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    this.data = const {},
  });

  final VmLogLevel level;
  final String message;

  /// Исходная ошибка, если запись о сбое.
  final Object? error;
  final StackTrace? stackTrace;

  /// Поля записи: попытка, код ответа, интервал. Ключ приложения и тексты
  /// уведомлений сюда не попадают — первое секрет, второе адресовано
  /// пользователю.
  final Map<String, Object?> data;

  @override
  String toString() {
    final parts = <String>['[${level.name}] $message'];
    if (data.isNotEmpty) parts.add(data.toString());
    if (error != null) parts.add('error: $error');
    return parts.join(' ');
  }
}

/// Приёмник записей на стороне приложения.
typedef VmLogSink = void Function(VmLogEvent event);

/// Отправляет записи в [sink], если он задан.
///
/// Исключение внутри приёмника гасится: чужой логгер не должен ронять
/// проверку версии — ради этого проверку и делали.
class VmLog {
  const VmLog(this.sink);

  final VmLogSink? sink;

  bool get isEnabled => sink != null;

  void call(
    VmLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
  }) {
    final target = sink;
    if (target == null) return;
    try {
      target(VmLogEvent(level: level, message: message, error: error, stackTrace: stackTrace, data: data));
    } catch (_) {
      // Приёмник сломался — это его дело, не наше.
    }
  }

  void debug(String message, {Map<String, Object?> data = const {}}) =>
      call(VmLogLevel.debug, message, data: data);

  void info(String message, {Map<String, Object?> data = const {}}) =>
      call(VmLogLevel.info, message, data: data);

  void warning(String message, {Object? error, Map<String, Object?> data = const {}}) =>
      call(VmLogLevel.warning, message, error: error, data: data);

  void error(String message, {Object? error, StackTrace? stackTrace, Map<String, Object?> data = const {}}) =>
      call(VmLogLevel.error, message, error: error, stackTrace: stackTrace, data: data);
}
