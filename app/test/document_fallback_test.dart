import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointage_container/data/document_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['ENTREE', 'SORTIE']) {
    final template = kind == 'SORTIE' ? 'gate-out-v1' : 'marsa-v1';
    for (final current in [true, false]) {
      test(
        '$kind local render failure ${current ? 'downloads the current form' : 'rejects a stale server PDF'}',
        () async {
          final paths = <String>[];
          final client = SupabaseClient(
            'https://example.supabase.co',
            'test',
            httpClient: MockClient((request) async {
              paths.add(request.url.path);
              if (request.url.path.contains('/rpc/')) {
                return http.Response(
                  '{}',
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              if (request.url.path.contains('/functions/')) {
                return http.Response(
                  jsonEncode({
                    'path': current
                        ? 'visit/doc-$template.pdf'
                        : kind == 'SORTIE'
                        ? 'visit/doc-marsa-v1.pdf'
                        : 'visit/doc.pdf',
                    'template_version': current ? template : 'marsa-v1',
                  }),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              if (request.url.path.contains('/storage/')) {
                return http.Response.bytes([37, 80, 68, 70], 200);
              }
              return http.Response(
                'null',
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          );
          final service = DocumentService(
            client,
            renderPdf: ({required document, visitData}) async =>
                throw StateError('Simulated local asset failure'),
          );
          final future = service.prepare({
            'id': 'doc',
            'kind': kind,
            'storage_path': 'visit/doc.pdf',
          });
          if (current) {
            expect(await future, [37, 80, 68, 70]);
            expect(paths.last, contains('doc-$template.pdf'));
          } else {
            await expectLater(future, throwsStateError);
            expect(paths.where((p) => p.contains('/storage/')), isEmpty);
          }
          expect(paths.any((p) => p.contains('/functions/')), true);
          await client.dispose();
        },
      );
    }
  }
}
