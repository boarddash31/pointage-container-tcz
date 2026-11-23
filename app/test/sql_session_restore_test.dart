import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointage_container/data/sql_session_storage.dart';
import 'package:pointage_container/data/sqlserver_api.dart';
import 'package:pointage_container/main.dart';

const actor = '11111111-1111-4111-8111-111111111111';
const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final now = DateTime.utc(2026, 11, 22, 10);
final expiry = now.add(const Duration(hours: 8));

class MemorySessionStorage implements SqlSessionStorage {
  String? value;
  @override
  String? read() => value;
  @override
  void write(String data) => value = data;
  @override
  void clear() => value = null;
}

class BlockedSessionStorage extends MemorySessionStorage {
  @override
  String? read() => throw StateError('Browser storage disabled');
  @override
  void write(String data) => throw StateError('Browser storage disabled');
  @override
  void clear() => throw StateError('Browser storage disabled');
}

http.Response json(Object data, [int code = 200]) => http.Response(
  jsonEncode(data),
  code,
  headers: {'content-type': 'application/json'},
);
String cached({String? base, DateTime? expires}) => jsonEncode({
  'version': 1,
  'api_base': base ?? 'http://172.17.18.208:9091/',
  'token': token,
  'expires_at': (expires ?? expiry).toIso8601String(),
});
SqlServerApi apiFor(
  MemorySessionStorage store,
  Future<http.Response> Function(http.Request) handle,
) => SqlServerApi(
  baseUri: Uri.parse('http://172.17.18.208:9091'),
  allowInsecureHttp: true,
  now: () => now,
  storage: store,
  client: MockClient((request) async {
    if (request.url.path == '/api/auth/login') {
      return json({
        'user_id': actor,
        'access_token': token,
        'token_type': 'Bearer',
        'must_change_password': false,
        'expires_at': expiry.toIso8601String(),
      });
    }
    expect(request.headers['authorization'], 'Bearer $token');
    return handle(request);
  }),
);
Future<void> login(SqlServerApi api) async {
  await api.login(username: 'agent', password: 'only-in-login-body');
}

void main() {
  test('disabled browser storage does not prevent login or logout', () async {
    final api = apiFor(
      BlockedSessionStorage(),
      (_) async => http.Response('', 204),
    );
    expect(await api.restoreSession(), isNull);
    await login(api);
    expect(api.session, isNotNull);
    await api.logout();
    expect(api.session, isNull);
    api.close();
  });

  test(
    'a later unauthorized request clears both live session and tab cache',
    () async {
      final store = MemorySessionStorage();
      final api = apiFor(
        store,
        (_) async => json({'error': 'authentication_required'}, 401),
      );
      await login(api);
      await expectLater(api.operators(), throwsA(isA<SqlApiException>()));
      expect(api.session, isNull);
      expect(store.value, isNull);
      api.close();
    },
  );
  test(
    'reload restores the same token only after server validation, without extending expiry',
    () async {
      final store = MemorySessionStorage();
      final first = apiFor(store, (_) async => json({}));
      await login(first);
      final saved = jsonDecode(store.value!) as Map;
      expect(saved.keys.toSet(), {
        'version',
        'api_base',
        'token',
        'expires_at',
      });
      expect(store.value, isNot(contains('only-in-login-body')));
      first.close();
      expect(store.value, isNotNull);
      var checks = 0;
      final second = apiFor(store, (request) async {
        expect(request.url.path, '/api/auth/session');
        checks++;
        return json({'user_id': actor, 'must_change_password': false});
      });
      expect(second.session, isNull);
      expect((await second.restoreSession())!.userId, actor);
      expect(second.sessionToken, token);
      expect(second.session!.expiresAt, expiry);
      await second.restoreSession();
      expect(checks, 1);
      second.close();
    },
  );

  test(
    'revoked or disabled account is rejected and the tab cache is cleared',
    () async {
      final store = MemorySessionStorage()..value = cached();
      final api = apiFor(
        store,
        (_) async => json({'error': 'authentication_required'}, 401),
      );
      expect(await api.restoreSession(), isNull);
      expect(store.value, isNull);
      expect(api.sessionToken, isNull);
      api.close();
    },
  );

  test(
    'expired, malformed and different-backend caches never send their token',
    () async {
      for (final value in [
        '{invalid',
        cached(expires: now),
        cached(base: 'https://other.example/'),
      ]) {
        final store = MemorySessionStorage()..value = value;
        final api = apiFor(store, (_) async {
          fail('Invalid cache sent to the server');
        });
        expect(await api.restoreSession(), isNull);
        expect(store.value, isNull);
        api.close();
      }
    },
  );

  test(
    'a server outage keeps the cache for retry but does not open a session',
    () async {
      final store = MemorySessionStorage()..value = cached();
      var available = false;
      final api = apiFor(
        store,
        (_) async => available
            ? json({'user_id': actor, 'must_change_password': false})
            : json({'error': 'database_unavailable'}, 503),
      );
      await expectLater(api.restoreSession(), throwsA(isA<SqlApiException>()));
      expect(store.value, isNotNull);
      expect(api.session, isNull);
      available = true;
      expect(await api.restoreSession(), isNotNull);
      api.close();
    },
  );

  test(
    'restored temporary passwords still cannot access business requests',
    () async {
      final store = MemorySessionStorage()..value = cached();
      final api = apiFor(
        store,
        (_) async => json({'user_id': actor, 'must_change_password': true}),
      );
      expect((await api.restoreSession())!.mustChangePassword, isTrue);
      expect(
        () => api.request('GET', 'api/operators'),
        throwsA(isA<SqlApiException>()),
      );
      api.close();
    },
  );

  test(
    'logout during restoration cannot resurrect a session or its saved token',
    () async {
      final store = MemorySessionStorage()..value = cached();
      final response = Completer<http.Response>();
      final api = apiFor(store, (_) => response.future);
      final restoring = api.restoreSession();
      await Future<void>.delayed(Duration.zero);
      await api.logout();
      response.complete(
        json({'user_id': actor, 'must_change_password': false}),
      );
      expect(await restoring, isNull);
      expect(store.value, isNull);
      expect(api.session, isNull);
      api.close();
    },
  );

  test('logout and password change remove the saved token', () async {
    for (final changePassword in [false, true]) {
      final store = MemorySessionStorage();
      final api = apiFor(store, (_) async => http.Response('', 204));
      await login(api);
      if (changePassword) {
        await api.changePassword(
          currentPassword: 'old-password-value',
          newPassword: 'a-new-password-value',
        );
      } else {
        await api.logout();
      }
      expect(store.value, isNull);
      expect(api.session, isNull);
      api.close();
    }
  });

  testWidgets(
    'reload checks the saved session before showing the temporary-password form',
    (tester) async {
      final store = MemorySessionStorage()..value = cached();
      final response = Completer<http.Response>();
      final api = apiFor(store, (_) => response.future);
      await tester.pumpWidget(MaterialApp(home: SqlAuthGate(api: api)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Identifiant'), findsNothing);
      response.complete(json({'user_id': actor, 'must_change_password': true}));
      await tester.pumpAndSettle();
      expect(find.text('Choisir votre mot de passe'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );
}
