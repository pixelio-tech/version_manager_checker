# version_manager_v3_checker

Клиент Version Manager v3 для Flutter-приложений: проверяет версию, закрывает
приложение экраном обязательного обновления и рисует внутриигровые уведомления
ровно так, как их собрали в конструкторе админки.

Три слоя — берите тот, который нужен:

| Слой | Что делает |
| --- | --- |
| `VersionManager` | Фасад: помнит ключ и параметры сборки, держит `instanceId` и ETag, ходит на сервер, показывает уведомления. |
| `VmV3Client` | Голый HTTP к `check-version` и `notification-event`: таймаут, повторы, ETag. |
| `VmUpdateGate`, `presentVmNotification` | Экран обновления и отрисовка одного уведомления. |

## Быстрый старт

```dart
await VersionManager.init(
  baseUrl: 'https://api.example.com',
  apiKey: 'vm_live_…',          // ключ приложения из админки
  namespace: 'com.example.app',  // bundle id
  version: '1.2.0',
  buildNumber: 42,
  platform: 'ios',               // ios | android | web
  storage: PrefsStorage(),       // см. «Хранилище»
);

final outcome = await VersionManager.instance.check();
final result = outcome.result;   // null — спросить не удалось и кэша нет
```

**Проверка версии не может сломать приложение.** `check()` не бросает никогда:
недоступный сервер, отозванный ключ, таймаут — всё это `VmUnavailable`, и
приложение продолжает работать так же, как до вызова. Оборачивать вызов в
`try` не нужно.

| Исход | Когда |
| --- | --- |
| `VmFresh` | сервер ответил новым конфигом |
| `VmUnchanged` | сервер ответил `304`: конфиг актуален, в `result` — прежний |
| `VmUnavailable` | спросить не вышло; в `result` — сохранённый конфиг, пока он не просрочен |

```dart
switch (outcome) {
  case VmFresh(:final result) when result.isBlocked:
    // показать экран блокировки
  case VmUnavailable(:final cause):
    // можно молча игнорировать: пакет уже записал это в лог
  default:
}
```

### Сколько живёт сохранённый конфиг

Ответ сервера сохраняется и переживает перезапуск приложения. Свежий ответ
всегда важнее: кэш подставляется только когда сервер не ответил.

```dart
await VersionManager.init(
  // …
  cacheTtl: const Duration(days: 3),  // по умолчанию 7 дней
  budget: const Duration(seconds: 5), // потолок на всю проверку с повторами
);
```

`cacheTtl: Duration.zero` выключает кэш: нет свежего ответа — нет ограничений.
Срок нужен с двух сторон: лежащий неделями сервер не должен держать людей
заблокированными, а выключенная сеть не должна снимать блокировку мгновенно.

`budget` ограничивает всю проверку целиком, вместе с повторами. Без него три
попытки по десять секунд держат `await check()` полминуты — формально ошибки
нет, а приложение всё это время не запускается.

Дальше — два сценария, обычно оба сразу.

### Обязательное обновление

```dart
VmUpdateGate(
  result: result,
  platform: 'ios',
  onOpenStore: (link) => launchUrlString(link.url),
  child: const HomeScreen(),
)
```

Гейт закрывает приложение, когда сервер вернул `status: blocked`/`isBlocked`
или `updatePriority: forced|required`. Текст берётся из `blockReason` и
`message`, ссылка — из `recommendedVersion.storeLinks` под платформу
установки. Открывает ссылку приложение (`url_launcher` и подобное) — пакет
намеренно не тянет эту зависимость.

### Уведомления

```dart
await VersionManager.instance.presentAll(
  context,
  onAction: (kind, value) {
    switch (kind) {
      case 'url':
        launchUrlString(value!);
      case 'deeplink':
        router.go(value!);
      case 'store':
        launchUrlString(storeUrl);
      case 'dismiss':
        break;
    }
  },
  onLocalPush: (p) => showLocalPush(p), // см. «Локальные пуши» ниже
  onSilent: (payload) => handleSilently(payload),
);
```

`presentAll` показывает всё, что пришло, и сам шлёт события воронки
(`shown` / `clicked` / `dismissed`) — в админке это графики CTR. Нужен
контроль над конкретным уведомлением — зовите `presentVmNotification`.

> **Контекст должен быть ниже `Navigator`.** Баннеры и шторки рисуются через
> `Overlay`, который создаётся внутри `Navigator`. Из `builder` у `MaterialApp`
> вызов упадёт с `No Overlay widget found` — оттуда доступен только
> `VmUpdateGate` (он просто подменяет виджет). Для показа уведомлений положите
> точку подписки на любой экран приложения.

### Локальные пуши (`localPush`)

Системное уведомление пакет не рисует сам и **не тянет**
`flutter_local_notifications` в зависимости: у плагина есть нативная часть
(манифест, разрешения, entitlements), и приложения, которые `localPush` не
используют, платили бы за неё впустую. Уведомление такого типа приходит в
`onLocalPush` — ставьте плагин у себя и показывайте:

