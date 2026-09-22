import 'package:flutter_test/flutter_test.dart';
import 'package:version_manager_v3_checker/version_manager_v3_checker.dart';

void main() {
  group('выбор перевода', () {
    test('пустая строка в нужной локали не побеждает непустую в другой', () {
      // Конструктор в админке заводит ключ на каждую локаль, даже незаполненную.
      expect(vmPickLocalized({'en': '', 'ru': 'Тест'}, 'en'), 'Тест');
    });

    test('заполненная локаль выбирается как есть', () {
      expect(vmPickLocalized({'en': 'Hi', 'ru': 'Привет'}, 'en'), 'Hi');
    });

    test('неизвестная локаль падает на любой непустой перевод', () {
      expect(vmPickLocalized({'de': 'Hallo'}, 'fr'), 'Hallo');
    });

    test('переводов нет совсем — пустая строка', () {
      expect(vmPickLocalized({'en': '', 'ru': '   '}, 'ru'), '');
    });

    test('блок текста использует тот же отбор', () {
      final block = NotificationBlock.fromJson({
        'type': 'text',
        'text': {'en': '', 'ru': 'Тест'},
      });
      expect((block as TextBlock).textFor('en'), 'Тест');
    });
  });
}
