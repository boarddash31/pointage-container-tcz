import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/main.dart';

void main() {
  testWidgets('login starts blank and does not expose one-click credentials', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    final emailField = find.widgetWithText(TextField, 'Numéro de téléphone ou e-mail');
    final passwordField = find.widgetWithText(TextField, 'Mot de passe');
    expect(tester.widget<TextField>(emailField).controller!.text, isEmpty);
    expect(tester.widget<TextField>(passwordField).controller!.text, isEmpty);
    expect(find.text('Admin 1-clic'), findsNothing);
    expect(find.text('Entrée 1-clic'), findsNothing);
    expect(find.text('Sortie 1-clic'), findsNothing);
    expect(find.text('AdminTCZ2026!'), findsNothing);
    expect(find.text('dahhaknouamane@gmail.com'), findsNothing);
    expect(find.text('Télécharger l’APK Android'), findsNothing);
  });

  testWidgets('password recovery asks for an email before contacting Auth', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    final emailField = find.widgetWithText(TextField, 'Numéro de téléphone ou e-mail');
    await tester.enterText(emailField, '');
    await tester.ensureVisible(find.text('Mot de passe oublié ?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pump();
    expect(find.text('Saisissez votre e-mail professionnel pour recevoir le lien.'),
        findsOneWidget);
  });
}
