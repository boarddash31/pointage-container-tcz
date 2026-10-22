import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bon_pdf_builder.dart';

class DocumentService {
  DocumentService(this.client);
  final SupabaseClient client;
  static const bridgeUrl=String.fromEnvironment('PDF_BRIDGE_URL');
  static const bridgeAutoPrint=bool.fromEnvironment('PDF_BRIDGE_AUTO_PRINT');

  Future<Map<String,dynamic>?> archiveWithBridge(Map<String,dynamic> document,
      {bool print=false}) async {
    if(bridgeUrl.isEmpty)return null;
    final token=client.auth.currentSession?.accessToken;
    if(token==null)throw StateError('Session Supabase requise pour le pont PDF.');
    final base=Uri.parse(bridgeUrl);
    if(base.scheme!='https'&&!(base.scheme=='http'&&
        ['127.0.0.1','localhost','::1'].contains(base.host))){
      throw StateError('Le pont PDF distant exige HTTPS.');
    }
    final uri=base.resolve('/api/documents/archive');
    final response=await http.post(uri,headers:{
      'authorization':'Bearer $token','content-type':'application/json',
    },body:jsonEncode({'document_id':document['id'],'print':print}))
      .timeout(const Duration(seconds:45));
    if(response.statusCode!=200){
      throw StateError('Pont PDF indisponible (${response.statusCode}) : ${response.body}');
    }
    return Map<String,dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<DocumentOutcome> finalizeLatest(String visitId,String kind) async {
    final document=await latest(visitId,kind);
    if(document==null)throw StateError('Bon $kind absent après pointage.');
    final bytes=await prepare(document);
    var shareReady=false,printed=false;
    String? warning;
    if(bridgeUrl.isNotEmpty){
      try{
        final result=await archiveWithBridge(document,print:bridgeAutoPrint);
        shareReady=result!=null;
        printed=result?['print_status']=='submitted_to_printer';
        if(result?['print_status']=='already_requested'){
          warning='Impression déjà demandée au pont : vérifier la file imprimante.';
        }
      }catch(e){warning='Archive réseau / impression à réessayer dans Bons : $e';}
    }
    if(!printed&&!bridgeAutoPrint){
      try{printed=await printPreferredLatest(visitId,kind);}
      catch(e){warning='Impression locale à réessayer dans Bons : $e';}
    }
    return DocumentOutcome(
      shareReady:shareReady,
      printed:printed,
      warning:warning,
      bytes:bytes,
      documentId:document['id'] as String?,
    );
  }

  Future<Map<String,dynamic>?> latest(String visitId,String kind) async =>
    client.from('generated_documents').select('id,visit_id,kind,status,storage_path,snapshot,created_at')
      .eq('visit_id',visitId).eq('kind',kind).order('created_at',ascending:false)
      .limit(1).maybeSingle();

  Future<Uint8List> prepare(Map<String,dynamic> document) async {
    // 1. Generate the modern, crystal-clear A5 Bon with truck visuals and gate-out rules
    try {
      Map<String, dynamic>? visitData;
      final visitId = document['visit_id'] as String?;
      if (visitId != null && visitId.isNotEmpty) {
        try {
          visitData = await client
              .from('truck_visits')
              .select('*,bookings(reference)')
              .eq('id', visitId)
              .maybeSingle();
        } catch (_) {}
      }
      return await BonPdfBuilder.buildA5(
        document: document,
        visitData: visitData,
      );
    } catch (_) {
      // Fallback to storage download if builder fails
      var path = document['storage_path'] as String?;
      if (path == null || path.isEmpty) {
        final response = await client.functions.invoke('generate-bon', body: {
          'document_id': document['id'],
        });
        if (response.status != 200) {
          throw StateError('Génération PDF refusée (${response.status}) : ${response.data}');
        }
        path = (response.data as Map<String, dynamic>)['path'] as String?;
        if (path == null) throw StateError('Chemin du PDF absent.');
      }
      return client.storage.from('pointage-documents').download(path);
    }
  }

  Future<Uint8List?> prepareLatest(String visitId,String kind) async {
    final document=await latest(visitId,kind);
    if(document==null)return null;
    return prepare(document);
  }

  Future<void> recordAction(Map<String,dynamic> document,String action) async {
    try {
      await client.rpc('record_document_action',params:{
        'p_document':document['id'],'p_action':action,
      });
    } catch (_) {
      // Non-critical audit logging: do not crash user flow if RPC fails
    }
  }

  Future<void> printWithDialog(Map<String,dynamic> document,{String printerName=''}) async {
    final bytes=await prepare(document);
    if(printerName.isNotEmpty){
      try {
        final info=await Printing.info();
        if(info.directPrint&&info.canListPrinters){
          final printers=await Printing.listPrinters();
          final matches=printers.where((printer)=>printer.name==printerName);
          if(matches.isNotEmpty){
            await recordAction(document,'DIRECT_PRINT_REQUESTED');
            final printed=await Printing.directPrintPdf(printer:matches.first,
              onLayout:(_)=>bytes,name:'TCZ-${document['kind']}-${document['visit_id']}');
            if(!printed)throw StateError('L’imprimante a refusé le bon.');
            return;
          }
        }
      } catch (_) {}
    }
    await recordAction(document,'PRINT_DIALOG_REQUESTED');
    try {
      await Printing.layoutPdf(onLayout:(_)=>bytes,name:'TCZ-${document['kind']}-${document['visit_id']}');
    } catch (_) {
      await Printing.sharePdf(bytes:bytes,filename:'TCZ-${document['kind']}-${document['visit_id']}.pdf');
    }
  }

  Future<bool> printPreferredLatest(String visitId,String kind) async {
    final printerName=await SharedPreferencesAsync().getString('preferred_printer_name')??'';
    if(printerName.isEmpty)return false;
    final info=await Printing.info();
    if(!info.directPrint||!info.canListPrinters)return false;
    final printers=await Printing.listPrinters();
    final matches=printers.where((printer)=>printer.name==printerName);
    if(matches.isEmpty)return false;
    final document=await latest(visitId,kind);
    if(document==null)return false;
    final bytes=await prepare(document);
    await recordAction(document,'DIRECT_PRINT_REQUESTED');
    return Printing.directPrintPdf(printer:matches.first,onLayout:(_)=>bytes,
      name:'TCZ-$kind-$visitId');
  }

  Future<void> downloadOrShare(Map<String,dynamic> document) async {
    final bytes=await prepare(document);
    await recordAction(document,'SHARE_REQUESTED');
    await Printing.sharePdf(bytes:bytes,
      filename:'TCZ-${document['kind']}-${document['visit_id']}.pdf');
  }
}

class DocumentOutcome {
  const DocumentOutcome({
    required this.shareReady,
    required this.printed,
    this.warning,
    this.bytes,
    this.documentId,
  });
  final bool shareReady, printed;
  final String? warning;
  final Uint8List? bytes;
  final String? documentId;
}
