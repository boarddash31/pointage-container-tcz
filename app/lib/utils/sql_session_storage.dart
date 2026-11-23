import '../data/sql_session_storage.dart';
import 'sql_session_storage_stub.dart'
    if (dart.library.js_interop) 'sql_session_storage_web.dart'
    as impl;

SqlSessionStorage? browserSessionStorage() => impl.browserSessionStorage();
