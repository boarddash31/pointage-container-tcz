import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FreepoolExport {
  FreepoolExport(this.client);
  final SupabaseClient client;
  static const categories = ['20 DV','40 DV ST','40 DV HC','45 DV',
    'FRIGO 20','FRIGO 40','OT&FL&HP&CT','UNCLASSIFIED'];

  Future<List<Map<String,dynamic>>> rows(DateTime day,{String? clientId,bool anyTime=false}) async {
    final date='${day.year}-${day.month.toString().padLeft(2,'0')}-${day.day.toString().padLeft(2,'0')}';
    final result=<Map<String,dynamic>>[];
    var offset=0;
    while(true){
      final batch=List<Map<String,dynamic>>.from(await client.rpc('freepool_rows',params:{
        'p_day':date,'p_client':clientId,'p_any_time':anyTime,
      }).range(offset,offset+999));
      result.addAll(batch);
      if(batch.length<1000)break;
      offset+=1000;
    }
    return result;
  }

  Map<String,num> summary(List<Map<String,dynamic>> rows) {
    final totals={for(final category in categories) category:0.0};
    for(final row in rows){
      final category=(row['category'] as String?)??'UNCLASSIFIED';
      totals[category]=(totals[category]??0)+(row['evp'] as num? ?? 0);
    }
    return totals;
  }

  List<int> workbook(List<Map<String,dynamic>> rows,DateTime day,
      {String clientName='Tous les clients',bool anyTime=false}) {
    final book=Excel.createExcel();
    book.rename('Sheet1','PARAMETRES');
    void write(Sheet sheet,int r,int c,Object? value){
      final cell=sheet.cell(CellIndex.indexByColumnRow(columnIndex:c,rowIndex:r));
      cell.value=switch(value){
        int v=>IntCellValue(v),double v=>DoubleCellValue(v),
        _=>TextCellValue(value?.toString()??''),
      };
    }
    final parameter=book['PARAMETRES'];
    write(parameter,0,0,'RAPPORT FREEPOOL - PARAMETRES');
    write(parameter,1,0,'Client');write(parameter,1,1,clientName);
    write(parameter,2,0,'Date de référence');write(parameter,2,1,
      '${day.year}-${day.month.toString().padLeft(2,'0')}-${day.day.toString().padLeft(2,'0')}');
    write(parameter,3,0,'Mode');write(parameter,3,1,anyTime?'Présence à un moment de la journée':'Stock fin de journée');
    write(parameter,4,0,'EVP 20 pieds');write(parameter,4,1,1);
    write(parameter,5,0,'EVP 40 pieds');write(parameter,5,1,2);
    write(parameter,6,0,'EVP 45 pieds');write(parameter,6,1,2.25);
    write(parameter,8,0,'Limite');write(parameter,8,1,
      'Sans inventaire d’ouverture importé, seules les visites capturées sont incluses.');
    write(parameter,9,0,'ISO non classé');write(parameter,9,1,
      'Contrôler les règles ISO; aucun EVP implicite.');
    final movements=book['MOUVEMENTS'];
    const heads=['CONTENEUR','CLIENT','ARMATEUR','CODE ISO','TYPE',
      'ARRIVEE TERMINAL','SORTIE TERMINAL','STATUT A DATE','EVP','POSITION'];
    for(var c=0;c<heads.length;c++) {
      write(movements,0,c,heads[c]);
    }
    for(var i=0;i<rows.length;i++){
      final x=rows[i],values=[x['container_number'],x['client_id'],x['armateur_id'],
        x['iso_code'],x['category']??'UNCLASSIFIED',x['arrived_at'],x['departed_at'],
        'PRESENT',x['evp']??'',x['position']??''];
      for(var c=0;c<values.length;c++) {
        write(movements,i+1,c,values[c]);
      }
    }
    for(final category in categories){
      final sheet=book[category];
      const columns=['CONTENEUR','LIGNE','CODE ISO','DATE D ARRIVEE AU TERMINAL',
        'HEURE D ARRIVEE AU TERMINAL','CLIENT','EVP'];
      for(var c=0;c<columns.length;c++) {
        write(sheet,0,c,columns[c]);
      }
      var r=1;
      for(final x in rows.where((x)=>(x['category']??'UNCLASSIFIED')==category)){
        final at=DateTime.parse(x['arrived_at'].toString()).toLocal();
        final vals=[x['container_number'],x['armateur_id'],x['iso_code'],
          '${at.year}-${at.month.toString().padLeft(2,'0')}-${at.day.toString().padLeft(2,'0')}',
          '${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}',
          x['client_id'],x['evp']??''];
        for(var c=0;c<vals.length;c++) {
          write(sheet,r,c,vals[c]);
        }r++;
      }
    }
    final recap=book['RECAP'];
    write(recap,0,0,'ARMATEUR');
    for(var c=0;c<categories.length;c++) {
      write(recap,0,c+1,categories[c]);
    }
    write(recap,0,categories.length+1,'TOTAL EVP');
    final armateurs=rows.map((x)=>x['armateur_id'].toString()).toSet().toList()..sort();
    for(var r=0;r<armateurs.length;r++){
      write(recap,r+1,0,armateurs[r]);var total=0.0;
      for(var c=0;c<categories.length;c++){
        final grouped=rows.where((x)=>x['armateur_id']==armateurs[r]&&
          (x['category']??'UNCLASSIFIED')==categories[c]).toList();
        write(recap,r+1,c+1,grouped.length);
        total+=grouped.fold<double>(0,(v,x)=>v+((x['evp'] as num?)?.toDouble()??0));
      }
      write(recap,r+1,categories.length+1,total);
    }
    return book.encode()??<int>[];
  }

  Future<void> share(List<int> bytes,DateTime day) async {
    if(bytes.isEmpty)throw StateError('Classeur vide');
    final name='Freepool_${day.year}-${day.month.toString().padLeft(2,'0')}-${day.day.toString().padLeft(2,'0')}.xlsx';
    await SharePlus.instance.share(ShareParams(
      files:[XFile.fromData(Uint8List.fromList(bytes),
        mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      fileNameOverrides:[name],
    ));
  }
}
