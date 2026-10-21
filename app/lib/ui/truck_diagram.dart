import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Four gate states share the same chassis: loaded/empty, mono/twin.
/// An empty slot is an outline on the chassis, never a container beside it.
class TruckScene extends StatelessWidget {
  const TruckScene({super.key, required this.kind, this.height = 125, this.width,
    this.isTwin = false, this.plate, this.containerNumber, this.iso, this.operator,
    this.containerNumber2, this.iso2, this.operator2, this.booking,
    this.booking2, this.showUnknown = false, this.highlightMissing = false,
    this.onPlateTap, this.onContainerTap});

  final String kind;
  final double height;
  final double? width;
  final bool isTwin, showUnknown, highlightMissing;
  final String? plate;
  final String? containerNumber, iso, operator, containerNumber2, iso2, operator2;
  final String? booking, booking2;
  final VoidCallback? onPlateTap;
  final ValueChanged<int>? onContainerTap;

  @override
  Widget build(BuildContext context) {
    final empty = kind == 'empty' || kind == 'depose';
    final twin = isTwin || containerNumber2 != null || iso2 != null || operator2 != null;
    return Semantics(
      label: '${empty ? 'Camion sans conteneur, emplacement prévu' : 'Camion chargé'} : '
        '${twin ? 'deux conteneurs' : 'un conteneur'}'
        '${plate?.trim().isNotEmpty == true ? ', plaque $plate' : ''}',
      child: SizedBox(
        width: width ?? height * 2.5,
        height: height,
        child: LayoutBuilder(builder: (context, constraints) {
          final diagram = CustomPaint(painter: _TruckPainter(
            empty: empty, twin: twin, compact: height <= 85,
            unknown: showUnknown, plate: plate,
            highlightMissing: highlightMissing,
            numbers: [containerNumber, containerNumber2],
            bookings: [booking, booking2],
            codes: [iso, iso2], lines: [operator, operator2],
          ));
          if (onPlateTap == null && onContainerTap == null) return diagram;
          return MouseRegion(cursor: SystemMouseCursors.click,
            child: GestureDetector(behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                const scene = Size(300, 120);
                final scale = math.min(constraints.maxWidth / scene.width,
                  constraints.maxHeight / scene.height);
                final x = (details.localPosition.dx -
                  (constraints.maxWidth - scene.width * scale) / 2) / scale;
                final y = (details.localPosition.dy -
                  (constraints.maxHeight - scene.height * scale) / 2) / scale;
                if (x >= 5 && x <= 81 && y >= 45 && y <= 94) {
                  onPlateTap?.call();
                } else if (x >= 88 && x <= 288 && y >= 21 && y <= 85) {
                  onContainerTap?.call(twin && x >= 190 ? 1 : 0);
                }
              }, child: diagram));
        }),
      ),
    );
  }
}

class _TruckPainter extends CustomPainter {
  const _TruckPainter({required this.empty, required this.twin, required this.compact,
    required this.unknown, required this.plate, required this.numbers, required this.codes,
    required this.lines, required this.bookings, required this.highlightMissing});
  final bool empty, twin, compact, unknown, highlightMissing;
  final String? plate;
  final List<String?> numbers, bookings, codes, lines;

