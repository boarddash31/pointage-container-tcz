import 'package:flutter/material.dart';

/// TCZ's own port-gate and sea mark, shared with the launcher and web icons.
class TczBrand extends StatelessWidget {
  const TczBrand({super.key, this.width = 200, this.onDark = false});
  final double width;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'TCZ · Terminal à conteneurs',
    image: true,
    child: Image.asset(
      onDark ? 'assets/brand/tcz-logo-light.png' : 'assets/brand/tcz-logo.png',
      width: width,
      height: width / 3.5,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    ),
  );
}
