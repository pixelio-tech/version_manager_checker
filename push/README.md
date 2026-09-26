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

## Проверка

В админке «Рассылки → Тест на устройство»: `instanceId` установки
(`vm.instanceId`) и сообщение — уйдёт сразу на одно устройство. Ответ FCM
показывается там же.

Без `VmPush` токен можно передать и самому: `vm.setPushToken(token)`,
а открытие — `vm.pushOpened(message.data)`.
