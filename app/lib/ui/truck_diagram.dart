import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../domain/container_number.dart';
import '../domain/truck_plate.dart';

/// Four gate states share the same chassis: loaded/empty, mono/twin.
/// Visualizes the Moroccan truck with 3-part license plate, CIN, 11-char container slots, and 4-char ISO slots.
class TruckScene extends StatelessWidget {
  const TruckScene({
    super.key,
    required this.kind,
    this.height = 125,
    this.width,
    this.isTwin = false,
    this.plate,
    this.driverCin,
    this.containerNumber,
    this.iso,
    this.operator,
    this.containerNumber2,
    this.iso2,
    this.operator2,
    this.booking,
    this.booking2,
    this.activeContainerIndex,
    this.showUnknown = false,
    this.highlightMissing = false,
    this.onPlateTap,
    this.onCinTap,
    this.onContainerNumberTap,
    this.onIsoTap,
    this.onLineTap,
    this.onContainerTap,
  });

  final String kind;
  final double height;
  final double? width;
  final bool isTwin, showUnknown, highlightMissing;
  final int? activeContainerIndex;
  final String? plate;
  final String? driverCin;
  final String? containerNumber, iso, operator, containerNumber2, iso2, operator2;
  final String? booking, booking2;
  final VoidCallback? onPlateTap;
  final VoidCallback? onCinTap;
  final ValueChanged<int>? onContainerNumberTap;
  final ValueChanged<int>? onIsoTap;
  final ValueChanged<int>? onLineTap;
  final ValueChanged<int>? onContainerTap;

  @override
  Widget build(BuildContext context) {
    final empty = kind == 'empty' || kind == 'depose';
    final twin = isTwin || containerNumber2 != null || iso2 != null || operator2 != null;
    return Semantics(
      label: '${empty ? 'Camion sans conteneur, emplacement prévu' : 'Camion chargé'} : '
        '${twin ? 'deux conteneurs' : 'un conteneur'}'
        '${plate?.trim().isNotEmpty == true ? ', plaque $plate' : ''}'
        '${driverCin?.trim().isNotEmpty == true ? ', CIN $driverCin' : ''}',
      child: SizedBox(
        width: width ?? height * 2.5,
        height: height,
        child: LayoutBuilder(builder: (context, constraints) {
          final diagram = CustomPaint(painter: _TruckPainter(
            empty: empty, twin: twin, compact: height <= 85,
            unknown: showUnknown, plate: plate, driverCin: driverCin,
            highlightMissing: highlightMissing,
            activeContainerIndex: activeContainerIndex,
            numbers: [containerNumber, containerNumber2],
            bookings: [booking, booking2],
            codes: [iso, iso2], lines: [operator, operator2],
          ));
          if (onPlateTap == null && onCinTap == null && onContainerNumberTap == null &&
              onIsoTap == null && onLineTap == null && onContainerTap == null) {
            return diagram;
          }
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                const scene = Size(300, 120);
                final scale = math.min(constraints.maxWidth / scene.width,
                  constraints.maxHeight / scene.height);
                final x = (details.localPosition.dx -
                  (constraints.maxWidth - scene.width * scale) / 2) / scale;
                final y = (details.localPosition.dy -
                  (constraints.maxHeight - scene.height * scale) / 2) / scale;

                // 1. Truck Cab Taps
                if (x >= 4 && x <= 80) {
                  if (y >= 40 && y < 74) {
                    (onCinTap ?? onPlateTap)?.call();
                  } else {
                    onPlateTap?.call();
                  }
                }
                // 2. Container Taps
                else if (x >= 85 && x <= 295 && y >= 18 && y <= 88) {
                  final index = twin && x >= 190 ? 1 : 0;
                  if (y >= 18 && y < 45) {
                    (onContainerNumberTap ?? onContainerTap)?.call(index);
                  } else if (y >= 45 && y < 65) {
                    (onIsoTap ?? onContainerTap)?.call(index);
                  } else {
                    (onLineTap ?? onContainerTap)?.call(index);
                  }
                }
              },
              child: diagram,
            ),
          );
        }),
      ),
    );
  }
}

