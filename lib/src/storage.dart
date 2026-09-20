/// Хранилище пары «ключ — строка»: пакету нужно помнить `instanceId` между
/// запусками и ETag последнего конфига.
///
/// Пакет намеренно не тянет `shared_preferences`, чтобы не навязывать
/// зависимость. Подключить его — пять строк:
///
/// ```dart
/// class PrefsStorage implements VmStorage {
///   @override
///   Future<String?> read(String key) async =>
///       (await SharedPreferences.getInstance()).getString(key);
///   @override
///   Future<void> write(String key, String value) async =>
///       (await SharedPreferences.getInstance()).setString(key, value);
/// }
/// ```
abstract class VmStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Хранилище по умолчанию: живёт в памяти процесса. Годится для отладки и
/// тестов; после перезапуска приложения `instanceId` будет новым, поэтому в
/// продакшене подставьте постоянное хранилище.
class VmMemoryStorage implements VmStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }
}
