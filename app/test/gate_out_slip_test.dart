import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/domain/gate_out_slip.dart';
import 'package:pointage_container/data/bon_pdf_builder.dart';

Map<String, dynamic> sample({bool twin = false, bool receiving = false}) => {
  'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  'event_id': 227653,
  'kind': 'SORTIE',
  'visit_id': 'visit',
  'created_at': '2026-10-27T13:09:01Z',
  'snapshot': {
    'entry_kind': receiving ? 'loaded' : 'empty',
    'plate': '33674-A-7',
    'driver_cin': 'H783343',
    'container_number': 'UETU8580329',
    'iso_code': '45G1',
    'armateur_id': 'MSC',
    'agent_name': 'Agent TCZ',
    'is_twin': twin,
    if (twin) 'container_number_2': 'CSQU3054383',
    if (twin) 'iso_code_2': '22G1',
    if (twin) 'armateur_id_2': 'MAE',
    'carrier_booking_reference': 'EDO-2026-001',
    'exit_document': {'load_status': 'MTY', 'gross_weight_kg': 3900},
  },
  'print_context': {
    'created_at_local': '2026-10-27 14:09:01',
    'agent_name': 'Current name',
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('gate-out preserves archived identities and explicit cargo data', () {
    final slip = GateOutSlip.fromDocument(
      sample(),
      visitData: {
        'plate': 'CHANGED',
        'driver_cin': 'CHANGED',
        'container_number': 'CHANGED',
      },
    );
    expect(slip.reference, '227653');
    expect(slip.date, '2026-10-27 14:09:01');
    expect(slip.plate, '33674-A-7');
    expect(slip.cin, 'H783343');
    expect(slip.agent, 'Agent TCZ');
    expect(slip.containers.single.number, 'UETU8580329');
    expect(slip.containers.single.status, 'Vide');
    expect(slip.containers.single.weight, '3900');
    expect(slip.fields['declaration_number'], '');
    expect(slip.fields['bill_of_lading'], '');
  });
  test(
    'receiving truck leaves empty and never lists the deposited container as outgoing',
    () {
      final slip = GateOutSlip.fromDocument(sample(receiving: true));
      expect(slip.emptyChassis, true);
      expect(slip.containers, isEmpty);
      expect(slip.containerValues((c) => c.iso), '');
    },
  );
  test(
    'two outgoing containers retain separate lines and ISO codes without guessing empty/full',
    () {
      final doc = sample(twin: true);
      (doc['snapshot'] as Map)['exit_document'] = {};
      final slip = GateOutSlip.fromDocument(doc);
      expect(slip.containers.length, 2);
      expect(slip.containers.map((c) => c.status), ['', '']);
      expect(slip.containerValues((c) => c.iso), '1 : 45G1 / 2 : 22G1');
      expect(slip.containers.last.line, 'MAE');
      expect(slip.fields['customs_office'], '');
    },
  );
  test(
    'missing local date is explicitly shown in UTC and document ID remains a real reference',
    () {
      final doc = sample()
        ..remove('print_context')
        ..remove('event_id');
      final slip = GateOutSlip.fromDocument(doc);
      expect(slip.date, '2026-10-27 13:09:01 UTC');
      expect(slip.reference, doc['id']);
    },
  );
  for (final twin in [false, true]) {
    test(
      'gate-out A4 form renders ${twin ? 2 : 1} container(s) on one page',
      () async {
        final bytes = await BonPdfBuilder.buildA5(document: sample(twin: twin));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        final text = String.fromCharCodes(bytes);
        expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 1);
        expect(bytes.length, greaterThan(3000));
        const preview = String.fromEnvironment('GATE_OUT_PDF_PREVIEW');
        if (preview.isNotEmpty && !twin) {
          await File(preview).writeAsBytes(bytes);
        }
      },
    );
  }
}
