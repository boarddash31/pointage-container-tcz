import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/gate_out_slip.dart';

class GateOutSlipPdf {
  static const copies = ['Client', 'Transporteur', 'Sécurité'];
  static Future<Uint8List> build(GateOutSlip slip) async {
    final pdf = pw.Document();
    final logo = pw.MemoryImage(
      (await rootBundle.load('assets/brand/zps-logo.jpeg')).buffer.asUint8List(),
    );
    pw.Widget cell(String value, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      child: pw.Text(value, style: pw.TextStyle(fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
    String containers(String Function(GateOutContainer) field) => [
      for (var i = 0; i < slip.containers.length; i++)
        'TC${i + 1} : ${field(slip.containers[i])}',
    ].join('\n');
    final rows = [
      ['TRANSPORTEUR', slip.fields['haulier'] ?? ''],
      ['DATE ET HEURE', slip.date],
      ['AUTORISATION N°', slip.reference],
      ['RÉF. ${slip.orderKind}', slip.orders.join(' / ')],
      ['CAMION IMM.', slip.plate],
      ['CIN CHAUFFEUR', slip.cin],
      ['CONTENEUR N°', containers((c) => c.number)],
      ['ISO CODE', containers((c) => c.iso)],
      ['LIGNE OPÉRATEUR', containers((c) => c.line)],
      ['SCELLÉ', containers((c) => c.seal)],
      ['STATUT', slip.emptyChassis ? 'Camion vide / Châssis nu' : containers((c) => c.status)],
      ['ID AGENT', (slip.fields['agent_id'] ?? '').isNotEmpty ? slip.fields['agent_id']! : slip.agent],
    ];
    for (final copy in copies) {
      pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(20),
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Image(logo, width: 84, height: 49, fit: pw.BoxFit.contain),
            pw.Text('Exemplaire $copy', style: const pw.TextStyle(fontSize: 9)),
          ]),
          pw.SizedBox(height: 9),
          pw.Center(child: pw.Text('BON DE SORTIE', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 14),
          pw.Table(border: pw.TableBorder.all(width: .6), columnWidths: {
            0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(6),
          }, children: [for (final row in rows)
            pw.TableRow(children: [cell(row[0], bold: true), cell(row[1])]),
          ]),
          pw.Spacer(),
          pw.Center(child: pw.Text('Zenata Port Sec', style: const pw.TextStyle(fontSize: 9))),
        ]),
      ));
    }
    return pdf.save();
  }
}
