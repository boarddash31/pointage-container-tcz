import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointage_container/data/document_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  for(final current in [true,false]){
    test(current?'local render failure downloads the regenerated Marsa form':'local render failure rejects a stale server PDF',()async{
      final paths=<String>[];
      final client=SupabaseClient('https://example.supabase.co','test',httpClient:MockClient((request)async{
        paths.add(request.url.path);
        if(request.url.path.contains('/rpc/'))return http.Response('{}',200,headers:{'content-type':'application/json'});
        if(request.url.path.contains('/functions/'))return http.Response(jsonEncode({'path':current?'visit/doc-marsa-v1.pdf':'visit/doc.pdf',if(current)'template_version':'marsa-v1'}),200,headers:{'content-type':'application/json'});
        if(request.url.path.contains('/storage/'))return http.Response.bytes([37,80,68,70],200);
        return http.Response('null',200,headers:{'content-type':'application/json'});
      }),authOptions:const AuthClientOptions(autoRefreshToken:false));
      final service=DocumentService(client,renderPdf:({required document,visitData})async=>throw StateError('Simulated local asset failure'));
      final future=service.prepare({'id':'doc','kind':'ENTREE','storage_path':'visit/doc.pdf'});
      if(current){expect(await future,[37,80,68,70]);expect(paths.last,contains('doc-marsa-v1.pdf'));}
      else{await expectLater(future,throwsStateError);expect(paths.where((p)=>p.contains('/storage/')),isEmpty);}
      expect(paths.any((p)=>p.contains('/functions/')),true);
      await client.dispose();
    });
  }
}
