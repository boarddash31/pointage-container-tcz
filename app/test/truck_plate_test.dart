import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/domain/truck_plate.dart';

void main() {
  test('validates and formats Moroccan truck plates', () {
    expect(TruckPlate.isValid('12345-A-06'), isTrue);
    expect(TruckPlate.isValid('12345A06'), isTrue);
    expect(TruckPlate.format('12345a06'), '12345-A-06');
  });

  test('rejects plates with missing parts or too many digits', () {
    expect(TruckPlate.isValid('123456-A-06'), isFalse);
    expect(TruckPlate.isValid('12345-06'), isFalse);
    expect(TruckPlate.isValid('ABC-A-06'), isFalse);
  });
}
