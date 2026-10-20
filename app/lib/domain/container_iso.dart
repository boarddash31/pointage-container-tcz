class ContainerIso {
  static bool sameLength(String expected, String actual) {
    final first = expected.trim().toUpperCase();
    final second = actual.trim().toUpperCase();
    final pattern = RegExp(r'^[0-9A-Z]{4}$');
    return pattern.hasMatch(first) && pattern.hasMatch(second) && first[0] == second[0];
  }

  static String? pickupError({required String expected, required String actual,
      String? expectedSecond, String? actualSecond, bool twin = false}) {
    if (!sameLength(expected, actual)) {
      return 'Taille ISO incompatible : visite $expected, conteneur $actual. '
          'La longueur doit correspondre à la réservation.';
    }
    if (twin) {
      final secondExpected = expectedSecond ?? expected;
      if (!expected.startsWith('2') || !secondExpected.startsWith('2')) {
        return 'Twin interdit : la visite doit prévoir deux conteneurs de 20 pieds.';
      }
      if (!sameLength(secondExpected, actualSecond ?? '')) {
        return 'Taille ISO incompatible pour le 2ème conteneur : '
            'visite $secondExpected, conteneur ${actualSecond ?? '—'}.';
      }
    }
    return null;
  }
}
