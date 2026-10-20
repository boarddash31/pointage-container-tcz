import 'package:flutter/material.dart';
import '../data/pointage_repository.dart';
import '../domain/container_number.dart';
import 'pointage_screens.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key,required this.repository});
  final PointageRepository repository;
  @override State<AdminScreen> createState()=>_AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  DateTime day=DateTime.now();String? selectedClient,selectedArmateur;
  late Future<List<Map<String,dynamic>>> activity,profiles,clients,armateurs,audit,forced;
  late Future<List<TruckVisit>> visits;
  String dateString(DateTime x)=>'${x.year}-${x.month.toString().padLeft(2,'0')}-${x.day.toString().padLeft(2,'0')}';
  @override void initState(){super.initState();refresh();}
  void refresh(){
    final db=widget.repository.client;
    setState((){
      activity=db.rpc('hourly_activity',params:{'p_day':dateString(day)})
        .then((x)=>List<Map<String,dynamic>>.from(x as List));
      profiles=db.from('profiles').select('id,display_name,active,user_roles(role)').order('display_name')
        .then((x)=>List<Map<String,dynamic>>.from(x));
      clients=db.from('clients').select('id,code,name').order('name')
        .then((x)=>List<Map<String,dynamic>>.from(x));
      armateurs=db.from('armateurs').select('id,name').order('name')
        .then((x)=>List<Map<String,dynamic>>.from(x));
      audit=db.from('audit_logs').select('entity,entity_id,action,actor_id,occurred_at,reason')
        .order('occurred_at',ascending:false).limit(100)
        .then((x)=>List<Map<String,dynamic>>.from(x));
      forced=widget.repository.forcedActions();
      visits=widget.repository.visits(insideOnly:false);
    });
  }
  Future<void> pickDate() async {
    final d=await showDatePicker(context:context,initialDate:day,
      firstDate:DateTime(2020),lastDate:DateTime.now());
    if(d!=null){day=d;refresh();}
  }
  Future<void> setRole(String user,String role,bool enabled) async {
    try{await widget.repository.client.rpc('set_user_role',params:{
      'p_user':user,'p_role':role,'p_enabled':enabled,
    });refresh();}catch(e){if(mounted)message(context,'Rôle refusé : $e');}
  }
  Future<void> inviteUser() async {
    final email=TextEditingController(),name=TextEditingController();
    String role='entree';
    try {
      final invited=await showDialog<bool>(context:context,builder:(dialog)=>StatefulBuilder(
        builder:(dialog,update)=>AlertDialog(
          title:const Text('Inviter un agent'),
          content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
            TextField(controller:email,keyboardType:TextInputType.emailAddress,
              decoration:const InputDecoration(labelText:'Email professionnel *')),
            const SizedBox(height:10),
            TextField(controller:name,decoration:const InputDecoration(labelText:'Nom affiché')),
            const SizedBox(height:10),
            DropdownButtonFormField<String>(initialValue:role,
              decoration:const InputDecoration(labelText:'Premier rôle *'),
              items:[for(final value in ['entree','engin','sortie','viewer','admin'])
                DropdownMenuItem(value:value,child:Text(value))],
              onChanged:(value){if(value!=null)update(()=>role=value);}),
            const SizedBox(height:10),
            const Text('Le compte reçoit une invitation par email pour définir son accès.'),
          ])),
          actions:[TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('Annuler')),
            FilledButton(onPressed:()async{
              if(!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())){
                message(dialog,'Adresse email invalide.');return;
              }
              try{
                await widget.repository.client.functions.invoke('invite-user',body:{
                  'email':email.text.trim(),'name':name.text.trim(),'role':role,
                });
                if(dialog.mounted)Navigator.pop(dialog,true);
              }catch(e){if(dialog.mounted)message(dialog,'Invitation refusée : $e');}
            },child:const Text('Envoyer invitation'))],
        )));
      if(invited==true&&mounted){message(context,'Invitation envoyée.');refresh();}
    } finally {email.dispose();name.dispose();}
  }
  Future<void> addClient() async {
    final code=TextEditingController(),name=TextEditingController();
    await showDialog(context:context,builder:(d)=>AlertDialog(title:const Text('Nouveau client'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:code,decoration:const InputDecoration(labelText:'Code')),
        const SizedBox(height:10),TextField(controller:name,decoration:const InputDecoration(labelText:'Nom'))]),
      actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Annuler')),
        FilledButton(onPressed:()async{try{await widget.repository.client.rpc('create_client',params:{
          'p_code':code.text,'p_name':name.text,
        });if(d.mounted)Navigator.pop(d);refresh();}
        catch(e){if(d.mounted)message(d,'Client refusé : $e');}},child:const Text('Créer'))]));
    code.dispose();name.dispose();
  }
  Future<void> assignClient() async {
    if(selectedClient==null||selectedArmateur==null){message(context,'Choisissez client et armateur.');return;}
    try{await widget.repository.client.rpc('assign_client_armateur',params:{
      'p_client':selectedClient,'p_armateur':selectedArmateur,
      'p_from':dateString(day),
    });if(mounted)message(context,'Affectation enregistrée.');}
    catch(e){if(mounted)message(context,'Affectation refusée : $e');}
  }
  Future<void> reconcileForced(Map<String,dynamic> action) async {
    final controller=TextEditingController();
    final reference=await showDialog<String>(context:context,builder:(dialog)=>AlertDialog(
      title:const Text('Rapprochement externe'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('${action['container_number']} · ${action['reason']}'),
        const SizedBox(height:12),
        TextField(controller:controller,
          decoration:const InputDecoration(labelText:'Référence dans l’autre base *')),
      ]),actions:[
        TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Annuler')),
        FilledButton(onPressed:()=>Navigator.pop(dialog,controller.text.trim()),
          child:const Text('Marquer rapproché')),
      ]));
    controller.dispose();
    if(reference==null)return;
    try{
      await widget.repository.resolveForcedAction(action['id'] as String,reference);
      if(mounted){message(context,'Exception rapprochée avec référence $reference.');refresh();}
    }catch(e){if(mounted)message(context,'Rapprochement refusé : $e');}
  }
  Future<void> registerObservedContainer() async {
    final number=TextEditingController(),iso=TextEditingController();
    try{
      final lines=await armateurs;
      if(!mounted)return;
      String? line=selectedArmateur;
      await showDialog(context:context,builder:(dialog)=>StatefulBuilder(
        builder:(dialog,update)=>AlertDialog(
          title:const Text('Conteneur observé hors référentiel'),
          content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
            TextField(controller:number,textCapitalization:TextCapitalization.characters,
              maxLength:11,decoration:const InputDecoration(labelText:'Numéro ISO 6346 *')),
            const SizedBox(height:10),TextField(controller:iso,
              textCapitalization:TextCapitalization.characters,maxLength:4,
              decoration:const InputDecoration(labelText:'Code ISO *')),
            const SizedBox(height:10),DropdownButtonFormField<String>(initialValue:line,
              isExpanded:true,decoration:const InputDecoration(labelText:'Armateur *'),
              items:[for(final x in lines)DropdownMenuItem<String>(
                value:x['id'] as String,child:Text(x['name'].toString(),
                  overflow:TextOverflow.ellipsis))],
              onChanged:(v)=>update(()=>line=v)),
            const SizedBox(height:10),const Text('Enregistrer le référentiel ne crée pas de stock yard.'),
          ])),actions:[
            TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Annuler')),
            FilledButton(onPressed:()async{
              final canonical=ContainerNumber.normalize(number.text);
              if(!ContainerNumber.isValid(canonical)||line==null||
                  !RegExp(r'^[0-9A-Z]{4}$').hasMatch(iso.text.trim().toUpperCase())){
                message(dialog,'Numéro, code ISO ou armateur invalide.');return;
              }
              try{
                await widget.repository.client.rpc('register_observed_container',params:{
                  'p_number':canonical,'p_iso':iso.text.trim().toUpperCase(),
                  'p_armateur':line,
                });
                if(dialog.mounted)Navigator.pop(dialog);
                if(mounted){
                  message(context,'Conteneur ajouté au référentiel, sans stock fictif.');
                  refresh();
                }
              }catch(e){if(dialog.mounted)message(dialog,'Ajout refusé : $e');}
            },child:const Text('Enregistrer')),
          ])));
    }catch(e){if(mounted)message(context,'Catalogue indisponible : $e');}
    finally{number.dispose();iso.dispose();}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Administration · TCZ'),actions:[
      IconButton(icon:const Icon(Icons.refresh),tooltip:'Actualiser',onPressed:refresh)]),
    body:ListView(padding:const EdgeInsets.all(18),children:[
      Wrap(spacing:12,runSpacing:8,children:[
        OutlinedButton.icon(onPressed:pickDate,icon:const Icon(Icons.calendar_today),
          label:Text(dateString(day))),
        OutlinedButton.icon(onPressed:()=>Navigator.push(context,
          MaterialPageRoute(builder:(_)=>FreepoolScreen(repository:widget.repository))),
          icon:const Icon(Icons.table_chart),label:const Text('Freepool')),
      ]),
      const SizedBox(height:15),
      FutureBuilder<List<TruckVisit>>(future:visits,builder:(c,s){
        if(!s.hasData)return const LinearProgressIndicator();
        final filtered=s.data!.where((v)=>
          (selectedArmateur==null||v.armateur==selectedArmateur)&&
          (v.enteredAt.toLocal().year==day.year&&v.enteredAt.toLocal().month==day.month&&
            v.enteredAt.toLocal().day==day.day)).toList();
        final inside=s.data!.where((v)=>v.isInside).length;
        final dwell=filtered.where((v)=>v.exitedAt!=null).map((v)=>
          DateTime.parse(v.exitedAt!).difference(v.enteredAt).inMinutes).toList();
        return Wrap(spacing:12,runSpacing:10,children:[
          _metric('Entrées du jour','${filtered.length}',Icons.login),
          _metric('Camions présents','$inside',Icons.local_shipping),
          _metric('Attente Engin','${s.data!.where((v)=>v.isInside&&v.needsEngin).length}',Icons.handyman),
          _metric('Séjour moyen',dwell.isEmpty?'—':'${dwell.reduce((a,b)=>a+b)~/dwell.length} min',Icons.timer),
        ]);
      }),
      const SizedBox(height:24),Text('Activité horaire',style:Theme.of(context).textTheme.titleLarge),
      const Text('Entrée / Engin / Sortie · heures 00–23, fuseau Maroc'),
      FutureBuilder<List<Map<String,dynamic>>>(future:activity,builder:(c,s){
        if(s.hasError)return Text('Erreur : ${s.error}');
        if(!s.hasData)return const LinearProgressIndicator();
        final byStage={for(final stage in ['ENTREE','ENGIN','SORTIE']) stage:
          {for(final row in s.data!.where((x)=>x['stage']==stage))
            row['hour'] as int:row['total'] as int}};
        return SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(
          columns:[const DataColumn(label:Text('Étape')),
            for(var h=0;h<24;h++)DataColumn(label:Text(h.toString().padLeft(2,'0')))],
          rows:[for(final stage in byStage.keys)DataRow(cells:[DataCell(Text(stage)),
            for(var h=0;h<24;h++)DataCell(Text('${byStage[stage]?[h]??0}'))])],
        ));
      }),
      const SizedBox(height:25),Row(children:[
        Expanded(child:Text('Utilisateurs et rôles',style:Theme.of(context).textTheme.titleLarge)),
        IconButton(onPressed:inviteUser,icon:const Icon(Icons.person_add_alt_1),
          tooltip:'Inviter un agent'),
      ]),
      const Text('Invitez les agents par email, puis ajustez leurs rôles ci-dessous.'),
      FutureBuilder<List<Map<String,dynamic>>>(future:profiles,builder:(c,s){
        if(s.hasError)return Text('Erreur : ${s.error}');
        if(!s.hasData)return const LinearProgressIndicator();
        return Column(children:[for(final p in s.data!) Card(child:ExpansionTile(
          title:Text((p['display_name'] as String).isEmpty?p['id']:p['display_name']),
          subtitle:Text('${p['id']} · ${p['active']?'Actif':'Inactif'}'),
          children:[for(final role in ['entree','engin','sortie','viewer','admin'])
            SwitchListTile(title:Text(role),
              value:(p['user_roles'] as List).any((x)=>x['role']==role),
              onChanged:(v)=>setRole(p['id'] as String,role,v))],))]);
      }),
      const SizedBox(height:24),Row(children:[Expanded(child:Text('Clients et armateurs',
        style:Theme.of(context).textTheme.titleLarge)),
        IconButton(onPressed:addClient,icon:const Icon(Icons.add),tooltip:'Créer client')]),
      FutureBuilder<List<Map<String,dynamic>>>(future:clients,builder:(c,s)=>
        s.hasData?DropdownButtonFormField<String>(initialValue:selectedClient,
          decoration:const InputDecoration(labelText:'Client'),
          items:[for(final x in s.data!)DropdownMenuItem(value:x['id'],child:Text(x['name']))],
          onChanged:(v)=>setState(()=>selectedClient=v)):
        const LinearProgressIndicator()),
      const SizedBox(height:12),FutureBuilder<List<Map<String,dynamic>>>(future:armateurs,builder:(c,s)=>
        s.hasData?DropdownButtonFormField<String>(initialValue:selectedArmateur,
          decoration:const InputDecoration(labelText:'Armateur'),
          items:[for(final x in s.data!)DropdownMenuItem(value:x['id'],child:Text(x['name']))],
          onChanged:(v)=>setState(()=>selectedArmateur=v)):
        const LinearProgressIndicator()),
      const SizedBox(height:10),FilledButton.tonal(onPressed:assignClient,
        child:const Text('Affecter à partir de la date choisie')),
      const SizedBox(height:25),Text('Prises forcées à rapprocher',
        style:Theme.of(context).textTheme.titleLarge),
      const Text('Exceptions auditables sans inventaire fictif dans le yard.'),
      FutureBuilder<List<Map<String,dynamic>>>(future:forced,builder:(c,s){
        if(s.hasError)return Text('Erreur : ${s.error}');
        if(!s.hasData)return const LinearProgressIndicator();
        final open=s.data!.where((x)=>x['resolved_at']==null).toList();
        if(open.isEmpty)return const ListTile(title:Text('Aucune exception non rapprochée.'));
        return Column(children:[for(final x in open)Card(child:ListTile(
          leading:const Icon(Icons.report_problem_outlined),
          title:Text(x['container_number'].toString()),
          subtitle:Text('${x['occurred_at']} · ${x['reason']}'),
          trailing:TextButton(onPressed:()=>reconcileForced(x),
            child:const Text('Rapprocher'))))]);
      }),
      const SizedBox(height:12),OutlinedButton.icon(onPressed:registerObservedContainer,
        icon:const Icon(Icons.add_box_outlined),
        label:const Text('Ajouter un conteneur observé')),
      const SizedBox(height:25),Text('Journal d’audit',style:Theme.of(context).textTheme.titleLarge),
      FutureBuilder<List<Map<String,dynamic>>>(future:audit,builder:(c,s)=>
        s.hasData?Column(children:[for(final x in s.data!)ListTile(
          title:Text('${x['action']} · ${x['entity']}'),
          subtitle:Text('${x['occurred_at']} · ${x['actor_id']} · ${x['entity_id']}'))]):
        s.hasError?Text('${s.error}'):const LinearProgressIndicator()),
    ]),
  );
  Widget _metric(String title,String value,IconData icon)=>SizedBox(width:195,child:Card(
    child:Padding(padding:const EdgeInsets.all(15),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon),const SizedBox(height:8),
        Text(title),Text(value,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold))]))));
}
