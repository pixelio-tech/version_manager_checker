import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vm_checker_example/main.dart';

void main() {
  testWidgets('песочница открывается и показывает разделы', (tester) async {
    await tester.pumpWidget(const DemoApp());
    expect(find.text('Version Manager — песочница'), findsOneWidget);
    expect(find.text('Уведомления без сервера'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Баннер'), findsOneWidget);
  });
}
