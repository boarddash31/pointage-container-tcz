import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/data/freepool_export.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Freepool workbook keeps movements, category counts and EVP totals', () {
    final report = FreepoolExport(
      SupabaseClient('https://example.supabase.co', 'publishable-test-key'),
    );
    final rows = <Map<String, dynamic>>[
      {
        'container_number': 'CSQU3054383', 'client_id': 'CLIENT-A',
        'armateur_id': 'MAE', 'iso_code': '22G1', 'category': '20 DV',
        'arrived_at': '2026-10-19T09:00:00Z', 'departed_at': null,
        'evp': 1, 'position': 'A-01',
      },
      {
        'container_number': 'ABCU1234560', 'client_id': 'CLIENT-A',
        'armateur_id': 'MAE', 'iso_code': '45G1', 'category': '40 DV HC',
        'arrived_at': '2026-10-19T11:00:00Z', 'departed_at': null,
        'evp': 2, 'position': 'B-03',
      },
    ];
    expect(report.summary(rows)['20 DV'], 1);
    expect(report.summary(rows)['40 DV HC'], 2);
    final bytes = report.workbook(rows, DateTime(2026, 10, 19));
    expect(bytes, isNotEmpty);
    final book = Excel.decodeBytes(bytes);
    expect(book['MOUVEMENTS'].maxRows, 3);
    expect(book['20 DV'].maxRows, 2);
    expect(book['40 DV HC'].maxRows, 2);
    final recap = book['RECAP'];
    expect(recap.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value?.toString(), 'MAE');
    expect(num.parse(recap.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: 1)).value.toString()), 3);
  });
}
