import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pointage_container/data/demo_store.dart';
import 'package:pointage_container/main.dart';
import 'package:pointage_container/ui/demo_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'demo lifecycle moves stock once and preserves the actor history',
    () async {
      final store = DemoStore.seeded();
      final entry = store.profiles[1], exit = store.profiles[2];
      final number = DemoStore.sampleContainer('TSTU123456');
      final visit = await store.enter(
        entry,
        plate: '11111A06',
        cin: 'AB123456',
        kind: 'loaded',
        iso: '22G1',
        line: 'MAE',
        number: number,
      );
      expect(store.stock.length, 1);
      await store.exit(exit, visit['id'] as String, position: 'B-02-03');
      expect(
        store.stock.singleWhere(
          (s) => s['container_number'] == number,
        )['position'],
        'B-02-03',
      );
      expect(visit['changer_name'], exit.name);
      final pickup = await store.enter(
        entry,
        plate: '22222-B-06',
        cin: 'CD123456',
        kind: 'empty',
        iso: '22G1',
        line: 'MAE',
        booking: 'DEMO-PICKUP',
      );
      await store.exit(exit, pickup['id'] as String, pickup: [number]);
      expect(
        store.stock.where((s) => s['container_number'] == number),
        isEmpty,
      );
      expect(pickup['container_number'], number);
      final before = jsonEncode(store.stock);
      await expectLater(
        store.exit(exit, pickup['id'] as String, pickup: [number]),
        throwsStateError,
      );
      expect(jsonEncode(store.stock), before);
    },
  );

  test(
    'demo role boundaries and twin validation reject changes atomically',
    () async {
      final store = DemoStore.seeded();
      final entry = store.profiles[1], exit = store.profiles[2];
      await expectLater(
        store.createProfile(entry, 'Unauthorized', 'admin'),
        throwsStateError,
      );
      expect(store.profiles.length, 3);
      await expectLater(store.exit(entry, 'demo-visit-1'), throwsStateError);
      final before = store.visits.length;
      await expectLater(
        store.enter(
          entry,
          plate: '33333-C-06',
          cin: 'AB123456',
          kind: 'loaded',
          iso: '45G1',
          line: 'MAE',
          number: DemoStore.sampleContainer('TSTU123456'),
          twin: true,
          number2: DemoStore.sampleContainer('TSTU654321'),
          iso2: '22G1',
        ),
        throwsStateError,
      );
      expect(store.visits.length, before);
      final visit = await store.enter(
        entry,
        plate: '33333-C-06',
        cin: 'AB123456',
        kind: 'empty',
        iso: '22G1',
        line: 'MAE',
        booking: 'DEMO-TWIN',
        twin: true,
        iso2: '22G1',
      );
      final second = DemoStore.sampleContainer('MSCU123456');
      store.stock.add({
        'container_number': second,
        'iso_code': '45G1',
        'armateur_id': 'MAE',
        'position': 'C-01',
        'arrived_at': DateTime.now().toIso8601String(),
      });
      final snapshot = jsonEncode([store.visits, store.stock, store.timeline]);
      await expectLater(
        store.exit(
          exit,
          visit['id'] as String,
          pickup: [store.stock.first['container_number'] as String, second],
        ),
        throwsStateError,
      );
      expect(jsonEncode([store.visits, store.stock, store.timeline]), snapshot);
    },
  );

  test(
    'demo profiles persist separately and reset preserves production storage',
    () async {
      SharedPreferences.setMockInitialValues({
        'production_session_fixture': 'unchanged',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = await DemoStore.load(preferences: prefs);
      final created = await store.createProfile(
        store.profiles.first,
        'Karim Démo',
        'entree',
      );
      final restored = await DemoStore.load(preferences: prefs);
      expect(
        restored.profiles.singleWhere((p) => p.id == created.id).name,
        'Karim Démo',
      );
      await expectLater(
        restored.setProfileActive(
          restored.profiles.first,
          restored.profiles.first,
          false,
        ),
        throwsStateError,
      );
      await restored.reset(restored.profiles.first);
      expect(restored.profiles.length, 3);
      expect(prefs.getString('production_session_fixture'), 'unchanged');
      expect(
        prefs.getString(DemoStore.storageKey),
        isNot(contains('password')),
      );
    },
  );

  test('demo PDF is generated locally from the synthetic visit', () async {
    final bytes = await DemoBonPdf.build(DemoStore.seeded().visits.first);
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(900));
  });

  testWidgets(
    'all public demo profile buttons open directly without initializing Supabase',
    (tester) async {
      await tester.runAsync(() async {
        rootBundle.evict('assets/operators.json');
        await rootBundle.loadString('assets/operators.json');
      });
      tester.view.physicalSize = const Size(1300, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var productionOpens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DemoAccessHome(
            store: DemoStore.seeded(),
            productionBuilder: (_) {
              productionOpens++;
              return const Scaffold(body: Text('PRODUCTION LOGIN'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final role in ['admin', 'entree', 'sortie']) {
        await tester.runAsync(() async {
          await tester.tap(find.byKey(ValueKey('demo-open-$role')));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        expect(find.text('TCZ · Démo'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Mot de passe'), findsNothing);
        expect(productionOpens, 0);
        await tester.tap(find.byKey(const ValueKey('demo-switch-profile')));
        await tester.pumpAndSettle();
      }
      expect(() => Supabase.instance, throwsAssertionError);
      await tester.tap(find.byKey(const ValueKey('open-production')));
      await tester.pumpAndSettle();
      expect(productionOpens, 1);
      expect(find.text('PRODUCTION LOGIN'), findsOneWidget);
    },
  );

  testWidgets(
    'demo Admin creates a profile which appears as a direct access choice',
    (tester) async {
      await tester.runAsync(() async {
        rootBundle.evict('assets/operators.json');
        await rootBundle.loadString('assets/operators.json');
      });
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = DemoStore.seeded();
      await tester.pumpWidget(
        MaterialApp(
          home: DemoAccessHome(
            store: store,
            productionBuilder: (_) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('demo-open-admin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('demo-add-profile')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('demo-profile-name')),
        'Karim Démo',
      );
      await tester.tap(find.byKey(const ValueKey('demo-save-profile')));
      await tester.pumpAndSettle();
      expect(store.profiles.length, 4);
      await tester.tap(find.byKey(const ValueKey('demo-switch-profile')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Karim Démo'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('Enregistrement de l’entrée'), findsOneWidget);
      expect(find.text('Karim Démo'), findsOneWidget);
    },
  );

  testWidgets('mobile demo roles fit a 390px viewport', (tester) async {
    await tester.runAsync(() async {
      rootBundle.evict('assets/operators.json');
      await rootBundle.loadString('assets/operators.json');
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DemoAccessHome(
          store: DemoStore.seeded(),
          productionBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final role in ['admin', 'entree', 'sortie']) {
      await tester.ensureVisible(find.byKey(ValueKey('demo-open-$role')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey('demo-open-$role')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('demo-switch-profile')));
      await tester.pumpAndSettle();
    }
  });
  testWidgets(
    'public app starts in demo and auth redirects retain the production flow',
    (tester) async {
      await tester.pumpWidget(const PointageApp());
      await tester.pumpAndSettle();
      expect(find.text('Accès démo'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Mot de passe'), findsNothing);
      expect(() => Supabase.instance, throwsAssertionError);
      expect(isProductionAuthLink(Uri.parse('https://example.test/')), isFalse);
      expect(
        isProductionAuthLink(Uri.parse('https://example.test/?auth=recovery')),
        isTrue,
      );
      expect(
        isProductionAuthLink(
          Uri.parse('https://example.test/?mode=production'),
        ),
        isTrue,
      );
    },
  );
}