```dart
// pubspec.yaml приложения: flutter_local_notifications: ^18.0.1
final push = FlutterLocalNotificationsPlugin();
await push.initialize(
  const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  ),
);
await push
    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
    ?.requestNotificationsPermission();

// ...
await VersionManager.instance.presentAll(
  context,
  onAction: ...,
  onLocalPush: (p) => push.show(
    p.id.hashCode,
    p.title,
    p.body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'vm_notifications',
        'Notifications',
        importance: Importance.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
    payload: p.id,
  ),
);
```

`style.icon` и `style.buttons` при желании раскладываются на иконку и
actions плагина — payload отдаётся целиком.

### Периодическая проверка

```dart
VersionManager.instance.startPolling(
  minInterval: const Duration(minutes: 5),
  onError: (e) => debugPrint('$e'),
);
// ...
VersionManager.instance.stopPolling();
```

Интервал берётся из `nextCheckInterval` ответа, `minInterval` — нижняя
граница. Новый конфиг приходит и в поток `VersionManager.instance.results`.

## Хранилище

**Без него статистика приложения врёт.** `instanceId` — то, по чему сервер
считает установки; если он новый на каждый запуск, каждый старт выглядит как
новая установка, а частотные ограничения показов считаются заново, и человек
видит одно и то же сообщение снова. Пакет ругается в лог при `init()` без
хранилища, но починить это за вас не может.


Пакету нужно помнить `instanceId` (по нему сервер считает частоту показов) и
ETag последнего конфига. Зависимость на `shared_preferences` не навязывается —
передайте свою реализацию:

```dart
class PrefsStorage implements VmStorage {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}
```

Без неё используется память процесса: после перезапуска `instanceId` будет
новым и лимиты показов начнут считаться заново.

## Что рисует пакет

`banner`, `modal` (в том числе на весь экран) и `bottomSheet` — целиком, по
дереву блоков из конструктора: текст (гарнитура, регистр, курсив,
межбуквенное, обрезка строк), картинка (ширина, соотношение, прозрачность,
затемнение, «край в край»), иконка, кнопки (свои цвета, символ, ширина,
промежуток), разделитель (сплошной и пунктир), отступ (в том числе
растяжимый), ряды и колонки с переносом. Плюс оформление карточки: поля по
сторонам, скругление по углам, тень, отступ от краёв экрана, максимальная
ширина, крестик, ручка шторки, длительность и кривая появления.

`localPush` — не карточка в дереве блоков, а системное уведомление; см.
«Локальные пуши» выше. `silent` не рисуется по определению — приходит в
`onSilent`.

Частоту показов (`maxImpressions`, `minIntervalHours`) считает сервер, на
клиенте дублировать её не нужно.

## Ошибки

* `VmApiException` — сервер ответил 4xx/5xx (`statusCode`, `body`).
* `VmNetworkException` — до сервера не достучались: нет сети, таймаут.

Клиент сам повторяет запрос на сетевых сбоях и 5xx (по умолчанию две
дополнительные попытки с нарастающей паузой), таймаут — 10 секунд. И то и
другое настраивается в `VersionManager.init`.

## Песочница

```bash
cd example
flutter run
```

В ней: все типы уведомлений без сервера (включая «картинку край в край»),
экран блокировки и обязательного обновления, живой запрос к
`check-version` с вводом адреса и ключа, журнал событий воронки.

## Тесты

```bash
flutter test
```

Покрыты клиент (ключ, ETag/304, 4xx, повторы, сетевые сбои), фасад
(`instanceId`, ETag, поток результатов), гейт обновления и отрисовка
(баннер, модалка, шторка, ручка, локали, «край в край»).

## Диагностика

Пакет ничего не печатает сам: библиотека, пишущая в чужой вывод, — плохая
библиотека. Вместо этого он отдаёт события, а вы решаете, куда их девать.

```dart
await VersionManager.init(
  baseUrl: 'https://vm-api.pixelio.tech',
  apiKey: 'vm_live_...',
  namespace: 'com.example.app',
  version: '1.2.0',
  buildNumber: 42,
  platform: 'ios',
  onLog: (e) {
    // В отладке — в консоль; в релизе можно слать в Crashlytics/Sentry.
    if (e.level == VmLogLevel.error) {
      FirebaseCrashlytics.instance.recordError(e.error ?? e.message, e.stackTrace);
    }
    debugPrint('[vm] ${e.level.name} ${e.message} ${e.data}');
  },
);
```

Что видно через этот канал:

| Событие | Уровень |
| --- | --- |
| инициализация, результат проверки, старт поллинга | `info` |
| повтор запроса с причиной и задержкой, `304`, расписание следующей проверки | `debug` |
| событие воронки не дошло | `warning` |
| попытки исчерпаны, сбой хранилища, отказ запланированной проверки | `error` |

В записи не попадают ключ приложения и тексты уведомлений: первое секрет,
второе адресовано пользователю. Исключение внутри вашего приёмника гасится —
чужой логгер не должен ломать проверку версии.

