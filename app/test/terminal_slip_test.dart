import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/domain/terminal_slip.dart';

void main(){
  test('entry reprint preserves the archived empty slot and the document author',(){
    final slip=TerminalSlip.fromDocument({'kind':'ENTREE','visit_id':'real-visit-id',
      'snapshot':{'entry_kind':'empty','plate':'87784-B-6','driver_cin':'T284529','container_number':null,'iso_code':'42G1','armateur_id':'MAE'},
      'print_context':{'agent_name':'yfathi','visit_number':213216,'created_at_local':'2026-10-23 14:35:06'}},
      visitData:{'entry_kind':'loaded','plate':'CHANGED','container_number':'CSQU3054383','agent_name':'Current viewer'});
    expect(slip.title,'Bon Charge');expect(slip.rows.single[3],'');expect(slip.rows.single[2],'');
    expect(slip.plate,'87784-B-6');expect(slip.agent,'yfathi');expect(slip.visit,'213216');
    expect(slip.date,'2026-10-23 14:35:06');
  });
  test('restitution and pickup forms preserve both actual movement containers',(){
    final snapshot={'entry_kind':'loaded','container_number':'CSQU3054383','iso_code':'22G1','armateur_id':'MAE','is_twin':true,
      'container_number_2':'AGCU1111117','iso_code_2':'22G1','armateur_id_2':'CMACGM','carrier_booking_reference':'ERO-1','booking_reference_2':'ERO-2'};
    final decharge=TerminalSlip.fromDocument({'kind':'DEPOSE','snapshot':snapshot});
    expect(decharge.title,'Bon Décharge');expect(decharge.rows.length,2);expect(decharge.rows[0][1],'In');
    expect(decharge.rows[1].sublist(3,6),['AGCU1111117','CMACGM','22G1']);
    expect(decharge.references,['ERO-1','ERO-2']);
    final charge=TerminalSlip.fromDocument({'kind':'PRISE','snapshot':{...snapshot,'entry_kind':'empty','container_number':null,
      'container_number_2':null,'event':{'container':'CSQU3054383','container_2':'AGCU1111117'}}});
    expect(charge.title,'Bon Charge');expect(charge.rows[0][1],'Out');expect(charge.rows[0][3],'CSQU3054383');
    expect(charge.rows[1][3],'AGCU1111117');
  });
}
