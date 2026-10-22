import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class BonPdfBuilder {
  static String decodeIso(String? iso) {
    if (iso == null || iso.isEmpty) return 'Standard';
    final code = iso.toUpperCase();
    if (code.startsWith('2')) {
      if (code.contains('R')) return "20' Reefer (Frigo)";
      if (code.contains('U') || code.contains('T')) return "20' Citerne / Open";
      return "20' Standard Dry";
    }
    if (code.startsWith('4')) {
      if (code == '45G1' || code == '45R1' || code.startsWith('45')) {
        return code.contains('R') ? "40' High Cube Reefer" : "40' High Cube Dry (9'6)";
      }
      if (code.contains('R')) return "40' Reefer (Frigo)";
      return "40' Standard Dry (8'6)";
    }
    if (code.startsWith('L') || code.startsWith('45')) return "45' High Cube";
    return "$code Container";
  }

  static String formatDateTime(String? rawIso) {
    if (rawIso == null || rawIso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(rawIso).toLocal();
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final year = dt.year.toString();
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$day/$month/$year à $hour:$minute';
    } catch (_) {
      return rawIso.split('.')[0].replaceFirst('T', ' ');
    }
  }

  static Future<Uint8List> buildA5({
    required Map<String, dynamic> document,
    Map<String, dynamic>? visitData,
  }) async {
    final pdf = pw.Document();

    final snapshot = (document['snapshot'] as Map<String, dynamic>?) ?? {};
    final event = (snapshot['event'] as Map<String, dynamic>?) ?? {};

    final docId = (document['id'] ?? '').toString();
    final visitId = (document['visit_id'] ?? snapshot['id'] ?? '').toString();
    final kind = (document['kind'] ?? 'ENTREE').toString().toUpperCase();
    final createdAt = (document['created_at'] ?? snapshot['entered_at'] ?? DateTime.now().toIso8601String()).toString();

    final plate = (visitData?['plate'] ?? snapshot['plate'] ?? '—').toString().toUpperCase();
    final cin = (visitData?['driver_cin'] ?? snapshot['driver_cin'] ?? '—').toString().toUpperCase();
    final entryKind = (visitData?['entry_kind'] ?? snapshot['entry_kind'] ?? 'empty').toString().toLowerCase();

    // Container 1
    final containerNumber = (visitData?['container_number'] ??
            event['container'] ??
            snapshot['container_number'] ??
            '')
        .toString()
        .trim();
    final isoCode = (visitData?['iso_code'] ?? snapshot['iso_code'] ?? '45G1').toString().toUpperCase();
    final armateur = (visitData?['armateur_id'] ?? snapshot['armateur_id'] ?? 'TCZ').toString().toUpperCase();
    final booking = (visitData?['bookings']?['reference'] ??
            visitData?['booking'] ??
            event['booking'] ??
            snapshot['booking'] ??
            '')
        .toString()
        .trim();
    final position = (visitData?['position'] ?? event['position'] ?? snapshot['position'] ?? '').toString().trim();

    // Twin (Container 2)
    final isTwin = (visitData?['is_twin'] ?? snapshot['is_twin'] ?? false) == true;
    final containerNumber2 = (visitData?['container_number_2'] ?? snapshot['container_number_2'] ?? '').toString().trim();
    final isoCode2 = (visitData?['iso_code_2'] ?? snapshot['iso_code_2'] ?? '').toString().toUpperCase();
    final armateur2 = (visitData?['armateur_id_2'] ?? snapshot['armateur_id_2'] ?? '').toString().toUpperCase();
    final booking2 = (visitData?['booking_reference_2'] ?? snapshot['booking_reference_2'] ?? '').toString().trim();

    // Color Palette
    final navy = PdfColor.fromHex('#075a8d');
    final darkNavy = PdfColor.fromHex('#043452');
    final ink = PdfColor.fromHex('#0f172a');
    final muted = PdfColor.fromHex('#64748b');
    final borderGray = PdfColor.fromHex('#cbd5e1');
    final lightBg = PdfColor.fromHex('#f8fafc');
    final emerald = PdfColor.fromHex('#16a34a');
    final lightEmerald = PdfColor.fromHex('#dcfce7');
    final amber = PdfColor.fromHex('#d97706');
    final lightAmber = PdfColor.fromHex('#fef3c7');
    final lightBlue = PdfColor.fromHex('#e0f2fe');

    // Title mapping
    String docTitle;
    PdfColor docColor;
    if (kind == 'ENTREE') {
      docTitle = "BON D'ENTRÉE (GATE-IN)";
      docColor = navy;
    } else if (kind == 'DEPOSE') {
      docTitle = 'BON DE DÉCHARGE YARD';
      docColor = PdfColor.fromHex('#0284c7');
    } else if (kind == 'PRISE') {
      docTitle = 'BON DE CHARGE YARD';
      docColor = amber;
    } else if (kind == 'SORTIE') {
      docTitle = 'BON DE SORTIE (GATE-OUT)';
      docColor = emerald;
    } else {
      docTitle = 'BON TCZ - $kind';
      docColor = navy;
    }

    // QR Payload for security scanning at gate-out
    final qrPayload = 'TCZ|DOC:$docId|VISIT:$visitId|PLATE:$plate|KIND:$kind|ARM:$armateur|CONT:${containerNumber.isEmpty ? 'NONE' : containerNumber}';

    // Load visual image asset safely
    pw.MemoryImage? truckImg;
    pw.MemoryImage? logoImg;
    try {
      final logoBytes = await rootBundle.load('assets/brand/tcz-logo.png');
      logoImg = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

    try {
      String assetName;
      if (entryKind == 'loaded') {
        assetName = 'assets/truck-loaded.png';
      } else {
        assetName = kind == 'PRISE' ? 'assets/truck-prise.png' : 'assets/truck-empty.png';
      }
      final truckBytes = await rootBundle.load(assetName);
      truckImg = pw.MemoryImage(truckBytes.buffer.asUint8List());
    } catch (_) {}

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ==========================================
              // 1. HEADER WITH LOGO, TITLE, REF & QR
              // ==========================================
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Logo & Terminal Name
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logoImg != null)
                          pw.Image(logoImg, width: 90, height: 26, fit: pw.BoxFit.contain)
                        else
                          pw.Text('TCZ',
                              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: navy)),
                        pw.SizedBox(height: 2),
                        pw.Text('TERMINAL CONTENEURS DE TANGER MED',
                            style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: darkNavy)),
                        pw.Text('PORT TANGER MED 2 · GUICHET CONTRÔLE D\'ACCÈS',
                            style: pw.TextStyle(fontSize: 5.5, color: muted)),
                      ],
                    ),
                  ),

                  // Document Badge
                  pw.Expanded(
                    flex: 5,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: docColor,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Text(
                            docTitle,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Réf: #${docId.length > 8 ? docId.substring(0, 8).toUpperCase() : docId}',
                            style: pw.TextStyle(color: PdfColors.white, fontSize: 7, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            formatDateTime(createdAt),
                            style: const pw.TextStyle(color: PdfColors.white, fontSize: 6.5),
                          ),
                        ],
                      ),
                    ),
                  ),

                  pw.SizedBox(width: 8),

                  // QR Code
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrPayload,
                    width: 44,
                    height: 44,
                  ),
                ],
              ),

              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1, color: navy),
              pw.SizedBox(height: 4),

              // ==========================================
              // 2. IDENTIFICATION TRANSPORT & CHAUFFEUR
              // ==========================================
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderGray, width: 0.7),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    // Camion
                    pw.Expanded(
                      flex: 3,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('TRACTEUR / CAMION',
                              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: muted)),
                          pw.SizedBox(height: 2),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              border: pw.Border.all(color: navy, width: 1.2),
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Text(
                              plate,
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: navy),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Chauffeur CIN
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('CIN CHAUFFEUR',
                              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: muted)),
                          pw.SizedBox(height: 2),
                          pw.Text(cin,
                              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: ink)),
                        ],
                      ),
                    ),

                    // Ligne Maritime / Armateur
                    pw.Expanded(
                      flex: 3,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('LIGNE MARITIME',
                              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: muted)),
                          pw.SizedBox(height: 2),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: pw.BoxDecoration(
                              color: lightBlue,
                              borderRadius: pw.BorderRadius.circular(3),
                            ),
                            child: pw.Text(
                              isTwin ? '$armateur / $armateur2' : armateur,
                              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: navy),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Visite ID
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('N° DE VISITE',
                              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: muted)),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            visitId.length > 8 ? '${visitId.substring(0, 8)}…' : visitId,
                            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 6),

              // ==========================================
              // 3. TABLEAU DES CONTENEURS & OPÉRATION
              // ==========================================
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderGray, width: 0.7),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Table(
                  border: pw.TableBorder(
                    horizontalInside: pw.BorderSide(color: borderGray, width: 0.5),
                  ),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(3.2), // Container
                    1: pw.FlexColumnWidth(1.6), // ISO
                    2: pw.FlexColumnWidth(2.6), // Description
                    3: pw.FlexColumnWidth(2.2), // Booking
                    4: pw.FlexColumnWidth(2.0), // Position
                  },
                  children: [
                    // Header Row
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#edf2f7')),
                      children: [
                        _th('CONTENEUR ISO 6346'),
                        _th('CODE ISO'),
                        _th('TYPE / FORMAT'),
                        _th('BOOKING / MISSION'),
                        _th('POSITION YARD'),
                      ],
                    ),

                    // Container 1 Row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.white),
                      children: [
                        _tdContainer(containerNumber, entryKind),
                        _td(isoCode, isBold: true),
                        _td(decodeIso(isoCode)),
                        _td(booking.isNotEmpty
                            ? booking
                            : (entryKind == 'loaded' ? 'Dépose directe' : 'Non requis')),
                        _tdPosition(position, entryKind, kind),
                      ],
                    ),

                    // Container 2 Row (Twin 2x20)
                    if (isTwin)
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.white),
                        children: [
                          _tdContainer(containerNumber2, entryKind),
                          _td(isoCode2.isNotEmpty ? isoCode2 : '22G1', isBold: true),
                          _td(decodeIso(isoCode2.isNotEmpty ? isoCode2 : '22G1')),
                          _td(booking2.isNotEmpty
                              ? booking2
                              : (entryKind == 'loaded' ? 'Dépose directe' : 'Non requis')),
                          _tdPosition(position, entryKind, kind),
                        ],
                      ),
                  ],
                ),
              ),

              pw.SizedBox(height: 6),

              // ==========================================
              // 4. VISUAL SCHÉMA & ÉTAT COMPARATIF ENTRÉE / SORTIE
              // ==========================================
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderGray, width: 0.8),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    // Left: Truck Illustration & Badge
                    pw.Expanded(
                      flex: 4,
                      child: pw.Column(
                        children: [
                          if (truckImg != null)
                            pw.Image(truckImg, height: 42, fit: pw.BoxFit.contain)
                          else
                            pw.Container(
                              height: 38,
                              alignment: pw.Alignment.center,
                              decoration: pw.BoxDecoration(
                                color: lightBlue,
                                borderRadius: pw.BorderRadius.circular(4),
                              ),
                              child: pw.Text(
                                entryKind == 'loaded' ? '🚛 [ CAMION CHARGÉ ]' : '🚛 [ CHÂSSIS NU ]',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: navy),
                              ),
                            ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            isTwin
                                ? 'Configuration : TWIN 2 x 20 PIEDS'
                                : (entryKind == 'loaded'
                                    ? 'Configuration : 1x ${decodeIso(isoCode)}'
                                    : 'Configuration : CHÂSSIS NU POUR PRISE'),
                            style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: muted),
                          ),
                        ],
                      ),
                    ),

                    pw.SizedBox(width: 8),

                    // Right: Comparison & Security Rule (État d'entrée vs État attendu en sortie)
                    pw.Expanded(
                      flex: 6,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(5),
                          border: pw.Border.all(
                            color: entryKind == 'empty' ? amber : navy,
                            width: 1,
                          ),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            // Constat Entrée
                            pw.Row(
                              children: [
                                pw.Text('1. CONSTAT ENTRÉE : ',
                                    style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: muted)),
                                pw.Text(
                                  entryKind == 'empty'
                                      ? 'CHÂSSIS NU (VIDE)'
                                      : 'CHARGÉ (DÉPOSE CONTENEUR)',
                                  style: pw.TextStyle(
                                    fontSize: 7,
                                    fontWeight: pw.FontWeight.bold,
                                    color: entryKind == 'empty' ? amber : navy,
                                  ),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 3),

                            // Règle Obligatoire Sortie
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                              decoration: pw.BoxDecoration(
                                color: entryKind == 'empty' ? lightAmber : lightEmerald,
                                borderRadius: pw.BorderRadius.circular(3),
                              ),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    entryKind == 'empty'
                                        ? '⚠️ CONTRÔLE SORTIE : DOIT SORTIR CHARGÉ'
                                        : '⚠️ CONTRÔLE SORTIE : DOIT SORTIR VIDE (CHÂSSIS NU)',
                                    style: pw.TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: pw.FontWeight.bold,
                                      color: entryKind == 'empty' ? PdfColor.fromHex('#92400e') : PdfColor.fromHex('#166534'),
                                    ),
                                  ),
                                  pw.Text(
                                    entryKind == 'empty'
                                        ? 'Le camion doit avoir chargé le conteneur assigné en Yard avant de franchir la porte de sortie.'
                                        : 'Vérifier que le conteneur a été déposé et que le plateau est vide avant validation.',
                                    style: pw.TextStyle(
                                      fontSize: 6,
                                      color: entryKind == 'empty' ? PdfColor.fromHex('#78350f') : PdfColor.fromHex('#14532d'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 8),

              // ==========================================
              // 5. ZONES D'ÉMARGEMENT & DE CONTRÔLE (3 CADRES)
              // ==========================================
              pw.Row(
                children: [
                  _signatureBox(
                    title: '1. POSTE ENTRÉE',
                    subtitle: 'Contrôle accès Gate-In',
                    field1: 'Date/Heure : ${formatDateTime(createdAt)}',
                    field2: 'Visa Agent : Conformité OK',
                    accentColor: navy,
                  ),
                  pw.SizedBox(width: 6),
                  _signatureBox(
                    title: '2. OPÉRATION PARC (YARD)',
                    subtitle: 'Manutention & Levage',
                    field1: position.isNotEmpty ? 'Position : $position' : 'Emplacement : [            ]',
                    field2: 'Engin N° : [           ]',
                    accentColor: amber,
                  ),
                  pw.SizedBox(width: 6),
                  _signatureBox(
                    title: '3. POSTE SORTIE (GATE-OUT)',
                    subtitle: 'Contrôle final & Clôture',
                    field1: 'Heure sortie : ___ : ___',
                    field2: 'Contrôle : [  ] Châssis  [  ] Scellé',
                    accentColor: emerald,
                  ),
                ],
              ),

              pw.Spacer(),

              // ==========================================
              // 6. FOOTER LÉGAL & SÉCURITÉ
              // ==========================================
              pw.Divider(thickness: 0.6, color: borderGray),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Document opérationnel officiel TCZ Tanger Med · Valable pour une seule rotation.',
                    style: pw.TextStyle(fontSize: 5.5, color: muted),
                  ),
                  pw.Text(
                    'Système N4 TOS · Pointage Sécurisé',
                    style: pw.TextStyle(fontSize: 5.5, fontWeight: pw.FontWeight.bold, color: navy),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _th(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
      child: pw.Text(
        label,
        style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#334155')),
      ),
    );
  }

  static pw.Widget _td(String text, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: PdfColor.fromHex('#0f172a'),
        ),
      ),
    );
  }

  static pw.Widget _tdContainer(String number, String entryKind) {
    if (number.isNotEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(
          number,
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#075a8d')),
        ),
      );
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        entryKind == 'empty' ? 'EN ATTENTE YARD (PRISE)' : 'NON RENSEIGNÉ',
        style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#d97706')),
      ),
    );
  }

  static pw.Widget _tdPosition(String position, String entryKind, String kind) {
    if (position.isNotEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(
          position,
          style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#16a34a')),
        ),
      );
    }
    final label = entryKind == 'empty'
        ? 'À désigner en Yard'
        : (kind == 'ENTREE' ? 'En attente engin' : 'N/A');
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        label,
        style: pw.TextStyle(fontSize: 6.5, color: PdfColor.fromHex('#64748b')),
      ),
    );
  }

  static pw.Widget _signatureBox({
    required String title,
    required String subtitle,
    required String field1,
    required String field2,
    required PdfColor accentColor,
  }) {
    return pw.Expanded(
      child: pw.Container(
        height: 68,
        padding: const pw.EdgeInsets.all(5),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(5),
          border: pw.Border.all(color: PdfColor.fromHex('#cbd5e1'), width: 0.7),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: accentColor)),
                pw.Text(subtitle, style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey700)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(field1, style: const pw.TextStyle(fontSize: 6, color: PdfColors.black)),
                pw.SizedBox(height: 1),
                pw.Text(field2, style: const pw.TextStyle(fontSize: 6, color: PdfColors.black)),
              ],
            ),
            pw.Container(
              height: 12,
              alignment: pw.Alignment.bottomRight,
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
              ),
              child: pw.Text('Cachet / Visa', style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey500)),
            ),
          ],
        ),
      ),
    );
  }
}
