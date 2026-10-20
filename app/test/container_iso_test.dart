import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/domain/container_iso.dart';

void main() {
  test('gate-out preserves booked length in both directions', () {
    expect(ContainerIso.pickupError(expected:'22G1',actual:'45G1'),isNotNull);
    expect(ContainerIso.pickupError(expected:'45G1',actual:'22G1'),isNotNull);
    expect(ContainerIso.pickupError(expected:'42G1',actual:'45G1'),isNull);
    expect(ContainerIso.pickupError(expected:'22G1',actual:'25G1'),isNull);
    expect(ContainerIso.pickupError(expected:'22G1',actual:'2'),isNotNull);
  });
  test('both twin containers must match a 20-foot visit', () {
    expect(ContainerIso.pickupError(expected:'22G1',actual:'22G1',twin:true,
        actualSecond:'45G1'),isNotNull);
    expect(ContainerIso.pickupError(expected:'45G1',actual:'45G1',twin:true,
        actualSecond:'22G1'),isNotNull);
    expect(ContainerIso.pickupError(expected:'22G1',actual:'22G1',twin:true,
        actualSecond:'22G1'),isNull);
  });
}
