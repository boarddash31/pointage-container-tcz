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
      return "20' Standard Dry (8'6)";
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
    if (rawIso == null || rawIso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(rawIso).toLocal();
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final year = dt.year.toString();
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$day/$month/$year a $hour:$minute';
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

    final plate = (visitData?['plate'] ?? snapshot['plate'] ?? '-').toString().toUpperCase();
    final cin = (visitData?['driver_cin'] ?? snapshot['driver_cin'] ?? '-').toString().toUpperCase();
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

    final isAnnulation = kind == 'ANNULATION';
    final cancelReason = (visitData?['cancel_reason'] ??
            event['reason'] ??
            snapshot['cancel_reason'] ??
            'Sortie sans depose de conteneur')
        .toString();

    // Title mapping
    String docTitle;
    PdfColor docColor;
    if (kind == 'ENTREE') {
      docTitle = "BON D'ENTREE (GATE-IN)";
      docColor = navy;
    } else if (kind == 'SORTIE') {
      docTitle = 'BON DE SORTIE (GATE-OUT)';
      docColor = emerald;
    } else if (kind == 'ANNULATION') {
      docTitle = "BON D'ANNULATION (SORTIE SANS DEPOSE)";
      docColor = PdfColor.fromHex('#dc2626');
    } else {
      docTitle = 'BON TCZ - $kind';
      docColor = navy;
    }

    // QR Payload for security scanning at gate-out
    final qrPayload = 'TCZ|ZENATA|DOC:$docId|VISIT:$visitId|PLATE:$plate|KIND:$kind|ARM:$armateur|CONT:${containerNumber.isEmpty ? 'NONE' : containerNumber}';

    // Safe short visit ID without unicode ellipsis
    final shortVisitId = visitId.length > 8 ? '${visitId.substring(0, 8)}...' : visitId;
    final shortDocId = docId.length > 8 ? docId.substring(0, 8).toUpperCase() : docId;

    // Load visual image assets safely (both empty and loaded for dual comparison)
    pw.MemoryImage? logoImg;
    pw.MemoryImage? truckEmptyImg;
    pw.MemoryImage? truckLoadedImg;

    try {
      final logoBytes = await rootBundle.load('assets/brand/tcz-logo.png');
      logoImg = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

    try {
      final emptyBytes = await rootBundle.load('assets/truck-empty.png');
      truckEmptyImg = pw.MemoryImage(emptyBytes.buffer.asUint8List());
    } catch (_) {}

    try {
      final loadedBytes = await rootBundle.load('assets/truck-loaded.png');
      truckLoadedImg = pw.MemoryImage(loadedBytes.buffer.asUint8List());
    } catch (_) {}

    final bool isEntryEmpty = entryKind == 'empty';
    final pw.MemoryImage? entryImg = isEntryEmpty ? truckEmptyImg : truckLoadedImg;
    final pw.MemoryImage? exitImg = isEntryEmpty ? truckLoadedImg : truckEmptyImg;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ==========================================
              // 1. HEADER: TERMINAL CONTENEURS ZENATA
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
                          pw.Image(logoImg, width: 88, height: 26, fit: pw.BoxFit.contain)
                        else
                          pw.Text('TCZ',
                              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: navy)),
                        pw.SizedBox(height: 2),
                        pw.Text('TERMINAL CONTENEURS ZENATA',
                            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: darkNavy)),
                        pw.Text('TCZ ZENATA - GUICHET UNIQUE & CONTROLE D\'ACCES',
                            style: pw.TextStyle(fontSize: 5.5, color: muted)),
                      ],
                    ),
                  ),

                  // Document Badge
                  pw.Expanded(
                    flex: 5,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
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
                            'Ref: #$shortDocId',
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
                    // Camion Plate
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

                    // Visite ID (clean, no tofu)
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('NO. DE VISITE',
                              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: muted)),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            shortVisitId,
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
              // 3. TABLEAU DES CONTENEURS (SANS STEP YARD)
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
                    0: pw.FlexColumnWidth(3.4), // Container
                    1: pw.FlexColumnWidth(1.6), // ISO
                    2: pw.FlexColumnWidth(2.8), // Description
                    3: pw.FlexColumnWidth(2.2), // Booking
                    4: pw.FlexColumnWidth(2.0), // Operation Statut
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
                        _th('STATUT ENTREE'),
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
                            : (entryKind == 'loaded' ? 'Depose directe' : 'Non requis')),
                        _td(entryKind == 'loaded' ? 'Plein (Depose)' : 'Vide (Prise)', isBold: true),
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
                              : (entryKind == 'loaded' ? 'Depose directe' : 'Non requis')),
                          _td(entryKind == 'loaded' ? 'Plein (Depose)' : 'Vide (Prise)', isBold: true),
                        ],
                      ),
                  ],
                ),
              ),

              pw.SizedBox(height: 6),

              // ==========================================
              // 4. VISUELS ROTATION TCZ : ENTREE VS SORTIE
              // ==========================================
              pw.Container(
                padding: const pw.EdgeInsets.all(5),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderGray, width: 0.8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    // Titre Bandeau Rotation
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      decoration: pw.BoxDecoration(
                        color: isAnnulation ? PdfColor.fromHex('#fee2e2') : PdfColor.fromHex('#e2e8f0'),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            isAnnulation
                                ? 'CONTROLE D\'EXCEPTION : SORTIE SANS DEPOSE'
                                : 'CONTROLE VISUEL DE ROTATION (TERMINAL TCZ ZENATA)',
                            style: pw.TextStyle(
                              fontSize: 6.5,
                              fontWeight: pw.FontWeight.bold,
                              color: isAnnulation ? PdfColor.fromHex('#991b1b') : darkNavy,
                            ),
                          ),
                          pw.Text(
                            isAnnulation
                                ? 'VISA SUPERVISEUR CODE 01010909 : VALIDE'
                                : (isEntryEmpty
                                    ? 'MISSION : PRISE DE CONTENEUR'
                                    : 'MISSION : DEPOSE DE CONTENEUR'),
                            style: pw.TextStyle(
                              fontSize: 6.5,
                              fontWeight: pw.FontWeight.bold,
                              color: isAnnulation ? PdfColor.fromHex('#dc2626') : (isEntryEmpty ? amber : emerald),
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 4),

                    // Visual Comparison: Left (Constat Entree) -> Center (Arrow) -> Right (Controle Sortie Exige)
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        // 1. CARTE ENTREE (GATE-IN)
                        pw.Expanded(
                          flex: 5,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              borderRadius: pw.BorderRadius.circular(5),
                              border: pw.Border.all(
                                color: isEntryEmpty ? amber : navy,
                                width: 0.8,
                              ),
                            ),
                            child: pw.Column(
                              children: [
                                pw.Container(
                                  width: double.infinity,
                                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                                  decoration: pw.BoxDecoration(
                                    color: isEntryEmpty ? lightAmber : lightBlue,
                                    borderRadius: pw.BorderRadius.circular(3),
                                  ),
                                  child: pw.Text(
                                    '1. CONSTAT ENTREE (GATE-IN)',
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(
                                      fontSize: 6,
                                      fontWeight: pw.FontWeight.bold,
                                      color: isEntryEmpty ? amber : navy,
                                    ),
                                  ),
                                ),
                                pw.SizedBox(height: 3),
                                if (entryImg != null)
                                  pw.Image(entryImg, height: 35, fit: pw.BoxFit.contain)
                                else
                                  pw.Container(
                                    height: 35,
                                    alignment: pw.Alignment.center,
                                    child: pw.Text(
                                      isEntryEmpty ? '[ CHASSIS NU ]' : '[ CAMION CHARGE ]',
                                      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: navy),
                                    ),
                                  ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  isEntryEmpty ? 'CHASSIS NU (VIDE)' : 'CAMION CHARGE',
                                  style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: ink),
                                ),
                                pw.Text(
                                  isEntryEmpty ? 'Arrive sans conteneur' : 'Conteneur a decharger',
                                  style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // 2. FLECHE DE ROTATION
                        pw.Expanded(
                          flex: 2,
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              pw.Text(
                                isAnnulation ? 'ANNULATION' : 'ROTATION',
                                style: pw.TextStyle(fontSize: 5.5, fontWeight: pw.FontWeight.bold, color: muted),
                              ),
                              pw.SizedBox(height: 1),
                              pw.Text(
                                isAnnulation ? '<<<<<' : '>>>>>',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: isAnnulation ? PdfColor.fromHex('#dc2626') : navy,
                                ),
                              ),
                              pw.SizedBox(height: 1),
                              pw.Text(
                                isAnnulation
                                    ? 'RESSORTI'
                                    : (isEntryEmpty ? 'PRISE' : 'DEPOSE'),
                                style: pw.TextStyle(
                                  fontSize: 5.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: isAnnulation ? PdfColor.fromHex('#dc2626') : (isEntryEmpty ? amber : emerald),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 3. CARTE SORTIE EXIGEE (GATE-OUT)
                        pw.Expanded(
                          flex: 5,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              borderRadius: pw.BorderRadius.circular(5),
                              border: pw.Border.all(
                                color: isAnnulation ? PdfColor.fromHex('#dc2626') : emerald,
                                width: 1.2,
                              ),
                            ),
                            child: pw.Column(
                              children: [
                                pw.Container(
                                  width: double.infinity,
                                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                                  decoration: pw.BoxDecoration(
                                    color: isAnnulation ? PdfColor.fromHex('#fee2e2') : lightEmerald,
                                    borderRadius: pw.BorderRadius.circular(3),
                                  ),
                                  child: pw.Text(
                                    isAnnulation
                                        ? '2. SORTIE AUTORISEE (ANNULATION)'
                                        : '2. CONTROLE SORTIE EXIGE (GATE-OUT)',
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(
                                      fontSize: 6,
                                      fontWeight: pw.FontWeight.bold,
                                      color: isAnnulation ? PdfColor.fromHex('#dc2626') : emerald,
                                    ),
                                  ),
                                ),
                                pw.SizedBox(height: 3),
                                if ((isAnnulation ? entryImg : exitImg) != null)
                                  pw.Image((isAnnulation ? entryImg : exitImg)!, height: 35, fit: pw.BoxFit.contain)
                                else
                                  pw.Container(
                                    height: 35,
                                    alignment: pw.Alignment.center,
                                    child: pw.Text(
                                      isAnnulation
                                          ? '[ SORTIE SANS DEPOSE ]'
                                          : (isEntryEmpty ? '[ DOIT SORTIR CHARGE ]' : '[ DOIT SORTIR VIDE ]'),
                                      style: pw.TextStyle(
                                        fontSize: 7,
                                        fontWeight: pw.FontWeight.bold,
                                        color: isAnnulation ? PdfColor.fromHex('#dc2626') : emerald,
                                      ),
                                    ),
                                  ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  isAnnulation
                                      ? 'SORTIE SANS DEPOSE'
                                      : (isEntryEmpty ? 'DOIT SORTIR CHARGE' : 'DOIT SORTIR VIDE (CHASSIS NU)'),
                                  style: pw.TextStyle(
                                    fontSize: 6.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: isAnnulation ? PdfColor.fromHex('#dc2626') : emerald,
                                  ),
                                ),
                                pw.Text(
                                  isAnnulation
                                      ? 'Ressorti avec son conteneur'
                                      : (isEntryEmpty ? 'Conteneur assigne + scelle' : 'Plateau verifie vide'),
                                  style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    pw.SizedBox(height: 4),

                    // Directive / Consigne de securite Gate-Out
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: isAnnulation
                            ? PdfColor.fromHex('#fee2e2')
                            : (isEntryEmpty ? lightAmber : lightEmerald),
                        borderRadius: pw.BorderRadius.circular(4),
                        border: pw.Border.all(
                          color: isAnnulation
                              ? PdfColor.fromHex('#dc2626')
                              : (isEntryEmpty ? amber : emerald),
                          width: 0.6,
                        ),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Text(
                            isAnnulation
                                ? '[ ALERTE SECURITE - SORTIE SANS DEPOSE ] : '
                                : '[ DIRECTIVE SORTIE ] : ',
                            style: pw.TextStyle(
                              fontSize: 6.5,
                              fontWeight: pw.FontWeight.bold,
                              color: isAnnulation
                                  ? PdfColor.fromHex('#991b1b')
                                  : (isEntryEmpty ? PdfColor.fromHex('#92400e') : PdfColor.fromHex('#166534')),
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              isAnnulation
                                  ? 'Motif : $cancelReason. Sortie autorisee par Superviseur (Code 01010909). Le camion ressort avec son chargement sans dechargement en yard.'
                                  : (isEntryEmpty
                                      ? 'Le camion est entre a vide. Verifier obligatoirement le conteneur charge et le scelle avant barriere.'
                                      : 'Le camion est entre charge. Verifier imperativement que le plateau est completement vide avant barriere.'),
                              style: pw.TextStyle(
                                fontSize: 6,
                                color: isAnnulation
                                    ? PdfColor.fromHex('#7f1d1d')
                                    : (isEntryEmpty ? PdfColor.fromHex('#78350f') : PdfColor.fromHex('#14532d')),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 8),

              // ==========================================
              // 5. ZONES D'EMARGEMENT: 2 CADRES (ENTREE & SORTIE NICHAN)
              // ==========================================
              pw.Row(
                children: [
                  _signatureBox(
                    title: '1. POSTE ENTREE (GATE-IN)',
                    subtitle: 'Controle acces & saisie initiale',
                    field1: 'Date / Heure : ${formatDateTime(createdAt)}',
                    field2: 'Visa Agent : Conformite validee [ OK ]',
                    accentColor: navy,
                  ),
                  pw.SizedBox(width: 10),
                  _signatureBox(
                    title: isAnnulation ? '2. VISA SUPERVISEUR TCZ' : '2. POSTE SORTIE (GATE-OUT)',
                    subtitle: isAnnulation ? 'Autorisation code 01010909' : 'Controle final & autorisation de passage',
                    field1: isAnnulation ? 'Motif : $cancelReason' : 'Heure effective de sortie : ___ : ___',
                    field2: isAnnulation ? 'Decision : Sortie sans decharge [ OK ]' : 'Controle de conformite : [  ] Chassis   [  ] Scelle',
                    accentColor: isAnnulation ? PdfColor.fromHex('#dc2626') : emerald,
                  ),
                ],
              ),

              pw.Spacer(),

              // ==========================================
              // 6. FOOTER: TCZ ZENATA
              // ==========================================
              pw.Divider(thickness: 0.6, color: borderGray),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Document operationnel officiel TCZ Zenata - Valable pour une seule rotation.',
                    style: pw.TextStyle(fontSize: 5.5, color: muted),
                  ),
                  pw.Text(
                    'Terminal Conteneurs Zenata - Pointage Securise',
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
        entryKind == 'empty' ? 'EN ATTENTE CHARGEMENT (PRISE)' : 'NON RENSEIGNE',
        style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#d97706')),
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
        height: 72,
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: PdfColor.fromHex('#cbd5e1'), width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: accentColor)),
                pw.Text(subtitle, style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey700)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(field1, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.black)),
                pw.SizedBox(height: 2),
                pw.Text(field2, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.black)),
              ],
            ),
            pw.Container(
              height: 14,
              alignment: pw.Alignment.bottomRight,
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
              ),
              child: pw.Text('Cachet / Visa de l\'agent', style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey500)),
            ),
          ],
        ),
      ),
    );
  }
}
