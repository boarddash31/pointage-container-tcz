import 'dart:js_interop';
import '../data/sql_session_storage.dart';

@JS('sessionStorage')
external _BrowserStorage get _storage;

extension type _BrowserStorage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

class _TabSessionStorage implements SqlSessionStorage {
  static const key = 'zenata.sql.session.v1';
  @override
  String? read() => _storage.getItem(key);
  @override
  void write(String value) => _storage.setItem(key, value);
  @override
  void clear() => _storage.removeItem(key);
}

SqlSessionStorage browserSessionStorage() => _TabSessionStorage();
