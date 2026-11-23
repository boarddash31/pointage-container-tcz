import 'package:flutter/material.dart';

/// ZPS mark supplied by operations in APPLICATION ZENATA.docx.
class TczBrand extends StatelessWidget {
  const TczBrand({super.key, this.width = 200, this.onDark = false});
  final double width;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ZPS · Zenata Port Sec',
    image: true,
    child: Image.asset(
      'assets/brand/zps-logo.jpeg',
      width: width,
      height: width * 112 / 192,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    ),
  );
}
