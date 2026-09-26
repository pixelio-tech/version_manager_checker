/// Важность канала уведомлений Android: как громко система показывает
/// уведомления канала.
enum VmPushImportance {
  /// Только в шторке, свёрнутым, без значка в строке состояния.
  min,

  /// В шторке, без звука и без баннера.
  low,

  /// В шторке со звуком, без баннера поверх экрана.
  normal,

  /// Со звуком и баннером поверх экрана. Для большинства рассылок.
  high;

  /// Значение для сервера (`min`/`low`/`default`/`high`).
  String get wire => this == normal ? 'default' : name;
}

/// Канал уведомлений Android (back#84).
///
/// С Android 8 каждое уведомление идёт через канал. У канала имя и важность,
/// и человек выключает каналы по отдельности в настройках приложения —
/// например, «Акции», не трогая «Важное». Каналы заводит разработчик, SDK
/// создаёт их на устройстве и сообщает серверу: в админке из них выбирается
/// канал рассылки. На iOS каналов нет — там поля ни на что не влияют.
class VmPushChannel {
  /// Постоянный id: по нему рассылка находит канал. Латиница, цифры, `_ . -`,
  /// до 64 символов. Менять нельзя — Android считает канал с новым id другим
  /// каналом, а настройки человека остаются у старого.
  final String id;

  /// Имя в настройках приложения — видит пользователь.
  final String name;

  /// Пояснение под именем в настройках.
  final String? description;

  /// Важность. Android запоминает её при создании канала: поменять важность
  /// уже созданного канала может только сам человек в настройках.
  final VmPushImportance importance;

  const VmPushChannel(this.id, this.name, {this.description, this.importance = VmPushImportance.high});

  static final _idPattern = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');

  /// Канал, который сервер примет: id по шаблону, имя от 1 до 100 символов.
  bool get isValid => _idPattern.hasMatch(id) && name.trim().isNotEmpty && name.length <= 100;

  Map<String, Object?> toJson({bool isDefault = false}) => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'importance': importance.wire,
    'isDefault': isDefault,
  };
}