  @override
  void paint(Canvas canvas, Size size) {
    const scene = Size(300, 120);
    final scale = math.min(size.width / scene.width, size.height / scene.height);
    canvas.save();
    canvas.translate((size.width - scene.width * scale) / 2,
      (size.height - scene.height * scale) / 2);
    canvas.scale(scale);

    final frame = Paint()..color = const Color(0xff17324d);
    final metal = Paint()..color = const Color(0xff55758c);
    final glass = Paint()..color = const Color(0xffa8e4fa);
    final accent = Paint()..color = const Color(0xff087e79);

    // Ground shadow and chassis make the load read as one truck at icon size.
    canvas.drawOval(const Rect.fromLTWH(12, 108, 279, 5),
      Paint()..color = const Color(0xff18384f).withValues(alpha: .12));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(72, 84, 220, 11),
      const Radius.circular(3)), frame);
    canvas.drawRect(const Rect.fromLTWH(84, 94, 198, 4), metal);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(282, 81, 14, 13),
      const Radius.circular(2)), accent);
    for (final x in [48.0, 207.0, 263.0]) {
      canvas.drawCircle(Offset(x, 99), 13, Paint()..color = const Color(0xff10283c));
      canvas.drawCircle(Offset(x, 99), 8, Paint()..color = const Color(0xffe8f2f5));
      canvas.drawCircle(Offset(x, 99), 3, metal);
    }

    // Rounded cab, split windows, mirror and visible licence plate.
    final cab = RRect.fromRectAndRadius(const Rect.fromLTWH(5, 44, 75, 49),
      const Radius.circular(8));
    canvas.drawRRect(cab, Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xff246081), Color(0xff123b58)],
    ).createShader(cab.outerRect));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(13, 50, 51, 24),
      const Radius.circular(4)), glass);
    canvas.drawLine(const Offset(51, 51), const Offset(51, 73),
      Paint()..color = const Color(0xff426c80)..strokeWidth = 2);
    canvas.drawLine(const Offset(3, 54), const Offset(13, 54),
      Paint()..color = frame.color..strokeWidth = 3);
    canvas.drawCircle(const Offset(76, 68), 2,
      Paint()..color = const Color(0xffffd368));
    final plateRect = RRect.fromRectAndRadius(const Rect.fromLTWH(9, 77, 65, 14),
      const Radius.circular(3));
    canvas.drawRRect(plateRect, Paint()..color = Colors.white);
    canvas.drawRRect(plateRect, Paint()..color = const Color(0xff075a8d)
      ..style = PaintingStyle.stroke..strokeWidth = 1.2);
    _text(canvas, plate?.trim().isNotEmpty == true ? plate!.toUpperCase() : 'PLAQUE ?',
      const Rect.fromLTWH(11, 77, 61, 14), const Color(0xff17324d), 8.5, 1,
      bold: true);

    final count = twin ? 2 : 1;
    for (var i = 0; i < count; i++) {
      final rect = twin
        ? Rect.fromLTWH(88 + i * 102, 21, 98, 64)
        : const Rect.fromLTWH(88, 21, 200, 64);
      _drawSlot(canvas, rect, i);
    }
    canvas.restore();
  }

  void _drawSlot(Canvas canvas, Rect rect, int index) {
    final outline = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    final value = empty ? bookings[index]?.trim() : numbers[index]?.trim();
    final missing = highlightMissing && (value == null || value.isEmpty ||
      codes[index]?.trim().isNotEmpty != true || lines[index]?.trim().isNotEmpty != true);
    final borderColor = missing ? const Color(0xffffc107) :
      (empty ? const Color(0xff087e79) : const Color(0xff921a17));
    if (!empty) {
      canvas.drawRRect(outline, Paint()..shader = const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xffec4536), Color(0xffb51e23)],
      ).createShader(rect));
      canvas.drawRRect(outline, Paint()..color = borderColor
        ..style = PaintingStyle.stroke..strokeWidth = missing ? 4 : 2);
      for (var x = rect.left + 11; x < rect.right - 5; x += 13) {
        canvas.drawLine(Offset(x, rect.top + 5), Offset(x, rect.bottom - 5),
          Paint()..color = Colors.white.withValues(alpha: .16)..strokeWidth = 1);
      }
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left + 5, rect.top + 5, rect.width - 10, rect.height - 10),
        const Radius.circular(2)), Paint()..color = Colors.white.withValues(alpha: .18)
          ..style = PaintingStyle.stroke..strokeWidth = .7);
    } else {
      canvas.drawRRect(outline, Paint()..color = const Color(0xffe7f3f5));
      final stroke = Paint()..color = borderColor
        ..strokeWidth = missing ? 3 : 2..style = PaintingStyle.stroke;
      const dash = 10.0;
      for (var x = rect.left + 4; x < rect.right - 4; x += dash * 1.6) {
        canvas.drawLine(Offset(x, rect.top),
          Offset(math.min(x + dash, rect.right - 4), rect.top), stroke);
        canvas.drawLine(Offset(x, rect.bottom),
          Offset(math.min(x + dash, rect.right - 4), rect.bottom), stroke);
      }
      canvas.drawLine(rect.topLeft, rect.bottomLeft, stroke);
      canvas.drawLine(rect.topRight, rect.bottomRight, stroke);
      canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(5),
        const Radius.circular(3)), Paint()..color = const Color(0xfff7fbfc));
    }
    final heading = value?.isNotEmpty == true
      ? (empty ? 'BOOK $value' : value!)
      : (highlightMissing ? (empty ? '? BOOKING *' : '? NUMÉRO *') : '?');
    final textColor = empty ? const Color(0xff075a8d) : Colors.white;
    if (compact) {
      _text(canvas, value?.isNotEmpty == true ? value! : (empty ? '?' : ''),
        rect.deflate(5), textColor, twin ? 22 : 28, 13, bold: true);
      return;
    }
    _text(canvas, heading, rect.deflate(6), textColor,
      twin ? 10 : 15, 2, bold: true);
    final code = codes[index]?.trim();
    final line = lines[index]?.trim();
    _text(canvas, code?.isNotEmpty == true ? 'ISO $code' : 'ISO *',
      rect.deflate(6), textColor, twin ? 8 : 11, 25);
    _text(canvas, line?.isNotEmpty == true ? line! : 'Ligne *',
      rect.deflate(6), textColor, twin ? 8 : 10, 43);
  }

  void _text(Canvas canvas, String value, Rect rect, Color color, double size,
      double offset, {bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: TextStyle(color: color, fontSize: size,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      maxLines: 1, ellipsis: '…', textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width);
    painter.paint(canvas, Offset(rect.left + (rect.width - painter.width) / 2,
      rect.top + offset));
  }

  @override
  bool shouldRepaint(covariant _TruckPainter old) =>
    old.empty != empty || old.twin != twin || old.compact != compact ||
    old.unknown != unknown ||
    old.plate != plate ||
    old.highlightMissing != highlightMissing ||
    !listEquals(old.numbers, numbers) || !listEquals(old.codes, codes) ||
    !listEquals(old.lines, lines) || !listEquals(old.bookings, bookings);
}
