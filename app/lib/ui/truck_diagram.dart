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
            empty: empty, twin: twin, unknown: showUnknown, plate: plate,
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
  const _TruckPainter({required this.empty, required this.twin,
    required this.unknown, required this.plate, required this.numbers, required this.codes,
    required this.lines, required this.bookings, required this.highlightMissing});
  final bool empty, twin, unknown, highlightMissing;
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
    final metal = Paint()..color = const Color(0xff49677e);
    final glass = Paint()..color = const Color(0xffa8e4fa);
    final accent = Paint()..color = const Color(0xff087e79);

    // Cabin and chassis remain identical across the four variants.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(5, 45, 76, 48),
      const Radius.circular(10)), frame);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(17, 51, 48, 24),
      const Radius.circular(4)), glass);
    final plateRect = RRect.fromRectAndRadius(const Rect.fromLTWH(7, 77, 69, 13),
      const Radius.circular(2));
    canvas.drawRRect(plateRect, Paint()..color = Colors.white);
    canvas.drawRRect(plateRect, Paint()..color = const Color(0xff075a8d)
      ..style = PaintingStyle.stroke..strokeWidth = 1);
    _text(canvas, plate?.trim().isNotEmpty == true ? plate!.toUpperCase() : 'PLAQUE',
      const Rect.fromLTWH(9, 77, 65, 13), const Color(0xff17324d), 8, 0,
      bold: true);
    canvas.drawRect(const Rect.fromLTWH(75, 86, 217, 8), frame);
    canvas.drawRect(const Rect.fromLTWH(85, 94, 201, 4), metal);
    canvas.drawRect(const Rect.fromLTWH(279, 80, 17, 13), accent);
    for (final x in [49.0, 207.0, 262.0]) {
      canvas.drawCircle(Offset(x, 99), 14, frame);
      canvas.drawCircle(Offset(x, 99), 6, glass);
    }

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
      canvas.drawRRect(outline, Paint()..color = const Color(0xffc92925));
      canvas.drawRRect(outline, Paint()..color = borderColor
        ..style = PaintingStyle.stroke..strokeWidth = missing ? 4 : 2);
      for (var x = rect.left + 12; x < rect.right - 5; x += 17) {
        canvas.drawLine(Offset(x, rect.top + 5), Offset(x, rect.bottom - 5),
          Paint()..color = Colors.white.withValues(alpha: .2)..strokeWidth = 1);
      }
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
    }
    final heading = value?.isNotEmpty == true
      ? (empty ? 'BOOK $value' : value!)
      : (highlightMissing ? (empty ? '? BOOKING *' : '? NUMÉRO *') : '?');
    _text(canvas, heading,
      rect.deflate(5), empty ? const Color(0xff075a8d) : Colors.white,
      twin ? 10 : 15, 0, bold: true);
    final code = codes[index]?.trim();
    final line = lines[index]?.trim();
    _text(canvas, code?.isNotEmpty == true ? 'ISO $code' : 'ISO *',
      rect.deflate(5), empty ? const Color(0xff075a8d) : Colors.white,
      twin ? 8 : 11, 25);
    _text(canvas, line?.isNotEmpty == true ? line! : 'Ligne *',
      rect.deflate(5), empty ? const Color(0xff075a8d) : Colors.white,
      twin ? 8 : 10, 42);
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
    old.empty != empty || old.twin != twin || old.unknown != unknown ||
    old.plate != plate ||
    old.highlightMissing != highlightMissing ||
    !listEquals(old.numbers, numbers) || !listEquals(old.codes, codes) ||
    !listEquals(old.lines, lines) || !listEquals(old.bookings, bookings);
}
