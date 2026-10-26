/// Presentation values for the Charge/Decharge form, derived from the archived event.
class TerminalSlip {
  TerminalSlip._({required this.title,required this.date,required this.visit,
    required this.plate,required this.cin,required this.agent,required this.rows,required this.references});
  final String title,date,visit,plate,cin,agent;
  final List<List<String>> rows;
  final List<String> references;
  static const columns=['VOIE','Hnd','P/V','Conteneur','Ligne','ISO','Lg','Ht','Tp'];
  static const footer=[
    "Société d'Exploitation des Ports SA, au capital de 733.956.000,00 DH -",
    "Angle boulevard Route d'El Jadida et Rue les Papillons, Casablanca - Maroc",
    'Tél (00 212) 522 23 23 24 (L.G) Fax (00 212) 522 23 23 35 - RC :',
    'Casablanca 156717 - CNSS : 7374804 - Taxe Professionnelle : 34770868 -',
    'IF : 1104763 - ICE : 000028283000040 - www.marsamaroc.co.ma',
  ];
  static bool supports(String kind)=>['ENTREE','DEPOSE','PRISE','SORTIE'].contains(kind.toUpperCase());
  static Map<String,dynamic> _map(dynamic value)=>value is Map?Map<String,dynamic>.from(value):{};
  static String _text(dynamic value)=>value?.toString().trim()??'';
  factory TerminalSlip.fromDocument(Map<String,dynamic> document,{Map<String,dynamic>? visitData}){
    final snapshot=_map(document['snapshot']);
    // A later visit state must never rewrite a historical entry or movement.
    final v={...?visitData,...snapshot};
    final event=_map(snapshot['event']);
    final context=_map(document['print_context']);
    final kind=_text(document['kind']).toUpperCase();
    final receiving=kind=='DEPOSE'||(kind!='PRISE'&&v['entry_kind']=='loaded');
    final rows=<List<String>>[];
    for(final suffix in ['',if(v['is_twin']==true)'_2']){
      final movementContainer=event[suffix.isEmpty?'container':'container_2'];
      final container=(kind=='PRISE'||kind=='DEPOSE')&&_text(movementContainer).isNotEmpty
        ?movementContainer:v['container_number$suffix'];
      rows.add([
        _text(v['lane$suffix']),receiving?'In':'Out',_text(v['load_status$suffix']),_text(container),
        _text(v['armateur_id$suffix']),_text(v['iso_code$suffix']),
        _text(v['length$suffix']),_text(v['height$suffix']),_text(v['type$suffix']),
      ]);
    }
    final references=<String>{
      _text(v['carrier_booking_reference']??_map(v['bookings'])['reference']??event['booking']??v['booking']),
      if(v['is_twin']==true)_text(v['booking_reference_2']),
    }..remove('');
    var date=_text(context['created_at_local']);
    if(date.isEmpty){
      final raw=_text(document['created_at']??v['entered_at']);
      final parsed=DateTime.tryParse(raw)?.toLocal();
      if(parsed==null){date=raw;}else{
        String pad(int n)=>n.toString().padLeft(2,'0');
        date='${parsed.year}-${pad(parsed.month)}-${pad(parsed.day)} ${pad(parsed.hour)}:${pad(parsed.minute)}:${pad(parsed.second)}';
      }
    }
    return TerminalSlip._(title:receiving?'Bon Décharge':'Bon Charge',date:date,
      visit:_text(context['visit_number']??snapshot['visit_number']??document['visit_id']??v['id']),
      plate:_text(v['plate']),cin:_text(v['driver_cin']),
      agent:_text(context['agent_name']??document['agent_name']??snapshot['agent_name']),
      rows:rows,references:references.toList());
  }
}
