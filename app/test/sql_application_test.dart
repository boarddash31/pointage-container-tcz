import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointage_container/data/sqlserver_api.dart';
import 'package:pointage_container/data/pointage_repository.dart';
import 'package:pointage_container/main.dart';
import 'package:pointage_container/ui/admin_screen.dart';

const actor = '11111111-1111-4111-8111-111111111111';
const visit = '22222222-2222-4222-8222-222222222222';
const item = '33333333-3333-4333-8333-333333333333';
const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Map<String, dynamic> row(int version) => {
  'id': visit,
  'version': version,
  'plate': '12345-A-06',
  'driver_cin': 'BK12365',
  'entry_kind': 'empty',
  'iso_code': '22G1',
  'armateur_id': 'MSC',
  'entered_at': '2026-11-21T10:00:00Z',
};
http.Response json(Object value, [int code = 200]) => http.Response(
  jsonEncode(value),
  code,
  headers: {'content-type': 'application/json'},
);
SqlServerApi apiFor(Future<http.Response> Function(http.Request) handle) =>
    SqlServerApi(
      baseUri: Uri.parse('http://172.17.18.208:9091'),
      allowInsecureHttp: true,
      client: MockClient((r) async {
        expect(
          r.url.host,
          '172.17.18.208',
          reason: 'No request may fall back to Supabase.',
        );
        if (r.url.path == '/api/auth/login') {
          return json({
            'user_id': actor,
            'access_token': token,
            'token_type': 'Bearer',
            'must_change_password': false,
            'expires_at': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 8))
                .toIso8601String(),
          });
        }
        expect(r.headers['authorization'], 'Bearer $token');
        return handle(r);
      }),
    );
Future<void> login(SqlServerApi api) => api
    .login(username: 'agent.msc', password: 'temporary-password')
    .then((_) {});
void main() {
  test(
    'entry retries retain their request ID only while the first outcome is unknown',
    () async {
      final ids = <String>[];
      var writes = 0;
      final api = apiFor((r) async {
        writes++;
        ids.add((jsonDecode(r.body) as Map)['request_id'] as String);
        return writes == 1
            ? json({'error': 'database_unavailable'}, 503)
            : json({'id': visit, 'version': 1}, 201);
      });
      await login(api);
      final repo = PointageRepository.sql(api);
      Future<String> enter() => repo.enter(
        plate: '12345-A-06',
        cin: 'BK12365',
        kind: 'empty',
        iso: '22G1',
        armateur: 'MSC',
        orderItemId: item,
      );
      await expectLater(enter(), throwsA(isA<SqlApiException>()));
      await enter();
      await enter();
      expect(ids[0], ids[1]);
      expect(ids[2], isNot(ids[1]));
      expect(
        RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(ids.first),
        true,
      );
      api.close();
    },
  );
  test(
    'remote HTTP is accepted only by explicit internal deployment opt-in',
    () {
      expect(
        () => SqlServerApi(baseUri: Uri.parse('http://172.17.18.208:9091')),
        throwsArgumentError,
      );
      final api = apiFor((_) async => json([]));
      api.close();
    },
  );
  test(
    'SQL roles and historical JSON details are decoded without initializing Supabase',
    () async {
      final api = apiFor(
        (r) async => r.url.path == '/api/me'
            ? json({
                'id': actor,
                'active': true,
                'roles': [
                  {'role': 'admin'},
                ],
              })
            : json([
                {...row(3), 'operational_details': '{"seal_number":"MSC-1"}'},
              ]),
      );
      await login(api);
      final repo = PointageRepository.sql(api);
      expect(await repo.roles(), ['admin']);
      expect((await repo.visitData(id: visit))!['operational_details'], {
        'seal_number': 'MSC-1',
      });
      expect(() => repo.client, throwsStateError);
      api.close();
    },
  );
  test(
    'loaded version is sent on a movement; no automatic retry after an ambiguous failure',
    () async {
      var writes = 0;
      final api = apiFor((r) async {
        if (r.method == 'GET') return json([row(7)]);
        writes++;
        expect(jsonDecode(r.body)['expected_version'], 7);
        return json({'error': 'database_unavailable'}, 503);
      });
      await login(api);
      final repo = PointageRepository.sql(api);
      await repo.visits();
      await expectLater(
        repo.exitWithDetails(visit, pickupContainer: 'CSQU3054383'),
        throwsA(
          isA<SqlApiException>().having(
            (e) => e.outcomeUnknown,
            'uncertain write',
            true,
          ),
        ),
      );
      expect(writes, 1);
      api.close();
    },
  );
  test(
    'account creation sends username, names and role without a phone or admin code',
    () async {
      final requests = <http.Request>[];
      final api = apiFor((r) async {
        requests.add(r);
        return r.url.path == '/api/users/'
            ? json({
                'id': actor,
                'version': 1,
                'must_change_password': true,
              }, 201)
            : json({'ok': true});
      });
      await login(api);
      await PointageRepository.sql(api).createAgent(
        phone: 'agent.msc',
        firstName: 'Agent',
        lastName: 'MSC',
        role: 'entree',
        password: 'temporary-password',
      );
      final body = jsonDecode(requests.first.body) as Map;
      expect(body['username'], 'agent.msc');
      expect(body['roles'], ['entree']);
      for (final r in requests) {
        expect(jsonDecode(r.body).keys, isNot(contains('phone')));
        expect(r.body, isNot(contains('admin_code')));
      }
      api.close();
    },
  );
  testWidgets(
    'SQL login uses normal identifiers without Supabase initialization',
    (tester) async {
      final api = apiFor((_) async => json([]));
      await tester.pumpWidget(MaterialApp(home: SqlAuthGate(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('Identifiant'), findsOneWidget);
      expect(find.text('Mot de passe'), findsOneWidget);
      expect(find.textContaining('Téléphone'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );
  testWidgets(
    'SQL account creation form has an identifier and no phone field',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(1500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = apiFor((_) async => json([]));
      await login(api);
      await tester.pumpWidget(
        MaterialApp(home: AdminScreen(repository: PointageRepository.sql(api))),
      );
      await tester.pumpAndSettle();
      final add = find.byIcon(Icons.person_add_rounded);
      await tester.ensureVisible(add.first);
      await tester.tap(add.first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Identifiant *'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Téléphone (WhatsApp) *'),
        findsNothing,
      );
      expect(
        find.textContaining('Nom d’utilisateur ou e-mail'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Générer un mot de passe'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Mot de passe initial *'),
            )
            .controller!
            .text
            .length,
        16,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );
}
