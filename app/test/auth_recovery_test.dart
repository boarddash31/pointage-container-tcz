import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/main.dart';

void main() {
  testWidgets('profile shortcuts select the account and require its password', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    final emailField = find.widgetWithText(TextField, 'Numéro de téléphone ou e-mail');
    final passwordField = find.widgetWithText(TextField, 'Mot de passe');
    expect(tester.widget<TextField>(passwordField).controller!.text,isEmpty);
    expect(tester.widget<TextField>(passwordField).obscureText,true);
    for(final profile in [
      ('Admin','dahhaknouamane@gmail.com'),
      ('Entrée','dahhaknouamane+tcz-entree@gmail.com'),
      ('Sortie','dahhaknouamane+tcz-sortie@gmail.com'),
    ]) {
      await tester.ensureVisible(find.text(profile.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text(profile.$1));
      await tester.pump();
      expect(tester.widget<TextField>(emailField).controller!.text,profile.$2);
      expect(tester.widget<TextField>(passwordField).controller!.text,isEmpty);
    }
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

  testWidgets('public login has no password disclosure or automatic test sign-in', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Mot de passe test :'), findsNothing);
    expect(find.text('Admin 1-clic'), findsNothing);
    expect(find.text('Entrée 1-clic'), findsNothing);
    expect(find.text('Sortie 1-clic'), findsNothing);
  });
}