class _TruckPainter extends CustomPainter {
  const _TruckPainter({
    required this.empty,
    required this.twin,
    required this.compact,
    required this.unknown,
    required this.plate,
    this.driverCin,
    this.activeContainerIndex,
    required this.numbers,
    required this.codes,
    required this.lines,
    required this.bookings,
    required this.highlightMissing,
  });

  final bool empty, twin, compact, unknown, highlightMissing;
  final int? activeContainerIndex;
  final String? plate;
  final String? driverCin;
  final List<String?> numbers, bookings, codes, lines;

  @override
  void paint(Canvas canvas, Size size) {
    const scene = Size(300, 120);
    final scale = math.min(size.width / scene.width, size.height / scene.height);
    canvas.save();
    canvas.translate((size.width - scene.width * scale) / 2,
      (size.height - scene.height * scale) / 2);
    canvas.scale(scale);

    const navy = Color(0xff103c63);
    final metal = Paint()..color = const Color(0xff7894a6);
    canvas.drawOval(const Rect.fromLTWH(9, 109, 285, 5),
      Paint()..color = navy.withValues(alpha: .09));

    // Trailer, suspension, reflectors and rear bogie
    _box(canvas, const Rect.fromLTWH(70, 84, 223, 7), const Color(0xff223d50), 2);
    _box(canvas, const Rect.fromLTWH(88, 92, 195, 3), const Color(0xff8ea5b2), 1);
    for (final x in [96.0, 155.0, 215.0, 280.0]) {
      _box(canvas, Rect.fromLTWH(x, 86, 5, 2), const Color(0xffffb74d), .6);
    }
    _box(canvas, const Rect.fromLTWH(290, 85, 3, 7), const Color(0xffd64545), 1);
    for (final x in [40.0, 228.0, 265.0]) {
      canvas.drawCircle(Offset(x, 99), 12, Paint()..color = const Color(0xff172a38));
      canvas.drawCircle(Offset(x, 99), 7.5, Paint()..color = const Color(0xffa7bac5));
      canvas.drawCircle(Offset(x, 99), 4.5, Paint()..color = const Color(0xffeaf0f4));
      canvas.drawCircle(Offset(x, 99), 1.8, metal);
    }

    // Cab: sloped windscreen, tall cab and door
    final cab = Path()
      ..moveTo(6, 91)..lineTo(6, 62)..lineTo(18, 38)
      ..quadraticBezierTo(20, 34, 27, 34)..lineTo(65, 34)
      ..quadraticBezierTo(73, 34, 73, 42)..lineTo(73, 91)..close();
    canvas.drawPath(cab, Paint()..color = navy);

    final door = Path()
      ..moveTo(11, 72)..lineTo(11, 62)..lineTo(22, 42)
      ..lineTo(65, 42)..lineTo(65, 75)..lineTo(11, 75)..close();
    canvas.drawPath(door, Paint()..color = const Color(0xffe8f3f9));

    final windshield = Path()
      ..moveTo(15, 60)..lineTo(24, 44)..lineTo(41, 44)
      ..lineTo(41, 61)..lineTo(15, 61)..close();
    canvas.drawPath(windshield, Paint()..color = const Color(0xff367da5));
    _box(canvas, const Rect.fromLTWH(45, 44, 16, 17), const Color(0xff367da5), 2);
    canvas.drawLine(const Offset(47, 45), const Offset(58, 45),
      Paint()..color = const Color(0xff92d5f0)..strokeWidth = 1.5);
    _box(canvas, const Rect.fromLTWH(51, 65, 9, 2), navy, 1);

    // 1. CIN Chauffeur (door badge)
    final hasCin = driverCin?.trim().isNotEmpty == true;
    final cinRect = const Rect.fromLTWH(11, 61, 44, 12);
    final cinBorder = (highlightMissing && !hasCin)
        ? const Color(0xffef4444)
        : const Color(0xff0284c7);
    _box(canvas, cinRect, hasCin ? Colors.white : (highlightMissing ? const Color(0xfffef2f2) : const Color(0xfff0f9ff)), 2);
    canvas.drawRRect(RRect.fromRectAndRadius(cinRect, const Radius.circular(2)),
      Paint()..color = cinBorder..style = PaintingStyle.stroke..strokeWidth = hasCin ? .8 : 1.2);
    final cinText = hasCin ? driverCin!.trim().toUpperCase() : 'CIN *';
    _text(canvas, cinText, cinRect.deflate(1), hasCin ? navy : cinBorder, 6.5, 1, bold: true);

    _box(canvas, const Rect.fromLTWH(2, 58, 4, 13), navy, 1);
    _box(canvas, const Rect.fromLTWH(3, 90, 74, 5), const Color(0xff233c4d), 2);
    _box(canvas, const Rect.fromLTWH(6, 86, 5, 4), const Color(0xffffcc70), 1);

    // 2. Moroccan License Plate (3 distinct divisions: [Serial] | [Letter] | [Region])
    _drawMoroccanPlate(canvas, const Rect.fromLTWH(10, 75, 62, 14));

    // 3. Container Slots
    final count = twin ? 2 : 1;
    for (var i = 0; i < count; i++) {
      final rect = twin
        ? Rect.fromLTWH(88 + i * 102, 20, 98, 66)
        : const Rect.fromLTWH(88, 20, 200, 66);
      _drawSlot(canvas, rect, i);
    }
    canvas.restore();
  }

