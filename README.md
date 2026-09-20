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

final result = await VersionManager.instance.check();
```

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
  onLocalPush: (payload) => scheduleLocalNotification(payload),
  onSilent: (payload) => handleSilently(payload),
);
```

`presentAll` показывает всё, что пришло, и сам шлёт события воронки
(`shown` / `clicked` / `dismissed`) — в админке это графики CTR. Нужен
контроль над конкретным уведомлением — зовите `presentVmNotification`.

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

`localPush` не рисуется: настоящее системное уведомление требует плагина
вроде `flutter_local_notifications`. Подпишитесь на `onLocalPush` и
запланируйте его сами. `silent` не рисуется по определению — приходит в
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
