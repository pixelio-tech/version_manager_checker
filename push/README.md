# version_manager_v3_push

Remote push для Version Manager v3 через Firebase Cloud Messaging. Рассылка из
админки («Уведомления → Рассылки») доходит и до закрытого приложения: сервер
отправляет её в FCM, система показывает уведомление сама.

Отдельный пакет, чтобы приложения без пушей не тянули `firebase_messaging`.

## Подключение

1. **Firebase.** Создайте проект в консоли Firebase, добавьте в него приложения
   iOS и Android, положите `GoogleService-Info.plist` и `google-services.json`
   (или `flutterfire configure`).
2. **iOS.** В Xcode: capability *Push Notifications* и *Background Modes →
   Remote notifications*. В консоли Firebase → Project settings → Cloud
   Messaging загрузите **APNs Authentication Key** (.p8). Без него iOS-пуши
   отклоняются: в рассылке это будет «APNs не принял сообщение».
3. **Ключ для сервера.** Firebase → Project settings → Service accounts →
   Generate new private key. JSON загрузите в админке: настройки приложения →
   «Push-уведомления».
4. **Код.**

```yaml
dependencies:
  version_manager_v3_checker: ...
  version_manager_v3_push:
    git:
      url: https://github.com/pixelio-tech/version_manager_checker
      path: push
```

```dart
await Firebase.initializeApp();
final vm = await VersionManager.init(...);

await VmPush.start(vm, onOpen: (open) {
  // Действие сообщения из админки.
  switch (open.action['kind']) {
    case 'url':
      launchUrl(Uri.parse(open.action['url'] as String));
    case 'deeplink':
      router.go(open.action['deeplink'] as String);
  }
});
```

`VmPush.start`:

- запрашивает разрешение (iOS, Android 13+); отказ — токен снимается с сервера;
- передаёт токен серверу (`POST /api/mobile/v2/push-token`) и повторяет при
  `onTokenRefresh`; пока токен, сборка и язык те же, в сеть не ходит;
- отмечает открытие пуша рассылки (`POST /push-opened`) — в админке это
  «открыли» — и зовёт `onOpen` с действием, в том числе для пуша, которым
  приложение запустили.

`VmPush.stop(vm)` — выход из аккаунта или выключатель в настройках: токен
снимается с сервера и удаляется в Firebase.

`start` возвращает `VmPushStatus`: `registered` — сервер знает токен,
`pending` — сервер недоступен или FCM ещё не выдал токен (SDK повторит сам),
`denied` — человек запретил уведомления, `rejected` — сервер отказал.

## Android: сборка

Пакет показывает уведомления через `flutter_local_notifications`, а тот
требует desugaring. В `android/app/build.gradle.kts`:

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

## Каналы Android

С Android 8 каждое уведомление идёт через канал. У канала имя и важность, и
человек выключает каналы по отдельности в настройках приложения — например,
«Акции», не трогая «Важное». Без своего канала FCM кладёт уведомления в
запасной «Miscellaneous» с обычной важностью: без баннера поверх экрана.

```dart
await VmPush.start(
  vm,
  channels: const [
    VmPushChannel('important', 'Важное'),                       // баннер и звук
    VmPushChannel('promo', 'Акции',
        description: 'Скидки и предложения',
        importance: VmPushImportance.low),                     // тихо, в шторке
  ],
  defaultChannel: 'important',
);
```

- Каналы уходят серверу вместе с токеном; в админке у рассылки поле
  «Канал (Android)». Рассылка без выбранного канала — в `defaultChannel`
  (по умолчанию первый).
- Не передали каналов — SDK заводит один свой: `vm_default`, «Уведомления».
- `id` канала не меняйте: Android считает канал с новым id другим каналом,
  а настройки, которые человек выставил старому, пропадут. Важность Android
  запоминает при создании канала — поменять её потом может только человек.
- На iOS каналов нет, параметры ни на что не влияют.

## Пока приложение открыто

По умолчанию рассылка показывается и при открытом приложении: на iOS — самой
системой, на Android — локальным уведомлением в канале рассылки; тап по нему
отмечает открытие и зовёт `onOpen`, как тап по обычному пушу.
`showInForeground: false` — не показывать; сообщение всё равно придёт в
`onMessage`.

Если приложение само пользуется `flutter_local_notifications`: у плагина
**один** обработчик тапов на всё приложение, и SDK не должен его перехватить.
Инициализируйте плагин сами и отдавайте тапы SDK:

```dart
final local = FlutterLocalNotificationsPlugin();
await local.initialize(
  settings: settings,
  onDidReceiveNotificationResponse: (r) async {
    if (await VmPush.handleLocalNotificationTap(r)) return; // рассылка VM
    // свои уведомления
  },
);
await VmPush.start(vm, localNotifications: local, initializeLocalNotifications: false);
```

## В фоне

Без фонового обработчика Firebase не доносит сообщение до Dart, пока
приложение свёрнуто или выгружено. По умолчанию SDK регистрирует свой
(`vmPushBackgroundHandler`). Firebase держит **один** обработчик на
приложение, поэтому:

- есть своя логика — передайте функцию в `onBackgroundMessage` (top-level или
  static, с `@pragma('vm:entry-point')`), SDK зарегистрирует её вместо своей;
- приложение регистрирует обработчик само (например, для своих пушей) —
  `handleBackground: false`, иначе SDK его заменит.

## Проверка

В админке «Рассылки → Тест на устройство»: `instanceId` установки
(`vm.instanceId`) и сообщение — уйдёт сразу на одно устройство. Ответ FCM
показывается там же.

Без `VmPush` токен можно передать и самому: `vm.setPushToken(token)`,
а открытие — `vm.pushOpened(message.data)`.