  void _drawMoroccanPlate(Canvas canvas, Rect plateArea) {
    final parts = TruckPlate.parseParts(plate ?? '');
    final serial = parts.$1.trim();
    final letter = parts.$2.trim();
    final region = parts.$3.trim();
    final isComplete = serial.isNotEmpty && letter.isNotEmpty && region.isNotEmpty;
    final hasAny = serial.isNotEmpty || letter.isNotEmpty || region.isNotEmpty;

    final borderColor = (highlightMissing && !isComplete)
        ? const Color(0xffef4444)
        : const Color(0xff0f172a);

    // Plate background
    _box(canvas, plateArea, Colors.white, 2);
    canvas.drawRRect(RRect.fromRectAndRadius(plateArea, const Radius.circular(2)),
      Paint()..color = borderColor..style = PaintingStyle.stroke..strokeWidth = (!isComplete && highlightMissing) ? 1.4 : 1.0);

    // Division 1: Serial digits (~50% width)
    final d1 = Rect.fromLTWH(plateArea.left + 1, plateArea.top + 1, 29, plateArea.height - 2);
    _text(canvas, serial.isNotEmpty ? serial : '----', d1,
      serial.isNotEmpty ? Colors.black : const Color(0xff94a3b8), 7.8, 1, bold: true);

    // Divider 1
    canvas.drawLine(Offset(plateArea.left + 30.5, plateArea.top + 1.5),
      Offset(plateArea.left + 30.5, plateArea.bottom - 1.5),
      Paint()..color = const Color(0xff334155)..strokeWidth = .8);

    // Division 2: Letter (~24% width)
    final d2 = Rect.fromLTWH(plateArea.left + 31, plateArea.top + 1, 14, plateArea.height - 2);
    _text(canvas, letter.isNotEmpty ? letter : '·', d2,
      letter.isNotEmpty ? Colors.black : const Color(0xff94a3b8), 7.8, 1, bold: true);

    // Divider 2
    canvas.drawLine(Offset(plateArea.left + 45.5, plateArea.top + 1.5),
      Offset(plateArea.left + 45.5, plateArea.bottom - 1.5),
      Paint()..color = const Color(0xff334155)..strokeWidth = .8);

    // Division 3: Region code (~26% width)
    final d3 = Rect.fromLTWH(plateArea.left + 46, plateArea.top + 1, 15, plateArea.height - 2);
    _text(canvas, region.isNotEmpty ? region : '--', d3,
      region.isNotEmpty ? Colors.black : const Color(0xff94a3b8), 7.8, 1, bold: true);

    // Required badge if missing
    if (highlightMissing && !hasAny) {
      final badge = Rect.fromLTWH(plateArea.left + 8, plateArea.top - 5, 46, 6);
      _box(canvas, badge, const Color(0xffef4444), 2);
      _text(canvas, 'PLAQUE *', badge, Colors.white, 4.5, 0.5, bold: true);
    }
  }

