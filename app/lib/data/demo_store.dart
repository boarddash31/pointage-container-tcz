import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/container_number.dart';
import '../domain/truck_plate.dart';

class DemoProfile {
  const DemoProfile(this.id, this.name, this.role, {this.active = true});
  final String id, name, role;
  final bool active;
  String get roleLabel => switch (role) {
    'admin' => 'Admin',
    'entree' => 'Entrée',
    _ => 'Sortie',
  };
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'active': active,
  };
  factory DemoProfile.fromJson(Map<String, dynamic> j) => DemoProfile(
    j['id'] as String,
    j['name'] as String,
    j['role'] as String,
    active: j['active'] == true,
  );
}

/// Disposable browser-local simulation. No Supabase client, tokens or HTTP calls.
class DemoStore extends ChangeNotifier {
  DemoStore._(this.preferences);
  static const storageKey = 'tcz_demo_v1';
  final SharedPreferences? preferences;
  final List<DemoProfile> profiles = [];
  final List<Map<String, dynamic>> visits = [];
  final List<Map<String, dynamic>> stock = [];
  final List<Map<String, dynamic>> timeline = [];
  int serial = 100;

  static Future<DemoStore> load({SharedPreferences? preferences}) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final store = DemoStore._(prefs);
    try {
      final raw = prefs.getString(storageKey);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (j['schema'] != 1) {
          throw const FormatException('Unknown demo schema');
        }
        store.profiles.addAll(
          (j['profiles'] as List).map(
            (p) => DemoProfile.fromJson(Map<String, dynamic>.from(p as Map)),
          ),
        );
        for (final pair in [
          (store.visits, 'visits'),
          (store.stock, 'stock'),
          (store.timeline, 'timeline'),
        ]) {
          pair.$1.addAll(
            (j[pair.$2] as List).map(
              (v) => Map<String, dynamic>.from(v as Map),
            ),
          );
        }
        store.serial = (j['serial'] as num).toInt();
        if (!store.profiles.any((p) => p.active && p.role == 'admin')) {
          throw const FormatException('Demo admin missing');
        }
        return store;
      }
    } catch (_) {
      /* Only a corrupt demo snapshot is replaced. */
    }
    store._seed();
    await store._save();
    return store;
  }

  factory DemoStore.seeded() {
    final store = DemoStore._(null);
    store._seed();
    return store;
  }

  void _seed() {
    profiles
      ..clear()
      ..addAll(const [
        DemoProfile('demo-admin', 'Admin démo', 'admin'),
        DemoProfile('demo-entree', 'Agent Entrée démo', 'entree'),
        DemoProfile('demo-sortie', 'Agent Sortie démo', 'sortie'),
      ]);
    visits.clear();
    stock.clear();
    timeline.clear();
    serial = 100;
    final now = DateTime.now();
    stock.add({
      'container_number': sampleContainer('MSCU654321'),
      'iso_code': '22G1',
      'armateur_id': 'MAE',
      'position': 'A-01-02',
      'arrived_at': now.subtract(const Duration(days: 2)).toIso8601String(),
    });
    visits.addAll([
      {
        'id': 'demo-visit-1',
        'plate': '12345-A-06',
        'driver_cin': 'AB123456',
        'entry_kind': 'loaded',
        'container_number': 'CSQU3054383',
        'iso_code': '22G1',
        'armateur_id': 'MSC',
        'is_twin': false,
        'entered_at': now
            .subtract(const Duration(minutes: 35))
            .toIso8601String(),
        'creator_name': 'Agent Entrée démo',
        'exited_at': null,
        'canceled_at': null,
      },
      {
        'id': 'demo-visit-2',
        'plate': '54321-B-06',
        'driver_cin': 'CD654321',
        'entry_kind': 'empty',
        'container_number': null,
        'carrier_booking_reference': 'DEMO-BOOK-002',
        'iso_code': '22G1',
        'armateur_id': 'MAE',
        'is_twin': false,
        'entered_at': now
            .subtract(const Duration(minutes: 15))
            .toIso8601String(),
        'creator_name': 'Agent Entrée démo',
        'exited_at': null,
        'canceled_at': null,
      },
    ]);
  }

  static String sampleContainer(String firstTen) =>
      '$firstTen${ContainerNumber.expectedCheckDigit(firstTen)}';
  List<Map<String, dynamic>> get inside => visits
      .where((v) => v['exited_at'] == null && v['canceled_at'] == null)
      .toList();
  void require(DemoProfile actor, String role) {
    final matches = profiles.where((p) => p.id == actor.id && p.active);
    if (matches.isEmpty ||
        !(matches.first.role == 'admin' || matches.first.role == role)) {
      throw StateError('Ce profil de démo ne possède pas cette autorisation.');
    }
  }

  Future<void> _save() async {
    await preferences?.setString(
      storageKey,
      jsonEncode({
        'schema': 1,
        'serial': serial,
        'profiles': profiles.map((p) => p.toJson()).toList(),
        'visits': visits,
        'stock': stock,
        'timeline': timeline,
      }),
    );
  }

  Future<void> _changed() async {
    await _save();
    notifyListeners();
  }

  void _event(DemoProfile actor, String action, String visitId) {
    timeline.add({
      'actor': actor.name,
      'action': action,
      'visit_id': visitId,
      'at': DateTime.now().toIso8601String(),
    });
  }

  Future<DemoProfile> createProfile(
    DemoProfile actor,
    String name,
    String role,
  ) async {
    require(actor, 'admin');
    final label = name.trim();
    if (label.length < 2 || label.length > 60) {
      throw StateError('Nom requis : 2 à 60 caractères.');
    }
    if (!['admin', 'entree', 'sortie'].contains(role)) {
      throw StateError('Rôle invalide.');
    }
    if (profiles.any((p) => p.name.toLowerCase() == label.toLowerCase())) {
      throw StateError('Ce nom existe déjà en démo.');
    }
    final profile = DemoProfile('demo-profile-${++serial}', label, role);
    profiles.add(profile);
    _event(actor, 'Création profil ${profile.roleLabel}', profile.id);
    await _changed();
    return profile;
  }

  Future<void> setProfileActive(
    DemoProfile actor,
    DemoProfile profile,
    bool active,
  ) async {
    require(actor, 'admin');
    if (!active &&
        profile.role == 'admin' &&
        profiles.where((p) => p.active && p.role == 'admin').length == 1) {
      throw StateError('Conservez au moins un Admin actif en démo.');
    }
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index < 0) throw StateError('Profil introuvable.');
    profiles[index] = DemoProfile(
      profile.id,
      profile.name,
      profile.role,
      active: active,
    );
    _event(
      actor,
      active ? 'Activation profil' : 'Désactivation profil',
      profile.id,
    );
    await _changed();
  }

  Future<Map<String, dynamic>> enter(
    DemoProfile actor, {
    required String plate,
    required String cin,
    required String kind,
    required String iso,
    required String line,
    String? number,
    String? booking,
    bool twin = false,
    String? number2,
    String? iso2,
    String? line2,
  }) async {
    require(actor, 'entree');
    if (!TruckPlate.isValid(plate)) {
      throw StateError('Plaque invalide : exemple 12345-A-06.');
    }
    if (cin.trim().isEmpty) throw StateError('CIN chauffeur requis.');
    if (!['loaded', 'empty'].contains(kind)) {
      throw StateError('Choisissez le type de camion.');
    }
    final codes = [iso.toUpperCase(), if (twin) (iso2 ?? iso).toUpperCase()];
    if (codes.any((c) => !RegExp(r'^[A-Z0-9]{4}$').hasMatch(c))) {
      throw StateError('Code ISO requis : 4 caractères.');
    }
    if (twin && codes.any((c) => !c.startsWith('2'))) {
      throw StateError('Twin : deux conteneurs de 20 pieds.');
    }
    if (line.isEmpty || (twin && (line2 ?? line).isEmpty)) {
      throw StateError('Armateur requis.');
    }
    final numbers = [
      ContainerNumber.normalize(number ?? ''),
      if (twin) ContainerNumber.normalize(number2 ?? ''),
    ];
    if (kind == 'loaded') {
      if (numbers.any((n) => !ContainerNumber.isValid(n))) {
        throw StateError('Numéro conteneur ou clé ISO 6346 invalide.');
      }
      if (numbers.toSet().length != numbers.length) {
        throw StateError('Deux conteneurs distincts sont requis.');
      }
      for (final n in numbers) {
        if (stock.any((s) => s['container_number'] == n) ||
            inside.any(
              (v) => v['container_number'] == n || v['container_number_2'] == n,
            )) {
          throw StateError(
            'Le conteneur $n est déjà au parc ou sur un camion présent.',
          );
        }
      }
    } else if ((booking ?? '').trim().isEmpty) {
      throw StateError('Référence booking requise.');
    }
    final formatted = TruckPlate.format(plate);
    if (inside.any((v) => v['plate'] == formatted)) {
      throw StateError('Ce camion est déjà présent.');
    }
    final visit = <String, dynamic>{
      'id': 'demo-visit-${++serial}',
      'plate': formatted,
      'driver_cin': cin.trim().toUpperCase(),
      'entry_kind': kind,
      'container_number': kind == 'loaded' ? numbers.first : null,
      'container_number_2': kind == 'loaded' && twin ? numbers.last : null,
      'iso_code': codes.first,
      'iso_code_2': twin ? codes.last : null,
      'armateur_id': line,
      'armateur_id_2': twin ? (line2 ?? line) : null,
      'is_twin': twin,
      'carrier_booking_reference': booking,
      'entered_at': DateTime.now().toIso8601String(),
      'creator_name': actor.name,
      'exited_at': null,
      'canceled_at': null,
    };
    visits.add(visit);
    _event(actor, 'Entrée', visit['id'] as String);
    await _changed();
    return visit;
  }

  Future<void> exit(
    DemoProfile actor,
    String id, {
    List<String> pickup = const [],
    bool leaveEmpty = false,
    String position = 'A-01-01',
  }) async {
    require(actor, 'sortie');
    final matching = inside.where((v) => v['id'] == id);
    if (matching.isEmpty) throw StateError('Camion déjà sorti ou introuvable.');
    final visit = matching.first;
    final twin = visit['is_twin'] == true;
    final count = twin ? 2 : 1;
    final selected = <Map<String, dynamic>>[];
    if (visit['entry_kind'] == 'empty' && !leaveEmpty) {
      if (pickup.length != count || pickup.toSet().length != count) {
        throw StateError(
          'Sélectionnez $count conteneur(s) distinct(s) du stock.',
        );
      }
      for (var i = 0; i < count; i++) {
        final rows = stock.where((s) => s['container_number'] == pickup[i]);
        if (rows.isEmpty) throw StateError('Conteneur absent du stock.');
        final item = rows.first;
        final expected = (visit[i == 0 ? 'iso_code' : 'iso_code_2'] as String);
        final expectedLine = visit[i == 0 ? 'armateur_id' : 'armateur_id_2'];
        if ((item['iso_code'] as String)[0] != expected[0] ||
            item['armateur_id'] != expectedLine) {
          throw StateError('ISO ou armateur incompatible avec le booking.');
        }
        selected.add(item);
      }
    }
    final now = DateTime.now().toIso8601String();
    if (visit['entry_kind'] == 'loaded') {
      for (var i = 0; i < count; i++) {
        stock.add({
          'container_number':
              visit[i == 0 ? 'container_number' : 'container_number_2'],
          'iso_code': visit[i == 0 ? 'iso_code' : 'iso_code_2'],
          'armateur_id': visit[i == 0 ? 'armateur_id' : 'armateur_id_2'],
          'position': position.trim().isEmpty ? 'A-01-01' : position.trim(),
          'arrived_at': now,
        });
      }
    } else if (!leaveEmpty) {
      for (var i = 0; i < selected.length; i++) {
        visit[i == 0 ? 'container_number' : 'container_number_2'] =
            selected[i]['container_number'];
        stock.remove(selected[i]);
      }
    }
    visit['exited_at'] = now;
    visit['changer_name'] = actor.name;
    visit['left_empty'] = leaveEmpty;
    _event(actor, 'Sortie', id);
    await _changed();
  }

  Future<void> moveContainer(
    DemoProfile actor,
    String number,
    String position,
  ) async {
    require(actor, 'admin');
    if (position.trim().isEmpty) throw StateError('Position requise.');
    stock.firstWhere((s) => s['container_number'] == number)['position'] =
        position.trim();
    _event(actor, 'Position $position', number);
    await _changed();
  }

  Future<void> reset(DemoProfile actor) async {
    require(actor, 'admin');
    _seed();
    await _changed();
  }
}
