/// Per-tab session cache. Passwords and user roles must never be stored here.
abstract interface class SqlSessionStorage {
  String? read();
  void write(String value);
  void clear();
}
