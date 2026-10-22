class TruckPlate {
  // Moroccan format used at the gate: serial number - letter - province number.
  // Separators are optional when scanning or pasting (12345A06 is accepted).
  static final _pattern = RegExp(r'^\d{1,5}[ -]?[A-Z][ -]?\d{1,2}$');

  static String normalize(String input) => input.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool isValid(String input) => _pattern.hasMatch(normalize(input));

  static String format(String input) {
    final value = normalize(input).replaceAll('-', '').replaceAll(' ', '');
    final match = RegExp(r'^(\d{1,5})([A-Z])(\d{1,2})$').firstMatch(value);
    if (match == null) return normalize(input);
    return '${match.group(1)}-${match.group(2)}-${match.group(3)}';
  }

  static (String, String, String) parseParts(String input) {
    final clean = normalize(input).replaceAll(' ', '-').replaceAll('|', '-');
    final m = RegExp(r'^(\d{1,5})[- ]?([A-Z\u0600-\u06FF])[- ]?(\d{1,2})$').firstMatch(clean);
    if (m != null) {
      return (m.group(1) ?? '', m.group(2) ?? '', m.group(3) ?? '');
    }
    final parts = clean.split('-').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 3) return (parts[0], parts[1], parts[2]);
    if (parts.length == 2) return (parts[0], parts[1], '');
    if (parts.length == 1) return (parts[0], '', '');
    return (clean, '', '');
  }
}
