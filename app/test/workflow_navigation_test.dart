import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/data/pointage_repository.dart';
import 'package:pointage_container/main.dart';
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
    expect(find.text('3. Booking / ordre libre *'), findsOneWidget);
    await tester.tap(find.text('2 · Engin'));
    await tester.pumpAndSettle();
    expect(find.text('Engin · dépose / prise'), findsOneWidget);
    await tester.tap(find.text('3 · Sortie'));
    await tester.pumpAndSettle();
    expect(find.text('Sortie · tous les camions présents'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
