import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/transport_order.dart';
import 'sql_session_storage.dart';

/// Application adapter for the private SQL Server API.
/// Sessions may be cached in the browser tab and are revalidated by SQL on reload.
class SqlApiException implements Exception {
  const SqlApiException(this.status, this.code, {this.outcomeUnknown = false});
  final int status;
  final String code;

  /// A failed write may have committed. Refresh before a manual retry.
  final bool outcomeUnknown;
  @override
  String toString() => outcomeUnknown
      ? 'Réponse non reçue. Actualisez les données avant de recommencer : l’opération peut avoir été enregistrée.'
      : switch (code) {
          'invalid_credentials' => 'Identifiant ou mot de passe incorrect.',
          'authentication_required' => 'Veuillez vous reconnecter.',
          'password_change_required' =>
            'Veuillez changer votre mot de passe temporaire.',
          'access_denied' => 'Votre compte ne permet pas cette opération.',
          'conflict_refresh_required' =>
            'Les données ont changé. Actualisez avant de recommencer.',
          'duplicate_reference' =>
            'Cette référence existe déjà. Ouvrez l’ordre existant.',
          'invalid_operation' =>
            'Opération refusée. Vérifiez le stock, le délai de 24 h, le code ISO et les quantités.',
          'database_unavailable' =>
            'Base de données indisponible. Réessayez plus tard.',
          _ => 'Opération impossible ($code).',
        };
}

class SqlSessionInfo {
  const SqlSessionInfo(this.userId, this.expiresAt, this.mustChangePassword);
  final String userId;
  final DateTime expiresAt;
  final bool mustChangePassword;
}

class SqlOrderLine {
  const SqlOrderLine({
    this.id,
    required this.isoCode,
    required this.armateurId,
    required this.quantity,
  });
  final String? id;
  final String isoCode, armateurId;
  final int quantity;
  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'iso_code': isoCode,
    'armateur_id': armateurId,
    'quantity': quantity,
  };
}

class SqlOrderCreated {
  const SqlOrderCreated(this.id, this.version);
  final String id;
  final int version;
}

class SqlQuantityChange {
  const SqlQuantityChange(this.quantity, this.version);
  final int quantity, version;
}

class SqlAccountChange {
  const SqlAccountChange(this.id, this.version, this.mustChangePassword);
  final String id;
  final int version;
  final bool? mustChangePassword;
}

