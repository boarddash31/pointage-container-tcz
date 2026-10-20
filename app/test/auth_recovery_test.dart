import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/main.dart';

void main() {
  testWidgets('password recovery asks for an email before contacting Auth', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pump();
    expect(find.text('Saisissez votre e-mail professionnel pour recevoir le lien.'),
        findsOneWidget);
  });
}
