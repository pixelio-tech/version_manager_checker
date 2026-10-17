import 'package:shared_preferences/shared_preferences.dart';

/// Хранилище пары «ключ — строка»: пакету нужно помнить `instanceId` между
/// запусками и ETag последнего конфига.
///
/// Готовое постоянное хранилище — [VmPrefsStorage], оно же стоит по
/// умолчанию в `VersionManager.init`. Свою реализацию (зашифрованное
/// хранилище, Hive, общий с приложением слой) передайте через `storage:`.
abstract class VmStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Постоянное хранилище поверх `shared_preferences` — хранилище по умолчанию.
///
/// Ключи те же, что у `PrefsStorage` из прежнего README, и лежат там же
/// (`SharedPreferences.getInstance`), поэтому переход со своей копии на этот
/// класс сохраняет `instanceId` и кэш конфига.
class VmPrefsStorage implements VmStorage {
  const VmPrefsStorage();

  @override
  Future<String?> read(String key) async => (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}

/// Хранилище в памяти процесса. Годится для отладки и тестов; после
/// перезапуска приложения `instanceId` будет новым, поэтому в продакшене
/// оставьте [VmPrefsStorage] или подставьте своё постоянное хранилище.
class VmMemoryStorage implements VmStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }
}
