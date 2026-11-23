part of 'pointage_repository.dart';

class SqlPointageRepository extends PointageRepository {
  SqlPointageRepository(this.api) : super.detached();
  final SqlServerApi api;
  final _versions = <String, int>{};
  final _accounts = <String, Map<String, dynamic>>{};
  String? _entryFingerprint, _entryRequestId;
  static String _requestId() {
    final random = Random.secure(), bytes = List.generate(16, (_) => 0);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  @override
  bool get usesSql => true;
  @override
  User? get user => null;
  @override
  DocumentService get documentService => DocumentService.sql(api);
  @override
  Future<void> signOut() => api.logout();
  static Map<String, dynamic> _map(dynamic value) {
    final row = Map<String, dynamic>.from(value as Map);
    if (row['operational_details'] is String) {
      row['operational_details'] = jsonDecode(
        row['operational_details'] as String,
      );
    }
    return row;
  }

  static List<Map<String, dynamic>> _rows(dynamic value) => [
    for (final row in value as List) _map(row),
  ];
  void _remember(Map<String, dynamic> row) {
    if (row['id'] is String && row['version'] is int) {
      _versions[row['id'] as String] = row['version'] as int;
    }
  }

  @override
  Future<dynamic> read(
    String operation, [
    Map<String, dynamic> p = const {},
  ]) async {
    final value = await api.request(
      'GET',
      'api/data/$operation',
      query: {
        for (final e in p.entries)
          if (e.value != null) e.key: e.value.toString(),
      },
    );
    final result = value is List ? _rows(value) : value;
    if (operation == 'visits') {
      for (final row in _rows(result)) {
        _remember(row);
      }
    }
    if (operation == 'profiles') {
      for (final row in _rows(result)) {
        _accounts[row['id'] as String] = row;
      }
    }
    return result;
  }

  @override
  Future<void> settings(String operation, Map<String, dynamic> p) async {
    if (operation == 'role') {
      final id = p['p_user'] as String;
      await read('profiles');
      final row = _accounts[id];
      if (row == null || row['account_linked'] != true) {
        throw StateError('Créez d’abord le compte local de cet utilisateur.');
      }
      final roles = {
        for (final role in row['user_roles'] as List)
          (role as Map)['role'] as String,
      };
      p['p_enabled'] == true
          ? roles.add(p['p_role'] as String)
          : roles.remove(p['p_role']);
      await api.updateAccount(
        id: id,
        expectedVersion: row['version'] as int,
        active: row['active'] == true,
        roles: roles.toList(),
      );
      return;
    }
    await api.request(
      'POST',
      'api/settings/$operation',
      body: {
        for (final e in p.entries)
          e.key.startsWith('p_') ? e.key.substring(2) : e.key: e.value,
      },
    );
  }

  @override
  Future<List<String>> roles() async => [
    for (final role in (await api.currentUser())['roles'] as List)
      role is Map ? role['role'] as String : role as String,
  ];
  @override
  Future<List<OperatorRecord>> operators() async =>
      (await api.operators()).map(OperatorRecord.fromJson).toList();
  @override
  Future<List<TransportOrderItem>> transportOrderItems() => api.orderItems();
  @override
  Future<String> createTransportOrder({
    required String kind,
    required String direction,
    required String reference,
    required String armateur,
    required List<Map<String, dynamic>> items,
  }) async => (await api.createOrder(
    kind: kind,
    reference: reference,
    items: items.map(_line).toList(),
  )).id;
  static SqlOrderLine _line(Map<String, dynamic> i) => SqlOrderLine(
    id: i['id'] as String?,
    isoCode: i['iso_code'] as String,
    armateurId: i['armateur_id'] as String,
    quantity: i['quantity'] as int,
  );
  @override
  Future<int> updateTransportOrder({
    required String orderId,
    required int expectedVersion,
    required List<Map<String, dynamic>> items,
  }) => api.updateOrder(
    id: orderId,
    expectedVersion: expectedVersion,
    items: items.map(_line).toList(),
  );
  @override
  Future<int> increaseTransportOrderQuantity({
    required String itemId,
    required int quantity,
  }) async =>
      (await api.increaseQuantity(itemId: itemId, quantity: quantity)).quantity;
  @override
  Future<List<DataTransaction>> transactions() async =>
      _rows(await read('transactions')).map(DataTransaction.fromJson).toList();
  @override
  Future<Map<String, dynamic>?> container(String number) async {
    final rows = _rows(await read('container', {'number': number}));
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<List<Map<String, dynamic>>> containerBlocks() async => _rows(
    await api.request(
      'GET',
      'api/container-blocks',
      query: {'pageSize': '1000'},
    ),
  );
  @override
  Future<void> setContainerBlock(
    String number,
    bool blocked,
    String reason, {
    required int expectedVersion,
  }) async {
    await api.request(
      'PUT',
      'api/container-blocks/${Uri.encodeComponent(number)}',
      body: {
        'blocked': blocked,
        'reason': reason,
        'expected_version': expectedVersion,
      },
    );
  }

  @override
  Future<String> enter({
    required String plate,
    required String cin,
    required String kind,
    required String iso,
    required String armateur,
    String? containerNumber,
    String? booking,
    bool isTwin = false,
    String? containerNumber2,
    String? iso2,
    String? armateur2,
    String? booking2,
    String? orderItemId,
    String? orderItemId2,
    Map<String, dynamic> operationalDetails = const {},
  }) async {
    final body = <String, dynamic>{
      'plate': plate,
      'cin': cin,
      'entry_kind': kind,
      'order_item_id': orderItemId,
      'is_twin': isTwin,
      'order_item_id2': orderItemId2,
      'container': containerNumber,
      'container2': containerNumber2,
      'operational_details': operationalDetails,
    };
    final fingerprint = jsonEncode(body);
    if (_entryFingerprint != fingerprint) {
      _entryFingerprint = fingerprint;
      _entryRequestId = _requestId();
    }
    try {
      final row = _map(
        await api.request(
          'POST',
          'api/visits',
          status: 201,
          body: {...body, 'request_id': _entryRequestId},
        ),
      );
      _entryFingerprint = null;
      _entryRequestId = null;
      _remember(row);
      return row['id'] as String;
    } on SqlApiException catch (error) {
      if (!error.outcomeUnknown) {
        _entryFingerprint = null;
        _entryRequestId = null;
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _paged(
    String route,
    Map<String, String> filter,
  ) async {
    final result = <Map<String, dynamic>>[];
    String? after;
    for (var page = 0; page < 100; page++) {
      final batch = _rows(
        await api.request(
          'GET',
          route,
          query: {...filter, 'pageSize': '1000', 'afterId': ?after},
        ),
      );
      result.addAll(batch);
      for (final row in batch) {
        _remember(row);
      }
      if (batch.length < 1000) return result;
      final next = batch.last['id'] as String;
      if (next == after) throw StateError('Pagination invalide.');
      after = next;
    }
    throw StateError('Trop de données à charger.');
  }

  @override
  Future<List<TruckVisit>> visits({bool insideOnly = true}) async =>
      (await _paged('api/visits', {
          'insideOnly': '$insideOnly',
        })).map(TruckVisit.fromJson).toList()
        ..sort((a, b) => a.enteredAt.compareTo(b.enteredAt));
  @override
  Future<List<Map<String, dynamic>>> stock({String? iso, String? armateur}) =>
      _paged('api/stock', {'iso': ?iso, 'line': ?armateur});
  Future<void> _move(
    String id,
    String operation, [
    Map<String, dynamic> fields = const {},
  ]) async {
    final version = _versions[id];
    if (version == null) {
      throw StateError('Actualisez la visite avant de la modifier.');
    }
    final row = _map(
      await api.request(
        'POST',
        'api/visits/$id/$operation',
        body: {'expected_version': version, ...fields},
      ),
    );
    _remember(row);
  }

  @override
  Future<void> engin(
    String visitId, {
    String? containerNumber,
    String? position,
  }) => _move(visitId, 'yard', {
    'container': containerNumber,
    'position': position,
  });
  @override
  Future<void> exit(String visitId) => _move(visitId, 'exit');
  @override
  Future<void> exitWithDetails(
    String visitId, {
    String? pickupContainer,
    String? pickupIso,
    String? pickupArmateur,
    bool isTwin = false,
    String? pickupContainer2,
    String? pickupIso2,
    String? pickupArmateur2,
    bool emptyExitWithoutPickup = false,
    Map<String, dynamic> operationalDetails = const {},
  }) => _move(visitId, emptyExitWithoutPickup ? 'empty-exit' : 'exit', {
    'container': pickupContainer,
    'container2': pickupContainer2,
    'operational_details': operationalDetails,
  });
  @override
  Future<void> cancel(String visitId, String reason, {String? adminCode}) =>
      _move(visitId, 'cancel', {'reason': reason});
  @override
  Future<String> forcePickup(
    String visitId,
    String containerNumber,
    String reason,
  ) async {
    final row = _map(
      await api.request(
        'POST',
        'api/visits/$visitId/force-pickup',
        body: {
          'expected_version': _versions[visitId],
          'container': containerNumber,
          'reason': reason,
        },
      ),
    );
    _remember({'id': visitId, 'version': row['version']});
    return row['id'] as String;
  }

  @override
  Future<List<Map<String, dynamic>>> forcedActions() async =>
      _rows(await read('forced'));
  @override
  Future<void> resolveForcedAction(String id, String externalReference) async {
    await settings('reconcile', {
      'id': id,
      'external_reference': externalReference,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> events(String visitId) async => _rows(
    await api.request(
      'GET',
      'api/visits/$visitId/events',
      query: {'pageSize': '1000'},
    ),
  );
  @override
  Future<List<Map<String, dynamic>>> documents() async =>
      _rows(await read('documents'));
  @override
  Future<Map<String, dynamic>> createAgent({
    required String phone,
    required String firstName,
    required String lastName,
    required String role,
    required String password,
    String? avatarUrl,
    String? adminCode,
  }) async {
    final result = await api.createAccount(
      username: phone.trim(),
      password: password,
      displayName: '$firstName $lastName'.trim(),
      roles: [role],
    );
    await settings('profile', {
      'id': result.id,
      'expected_version': result.version,
      'first_name': firstName,
      'last_name': lastName,
      'avatar_url': ?avatarUrl,
    });
    return {'id': result.id, 'user_id': result.id, 'username': phone.trim()};
  }

  @override
  Future<List<Map<String, dynamic>>> listAgents() async =>
      _rows(await read('profiles'));
  @override
  Future<Map<String, dynamic>> updateAgent({
    required String userId,
    required String phone,
    required String firstName,
    required String lastName,
    required String role,
    String? password,
    bool active = true,
    String? adminCode,
  }) async {
    await read('profiles');
    final row = _accounts[userId];
    if (row == null) throw StateError('Profil absent.');
    int version;
    if (row['account_linked'] != true) {
      if (password == null || password.isEmpty) {
        throw StateError(
          'Indiquez un mot de passe initial pour activer ce compte local.',
        );
      }
      final result = await api.createAccount(
        username: phone.trim(),
        password: password,
        displayName: '$firstName $lastName'.trim(),
        roles: [role],
        existingProfileId: userId,
      );
      version = result.version;
    } else {
      final result = await api.updateAccount(
        id: userId,
        expectedVersion: row['version'] as int,
        active: active,
        roles: [role],
      );
      version = result.version;
      if (password != null && password.isNotEmpty) {
        version = (await api.resetPassword(
          id: userId,
          expectedVersion: version,
          password: password,
        )).version;
      }
    }
    await settings('profile', {
      'id': userId,
      'expected_version': version,
      'first_name': firstName,
      'last_name': lastName,
    });
    return {'id': userId};
  }

  @override
  Future<Map<String, dynamic>> dashboardKpis([DateTime? day]) async {
    final d = day ?? DateTime.now();
    return _map(
      await read('dashboard', {
        'day':
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      }),
    );
  }
}
