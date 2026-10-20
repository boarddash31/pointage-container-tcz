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

void main() {
  testWidgets('operator can navigate Entrée, Engin and Sortie; empty booking replaces ISO boxes',
      (tester) async {
    final repository = QueueFixture();
    await tester.pumpWidget(MaterialApp(home: PointageShell(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrement de l’entrée'), findsOneWidget);
    expect(tester.widgetList<TextField>(find.byType(TextField))
        .where((field) => field.maxLength == 1).length, 11);
    await tester.ensureVisible(find.text('Sans conteneur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sans conteneur'));
    await tester.pumpAndSettle();
    expect(find.text('Booking / ordre libre *'), findsOneWidget);
    await tester.tap(find.text('Engin'));
    await tester.pumpAndSettle();
    expect(find.text('Engin · dépose / prise'), findsOneWidget);
    await tester.tap(find.text('Sortie'));
    await tester.pumpAndSettle();
    expect(find.text('Sortie · tous les camions présents'), findsOneWidget);
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
}
