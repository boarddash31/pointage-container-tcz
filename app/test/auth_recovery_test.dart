import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/main.dart';

void main() {
  testWidgets('neutral login has no preset account or role shortcuts', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    final identifier = find.widgetWithText(TextField, 'Identifiant');
    final password = find.widgetWithText(TextField, 'Mot de passe');
    expect(tester.widget<TextField>(identifier).controller!.text,isEmpty);
    expect(tester.widget<TextField>(password).controller!.text,isEmpty);
    expect(tester.widget<TextField>(password).obscureText,true);
    expect(find.text('Gestion des flux'),findsOneWidget);
    expect(find.text('Accès rapide'),findsNothing);
    expect(find.byType(ChoiceChip),findsNothing);
  });

  testWidgets('password recovery asks for an email before contacting Auth', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    final emailField = find.widgetWithText(TextField, 'Identifiant');
    await tester.enterText(emailField, '');
    await tester.ensureVisible(find.text('Mot de passe oublié ?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pump();
    expect(find.text('Saisissez votre adresse e-mail pour recevoir le lien.'),
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
