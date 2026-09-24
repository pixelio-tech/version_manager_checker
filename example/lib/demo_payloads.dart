import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

/// Демо-данные ровно того вида, что присылает сервер: с ними песочницу можно
/// щупать без бэкенда, а заодно видно, что дерево блоков из конструктора
/// рисуется один в один.
Map<String, dynamic> _style({
  required List<Map<String, dynamic>> blocks,
  int cornerRadius = 16,
  String position = 'top',
  bool closeButton = false,
  Map<String, dynamic>? extra,
}) => {
  'cornerRadius': cornerRadius,
  'position': position,
  'padding': 16,
  'gap': 12,
  'closeButton': closeButton,
  'colors': {'background': '#141821', 'surface': '#1c212c', 'text': '#f4f6f8', 'accent': '#5b8cff'},
  'icon': {'source': 'app', 'size': 32, 'shape': 'squircle'},
  // Ограничение ширины: на планшете и в вебе карточка иначе расползается.
  'maxWidth': 420,
  'blocks': blocks,
  ...?extra,
};

Map<String, dynamic> _text(String text, {int size = 15, int weight = 700, Map<String, dynamic>? box}) => {
  'id': 't${text.hashCode}',
  'type': 'text',
  'text': {'ru': text},
  'size': size,
  'weight': weight,
  'align': 'left',
  'opacity': 1,
  'lineHeight': 1.35,
  'box': ?box,
};

const _imageUrl =
    // PNG в data-URI: Flutter умеет PNG из коробки, SVG потребовал бы
    // отдельный пакет — демо не должно тянуть зависимости.
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAPAAAABgCAIAAACsUWiGAAAC90lEQVR42u3d904UURTAYZ8GGzZs2LBhW3rvZYFdioCAgICAgIC+nk+kk3BzGSUY0KCw8yW/R/j+mOSec+Zc2ddc2ZfQ+dhu7sJuTexi0k7o0k5taLv2cqry7bryz6Ersa26q1v1sWtJm6Hrmw2hjYYbqSo2Gis+hW7G1htvrTfFbiethe6sNYdWm++mqlxtqfwYuhdbabm/0hp7kLQcerjcFlpqe5Sqaqm96kPocWyx/cliR+xp0kLo2UJnaL7zearq+a7q96EXsbmul3PdsVdJs6HXsz2hmZ43qXIzvbl3oZrYdG/tdF+sLmkqVD/VH5rsb0jVODnQ+DbUFJsYaJ4YjLUkjYdax/OhsXxbqvaxofbRUEesONRZHI51JRVC3YWR0MhIT6rekULvcKgvNlToHyrGBpLyocH8aGhwNJ/qHNBAAw000EADDTTQQAMNNNBAAw000EADDTTQQAMNNNBAAw000EADDTTQQAMNNNBAAw000EADDTTQQAMNNNBAAw000EADDTTQQAMNNNBAAw000EADDTTQQAMNNNBAAw000EADDTTQQAMNNNBHBP39W/HoAQ30qQB9LLV/FtBAnyDofyD49wEN9N+C/u+IDwtooI8B+tQ6PhjQQB8K+gw5PhjQQO+DPtOUD7IGOrugS4ZyOqAzCrokNQfTQGcKdAlT/oU10KUPOiOa9wK6xEFnSvNPpoEuPdAZ1LxvGugSA51ZzcE00EADDTTQQAN98qAzrnkvoIEGGmiggQbaN7RvaKCBBhpooIH2UuilEGizHGY5gDZtZ9oOaPPQ5qFtrNhYAdpOoZ1CoG192/oG2l0OdzmAdjkJaKDdtgPa9VHXR4F2H9p9aKBd8AcaaP9YARpooIEGGmiggQYaaKCBBhpooIEGGmiggQYaaKCBBhpooIEGGmiggQYaaKCBBhpooIEGGmiggQYaaKCBBhpooIEGGmiggQYaaKCBBhpooIEGGmiggQYaaKCBBhpooIEGGmiggQYa6L1+AJidHS9V2nizAAAAAElFTkSuQmCC';

Map<String, dynamic> _image({bool bleed = false, int height = 140}) => {
  'id': 'img',
  'type': 'image',
  'url': _imageUrl,
  'height': height,
  'fit': 'cover',
  'radius': bleed ? 0 : 10,
  if (bleed) 'box': {'bleed': true},
};

Map<String, dynamic> _buttons(List<Map<String, dynamic>> buttons) => {
  'id': 'btns',
  'type': 'buttons',
  'layout': 'row',
  'shape': {'radius': 10, 'height': 38, 'fullWidth': true},
  'buttons': buttons,
};

