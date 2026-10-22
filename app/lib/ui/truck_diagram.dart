import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Four gate states share the same chassis: loaded/empty, mono/twin.
/// An empty slot is an outline on the chassis, never a container beside it.
class TruckScene extends StatelessWidget {
  const TruckScene({super.key, required this.kind, this.height = 125, this.width,
    this.isTwin = false, this.plate, this.driverCin, this.containerNumber, this.iso, this.operator,
    this.containerNumber2, this.iso2, this.operator2, this.booking,
    this.booking2, this.showUnknown = false, this.highlightMissing = false,
    this.onPlateTap, this.onContainerTap});

  final String kind;
  final double height;
  final double? width;
  final bool isTwin, showUnknown, highlightMissing;
  final String? plate;
  final String? driverCin;
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
    required this.unknown, required this.plate, this.driverCin, required this.numbers, required this.codes,
    required this.lines, required this.bookings, required this.highlightMissing});
  final bool empty, twin, compact, unknown, highlightMissing;
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
      Paint()..color = navy.withValues(alpha:.09));
    // Trailer, suspension, reflectors and the rear bogie.
    _box(canvas,const Rect.fromLTWH(70,84,223,7),const Color(0xff223d50),2);
    _box(canvas,const Rect.fromLTWH(88,92,195,3),const Color(0xff8ea5b2),1);
    for(final x in [96.0,155.0,215.0,280.0]) {
      _box(canvas,Rect.fromLTWH(x,86,5,2),const Color(0xffffb74d),.6);
    }
    _box(canvas,const Rect.fromLTWH(290,85,3,7),const Color(0xffd64545),1);
    for(final x in [40.0,228.0,265.0]) {
      canvas.drawCircle(Offset(x,99),12,Paint()..color=const Color(0xff172a38));
      canvas.drawCircle(Offset(x,99),7.5,Paint()..color=const Color(0xffa7bac5));
      canvas.drawCircle(Offset(x,99),4.5,Paint()..color=const Color(0xffeaf0f4));
      canvas.drawCircle(Offset(x,99),1.8,metal);
    }
    // A recognizable tractor: sloped windscreen, tall cab and white door.
    final cab=Path()..moveTo(6,91)..lineTo(6,62)..lineTo(18,38)
      ..quadraticBezierTo(20,34,27,34)..lineTo(65,34)
      ..quadraticBezierTo(73,34,73,42)..lineTo(73,91)..close();
    canvas.drawPath(cab,Paint()..color=navy);
    final door=Path()..moveTo(11,72)..lineTo(11,62)..lineTo(22,42)
      ..lineTo(65,42)..lineTo(65,75)..lineTo(11,75)..close();
    canvas.drawPath(door,Paint()..color=const Color(0xffe8f3f9));
    final windshield=Path()..moveTo(15,60)..lineTo(24,44)..lineTo(41,44)
      ..lineTo(41,61)..lineTo(15,61)..close();
    canvas.drawPath(windshield,Paint()..color=const Color(0xff367da5));
    _box(canvas,const Rect.fromLTWH(45,44,16,17),const Color(0xff367da5),2);
    canvas.drawLine(const Offset(47,45),const Offset(58,45),
      Paint()..color=const Color(0xff92d5f0)..strokeWidth=1.5);
    _box(canvas,const Rect.fromLTWH(51,65,9,2),navy,1);
    // CIN chauffeur sur la portière de la cabine
    final hasCin = driverCin?.trim().isNotEmpty == true;
    final cinText = hasCin ? driverCin!.trim().toUpperCase() : (highlightMissing ? 'CIN ?' : 'CIN');
    _text(canvas, cinText, const Rect.fromLTWH(13, 64, 36, 10), navy, 6.8, 0, bold: true);
    _box(canvas,const Rect.fromLTWH(2,58,4,13),navy,1);
    _box(canvas,const Rect.fromLTWH(3,90,74,5),const Color(0xff233c4d),2);
    _box(canvas,const Rect.fromLTWH(6,86,5,4),const Color(0xffffcc70),1);
    // The plate is placed on the cab, with enough width for a Moroccan plate.
    const plateArea=Rect.fromLTWH(12,77,57,13);
    _box(canvas,plateArea,Colors.white,2);
    final hasPlate=plate?.trim().isNotEmpty==true;
    if(highlightMissing&&!hasPlate) {
      canvas.drawRRect(RRect.fromRectAndRadius(plateArea,const Radius.circular(2)),
        Paint()..color=const Color(0xffe8a128)..style=PaintingStyle.stroke..strokeWidth=1.2);
    }
    _text(canvas,hasPlate?plate!.toUpperCase():'PLAQUE ?',plateArea.deflate(2),
      navy,8,0,bold:true);

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
    final outline = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    final value = empty ? bookings[index]?.trim() : numbers[index]?.trim();
    final missing = highlightMissing && (value == null || value.isEmpty ||
      codes[index]?.trim().isNotEmpty != true || lines[index]?.trim().isNotEmpty != true);
    final borderColor = empty ? const Color(0xff45a5c3) : const Color(0xffa83238);
    if (!empty) {
      canvas.drawRRect(outline, Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xffdf5557), Color(0xffc33c43)],
      ).createShader(rect));
      canvas.drawRRect(outline, Paint()..color = borderColor
        ..style = PaintingStyle.stroke..strokeWidth = 1.2);
      for (var x = rect.left + 8; x < rect.right - 4; x += 9) {
        canvas.drawLine(Offset(x, rect.top + 5), Offset(x, rect.bottom - 5),
          Paint()..color = const Color(0xff8f202d).withValues(alpha:.18)..strokeWidth = 2);
        canvas.drawLine(Offset(x+1, rect.top + 5), Offset(x+1, rect.bottom - 5),
          Paint()..color = Colors.white.withValues(alpha:.12)..strokeWidth = .6);
      }
      for(final x in [rect.left+3,rect.right-6]) {
        for(final y in [rect.top+2,rect.bottom-6]) {
          _box(canvas,Rect.fromLTWH(x,y,3,4),const Color(0xfff48c85),.5);
        }
      }
    } else {
      canvas.drawRRect(outline, Paint()..color = const Color(0xffeef8fc));
      final stroke = Paint()..color = borderColor
        ..strokeWidth = 1.4..style = PaintingStyle.stroke;
      const dash = 6.0;
      for (var x = rect.left + 4; x < rect.right - 4; x += dash * 1.6) {
        canvas.drawLine(Offset(x, rect.top),
          Offset(math.min(x + dash, rect.right - 4), rect.top), stroke);
        canvas.drawLine(Offset(x, rect.bottom),
          Offset(math.min(x + dash, rect.right - 4), rect.bottom), stroke);
      }
      canvas.drawLine(rect.topLeft, rect.bottomLeft, stroke);
      canvas.drawLine(rect.topRight, rect.bottomRight, stroke);
    }
    final hasValue=value?.isNotEmpty==true;
    final hasDetails=highlightMissing || hasValue ||
      codes[index]?.isNotEmpty==true || lines[index]?.isNotEmpty==true;
    final textColor = empty ? const Color(0xff176b93) : Colors.white;
    if(!hasDetails) {
      if(empty) _text(canvas,'?',rect.deflate(6),textColor,24,10,bold:true);
      return;
    }
    if(compact) {
      _text(canvas,hasValue?value!:'?',rect.deflate(6),textColor,12,15,bold:true);
      return;
    }
    if(!empty) {
      // A quiet inset keeps live white lettering legible over corrugation.
      _box(canvas,rect.deflate(6),const Color(0xff9d2330).withValues(alpha:.68),3);
    }
    if(missing) {
      _box(canvas,Rect.fromLTWH(rect.center.dx-15,rect.top-2,30,3),
        const Color(0xffe8a128),1.5);
    }
    final textRect=rect.deflate(9);
    final heading=hasValue?value!:(empty?'? BOOKING':'? NUMÉRO');
    _text(canvas,heading,textRect,textColor,twin?11:15,0,bold:true);
    final code = codes[index]?.trim();
    final line = lines[index]?.trim();
    _text(canvas,code?.isNotEmpty==true?'ISO  $code':'ISO à saisir',
      textRect,textColor,twin?8:9,20);
    _text(canvas,line?.isNotEmpty==true?line!:'Ligne à choisir',
      textRect,textColor,twin?9:11,34,bold:true);
  }

  void _box(Canvas canvas,Rect rect,Color color,double radius) =>
    canvas.drawRRect(RRect.fromRectAndRadius(rect,Radius.circular(radius)),
      Paint()..color=color);

  void _text(Canvas canvas, String value, Rect rect, Color color, double size,
      double offset, {bool bold = false}) {
    var painter = TextPainter(
      text: TextSpan(text: value, style: TextStyle(fontFamily:'Roboto',color: color, fontSize: size,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      maxLines: 1, ellipsis: '…', textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width);
    // Keep every character of the ID visible, especially on twin containers.
    while(painter.didExceedMaxLines && size > 5) {
      size -= .5;
      painter=TextPainter(text:TextSpan(text:value,style:TextStyle(
        fontFamily:'Roboto',color:color,fontSize:size,fontWeight:bold?FontWeight.w800:FontWeight.w600)),
        maxLines:1,ellipsis:'…',textDirection:TextDirection.ltr)..layout(maxWidth:rect.width);
    }
    painter.paint(canvas, Offset(rect.left + (rect.width - painter.width) / 2,
      rect.top + offset));
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
