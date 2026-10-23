import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/main.dart';

void main() {
  testWidgets('quick role buttons select an account but never fill its password', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    final emailField = find.widgetWithText(TextField, 'Numéro de téléphone ou e-mail');
    final passwordField = find.widgetWithText(TextField, 'Mot de passe');
    expect(tester.widget<TextField>(emailField).controller!.text, isEmpty);
    expect(tester.widget<TextField>(passwordField).controller!.text, isEmpty);
    for (final profile in [
      ('admin', 'dahhaknouamane@gmail.com'),
      ('entrée', 'dahhaknouamane+tcz-entree@gmail.com'),
      ('sortie', 'dahhaknouamane+tcz-sortie@gmail.com'),
    ]) {
      await tester.tap(find.byKey(ValueKey('quick-profile-${profile.$1}')));
      await tester.pump();
      expect(tester.widget<TextField>(emailField).controller!.text, profile.$2);
      expect(tester.widget<TextField>(passwordField).controller!.text, isEmpty);
    }
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
