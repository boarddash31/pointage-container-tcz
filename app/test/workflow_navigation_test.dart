import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/data/pointage_repository.dart';
import 'package:pointage_container/main.dart';
import 'package:pointage_container/ui/pointage_screens.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QueueFixture extends PointageRepository {
  QueueFixture() : super(SupabaseClient('https://example.supabase.co', 'publishable-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false)));
  @override Future<List<String>> roles() async => ['entree', 'engin', 'sortie'];
  @override Future<List<OperatorRecord>> operators() async =>
      [const OperatorRecord('MAE', 'Maersk', 'MAEU')];
  @override Future<List<TruckVisit>> visits({bool insideOnly = true}) async => [];
}

class QueueFixtureWithTrucks extends PointageRepository {
  QueueFixtureWithTrucks(this.mockVisits) : super(SupabaseClient('https://example.supabase.co', 'publishable-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final List<TruckVisit> mockVisits;
  @override Future<List<String>> roles() async => ['entree', 'sortie'];
  @override Future<List<OperatorRecord>> operators() async =>
      [const OperatorRecord('MAE', 'Maersk', 'MAEU')];
  @override Future<List<TruckVisit>> visits({bool insideOnly = true}) async => mockVisits;
}

void main() {
  testWidgets('operator navigates Entrée and Sortie directly; Sortie requires search before verification',
      (tester) async {
    final sampleVisit = TruckVisit(
      id: 'test-visit-1',
      plate: '12345-A-06',
      cin: 'AB123456',
      entryKind: 'loaded',
      container: 'CSQU3054383',
      booking: null,
      iso: '45G1',
      armateur: 'MAE',
      enteredAt: DateTime.now(),
      enginAt: null,
      exitedAt: null,
      canceledAt: null,
    );
    final repository = QueueFixtureWithTrucks([sampleVisit]);
    await tester.pumpWidget(MaterialApp(home: PointageShell(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('Enregistrement de l’entrée'), findsOneWidget);
    expect(tester.widgetList<TextField>(find.byType(TextField))
        .where((field) => field.maxLength == 1).length, 11);

    // Engin is hidden from header
    expect(find.text('Engin'), findsNothing);

    // Navigate to Sortie
    await tester.tap(find.text('Sortie'));
    await tester.pumpAndSettle();

    expect(find.text('Validation de la sortie'), findsOneWidget);
    expect(find.text('Plaque ou Conteneur *'), findsOneWidget);

    // Without search, truck details are not shown upfront
    expect(find.text('Saisie requise pour valider la sortie'), findsOneWidget);
    expect(find.text('Données du camion à vérifier'), findsNothing);

    // Enter plate or container in search
    await tester.enterText(find.widgetWithText(TextFormField, 'Plaque ou Conteneur *'), '12345');
    await tester.pumpAndSettle();

    // Verification card is now displayed
    expect(find.text('Données du camion à vérifier'), findsOneWidget);
    expect(find.text('12345-A-06'), findsOneWidget);
    expect(find.text('AB123456'), findsOneWidget);
    expect(find.text('CSQU3054383'), findsOneWidget);
    expect(find.text('45G1'), findsOneWidget);
    expect(find.text('MAE'), findsOneWidget);
    expect(find.text('Valider la sortie du camion'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('VisitActionSheet for loaded truck does not show position field', (tester) async {
    final repository = QueueFixture();
    final visit = TruckVisit(
      id: 'test-visit-1',
      plate: '12345-A-06',
      cin: 'AB123456',
      entryKind: 'loaded',
      container: 'MSCU1234567',
      booking: null,
      iso: '45G1',
      armateur: 'MAE',
      enteredAt: DateTime.now(),
      enginAt: null,
      exitedAt: null,
      canceledAt: null,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VisitActionSheet(
      repository: repository,
      visit: visit,
      canCancel: false,
      exitMode: false,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Position réelle de dépose *'), findsNothing);
    expect(find.text('Valider la dépose'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('BonPdfScreen displays PDF preview with print action', (tester) async {
    final samplePdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
    await tester.pumpWidget(MaterialApp(
      home: BonPdfScreen(
        bytes: samplePdf,
        kind: 'ENTRÉE',
        visitId: 'test-visit-1',
        autoPrint: false,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Bon ENTRÉE'), findsOneWidget);
    expect(find.byIcon(Icons.print), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
