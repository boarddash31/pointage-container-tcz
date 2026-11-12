import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pointage_container/data/pointage_repository.dart';
import 'package:pointage_container/main.dart';

class AdminFixture extends PointageRepository {
  AdminFixture(super.client);
  @override Future<List<String>> roles() async => ['admin'];
  @override Future<List<TruckVisit>> visits({bool insideOnly = true}) async => [];
  @override Future<List<Map<String, dynamic>>> forcedActions() async => [];
}

void main() {
  for (final phone in ['', '0612345678']) {
  testWidgets('phone=$phone: saved Admin opens production administration and creates an assigned account in the web form', (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? submitted;
    final client = SupabaseClient('https://example.supabase.co', 'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/rpc/admin_save_username_account')) {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'username': 'karim.test', 'full_name': 'Karim Test', 'phone': phone, 'role': 'sortie'}), 200,
            request: request, headers: {'content-type': 'application/json'});
        }
        return http.Response('[]', 200, request: request, headers: {'content-type': 'application/json'});
      }));

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: PointageShell(repository: AdminFixture(client), initialDestination: 'Auto')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.runAsync(() async { await tester.pump(); await Future<void>.delayed(const Duration(milliseconds: 200)); });
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Administration · TCZ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin-create-profile')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.widgetWithText(TextField, 'Username *'), 'karim.test');
    await tester.enterText(find.widgetWithText(TextField, 'Prénom *'), 'Karim');
    await tester.enterText(find.widgetWithText(TextField, 'Nom *'), 'Test');
    await tester.enterText(find.widgetWithText(TextField, 'Téléphone (optionnel)'), phone);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('AGENT SORTIE (Gate-Out)').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.runAsync(() async { await tester.pump(); await Future<void>.delayed(const Duration(milliseconds: 200)); });
    await tester.pump(const Duration(milliseconds: 500));
    expect(submitted?['p_role'], 'sortie');
    expect(submitted?['p_phone'], phone);
    expect(submitted?['p_username'], 'karim.test');
    expect(submitted?['p_admin_code'], isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Collaborateur enregistré !'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  }
}
