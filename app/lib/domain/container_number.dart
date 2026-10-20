class ContainerNumber {
  static final _pattern = RegExp(r'^[A-Z]{4}[0-9]{7}$');

  static String normalize(String input) => input.trim().toUpperCase();

  static bool isValid(String input) {
    final number = normalize(input);
    if (!_pattern.hasMatch(number)) return false;
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final code = number.codeUnitAt(i);
      final value = i >= 4
          ? code - 48
          : 10 + code - 65 + ((10 + code - 65 - 1) ~/ 10);
      sum += value * (1 << i);
    }
    return (sum % 11) % 10 == number.codeUnitAt(10) - 48;
  }

  static int? expectedCheckDigit(String input) {
    final number = normalize(input);
    if (number.length < 10 || !RegExp(r'^[A-Z]{4}[0-9]{6}').hasMatch(number)) return null;
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final code = number.codeUnitAt(i);
      final value = i >= 4
          ? code - 48
          : 10 + code - 65 + ((10 + code - 65 - 1) ~/ 10);
      sum += value * (1 << i);
    }
    return (sum % 11) % 10;
  }
}
