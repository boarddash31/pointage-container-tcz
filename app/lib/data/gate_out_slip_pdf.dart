import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/gate_out_slip.dart';
import '../domain/terminal_slip.dart';

class GateOutSlipPdf {
  static Future<Uint8List> build(GateOutSlip slip) async {
    final pdf = pw.Document();
    final tcz = pw.MemoryImage(
      (await rootBundle.load('assets/brand/tcz-logo.png')).buffer.asUint8List(),
    );
    final marsa = pw.MemoryImage(
      (await rootBundle.load(
        'assets/brand/marsa-maroc-logo.png',
      )).buffer.asUint8List(),
    );
    final navy = PdfColor.fromHex('#075a8d');
    pw.Widget text(String value, {bool bold = false, double size = 10}) =>
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        );
    pw.Widget cell(String value, {bool bold = false, double height = 25}) =>
        pw.Container(
          constraints: pw.BoxConstraints(minHeight: height),
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: text(value, bold: bold),
        );
    pw.Widget table(List<List<String>> rows, {double labelWidth = 200}) =>
        pw.Table(
          border: pw.TableBorder.all(width: .6),
          columnWidths: {
            0: pw.FixedColumnWidth(labelWidth),
            1: const pw.FlexColumnWidth(),
          },
          children: [
            for (final row in rows)
              pw.TableRow(children: [cell(row[0], bold: true), cell(row[1])]),
          ],
        );
    String controlDate(String prefix, String key) =>
        slip.fields['${prefix == 'gate_agent' ? 'gate' : prefix}_$key'] ?? '';
    pw.Widget inspection(
      String title,
      String prefix, {
      bool seal = false,
      bool gate = false,
    }) => pw.Table(
      border: pw.TableBorder.all(width: .6),
      columnWidths: {
        0: const pw.FixedColumnWidth(65),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(2),
        if (gate) 3: const pw.FlexColumnWidth(),
      },
      children: [
        pw.TableRow(
          children: [
            cell(title, bold: true),
            cell(
              'NOM / PRENOM : ${slip.fields['${prefix}_name'] ?? ''}',
              bold: true,
            ),
            cell('PPR : ${slip.fields['${prefix}_ppr'] ?? ''}', bold: true),
            if (gate) cell('PORTE : ${slip.fields['gate_number']}', bold: true),
          ],
        ),
        pw.TableRow(
          children: [
            cell(''),
            cell('DATE : ${controlDate(prefix, 'date')}', bold: true),
            cell('HEURE : ${controlDate(prefix, 'time')}', bold: true),
            if (gate) cell(''),
          ],
        ),
        if (seal)
          pw.TableRow(
            children: [
              cell(''),
              cell('SCELLES : ${slip.fields['seal_number']}', bold: true),
              cell(''),
            ],
          ),
      ],
    );
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 30, 30, 24),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Image(
                      tcz,
                      width: 122,
                      height: 40,
                      fit: pw.BoxFit.contain,
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'TERMINAL CONTENEURS ZENATA',
                      style: pw.TextStyle(fontSize: 6, color: navy),
                    ),
                  ],
                ),
                pw.Image(marsa, width: 105, height: 45, fit: pw.BoxFit.contain),
              ],
            ),
            pw.SizedBox(height: 28),
            pw.Center(child: text('BON DE SORTIE', bold: true, size: 14)),
            pw.SizedBox(height: 20),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 128,
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: .6)),
                child: text(
                  'DOUANE : ${slip.fields['customs_office']}',
                  size: 9,
                ),
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Table(
              border: pw.TableBorder.all(width: .6),
              columnWidths: {
                0: const pw.FlexColumnWidth(),
                1: const pw.FlexColumnWidth(),
              },
              children: [
                pw.TableRow(
                  children: [
                    cell('DATE/HEURE : ${slip.date}'),
                    cell('AUTORISATION DE SORTIE N° : ${slip.reference}'),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(width: .6)),
              padding: const pw.EdgeInsets.all(8),
              child: text('IDENTIFICATION', bold: true),
            ),
            pw.Stack(
              children: [
                pw.Positioned(
                  left: 65,
                  top: 3,
                  child: pw.Opacity(
                    opacity: .17,
                    child: pw.Text(
                      'DOUANE',
                      style: pw.TextStyle(
                        fontSize: 48,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ),
                ),
                pw.Table(
                  border: pw.TableBorder.all(width: .6),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(105),
                    for (
                      var i = 0;
                      i <
                          (slip.containers.isEmpty
                              ? 1
                              : slip.containers.length);
                      i++
                    )
                      i + 1: const pw.FlexColumnWidth(),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        cell('NUMERO', bold: true),
                        if (slip.containers.isEmpty)
                          cell('')
                        else
                          for (final c in slip.containers) cell(c.number),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        cell('Statut', bold: true),
                        if (slip.emptyChassis)
                          cell('Camion vide / Châssis nu')
                        else
                          for (final c in slip.containers) cell(c.status),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            table([
              ['N° DECLARATION', slip.fields['declaration_number']!],
              ["MOYEN D'ENLEVEMENT", 'CAMION ${slip.plate}'],
              ['IDENTITE CHAUFFEUR', slip.cin],
              ["L'AGENT DU TERMINAL", slip.agent],
              ['ISO CODE', slip.containerValues((c) => c.iso)],
              ['LIGNE OPERATEUR', slip.containerValues((c) => c.line)],
              ['CONNAISSEMENT (B/L)', slip.fields['bill_of_lading']!],
              [
                'POIDS BRUT (KG)',
                slip.containerValues(
                  (c) => c.weight.isEmpty ? '' : '${c.weight} kg',
                ),
              ],
            ]),
            if (slip.orders.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: text('ORDRE(S) : ${slip.orders.join(' / ')}', size: 8),
              ),
            pw.SizedBox(height: 10),
            inspection('ECOR', 'ecor', seal: true),
            pw.SizedBox(height: 20),
            inspection('SORTIE DU\nTERMINAL', 'gate_agent', gate: true),
            pw.Spacer(),
            pw.Center(
              child: pw.Text(
                'Terminal Conteneurs Zenata - Marsa Maroc',
                style: pw.TextStyle(
                  fontSize: 7,
                  color: navy,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            for (final line in TerminalSlip.footer)
              pw.Text(
                line,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 6.2, color: navy),
              ),
          ],
        ),
      ),
    );
    return pdf.save();
  }
}
