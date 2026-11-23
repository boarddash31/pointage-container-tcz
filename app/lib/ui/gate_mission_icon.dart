import 'package:flutter/material.dart';

class GateMissionIcon extends StatelessWidget {
  const GateMissionIcon({
    super.key,
    required this.restitution,
    required this.count,
  }) : assert(count == 1 || count == 2);

  final bool restitution;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = restitution
        ? const Color(0xff087b68)
        : const Color(0xff075a8d);
    return Semantics(
      label:
          '${restitution ? 'Restitution' : 'Livraison'} · $count conteneur${count == 2 ? 's' : ''}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 66,
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  restitution
                      ? Icons.move_to_inbox_outlined
                      : Icons.outbox_outlined,
                  size: 32,
                  color: color,
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 23,
                  height: 23,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