class SqlServerApi {
  SqlServerApi({
    required Uri baseUri,
    http.Client? client,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 30),
    this.storage,
    bool allowInsecureLoopback = false,
    bool allowInsecureHttp = false,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _now = now ?? DateTime.now,
       _base = _validateBase(
         baseUri,
         allowInsecureLoopback || allowInsecureHttp,
         allowInsecureHttp,
       ) {
    if (timeout <= Duration.zero) {
      throw ArgumentError('A positive timeout is required.');
    }
  }
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final Uri _base;
  final Duration timeout;
  final SqlSessionStorage? storage;
  Future<SqlSessionInfo?>? _restorePending;
  String? _token;
  final _changes = StreamController<SqlSessionInfo?>.broadcast();
  Stream<SqlSessionInfo?> get sessionChanges => _changes.stream;
  String? get sessionToken => session == null ? null : _token;
  SqlSessionInfo? _info;
  bool _closed = false, _loginPending = false;
  int _epoch = 0;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static Uri _validateBase(Uri uri, bool allowLoopback, bool allowHttp) {
    final local =
        uri.scheme == 'http' &&
        (allowHttp ||
            allowLoopback &&
                ['localhost', '127.0.0.1', '::1'].contains(uri.host));
    if ((!local && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.any(
          (s) => s == '..' || s == '.' || s.contains('\\') || s.contains('/'),
        )) {
      throw ArgumentError(
        'Provide an HTTPS API base URL without credentials, query or fragment.',
      );
    }
    return Uri.parse('${uri.toString()}${uri.path.endsWith('/') ? '' : '/'}');
  }

  static Never _invalid() => throw const SqlApiException(0, 'invalid_response');
  static Map<String, dynamic> _object(dynamic value) =>
      value is Map<String, dynamic> ? value : _invalid();
  static List<Map<String, dynamic>> _rows(dynamic value) =>
      value is List ? value.map(_object).toList() : _invalid();
  static String _id(dynamic value) =>
      value is String && value.length == 36 && _uuid.hasMatch(value)
      ? value
      : _invalid();
  static int _version(dynamic value) =>
      value is int && value > 0 ? value : _invalid();
  static String _pathId(String id) {
    if (id.length != 36 || !_uuid.hasMatch(id)) {
      throw ArgumentError('A valid UUID is required.');
    }
    return id;
  }

  SqlSessionInfo? get session {
    if (_info != null && !_info!.expiresAt.isAfter(_now().toUtc())) {
      _forget();
    }
    return _info;
  }

  void _forget({bool clearStorage = true}) {
    _epoch++;
    _token = null;
    _info = null;
    if (clearStorage) {
      try {
        storage?.clear();
      } catch (_) {
        /* Storage may be disabled by the browser. */
      }
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  void _rememberSession() {
    if (_token == null || _info == null) return;
    try {
      storage?.write(
        jsonEncode({
          'version': 1,
          'api_base': _base.toString(),
          'token': _token,
          'expires_at': _info!.expiresAt.toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      /* A blocked tab store must not prevent login. */
    }
  }

  Future<SqlSessionInfo?> restoreSession() {
    if (_closed || _loginPending) {
      throw StateError('Session restoration is unavailable.');
    }
    if (session != null) return Future.value(session);
    return _restorePending ??= _restoreSavedSession().whenComplete(
      () => _restorePending = null,
    );
  }

  Future<SqlSessionInfo?> _restoreSavedSession() async {
    final generation = ++_epoch;
    String? raw;
    try {
      raw = storage?.read();
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    String token;
    DateTime expires;
    try {
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['version'] != 1 ||
          data['api_base'] != _base.toString() ||
          data['token'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(data['token'] as String) ||
          data['expires_at'] is! String) {
        throw const FormatException();
      }
      token = data['token'] as String;
      expires = DateTime.parse(data['expires_at'] as String).toUtc();
      if (!expires.isAfter(_now().toUtc())) throw const FormatException();
    } catch (_) {
      _forget();
      return null;
    }
    try {
      final data = _object(
        await _send('GET', 'api/auth/session', token: token),
      );
      if (_closed || generation != _epoch) return null;
      if (!expires.isAfter(_now().toUtc())) {
        _forget();
        return null;
      }
      final change = data['must_change_password'];
      if (change is! bool) _invalid();
      final info = SqlSessionInfo(_id(data['user_id']), expires, change);
      _token = token;
      _info = info;
      _rememberSession();
      _changes.add(info);
      return info;
    } on SqlApiException catch (error) {
      if (_closed || generation != _epoch) return null;
      if (error.status == 401) {
        _forget();
        return null;
      }
      rethrow; // Keep a valid cache through a network outage; retry before showing protected screens.
    }
  }

  String _credential({bool allowTemporary = false}) {
    if (_closed) {
      throw StateError('API adapter is closed.');
    }
    final info = session;
    if (info == null) {
      throw const SqlApiException(401, 'authentication_required');
    }
    if (info.mustChangePassword && !allowTemporary) {
      throw const SqlApiException(403, 'password_change_required');
    }
    return _token!;
  }

  Future<dynamic> _send(
    String method,
    String route, {
    String? token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
    int expectedStatus = 200,
  }) async {
    if (_closed) {
      throw StateError('API adapter is closed.');
    }
    final uri = _base.resolve(route).replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers['accept'] = 'application/json';
    if (token != null) {
      request.headers['authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    final write = method != 'GET';
    late http.Response response;
    try {
      response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
    } on TimeoutException {
      throw SqlApiException(0, 'request_timeout', outcomeUnknown: write);
    } on http.ClientException {
      throw SqlApiException(0, 'network_error', outcomeUnknown: write);
    }
    if (response.statusCode == 401 && token != null && token == _token) {
      _forget();
    }
    if (response.statusCode != expectedStatus) {
      var code = 'http_error';
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final value = data is Map ? data['error'] : null;
        if (value is String &&
            value.length <= 64 &&
            RegExp(r'^[a-z_]+$').hasMatch(value)) {
          code = value;
        }
      } on FormatException {
        /* Never expose a raw proxy/backend response. */
      }
      throw SqlApiException(
        response.statusCode,
        code,
        outcomeUnknown:
            write &&
            (response.statusCode >= 500 ||
                response.statusCode == 408 ||
                (response.statusCode >= 200 && response.statusCode < 400)),
      );
    }
    if (expectedStatus == 204) {
      return null;
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw SqlApiException(
        response.statusCode,
        'invalid_response',
        outcomeUnknown: write,
      );
    }
  }

  Future<SqlSessionInfo> login({
    required String username,
    required String password,
  }) async {
    if (_loginPending || _restorePending != null || session != null) {
      throw StateError('Complete logout before another login.');
    }
    final generation = ++_epoch;
    _loginPending = true;
    try {
      final data = _object(
        await _send(
          'POST',
          'api/auth/login',
          body: {'username': username, 'password': password},
        ),
      );
      final token = data['access_token'];
      if (token is! String ||
          token.length != 43 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token) ||
          data['token_type'] != 'Bearer') {
        _invalid();
      }
      final expires = data['expires_at'] is String
          ? DateTime.tryParse(data['expires_at'] as String)?.toUtc()
          : null;
      final change = data['must_change_password'];
      if (expires == null ||
          !expires.isAfter(_now().toUtc()) ||
          change is! bool) {
        _invalid();
      }
      final info = SqlSessionInfo(_id(data['user_id']), expires, change);
      if (_epoch != generation || _closed) {
        if (!_closed) {
          try {
            await _send(
              'POST',
              'api/auth/logout',
              token: token,
              expectedStatus: 204,
            );
          } catch (_) {
            /* Session still expires on the server. */
          }
        }
        throw const SqlApiException(0, 'login_cancelled');
      }
      _token = token;
      _info = info;
      _rememberSession();
      _changes.add(info);
      return info;
    } finally {
      _loginPending = false;
    }
  }

  Future<void> logout() async {
    final token = _token;
    _forget(); // A late response cannot restore a locally closed session.
    if (token == null) {
      return;
    }
    try {
      await _send('POST', 'api/auth/logout', token: token, expectedStatus: 204);
    } on SqlApiException catch (error) {
      if (error.status != 401) {
        rethrow;
      }
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = _credential(allowTemporary: true);
    await _send(
      'POST',
      'api/auth/password',
      token: token,
      expectedStatus: 204,
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
    if (token == _token) {
      _forget();
    }
  }

  Future<Map<String, dynamic>> currentUser() async =>
      _object(await _send('GET', 'api/me', token: _credential()));
  Future<dynamic> request(
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    int status = 200,
  }) {
    if (!route.startsWith('api/') ||
        route.contains('..') ||
        route.contains('?') ||
        route.contains('#')) {
      throw ArgumentError('Invalid API route.');
    }
    return _send(
      method,
      route,
      token: _credential(),
      body: body,
      query: query,
      expectedStatus: status,
    );
  }

  Future<List<Map<String, dynamic>>> operators() async =>
      _rows(await _send('GET', 'api/operators', token: _credential()));
  Future<List<TransportOrderItem>> orderItems({String? direction}) async {
    if (direction != null &&
        !['LIVRAISON', 'RESTITUTION'].contains(direction)) {
      throw ArgumentError('Invalid movement direction.');
    }
    final rows = _rows(
      await _send(
        'GET',
        'api/orders/items',
        token: _credential(),
        query: direction == null ? null : {'direction': direction},
      ),
    );
    try {
      return rows.map(TransportOrderItem.fromJson).toList();
    } on TypeError {
      _invalid();
    }
  }

  Future<SqlOrderCreated> createOrder({
    required String kind,
    required String reference,
    required List<SqlOrderLine> items,
  }) async {
    final data = _object(
      await _send(
        'POST',
        'api/orders',
        token: _credential(),
        expectedStatus: 201,
        body: {
          'kind': kind,
          'reference': reference,
          'items': items.map((i) => i.toJson()).toList(),
        },
      ),
    );
    return SqlOrderCreated(_id(data['id']), _version(data['version']));
  }

  Future<int> updateOrder({
    required String id,
    required int expectedVersion,
    required List<SqlOrderLine> items,
  }) async {
    final data = _object(
      await _send(
        'PUT',
        'api/orders/${_pathId(id)}',
        token: _credential(),
        body: {
          'expected_version': expectedVersion,
          'items': items.map((i) => i.toJson()).toList(),
        },
      ),
    );
    return _version(data['version']);
  }

  Future<SqlQuantityChange> increaseQuantity({
    required String itemId,
    required int quantity,
  }) async {
    final data = _object(
      await _send(
        'POST',
        'api/orders/items/${_pathId(itemId)}/quantity',
        token: _credential(),
        body: {'quantity': quantity},
      ),
    );
    return SqlQuantityChange(
      _version(data['quantity']),
      _version(data['version']),
    );
  }

  Future<List<Map<String, dynamic>>> accounts() async =>
      _rows(await _send('GET', 'api/users/', token: _credential()));
  static SqlAccountChange _accountChange(dynamic result) {
    final data = _object(result), flag = data['must_change_password'];
    if (flag != null && flag is! bool) {
      _invalid();
    }
    return SqlAccountChange(
      _id(data['id']),
      _version(data['version']),
      flag as bool?,
    );
  }

  Future<SqlAccountChange> createAccount({
    required String username,
    required String password,
    required String displayName,
    required List<String> roles,
    String? existingProfileId,
  }) async => _accountChange(
    await _send(
      'POST',
      'api/users/',
      token: _credential(),
      expectedStatus: 201,
      body: {
        'username': username,
        'password': password,
        'display_name': displayName,
        'roles': roles,
        if (existingProfileId != null)
          'existing_profile_id': _pathId(existingProfileId),
      },
    ),
  );
  Future<SqlAccountChange> updateAccount({
    required String id,
    required int expectedVersion,
    required bool active,
    required List<String> roles,
  }) async => _accountChange(
    await _send(
      'PUT',
      'api/users/${_pathId(id)}',
      token: _credential(),
      body: {
        'expected_version': expectedVersion,
        'active': active,
        'roles': roles,
      },
    ),
  );
  Future<SqlAccountChange> resetPassword({
    required String id,
    required int expectedVersion,
    required String password,
  }) async => _accountChange(
    await _send(
      'POST',
      'api/users/${_pathId(id)}/password',
      token: _credential(),
      body: {'expected_version': expectedVersion, 'password': password},
    ),
  );
  void close() {
    _closed = true;
    _forget(clearStorage: false);
    _changes.close();
    if (_ownsClient) {
      _client.close();
    }
  }
}
