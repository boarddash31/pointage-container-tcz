import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/data/pointage_repository.dart';
import 'package:pointage_container/ui/pointage_screens.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionFixture extends PointageRepository {
  TransactionFixture() : super(SupabaseClient('https://example.supabase.co',
      'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false)));
  @override
  Future<List<DataTransaction>> transactions() async => [DataTransaction.fromJson({
    'id': 'visit-1', 'plate': '12345-A', 'driver_cin': 'AB1234',
    'entry_kind': 'loaded', 'iso_code': '22G1', 'armateur_id': 'MAE',
    'entered_at': '2026-10-20T10:00:00Z', 'transaction_number': '213216',
    'creator_name': 'Entry Operator', 'changer_name': 'Exit Operator',
    'changed_at': '2026-10-20T11:00:00Z',
    'canceled_at': '2026-10-20T11:00:00Z',
  })];
  @override
  Future<List<Map<String, dynamic>>> stock({String? iso, String? armateur}) async => [];
  @override
  Future<List<Map<String, dynamic>>> events(String visitId) async => [];
}

void main() {
  testWidgets('Data shows identity, type and cancellation; search matches changer', (tester) async {
    final repository = TransactionFixture();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: DataScreen(repository: repository))));
    await tester.pumpAndSettle();
    expect(find.text('213216'), findsOneWidget);
    expect(find.text('Réception'), findsOneWidget);
    expect(find.text('Entry Operator'), findsOneWidget);
    expect(find.text('Exit Operator'), findsOneWidget);
    expect(find.text('Annulée'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'exit operator');
    await tester.pumpAndSettle();
    expect(find.text('213216'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'unknown operator');
    await tester.pumpAndSettle();
    expect(find.text('213216'), findsNothing);
    expect(find.text('Aucune transaction trouvée'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
