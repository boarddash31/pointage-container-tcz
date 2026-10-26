import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/data/pointage_repository.dart';
import 'package:pointage_container/domain/booking_group.dart';

DataTransaction row(String id, String client, String line, {bool twin=false}) => DataTransaction.fromJson({
  'id':id,'plate':'12345-A-1','driver_cin':'AB12345','entry_kind':'empty','iso_code':'22G1',
  'armateur_id':line,'entered_at':'2026-10-23T10:00:00Z','creator_name':'Entry','changer_name':'EDI',
  'changed_at':'2026-10-23T11:00:00Z','client_id':client,'client_name':client,
  'client_order_reference':'ORDER-123','bookings':{'reference':'BOOK-123'},
  'container_number':'BOX-$id','is_twin':twin,'container_number_2':twin?'SECOND-$id':null,
});
void main(){
  test('read-only order groups preserve client and carrier booking identity',(){
    final groups=ClientOrderGroup.fromTransactions([row('1','client-a','MSC'),row('2','client-a','MAE'),row('3','client-b','MSC')]);
    expect(groups,hasLength(2));
    expect(groups.first.bookings,hasLength(2));
    expect(groups.first.transactions,hasLength(2));
    expect(groups.first.containerCount,2);
  });
  test('twin counts as one visit and two containers',(){
    final group=ClientOrderGroup.fromTransactions([row('1','client-a','MSC',twin:true)]).single;
    expect(group.transactions,hasLength(1));
    expect(group.containerCount,2);
    expect(group.bookings.single.parts,hasLength(2));
  });
}
