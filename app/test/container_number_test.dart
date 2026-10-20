import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/domain/container_number.dart';

void main() {
  test('ISO 6346 examples and altered check digit', () {
    expect(ContainerNumber.isValid('CSQU3054383'), isTrue);
    expect(ContainerNumber.isValid('CSQU3054384'), isFalse);
    expect(ContainerNumber.isValid('csqu3054383'), isTrue);
    expect(ContainerNumber.isValid('BOOKING-123'), isFalse);
  });
}
