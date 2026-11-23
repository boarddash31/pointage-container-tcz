import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/data/pointage_repository.dart';
import 'package:pointage_container/ui/gate_mission_icon.dart';
import 'package:pointage_container/ui/transport_orders_screen.dart';

class CatalogueFixture extends PointageRepository {
  CatalogueFixture() : super.detached();
  bool fail = false;
  List<OperatorRecord> rows = [];
  @override
  Future<List<OperatorRecord>> operators() async {
    if (fail) throw StateError('fixture network failure');
    return rows;
  }
}

void main() {
  testWidgets(
    'empty catalogue is explained and a reload enables selecting ZIMAG',
    (tester) async {
      final repo = CatalogueFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: CreateTransportOrderScreen(
            repository: repo,
            direction: 'RESTITUTION',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Aucun armateur configuré'), findsOneWidget);
      final armateurInput = find
          .descendant(
            of: find.byType(DropdownMenuFormField<String>).last,
            matching: find.byType(TextField),
          )
          .first;
      expect(tester.widget<TextField>(armateurInput).enabled, isFalse);
      repo.rows = [const OperatorRecord('ZIMAG', 'ZIMAG', 'ZIM')];
      await tester.tap(find.text('Actualiser les armateurs'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aucun armateur configuré'), findsNothing);
      final field = tester.widget<DropdownMenuFormField<String>>(
        find.byType(DropdownMenuFormField<String>).last,
      );
      expect(tester.widget<TextField>(armateurInput).enabled, isTrue);
      expect(field.dropdownMenuEntries.single.value, 'ZIMAG');
      final input = find
          .descendant(
            of: find.byType(DropdownMenuFormField<String>).last,
            matching: find.byType(TextField),
          )
          .first;
      await tester.ensureVisible(input);
      await tester.tap(input);
      await tester.enterText(input, 'ZI');
      await tester.pumpAndSettle();
      expect(find.text('ZIMAG · ZIMAG'), findsOneWidget);
    },
  );

  testWidgets('network failure is distinguishable from an empty catalogue', (
    tester,
  ) async {
    final repo = CatalogueFixture()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: CreateTransportOrderScreen(
          repository: repo,
          direction: 'RESTITUTION',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Impossible de charger les armateurs'),
      findsOneWidget,
    );
    expect(find.textContaining('Aucun armateur configuré'), findsNothing);
  });

  testWidgets(
    'mission pictograms distinguish restitution and delivery with their quantity',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                GateMissionIcon(restitution: true, count: 1),
                GateMissionIcon(restitution: false, count: 2),
              ],
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.move_to_inbox_outlined), findsOneWidget);
      expect(find.byIcon(Icons.outbox_outlined), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );
}
