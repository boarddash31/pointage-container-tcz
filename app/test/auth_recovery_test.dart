import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/main.dart';

void main() {
  testWidgets('profile shortcuts select the account and require its password', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    final emailField = find.widgetWithText(TextField, 'Username');
    final passwordField = find.widgetWithText(TextField, 'Mot de passe');
    expect(tester.widget<TextField>(passwordField).controller!.text,isEmpty);
    expect(tester.widget<TextField>(passwordField).obscureText,true);
    for(final profile in [
      ('Admin','boarddash31@gmail.com'),
      ('Entrée','boarddash31+tcz-entree@gmail.com'),
      ('Sortie','boarddash31+tcz-sortie@gmail.com'),
    ]) {
      await tester.ensureVisible(find.text(profile.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text(profile.$1));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(emailField).controller!.text,profile.$2);
      expect(tester.widget<TextField>(passwordField).controller!.text,isEmpty);
    }
  });

  testWidgets('saved admin session opens each selected destination without a password', (tester) async {
    String? opened;
    await tester.pumpWidget(MaterialApp(home:LoginScreen(
      sessionRoles:() async=>['admin'],onAuthenticated:(profile)=>opened=profile)));
    for(final label in ['Admin','Entrée','Sortie']) {
      opened=null;
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(opened,label);
      final passwordField=find.widgetWithText(TextField,'Mot de passe');
      expect(tester.widget<TextField>(passwordField).controller!.text,isEmpty);
    }
  });

  testWidgets('saved entry session cannot open Admin or Sortie', (tester) async {
    String? opened;
    await tester.pumpWidget(MaterialApp(home:LoginScreen(
      sessionRoles:() async=>['entree'],onAuthenticated:(profile)=>opened=profile)));
    for(final label in ['Admin','Sortie']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(opened,isNull);
      expect(find.text('Connectez le compte autorisé pour ce profil.'),findsOneWidget);
    }
    await tester.tap(find.text('Entrée'));
    await tester.pumpAndSettle();
    expect(opened,'Entrée');
  });

  testWidgets('failed session role verification never opens a destination', (tester) async {
    var opened=false;
    await tester.pumpWidget(MaterialApp(home:LoginScreen(
      sessionRoles:() async=>throw Exception('network unavailable'),
      onAuthenticated:(_)=>opened=true)));
    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    expect(opened,isFalse);
    expect(find.text('Session indisponible. Réessayez ou reconnectez-vous.'),findsOneWidget);
  });

  testWidgets('password recovery asks for an email before contacting Auth', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    final emailField = find.widgetWithText(TextField, 'Username');
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
