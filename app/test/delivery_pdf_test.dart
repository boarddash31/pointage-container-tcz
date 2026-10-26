import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:pointage_container/data/bon_pdf_builder.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('simplified delivery PDF renders a twin using the archived snapshot',()async{
    final bytes=await BonPdfBuilder.buildA5(document:{'id':'doc-123','visit_id':'visit-123','kind':'SORTIE','created_at':'2026-10-23T12:00:00Z','snapshot':{
      'entry_kind':'empty','plate':'12345-A-06','driver_cin':'AB12345','entered_at':'2026-10-23T11:00:00Z',
      'container_number':'CSQU3054383','iso_code':'22G1','armateur_id':'MAE','carrier_booking_reference':'EDO-1',
      'is_twin':true,'container_number_2':'AGCU1111117','iso_code_2':'22G1','armateur_id_2':'CMACGM','booking_reference_2':'EDO-2',
    },'print_context':{'agent_name':'yfathi','visit_number':213216,'created_at_local':'2026-10-23 14:35:06'}});
    expect(String.fromCharCodes(bytes.take(5)),'%PDF-');
    expect(bytes.length,greaterThan(2000));
    const preview=String.fromEnvironment('DELIVERY_PDF_PREVIEW');
    if(preview.isNotEmpty)await File(preview).writeAsBytes(bytes);
  });
  test('Marsa Maroc decharge form fits two rows and long order references on A5',()async{
    final document=<String,dynamic>{'id':'doc-decharge','visit_id':'visit-456','kind':'DEPOSE','snapshot':{
      'entry_kind':'loaded','plate':'87784-B-6','driver_cin':'T284529','container_number':'CSQU3054383','iso_code':'22G1','armateur_id':'MAE',
      'is_twin':true,'container_number_2':'AGCU1111117','iso_code_2':'22G1','armateur_id_2':'CMACGM',
      'carrier_booking_reference':'A'*150,'booking_reference_2':'B'*150,
    },'print_context':{'agent_name':'Agent de restitution','visit_number':213217,'created_at_local':'2026-10-23 14:35:06'}};
    final bytes=await BonPdfBuilder.buildA5(document:document);
    expect(String.fromCharCodes(bytes.take(5)),'%PDF-');
    const preview=String.fromEnvironment('DECHARGE_PDF_PREVIEW');
    if(preview.isNotEmpty){
      final sample=await BonPdfBuilder.buildA5(document:{...document,'snapshot':{
        ...(document['snapshot'] as Map<String,dynamic>),'carrier_booking_reference':'ERO-2026-001','booking_reference_2':'ERO-2026-002'}});
      await File(preview).writeAsBytes(sample);
    }
  });
}