  void _drawSlot(Canvas canvas, Rect rect, int index) {
    final outline = RRect.fromRectAndRadius(rect, const Radius.circular(3.5));
    final value = empty ? bookings[index]?.trim() : numbers[index]?.trim();
    final code = codes[index]?.trim().toUpperCase() ?? '';
    final line = lines[index]?.trim() ?? '';

    final has11Chars = !empty && value != null && value.length == 11;
    final is11Valid = has11Chars && ContainerNumber.isValid(value);
    final has4Iso = code.length == 4;
    final hasLine = line.isNotEmpty;

    final missing = highlightMissing && (!empty ? (!has11Chars || !has4Iso || !hasLine) : (value == null || value.isEmpty || !has4Iso || !hasLine));
    final isActive = twin && activeContainerIndex == index;
    final borderColor = isActive
        ? const Color(0xff38bdf8)
        : (empty ? const Color(0xff0284c7) : const Color(0xff991b1b));

    if (isActive) {
      final glowRing = RRect.fromRectAndRadius(rect.inflate(2.5), const Radius.circular(5.5));
      canvas.drawRRect(glowRing, Paint()
        ..color = const Color(0xff38bdf8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4);
    }

    if (!empty) {
      // Corrugated metallic red container
      canvas.drawRRect(outline, Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: isActive
          ? const [Color(0xfff87171), Color(0xffb91c1c)]
          : const [Color(0xffdc2626), Color(0xff991b1b)],
      ).createShader(rect));
      canvas.drawRRect(outline, Paint()..color = borderColor
        ..style = PaintingStyle.stroke..strokeWidth = isActive ? 2.0 : (missing ? 1.5 : 1.0));

      // Corrugation ribs
      for (var x = rect.left + 7; x < rect.right - 4; x += 8) {
        canvas.drawLine(Offset(x, rect.top + 3), Offset(x, rect.bottom - 3),
          Paint()..color = const Color(0xff7f1d1d).withValues(alpha: .28)..strokeWidth = 1.8);
        canvas.drawLine(Offset(x + 1, rect.top + 3), Offset(x + 1, rect.bottom - 3),
          Paint()..color = Colors.white.withValues(alpha: .12)..strokeWidth = .6);
      }
      // Corner castings
      for (final x in [rect.left + 2, rect.right - 5]) {
        for (final y in [rect.top + 2, rect.bottom - 5]) {
          _box(canvas, Rect.fromLTWH(x, y, 3, 3), const Color(0xfffecaca), .5);
        }
      }
    } else {
      // Empty container chassis outline
      canvas.drawRRect(outline, Paint()..color = isActive ? const Color(0xffe0f2fe) : const Color(0xfff0f9ff));
      final stroke = Paint()
        ..color = borderColor
        ..strokeWidth = isActive ? 2.0 : 1.3
        ..style = PaintingStyle.stroke;
      const dash = 6.0;
      for (var x = rect.left + 4; x < rect.right - 4; x += dash * 1.5) {
        canvas.drawLine(Offset(x, rect.top), Offset(math.min(x + dash, rect.right - 4), rect.top), stroke);
        canvas.drawLine(Offset(x, rect.bottom), Offset(math.min(x + dash, rect.right - 4), rect.bottom), stroke);
      }
      canvas.drawLine(rect.topLeft, rect.bottomLeft, stroke);
      canvas.drawLine(rect.topRight, rect.bottomRight, stroke);
    }

    // Dim inactive slot in twin mode so active slot pops out
    if (twin && activeContainerIndex != null && !isActive) {
      canvas.drawRRect(outline, Paint()..color = Colors.black.withValues(alpha: 0.16));
    }

    // Top indicator pill (Active or Missing)
    if (isActive) {
      final activeBadge = Rect.fromLTWH(rect.center.dx - 22, rect.top - 5.5, 44, 6.5);
      _box(canvas, activeBadge, const Color(0xff0284c7), 2);
      _text(canvas, 'EN SAISIE ⛶', activeBadge, Colors.white, 4.0, 0.5, bold: true);
    } else if (missing) {
      final pill = Rect.fromLTWH(rect.center.dx - 18, rect.top - 4, 36, 5);
      _box(canvas, pill, const Color(0xffef4444), 2);
      _text(canvas, 'INCOMPLET *', pill, Colors.white, 3.8, 0.5, bold: true);
    }

    // =========================================================================
    // ROW 1: 11 CHARACTER CONTAINER NUMBER SLOTS (or Booking if empty)
    // =========================================================================
    if (!empty) {
      final numStr = value ?? '';
      if (!twin) {
        // MONO CONTAINER (Width: 200) -> 11 Distinct Interactive Character Slots
        const slotW = 12.5;
        const slotH = 16.0;
        const gap = 2.0;
        const groupGap = 5.0;
        // 4 owner + groupGap + 6 serial + groupGap + 1 check digit = 159px
        const totalW = 4 * slotW + 3 * gap + groupGap + 6 * slotW + 5 * gap + groupGap + slotW;
        final startX = rect.left + (rect.width - totalW) / 2;
        final slotY = rect.top + 8;

        for (int k = 0; k < 11; k++) {
          double x;
          if (k < 4) {
            x = startX + k * (slotW + gap);
          } else if (k < 10) {
            x = startX + 4 * (slotW + gap) - gap + groupGap + (k - 4) * (slotW + gap);
          } else {
            x = startX + 4 * (slotW + gap) - gap + groupGap + 6 * (slotW + gap) - gap + groupGap;
          }
          final sRect = Rect.fromLTWH(x, slotY, slotW, slotH);
          final ch = k < numStr.length ? numStr[k] : '';
          final hasCh = ch.isNotEmpty;

          // Slot styling
          Color slotBg = hasCh ? const Color(0xff0f172a) : const Color(0x55000000);
          Color slotBorder;
          if (hasCh) {
            if (k < 4) {
              slotBorder = const Color(0xff38bdf8); // Sky for letters
            } else if (k < 10) {
              slotBorder = const Color(0xffcbd5e1); // Silver for serial
            } else {
              slotBorder = is11Valid ? const Color(0xff10b981) : const Color(0xfff59e0b); // Green/amber check digit
            }
          } else {
            slotBorder = highlightMissing ? const Color(0xffef4444) : const Color(0x66ffffff);
          }

          _box(canvas, sRect, slotBg, 2.5);
          canvas.drawRRect(RRect.fromRectAndRadius(sRect, const Radius.circular(2.5)),
            Paint()..color = slotBorder..style = PaintingStyle.stroke..strokeWidth = hasCh ? 1.0 : 0.8);
          _text(canvas, hasCh ? ch : '·', sRect,
            hasCh ? (k == 10 ? const Color(0xfffbbf24) : Colors.white) : const Color(0xff94a3b8),
            9.2, 1.8, bold: true);
        }
      } else {
        // TWIN CONTAINER (Width: 98) -> Compact 11 Slots
        const slotW = 6.8;
        const slotH = 13.0;
        const gap = 1.0;
        const groupGap = 2.5;
        const totalW = 4 * slotW + 3 * gap + groupGap + 6 * slotW + 5 * gap + groupGap + slotW;
        final startX = rect.left + (rect.width - totalW) / 2;
        final slotY = rect.top + 7;

        for (int k = 0; k < 11; k++) {
          double x;
          if (k < 4) {
            x = startX + k * (slotW + gap);
          } else if (k < 10) {
            x = startX + 4 * (slotW + gap) - gap + groupGap + (k - 4) * (slotW + gap);
          } else {
            x = startX + 4 * (slotW + gap) - gap + groupGap + 6 * (slotW + gap) - gap + groupGap;
          }
          final sRect = Rect.fromLTWH(x, slotY, slotW, slotH);
          final ch = k < numStr.length ? numStr[k] : '';
          final hasCh = ch.isNotEmpty;

          Color slotBg = hasCh ? const Color(0xff0f172a) : const Color(0x55000000);
          Color slotBorder = hasCh
              ? (k == 10 && is11Valid ? const Color(0xff10b981) : const Color(0xffcbd5e1))
              : (highlightMissing ? const Color(0xffef4444) : const Color(0x66ffffff));

          _box(canvas, sRect, slotBg, 1.5);
          canvas.drawRRect(RRect.fromRectAndRadius(sRect, const Radius.circular(1.5)),
            Paint()..color = slotBorder..style = PaintingStyle.stroke..strokeWidth = .7);
          _text(canvas, hasCh ? ch : '·', sRect,
            hasCh ? Colors.white : const Color(0xff94a3b8), 7.2, 1, bold: true);
        }
      }
    } else {
      // EMPTY CONTAINER: Booking Banner
      final bookRect = Rect.fromLTWH(rect.left + 8, rect.top + 7, rect.width - 16, twin ? 13 : 16);
      final hasBook = value != null && value.isNotEmpty;
      _box(canvas, bookRect, hasBook ? const Color(0xff0369a1) : (highlightMissing ? const Color(0xfffee2e2) : const Color(0xffe0f2fe)), 3);
      if (!hasBook && highlightMissing) {
        canvas.drawRRect(RRect.fromRectAndRadius(bookRect, const Radius.circular(3)),
          Paint()..color = const Color(0xffef4444)..style = PaintingStyle.stroke..strokeWidth = 1.0);
      }
      _text(canvas, hasBook ? '📑 BOOKING: $value' : '📑 SAISIR BOOKING *',
        bookRect, hasBook ? Colors.white : (highlightMissing ? const Color(0xffb91c1c) : const Color(0xff0369a1)),
        twin ? 7.2 : 9.0, twin ? 1.5 : 2.0, bold: true);
    }

    // =========================================================================
    // ROW 2: CODE ISO (4 CHARACTER SLOTS)
    // =========================================================================
    final isoY = rect.top + (twin ? 23 : 28);
    final isoSlotH = twin ? 12.0 : 15.0;
    final isoSlotW = twin ? 9.5 : 14.0;
    final isoGap = twin ? 1.5 : 2.5;

    // ISO Label Pill
    final isoLabelW = twin ? 18.0 : 26.0;
    final isoTotalW = isoLabelW + 4 + 4 * isoSlotW + 3 * isoGap;
    final isoStartX = rect.left + (rect.width - isoTotalW) / 2;

    final labelRect = Rect.fromLTWH(isoStartX, isoY, isoLabelW, isoSlotH);
    _box(canvas, labelRect, const Color(0xff0f172a), 2);
    _text(canvas, 'ISO', labelRect, const Color(0xff38bdf8), twin ? 6.5 : 8.5, twin ? 1.5 : 2.2, bold: true);

    for (int k = 0; k < 4; k++) {
      final sRect = Rect.fromLTWH(isoStartX + isoLabelW + 4 + k * (isoSlotW + isoGap), isoY, isoSlotW, isoSlotH);
      final ch = k < code.length ? code[k] : '';
      final hasCh = ch.isNotEmpty;

      Color sBg = hasCh ? const Color(0xff0f172a) : (empty ? const Color(0xffe2e8f0) : const Color(0x55000000));
      Color sBorder = hasCh
          ? const Color(0xff38bdf8)
          : (highlightMissing ? const Color(0xffef4444) : (empty ? const Color(0xff94a3b8) : const Color(0x66ffffff)));

      _box(canvas, sRect, sBg, 2);
      canvas.drawRRect(RRect.fromRectAndRadius(sRect, const Radius.circular(2)),
        Paint()..color = sBorder..style = PaintingStyle.stroke..strokeWidth = hasCh ? 1.0 : .8);
      _text(canvas, hasCh ? ch : '_', sRect,
        hasCh ? Colors.white : (highlightMissing ? const Color(0xffef4444) : const Color(0xff94a3b8)),
        twin ? 7.2 : 9.5, twin ? 1.2 : 1.8, bold: true);
    }

    // =========================================================================
    // ROW 3: LIGNE MARITIME (ARMATEUR / OPERATOR)
    // =========================================================================
    final lineY = rect.top + (twin ? 38 : 47);
    final lineH = twin ? 12.0 : 14.5;
    final lineW = rect.width - (twin ? 12 : 24);
    final lineRect = Rect.fromLTWH(rect.left + (rect.width - lineW) / 2, lineY, lineW, lineH);

    if (hasLine) {
      _box(canvas, lineRect, const Color(0xff0f172a), 2.5);
      canvas.drawRRect(RRect.fromRectAndRadius(lineRect, const Radius.circular(2.5)),
        Paint()..color = const Color(0xff10b981)..style = PaintingStyle.stroke..strokeWidth = .9);
      _text(canvas, '🚢 ${line.toUpperCase()}', lineRect, const Color(0xffe2e8f0),
        twin ? 6.8 : 8.8, twin ? 1.2 : 1.8, bold: true);
    } else {
      final lineMissingBg = highlightMissing ? const Color(0xffef4444) : (empty ? const Color(0xffe2e8f0) : const Color(0x44000000));
      _box(canvas, lineRect, lineMissingBg, 2.5);
      if (highlightMissing) {
        canvas.drawRRect(RRect.fromRectAndRadius(lineRect, const Radius.circular(2.5)),
          Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = .8);
      }
      _text(canvas, highlightMissing ? '⚠ CHOISIR LIGNE *' : '+ Ligne maritime',
        lineRect, highlightMissing ? Colors.white : const Color(0xff94a3b8),
        twin ? 6.2 : 8.2, twin ? 1.2 : 1.8, bold: true);
    }
  }

  void _box(Canvas canvas, Rect rect, Color color, double radius) =>
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color);

  void _text(Canvas canvas, String value, Rect rect, Color color, double size,
      double offset, {bool bold = false}) {
    var painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Roboto',
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width);

    while (painter.didExceedMaxLines && size > 4.5) {
      size -= .4;
      painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'Roboto',
            color: color,
            fontSize: size,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width);
    }
    painter.paint(canvas, Offset(rect.left + (rect.width - painter.width) / 2, rect.top + offset));
  }

  @override
  bool shouldRepaint(covariant _TruckPainter old) =>
    old.empty != empty || old.twin != twin || old.compact != compact ||
    old.unknown != unknown ||
    old.plate != plate ||
    old.driverCin != driverCin ||
    old.highlightMissing != highlightMissing ||
    !listEquals(old.numbers, numbers) || !listEquals(old.codes, codes) ||
    !listEquals(old.lines, lines) || !listEquals(old.bookings, bookings);
}
