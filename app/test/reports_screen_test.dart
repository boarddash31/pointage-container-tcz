import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pointage_container/data/reports_api.dart';
import 'package:pointage_container/ui/reports_screen.dart';

class ReportFixture extends ReportsApi {
  ReportFixture() : super(SupabaseClient('https://example.supabase.co', 'test-public', authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final writes = <Map<String, dynamic>>[];
  @override
  Future<dynamic> json(String method, String route, [Object? body]) async {
    if (method != 'GET') { writes.add({'route': route, 'body': body}); return {}; }
    if (route == 'clients') return <Map<String, dynamic>>[{'id': 'client-a', 'name': 'Client métier A'}];
    if (route == 'operators') return <Map<String, dynamic>>[{'id': 'MSC', 'name': 'MSC'}, {'id': 'CMACGM', 'name': 'CMA CGM'}];
    return {
      'smtp': {'version': 0, 'host': '', 'port': 587, 'from': '', 'security': 'starttls', 'username': '', 'has_password': false},
      'ready': {'source': false, 'smtp': false, 'smtp_driver': false}, 'jobs': [], 'runs': [],
    };
  }
}

void main() {
  testWidgets('SMTP can be entered later in the application without exposing a saved password', (tester) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ReportFixture();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReportsScreen(api: api))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuration e-mail')); await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'smtp.example.invalid');
    await tester.enterText(fields.at(1), '587');
    await tester.enterText(fields.at(2), 'zenata@example.invalid');
    await tester.tap(find.text('Enregistrer')); await tester.pumpAndSettle();
    expect(api.writes.single['route'], 'smtp');
    expect((api.writes.single['body'] as Map)['host'], 'smtp.example.invalid');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('new report supports Morocco schedules and business-client filters while sends are disabled', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ReportFixture();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReportsScreen(api: api))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouveau rapport')); await tester.pumpAndSettle();
    expect(find.text('Heure Maroc (HH:mm)'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), 'metier@example.invalid');
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1)); await tester.pumpAndSettle();
    await tester.tap(find.text('MSC · MSC').last); await tester.pumpAndSettle();
    final period = find.byType(DropdownButtonFormField<String>).at(3);
    await tester.ensureVisible(period); await tester.tap(period); await tester.pumpAndSettle();
    await tester.tap(find.text('Dernier shift terminé').last); await tester.pumpAndSettle();
    final start = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Début du shift Maroc (HH:mm)');
    final end = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Fin du shift Maroc (HH:mm)');
    await tester.ensureVisible(start); await tester.enterText(start, '22:00');
    await tester.ensureVisible(end); await tester.enterText(end, '06:00');
    await tester.ensureVisible(find.byType(CheckboxListTile).first);
    await tester.tap(find.byType(CheckboxListTile).first); await tester.pumpAndSettle();
    expect(find.text('Client métier A'), findsOneWidget);
    await tester.ensureVisible(find.text('Client métier A'));
    await tester.tap(find.text('Client métier A')); await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer')); await tester.pumpAndSettle();
    final body = api.writes.single['body'] as Map, job = body['job'] as Map;
    expect(job['enabled'], false);
    expect(job['line_id'], 'MSC');
    expect(job['layout'], 'shift_client');
    expect(job['period'], 'shift');
    expect(job['shift_start'], '22:00');
    expect(job['shift_end'], '06:00');
    expect(job['client_ids'], ['client-a']);
    expect((job['schedule'] as Map)['timezone'], 'Africa/Casablanca');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