Map<String, dynamic> _button(String label, String kind, {String? value, String style = 'primary', String? icon}) => {
  'id': 'b$label',
  'label': {'ru': label},
  'style': style,
  'icon': ?icon,
  'action': {'kind': kind, 'value': ?value},
};

/// Набор сценариев для песочницы: по одному на каждый тип поверхности плюс
/// проверка «картинка край в край».
final demoNotifications = <String, NotificationPayload>{
  'Баннер': NotificationPayload.fromJson({
    'id': 'demo-banner',
    'type': 'banner',
    'title': 'Доступно обновление',
    'body': 'В новой версии — исправления и ускорение работы.',
    'action': {'kind': 'dismiss'},
    'style': _style(
      closeButton: true,
      blocks: [
        _text('Доступно обновление 4.2'),
        _text('Мы починили синхронизацию и ускорили загрузку ленты.', size: 13, weight: 400),
        _buttons([_button('Обновить', 'store', icon: '↑'), _button('Позже', 'dismiss', style: 'text')]),
      ],
    ),
  }),
  'Баннер снизу': NotificationPayload.fromJson({
    'id': 'demo-banner-bottom',
    'type': 'banner',
    'title': 'Напоминание',
    'body': '短 текст снизу экрана.',
    'action': {'kind': 'dismiss'},
    'style': _style(
      position: 'bottom',
      cornerRadius: 24,
      blocks: [
        _text('Не забудьте про обновление', size: 14),
        _buttons([_button('Ок', 'dismiss')]),
      ],
    ),
  }),
  'Модалка': NotificationPayload.fromJson({
    'id': 'demo-modal',
    'type': 'modal',
    'title': 'Технические работы',
    'body': 'Сервис недоступен до 14:00.',
    'action': {'kind': 'dismiss'},
    'style': _style(
      cornerRadius: 20,
      closeButton: true,
      blocks: [
        _image(),
        _text('Технические работы'),
        _text('Сервис недоступен до 14:00 по московскому времени.', size: 13, weight: 400),
        _buttons([_button('Понятно', 'dismiss')]),
      ],
    ),
  }),
  'Шторка': NotificationPayload.fromJson({
    'id': 'demo-sheet',
    'type': 'bottomSheet',
    'title': 'Что нового',
    'body': 'Список изменений.',
    'action': {'kind': 'dismiss'},
    'style': _style(
      cornerRadius: 22,
      blocks: [
        _text('Что нового в 4.2'),
        _text('• Быстрее лента\n• Починили синхронизацию\n• Мелкие правки', size: 13, weight: 400),
        _buttons([_button('Отлично', 'dismiss')]),
      ],
    ),
  }),
  'Шторка: картинка край в край': NotificationPayload.fromJson({
    'id': 'demo-sheet-bleed',
    'type': 'bottomSheet',
    'title': 'Летнее обновление',
    'body': 'Картинка занимает верх карточки целиком.',
    'action': {'kind': 'dismiss'},
    'style': _style(
      cornerRadius: 24,
      extra: {'sheetHandle': true, 'handleColor': '#ffffff55'},
      blocks: [
        _image(bleed: true, height: 160),
        _text('Летнее обновление'),
        _text('Картинка идёт до краёв карточки — поля ей не применяются.', size: 13, weight: 400),
        _buttons([_button('Смотреть', 'url', value: 'https://example.com'), _button('Позже', 'dismiss', style: 'secondary')]),
      ],
    ),
  }),
  'Локальный push': NotificationPayload.fromJson({
    'id': 'demo-push',
    'type': 'localPush',
    'title': 'Обновите приложение',
    'body': 'Это уведомление рисует операционная система.',
    'action': {'kind': 'store'},
    'style': _style(blocks: []),
  }),
};

/// Ответ `check-version` для проверки экрана блокировки без сервера.
CheckResult demoBlockedResult({required bool blocked}) => CheckResult.fromJson({
  'status': blocked ? 'blocked' : 'update_available',
  'isBlocked': blocked,
  'blockReason': blocked ? 'Версия 1.0.0 больше не поддерживается.' : null,
  'updatePriority': blocked ? 'forced' : 'recommended',
  'recommendedVersion': {
    'versionNumber': '4.2.0',
    'buildNumber': 420,
    'changelog': 'Быстрее лента, починили синхронизацию.',
    'frequency': 'once',
    'storeLinks': [
      {'platform': 'ios', 'storeName': 'App Store', 'url': 'https://apps.apple.com/app/id0000000000'},
      {'platform': 'android', 'storeName': 'Google Play', 'url': 'https://play.google.com/store/apps/details?id=com.example'},
    ],
  },
  'notifications': const <Map<String, dynamic>>[],
  'nextCheckInterval': 3600,
  'configHash': 'demo-hash',
  'message': 'Обновите приложение, чтобы продолжить.',
  'serverTimestamp': DateTime.now().toIso8601String(),
});
