import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/document_service.dart';
import '../data/freepool_export.dart';
import '../data/pointage_repository.dart';
import '../domain/container_number.dart';

void message(BuildContext context,String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()..showSnackBar(SnackBar(content:Text(text)));

class TruckScene extends StatelessWidget {
  const TruckScene({super.key,required this.kind,this.height=125});
  final String kind; final double height;
  @override Widget build(BuildContext context) => Semantics(
    label:switch(kind){'loaded'=>'Camion avec conteneur sur châssis',
      'depose'=>'Conteneur posé au sol à côté du camion vide',
      'prise'=>'Conteneur chargé sur le châssis du camion',
      _=>'Camion sans conteneur'},
    child:Image.asset('assets/truck-$kind.png',height:height,fit:BoxFit.contain));
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key,required this.repository,required this.canCorrect});
  final PointageRepository repository;final bool canCorrect;
  @override State<EntryScreen> createState()=>_EntryScreenState();
}
class _EntryScreenState extends State<EntryScreen> {
  final form=GlobalKey<FormState>();
  final plate=TextEditingController(),cin=TextEditingController(),booking=TextEditingController();
  final boxes=List.generate(11,(_)=>TextEditingController());
  final focus=List.generate(11,(_)=>FocusNode());
  List<OperatorRecord> operators=[];OperatorRecord? operator;
  String iso='45G1',kind='loaded';bool busy=false;String? lookupHint;
  @override void initState(){super.initState();loadOperators();}
  Future<void> loadOperators() async {
    try{
      final records=await widget.repository.operators();
      if(mounted){
        setState((){
          operators=records;
          if(operator==null&&records.isNotEmpty){
            operator=records.where((o)=>o.id=='MAE').firstOrNull??records.first;
          }
        });
      }
    }catch(_){
      try{
        final raw=await rootBundle.loadString('assets/operators.json');
        if(mounted) {
          final list=(jsonDecode(raw) as List).map((x)=>OperatorRecord.fromJson(x)).toList();
          setState((){
            operators=list;
            if(operator==null&&list.isNotEmpty){
              operator=list.where((o)=>o.id=='MAE').firstOrNull??list.first;
            }
          });
        }
      }catch(_){ if(mounted)message(context,'Catalogue des armateurs indisponible.'); }
    }
  }
  @override void dispose(){for(final c in [plate,cin,booking,...boxes]){c.dispose();}
    for(final f in focus){f.dispose();}super.dispose();}
  String get number=>boxes.map((x)=>x.text).join().toUpperCase();
  Future<void> lookup() async {
    final requestedNumber=number;
    if(requestedNumber.length!=11||!ContainerNumber.isValid(requestedNumber))return;
    try{
      final row=await widget.repository.container(requestedNumber);
      if(!mounted||number!=requestedNumber)return;
      if(row==null){if(mounted)setState(()=>lookupHint='Conteneur absent du référentiel : vérification en zone requise.');return;}
      setState((){
        iso=row['iso_code'] as String;
        operator=operators.where((o)=>o.id==row['armateur_id']).firstOrNull??operator;
        lookupHint='ISO et armateur repris du référentiel.';
      });
    }catch(e){if(mounted)setState(()=>lookupHint='Recherche indisponible : $e');}
  }
  Future<void> pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) {
        if (mounted) message(context, 'Presse-papier vide.');
        return;
      }
      setContainerText(text);
    } catch (_) {
      if (mounted) message(context, 'Impossible d’accéder au presse-papier.');
    }
  }
  void setContainerText(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    for (var i = 0; i < 11; i++) {
      if (i < cleaned.length) {
        boxes[i].text = cleaned[i];
      } else {
        boxes[i].clear();
      }
    }
    setState(() {});
    if (number.length == 11) {
      FocusScope.of(context).unfocus();
      lookup();
    } else if (cleaned.isNotEmpty && cleaned.length < 11) {
      focus[cleaned.length].requestFocus();
    }
  }
  void clearBoxes() {
    for (final b in boxes) {
      b.clear();
    }
    setState(() => lookupHint = null);
    focus[0].requestFocus();
  }
  Future<void> pickOperator() async {
    var query='';
    final chosen=await showModalBottomSheet<OperatorRecord>(context:context,isScrollControlled:true,
      showDragHandle:true,builder:(sheet)=>StatefulBuilder(builder:(sheet,update){
        final filtered=operators.where((o)=>'${o.name} ${o.id} ${o.bic}'
          .toLowerCase().contains(query.toLowerCase())).toList();
        return SafeArea(child:Padding(padding:EdgeInsets.only(
          bottom:MediaQuery.viewInsetsOf(sheet).bottom),child:SizedBox(height:500,
            child:Column(children:[Padding(padding:const EdgeInsets.all(16),child:TextField(
              autofocus:true,decoration:const InputDecoration(labelText:'Rechercher parmi 95 armateurs',
                prefixIcon:Icon(Icons.search)),onChanged:(v)=>update(()=>query=v))),
              Expanded(child:ListView.builder(itemCount:filtered.length,itemBuilder:(ctx,i){
                final o=filtered[i];return ListTile(title:Text(o.name),subtitle:Text('${o.id} · ${o.bic}'),
                  leading:CircleAvatar(child:Text(o.name.isEmpty?'?':o.name[0])),
                  onTap:()=>Navigator.pop(sheet,o));}))]))));}));
    if(chosen!=null&&mounted)setState(()=>operator=chosen);
  }
  Future<void> submit() async {
    if(!form.currentState!.validate())return;
    if(operator==null){message(context,'Choisissez un armateur.');return;}
    if(kind=='loaded'){
      if(number.length < 11){
        message(context,'Veuillez saisir les 11 caractères du numéro de conteneur.');
        return;
      }
      if(!ContainerNumber.isValid(number)){
        final expected = ContainerNumber.expectedCheckDigit(number);
        if(expected != null){
          message(context,'Chiffre de contrôle ISO 6346 invalide. Le chiffre attendu est $expected.');
        } else {
          message(context,'Numéro de conteneur ISO 6346 invalide (4 lettres + 7 chiffres requis).');
        }
        return;
      }
    }
    setState(()=>busy=true);
    try{
      final visitId=await widget.repository.enter(plate:plate.text.trim(),cin:cin.text.trim(),kind:kind,
        iso:iso,armateur:operator!.id,containerNumber:kind=='loaded'?number:null,
        booking:kind=='empty'?booking.text.trim():null);
      if(!mounted)return;
      try{
        final documents=DocumentService(widget.repository.client);
        final outcome=await documents.finalizeLatest(visitId,'ENTREE');
        if(mounted){message(context,outcome.warning!=null?
          'Entrée enregistrée et bon cloud archivé. ${outcome.warning}':(outcome.printed?
          'Entrée enregistrée, bon archivé et impression demandée.':
          'Entrée enregistrée, bon archivé. Le camion apparaît dans Engin.'));}
      }catch(error){
        if(mounted)message(context,'Entrée enregistrée. Bon PDF à réessayer dans Bons : $error');
      }
      form.currentState!.reset();for(final c in [plate,cin,booking,...boxes]){c.clear();}
      setState((){
        operator=operators.where((o)=>o.id=='MAE').firstOrNull??operators.firstOrNull;
        lookupHint=null;kind='loaded';iso='45G1';
      });
    }catch(e){
      if(mounted){
        final raw = e.toString();
        String msg = 'Entrée refusée : $raw';
        if(raw.contains('one_active_container_on_truck')){
          msg = 'Le conteneur $number est déjà sur un camion actif dans le terminal. Terminez sa sortie ou son opération d’abord.';
        } else if(raw.contains('plate')){
          msg = 'Plaque d’immatriculation non valide ou déjà active.';
        }
        message(context, msg);
      }
    }
    finally{if(mounted)setState(()=>busy=false);}
  }
  Widget containerBoxes(){
    final currentNumber = number;
    final isValid = currentNumber.length == 11 && ContainerNumber.isValid(currentNumber);
    final expected = currentNumber.length >= 10 ? ContainerNumber.expectedCheckDigit(currentNumber) : null;
    final has11 = currentNumber.length == 11;
    final checkDigitMismatch = has11 && !isValid && expected != null;

    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Numéro du conteneur · ISO 6346 *', style: TextStyle(fontWeight: FontWeight.w700)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: pasteFromClipboard,
                icon: const Icon(Icons.paste_rounded, size: 16),
                label: const Text('Coller', style: TextStyle(fontSize: 12)),
              ),
              if (currentNumber.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: 'Effacer',
                  onPressed: clearBoxes,
                ),
            ],
          ),
        ],
      ),
      const SizedBox(height:6),
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyV, control: true): pasteFromClipboard,
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true): pasteFromClipboard,
        },
        child: SingleChildScrollView(scrollDirection:Axis.horizontal,
          child:Row(children:List.generate(11,(i){
            final isLetter = i < 4;
            final isCheckDigit = i == 10;
            return Padding(
              padding: EdgeInsets.only(right: isLetter && i == 3 ? 10 : (isCheckDigit ? 0 : 3)),
              child: SizedBox(width:32, child: TextFormField(controller:boxes[i],focusNode:focus[i],
                textAlign:TextAlign.center,maxLength:1,
                inputFormatters:[isLetter?FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')):
                  FilteringTextInputFormatter.digitsOnly,UpperCaseFormatter()],
                keyboardType:isLetter?TextInputType.text:TextInputType.number,
                decoration:InputDecoration(counterText:'',contentPadding:const EdgeInsets.symmetric(vertical:12),
                  filled:true,
                  fillColor:isLetter
                    ? const Color(0xffe9f3fa)
                    : (isCheckDigit ? const Color(0xfffff8e1) : Colors.white),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: isCheckDigit ? Colors.amber.shade700 : Colors.grey.shade400,
                      width: isCheckDigit ? 1.5 : 1.0,
                    ),
                  ),
                ),
                onChanged:(v){
                  if(lookupHint!=null){setState(()=>lookupHint=null);}
                  setState((){});
                  if(v.isNotEmpty){if(i<10) {
                    focus[i+1].requestFocus();
                  } else {
                    FocusScope.of(context).unfocus();
                    lookup();
                  }}
                },
              )),
            );
          })),
        ),
      ),
      const SizedBox(height:6),
      if (isValid)
        const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xff168846), size: 16),
            SizedBox(width: 6),
            Text('Numéro ISO 6346 conforme et vérifié',
                style: TextStyle(fontSize: 12, color: Color(0xff168846), fontWeight: FontWeight.w600)),
          ],
        )
      else if (checkDigitMismatch)
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
            const SizedBox(width: 6),
            Text('Chiffre calculé : $expected (saisi : ${boxes[10].text})',
                style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text('Corriger en $expected', style: const TextStyle(fontSize: 11)),
              onPressed: () {
                boxes[10].text = expected.toString();
                setState(() {});
                lookup();
              },
            ),
          ],
        )
      else if (currentNumber.length == 10 && expected != null)
        Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xff075a8d), size: 16),
            const SizedBox(width: 6),
            Text('Chiffre de contrôle attendu : $expected',
                style: const TextStyle(fontSize: 12, color: Color(0xff075a8d), fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text('Appliquer $expected', style: const TextStyle(fontSize: 11)),
              onPressed: () {
                boxes[10].text = expected.toString();
                setState(() {});
                lookup();
              },
            ),
          ],
        )
      else
        const Text('4 lettres + 7 chiffres, avec chiffre de contrôle',style:TextStyle(fontSize:11, color: Colors.grey)),
    ]);
  }
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
    Text('Enregistrement de l’entrée',style:Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height:8),const Text('Un formulaire · ordre des champs conforme au poste Entrée'),
    const SizedBox(height:16),Card(child:Padding(padding:const EdgeInsets.all(16),child:Form(key:form,
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextFormField(controller:plate,textCapitalization:TextCapitalization.characters,
          decoration:const InputDecoration(labelText:'1. Plaque camion *'),
          validator:(v)=>(v?.trim().length??0)<2?'Plaque requise':null),
        const SizedBox(height:14),
        TextFormField(controller:cin,textCapitalization:TextCapitalization.characters,
          decoration:const InputDecoration(labelText:'2. CIN chauffeur *'),
          validator:(v)=>(v?.trim().length??0)<2?'CIN requis':null),
        const SizedBox(height:17),
        if(kind=='loaded')containerBoxes() else TextFormField(controller:booking,
          decoration:const InputDecoration(labelText:'3. Booking / ordre libre *',
            helperText:'Le booking n’est pas un numéro ISO de conteneur'),
          validator:(v)=>v==null||v.trim().isEmpty?'Booking requis':null),
        if(lookupHint!=null)Padding(padding:const EdgeInsets.only(top:7),child:Text(lookupHint!,
          style:TextStyle(color:Theme.of(context).colorScheme.primary))),
        const SizedBox(height:18),const Text('4. État du camion à l’entrée',style:TextStyle(fontWeight:FontWeight.w700)),
        const SizedBox(height:8),Row(children:[for(final value in ['loaded','empty'])
          Expanded(child:Padding(padding:const EdgeInsets.all(4),child:InkWell(
            borderRadius:BorderRadius.circular(13),onTap:()=>setState(()=>kind=value),
            child:Container(decoration:BoxDecoration(color:kind==value?const Color(0xffe7f3ff):Colors.white,
              border:Border.all(color:kind==value?Theme.of(context).colorScheme.primary:Colors.grey.shade300),
              borderRadius:BorderRadius.circular(13)),padding:const EdgeInsets.all(8),
              child:Column(children:[TruckScene(kind:value,height:88),
                Text(value=='loaded'?'Avec conteneur':'Sans conteneur'),
                if(kind==value)const Icon(Icons.check_circle,color:Color(0xff075a8d))]))))),]),
        const SizedBox(height:18),TextFormField(key:ValueKey(iso),initialValue:iso,
          decoration:const InputDecoration(labelText:'5. Code ISO *',
            helperText:'4 caractères alphanumériques, ex. 22G1 ou 45R1'),
          maxLength:4,textCapitalization:TextCapitalization.characters,
          inputFormatters:[FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
            UpperCaseFormatter()],
          readOnly:!widget.canCorrect&&lookupHint=='ISO et armateur repris du référentiel.',
          onChanged:(v)=>iso=v.toUpperCase(),
          validator:(v)=>RegExp(r'^[0-9A-Z]{4}$').hasMatch(v??'')?null:'Code ISO invalide'),
        const SizedBox(height:16),OutlinedButton.icon(
          onPressed:widget.canCorrect||lookupHint!='ISO et armateur repris du référentiel.'?pickOperator:null,
          icon:const Icon(Icons.search),label:Text(operator==null?'6. Choisir armateur *':
            '6. ${operator!.name} (${operator!.id})')),
        const SizedBox(height:16),FilledButton.icon(onPressed:busy?null:submit,
          icon:const Icon(Icons.save),label:Text(busy?'Enregistrement…':'Enregistrer l’entrée')),
      ]))))
  ]);
}

class UpperCaseFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue oldValue,TextEditingValue newValue)=>
    newValue.copyWith(text:newValue.text.toUpperCase());
}

class EnginScreen extends StatefulWidget {
  const EnginScreen({super.key,required this.repository,required this.canCancel});
  final PointageRepository repository;final bool canCancel;
  @override State<EnginScreen> createState()=>_EnginScreenState();
}
class _EnginScreenState extends State<EnginScreen> {
  late Future<List<TruckVisit>> queue;
  @override void initState(){super.initState();queue=widget.repository.visits();}
  void refresh()=>setState((){queue=widget.repository.visits();});
  @override Widget build(BuildContext context)=>VisitQueue(title:'Engin · dépose / prise',
    repository:widget.repository,queue:queue,onRefresh:refresh,
    canCancel:widget.canCancel,exitMode:false);
}

class ExitScreen extends StatefulWidget {
  const ExitScreen({super.key,required this.repository,required this.canCancel});
  final PointageRepository repository;final bool canCancel;
  @override State<ExitScreen> createState()=>_ExitScreenState();
}
class _ExitScreenState extends State<ExitScreen> {
  late Future<List<TruckVisit>> queue;
  @override void initState(){super.initState();queue=widget.repository.visits();}
  void refresh()=>setState((){queue=widget.repository.visits();});
  @override Widget build(BuildContext context)=>VisitQueue(title:'Sortie · tous les camions présents',
    repository:widget.repository,queue:queue,onRefresh:refresh,
    canCancel:widget.canCancel,exitMode:true);
}

class VisitQueue extends StatelessWidget {
  const VisitQueue({super.key,required this.title,required this.repository,
    required this.queue,required this.onRefresh,required this.canCancel,required this.exitMode});
  final String title;final PointageRepository repository;final Future<List<TruckVisit>> queue;
  final VoidCallback onRefresh;final bool canCancel,exitMode;
  Future<void> open(BuildContext context,TruckVisit visit) async {
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,
      builder:(_)=>VisitActionSheet(repository:repository,visit:visit,canCancel:canCancel,exitMode:exitMode));
    onRefresh();
  }
  @override Widget build(BuildContext context)=>RefreshIndicator(onRefresh:()async {onRefresh();await queue;},
    child:FutureBuilder<List<TruckVisit>>(future:queue,builder:(context,snapshot){
      final visits=(snapshot.data??[]).where((v)=>v.isInside).toList();
      if(snapshot.hasError) {
        return ListView(children:[ListTile(title:Text('Chargement impossible : ${snapshot.error}'),
        trailing:IconButton(onPressed:onRefresh,icon:const Icon(Icons.refresh)))]);
      }
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      if(visits.isEmpty) {
        return ListView(padding:const EdgeInsets.all(16),children:[
          Text(title,style:Theme.of(context).textTheme.headlineSmall),
          const Text('FIFO · du plus ancien au plus récent'),
          const SizedBox(height:90),
          const Center(child:Text('Aucun camion dans la file.')),
        ]);
      }
      return ListView(padding:const EdgeInsets.all(16),children:[
        Text(title,style:Theme.of(context).textTheme.headlineSmall),
        const Text('FIFO · du plus ancien au plus récent'),const SizedBox(height:12),
        for(final v in visits)Card(child:InkWell(onTap:()=>open(context,v),
          child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
            TruckScene(kind:v.needsEngin?(v.entryKind=='loaded'?'loaded':'empty'):
              (v.entryKind=='loaded'?'empty':'loaded'),height:75),
            const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
              children:[Text(v.plate,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
                Text(v.container??v.booking??'—',maxLines:1,overflow:TextOverflow.ellipsis),
                Text(v.enteredAt.toLocal().toString().substring(0,16),
                  style:const TextStyle(fontSize:11,color:Colors.grey))])),
            const SizedBox(width:5),Column(children:[Chip(label:Text(v.needsEngin?'À saisir':'Validé'),
              backgroundColor:v.needsEngin?const Color(0xffffe5e2):const Color(0xffdaf4e7)),
              const Icon(Icons.chevron_right)]),
          ]))))
      ]);
    }));
}

class VisitActionSheet extends StatefulWidget {
  const VisitActionSheet({super.key,required this.repository,required this.visit,
    required this.canCancel,required this.exitMode});
  final PointageRepository repository;final TruckVisit visit;
  final bool canCancel,exitMode;
  @override State<VisitActionSheet> createState()=>_VisitActionSheetState();
}
class _VisitActionSheetState extends State<VisitActionSheet> {
  final container=TextEditingController(),position=TextEditingController(),reason=TextEditingController();
  bool busy=false,completedMissing=false;
  @override void dispose(){container.dispose();position.dispose();reason.dispose();super.dispose();}
  Future<void> run(Future<void> Function() action,String success) async {
    setState(()=>busy=true);
    try{await action();if(!mounted)return;message(context,success);Navigator.pop(context);}
    catch(e){if(mounted)message(context,'Opération refusée : $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> engin() async {
    if(widget.visit.entryKind=='empty'&&!ContainerNumber.isValid(container.text)){
      final expected = ContainerNumber.expectedCheckDigit(container.text);
      if (expected != null) {
        message(context, 'Chiffre de contrôle ISO 6346 invalide. Le chiffre attendu est $expected.');
      } else {
        message(context, 'Numéro de conteneur ISO 6346 invalide (4 lettres + 7 chiffres requis).');
      }
      return;
    }
    if(widget.visit.entryKind=='loaded'&&position.text.trim().isEmpty){
      message(context,'Position de dépose requise.');return;}
    await run(()async {await widget.repository.engin(widget.visit.id,
      containerNumber:widget.visit.entryKind=='empty'?ContainerNumber.normalize(container.text):null,
      position:widget.visit.entryKind=='loaded'?position.text.trim():null);
      try{final documents=DocumentService(widget.repository.client);
        final kind=widget.visit.entryKind=='loaded'?'DEPOSE':'PRISE';
        await documents.finalizeLatest(widget.visit.id,kind);
      }catch(_){/* Retry in Bons. */}},
      widget.visit.entryKind=='loaded'?'Dépose validée.':'Prise validée.');
  }
  Future<void> forcePickup() async {
    if(!ContainerNumber.isValid(container.text)){
      final expected = ContainerNumber.expectedCheckDigit(container.text);
      if (expected != null) {
        message(context, 'Chiffre de contrôle ISO 6346 invalide. Le chiffre attendu est $expected.');
      } else {
        message(context, 'Numéro de conteneur ISO 6346 invalide (4 lettres + 7 chiffres requis).');
      }
      return;
    }
    if(reason.text.trim().length<10){
      message(context,'Motif détaillé de 10 caractères minimum requis.');return;
    }
    await run(()async {
      await widget.repository.forcePickup(widget.visit.id,
        ContainerNumber.normalize(container.text),reason.text.trim());
      try{final documents=DocumentService(widget.repository.client);
        await documents.finalizeLatest(widget.visit.id,'PRISE');}
      catch(_){/* Retry in Bons. */}
    },'Prise forcée tracée pour rapprochement externe.');
  }
  @override Widget build(BuildContext context){
    final v=widget.visit,pending=v.needsEngin;
    return SafeArea(child:SingleChildScrollView(padding:EdgeInsets.fromLTRB(18,8,18,
      MediaQuery.viewInsetsOf(context).bottom+25),child:Column(
        crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
      Text(v.plate,style:Theme.of(context).textTheme.headlineSmall),
      Text('${v.armateur} · ${v.iso} · ${v.container??v.booking??''}'),
      const SizedBox(height:12),TruckScene(kind:pending?
        (v.entryKind=='loaded'?'depose':'prise'):
        (v.entryKind=='loaded'?'empty':'loaded'),height:165),
      Text(pending?(v.entryKind=='loaded'?'DÉPOSE · conteneur au sol':'PRISE · conteneur sur châssis'):
        'Engin validé',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:14),
      if(pending && v.entryKind=='empty') TextField(controller:container,
        inputFormatters:[UpperCaseFormatter()],maxLength:11,
        decoration:const InputDecoration(labelText:'Numéro du conteneur pris *')),
      if(pending && v.entryKind=='loaded') TextField(controller:position,
        decoration:const InputDecoration(labelText:'Position réelle de dépose *')),
      if(pending)FilledButton.icon(onPressed:busy?null:engin,icon:const Icon(Icons.check),
        label:Text(v.entryKind=='loaded'?'Valider la dépose':'Valider la prise')),
      if(widget.exitMode) ...[
        if(pending)const Padding(padding:EdgeInsets.symmetric(vertical:8),
          child:Text('Complétez Engin ici, puis rouvrez le camion pour valider la sortie.')),
        FilledButton.icon(onPressed:pending||busy?null:()=>run(
          ()async {await widget.repository.exit(v.id);
            try{final documents=DocumentService(widget.repository.client);
              await documents.finalizeLatest(v.id,'SORTIE');}
            catch(_){/* Retry in Bons. */}},'Sortie confirmée.'),
          icon:const Icon(Icons.exit_to_app),label:const Text('Valider la sortie')),
      ],
      if(widget.canCancel&&pending)...[
        const SizedBox(height:10),TextField(controller:reason,
          decoration:const InputDecoration(labelText:'Motif d’exception / annulation (admin)')),
        if(v.entryKind=='empty')...[
          const Padding(padding:EdgeInsets.symmetric(vertical:8),
            child:Text('Forcer seulement si le conteneur est présent physiquement mais absent du stock. '
              'Cette action ne crée pas de stock fictif; elle apparaît dans la liste de rapprochement.')),
          OutlinedButton.icon(onPressed:busy?null:forcePickup,
            icon:const Icon(Icons.report_problem_outlined),
            label:const Text('Forcer la prise sans stock')),
        ],
        TextButton.icon(onPressed:busy?null:(){if(reason.text.trim().length<5){
          message(context,'Motif détaillé requis.');return;}
          run(()=>widget.repository.cancel(v.id,reason.text.trim()),'Visite annulée avec trace.');},
          icon:const Icon(Icons.cancel_outlined),label:const Text('Annuler cette visite')),
      ],
    ])));
  }
}

class DataScreen extends StatefulWidget {
  const DataScreen({super.key,required this.repository});final PointageRepository repository;
  @override State<DataScreen> createState()=>_DataScreenState();
}
class _DataScreenState extends State<DataScreen> {
  String query='';late Future<List<TruckVisit>> visits;
  @override void initState(){super.initState();visits=widget.repository.visits(insideOnly:false);}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
    Text('Data · visites & stock',style:Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height:12),TextField(decoration:const InputDecoration(labelText:'Rechercher camion, conteneur, booking, armateur',
      prefixIcon:Icon(Icons.search)),onChanged:(x)=>setState(()=>query=x.toLowerCase())),
    FutureBuilder<List<TruckVisit>>(future:visits,builder:(context,s){
      if(s.hasError)return ListTile(title:Text('${s.error}'));
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final rows=s.data!.where((v)=>'${v.plate} ${v.container} ${v.booking} ${v.armateur}'
        .toLowerCase().contains(query));
      return Column(children:[for(final v in rows)Card(child:ExpansionTile(title:Text(v.plate),
        subtitle:Text('${v.container??v.booking??'—'} · ${v.armateur} · ${v.exitedAt==null?'Présent':'Sorti'}'),
        children:[ListTile(title:Text('Entrée : ${v.enteredAt.toLocal()}')),
          if(v.enginAt!=null)ListTile(title:Text('Engin : ${DateTime.parse(v.enginAt!).toLocal()}')),
          if(v.exitedAt!=null)ListTile(title:Text('Sortie : ${DateTime.parse(v.exitedAt!).toLocal()}'),
            subtitle:Text('Durée : ${DateTime.parse(v.exitedAt!).difference(v.enteredAt).inMinutes} min')),
          FutureBuilder<List<Map<String,dynamic>>>(future:widget.repository.events(v.id),
            builder:(c,e)=>e.hasData?Column(children:[for(final x in e.data!)
              ListTile(title:Text(x['action'].toString()),
                subtitle:Text('${x['occurred_at']} · ${x['actor_id']}'))]):const SizedBox.shrink()),
        ]))]);
    }),
    const SizedBox(height:18),Text('Conteneurs présents au yard',style:Theme.of(context).textTheme.titleLarge),
    ListTile(leading:const Icon(Icons.table_chart),title:const Text('Rapport Freepool'),
      subtitle:const Text('Stock fin de journée ou présence; export Excel'),
      trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,
        MaterialPageRoute(builder:(_)=>FreepoolScreen(repository:widget.repository)))),
    FutureBuilder<List<Map<String,dynamic>>>(future:widget.repository.stock(),builder:(c,s)=>
      s.hasData?Column(children:[for(final x in s.data!)ListTile(
        title:Text(x['container_number'].toString()),
        subtitle:Text('${x['iso_code']} · ${x['armateur_id']} · ${x['position']??'Position inconnue'}'))]):
        s.hasError?Text('${s.error}'):const CircularProgressIndicator()),
  ]);
}

class FreepoolScreen extends StatefulWidget {
  const FreepoolScreen({super.key,required this.repository});
  final PointageRepository repository;
  @override State<FreepoolScreen> createState()=>_FreepoolScreenState();
}
class _FreepoolScreenState extends State<FreepoolScreen> {
  late FreepoolExport report;
  DateTime day=DateTime.now();bool anyTime=false,busy=false;
  List<Map<String,dynamic>>? rows;String? error;
  @override void initState(){super.initState();report=FreepoolExport(widget.repository.client);load();}
  Future<void> load() async {
    setState((){busy=true;error=null;});
    try{final values=await report.rows(day,anyTime:anyTime);
      if(mounted)setState(()=>rows=values);
    }catch(e){if(mounted)setState(()=>error='$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context){
    final totals=report.summary(rows??[]);
    final sum=totals.values.fold<double>(0,(v,n)=>v+n.toDouble());
    return Scaffold(appBar:AppBar(title:const Text('Rapport Freepool')),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        const Card(child:Padding(padding:EdgeInsets.all(14),child:Text(
          'Les chiffres couvrent les mouvements enregistrés dans cette application. '
          'Sans import d’inventaire d’ouverture, les jours historiques sont incomplets.'))),
        Row(children:[OutlinedButton.icon(onPressed:()async{
          final picked=await showDatePicker(context:context,initialDate:day,
            firstDate:DateTime(2020),lastDate:DateTime.now());
          if(picked!=null){setState(()=>day=picked);load();}},
          icon:const Icon(Icons.calendar_today),label:Text('${day.day}/${day.month}/${day.year}')),
          const SizedBox(width:12),Expanded(child:SwitchListTile(title:const Text('Présent à un moment'),
            value:anyTime,onChanged:(v){setState(()=>anyTime=v);load();})),
        ]),
        if(busy)const LinearProgressIndicator(),
        if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
        if(rows!=null)...[
          Card(child:ListTile(title:Text('${rows!.length} conteneurs'),
            subtitle:Text('Total EVP classés : ${sum.toStringAsFixed(2)}'))),
          for(final category in FreepoolExport.categories)
            Card(child:ListTile(title:Text(category),trailing:Text(
              '${rows!.where((x)=>(x['category']??'UNCLASSIFIED')==category).length} · '
              '${totals[category]!.toStringAsFixed(2)} EVP'))),
          if(rows!.any((x)=>x['category']==null||x['evp']==null))
            const ListTile(leading:Icon(Icons.warning_amber),
              title:Text('ISO non classés : vérifier les règles avant facturation')),
          FilledButton.icon(onPressed:busy?null:()async{
            try{await report.share(report.workbook(rows!,day,anyTime:anyTime),day);}
            catch(e){if(context.mounted)message(context,'Export impossible : $e');}},
            icon:const Icon(Icons.download),label:const Text('Exporter XLSX')),
        ],
      ]));
  }
}

class BonsScreen extends StatefulWidget {
  const BonsScreen({super.key,required this.repository});final PointageRepository repository;
  @override State<BonsScreen> createState()=>_BonsScreenState();
}
class _BonsScreenState extends State<BonsScreen> {
  late Future<List<Map<String,dynamic>>> documents;
  late DocumentService service;
  final preferences=SharedPreferencesAsync();
  String preferredPrinter='';
  @override void initState(){super.initState();service=DocumentService(widget.repository.client);refresh();loadPreference();}
  Future<void> loadPreference() async {
    final value=await preferences.getString('preferred_printer_name')??'';
    if(mounted)setState(()=>preferredPrinter=value);
  }
  Future<void> choosePrinter() async {
    try{
      final printers=await Printing.listPrinters();
      if(!mounted)return;
      final selected=await showDialog<String>(context:context,builder:(c)=>SimpleDialog(
        title:const Text('Imprimante préférée'),children:[
          SimpleDialogOption(onPressed:()=>Navigator.pop(c,''),child:const Text('Aucune préférence')),
          for(final printer in printers)SimpleDialogOption(
            onPressed:()=>Navigator.pop(c,printer.name),child:Text(printer.name)),
        ]));
      if(selected!=null){await preferences.setString('preferred_printer_name',selected);
        if(mounted)setState(()=>preferredPrinter=selected);}
    }catch(e){if(mounted)message(context,'Imprimantes indisponibles : $e');}
  }
  void refresh()=>setState((){documents=widget.repository.documents();});
  Future<void> action(Future<void> Function() run) async {
    try{await run();refresh();}catch(e){if(mounted)message(context,'Bon PDF indisponible : $e');}
  }
  Future<void> preview(Map<String,dynamic> doc) async {
    try{
      final bytes=await service.prepare(doc);
      await service.recordAction(doc,'PREVIEW_REQUESTED');
      if(!mounted)return;
      await Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(
        appBar:AppBar(title:Text('Bon ${doc['kind']}')),
        body:PdfPreview(build:(_)=>bytes,allowPrinting:true,allowSharing:true))));
      refresh();
    }catch(e){if(mounted)message(context,'Aperçu impossible : $e');}
  }
  @override Widget build(BuildContext context)=>FutureBuilder<List<Map<String,dynamic>>>(
    future:documents,builder:(context,s){
      if(s.hasError)return Center(child:Text('Bons indisponibles : ${s.error}'));
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      return ListView(padding:const EdgeInsets.all(16),children:[
        Text('Bons',style:Theme.of(context).textTheme.headlineSmall),
        const Text('Documents privés · le PDF est conservé dans Supabase Storage'),
        ListTile(leading:const Icon(Icons.print),
          title:Text(preferredPrinter.isEmpty?'Imprimante préférée : aucune':
            'Imprimante préférée : $preferredPrinter'),
          subtitle:const Text('Impression directe après pointage si disponible; sinon dialogue système.'),
          trailing:const Icon(Icons.edit),onTap:choosePrinter),
        Align(alignment:Alignment.centerRight,child:IconButton(onPressed:refresh,
          icon:const Icon(Icons.refresh),tooltip:'Actualiser')),
        const SizedBox(height:12),
        for(final d in s.data!)Card(child:Column(children:[ListTile(
          leading:const Icon(Icons.picture_as_pdf,color:Colors.red),
          title:Text('${d['kind']} · ${d['visit_id']}'),
          subtitle:Text('${d['created_at']} · ${d['status']}'),
          trailing:d['status']=='uploaded'?const Icon(Icons.check_circle,color:Colors.green):
            const Icon(Icons.schedule),
        ),Padding(padding:const EdgeInsets.fromLTRB(12,0,12,12),child:Wrap(spacing:8,children:[
          OutlinedButton(onPressed:()=>preview(d),child:const Text('Aperçu')),
          OutlinedButton(onPressed:()=>action(()=>service.downloadOrShare(d)),
            child:const Text('Télécharger / partager')),
          if(DocumentService.bridgeUrl.isNotEmpty)OutlinedButton(
            onPressed:()=>action(()async{
              final result=await service.archiveWithBridge(d,
                print:DocumentService.bridgeAutoPrint);
              if(context.mounted){message(context,
                'Archive réseau : ${result?['archive_name']} · impression : ${result?['print_status']}');}
            }),child:const Text('Archive réseau / relance')),
          FilledButton.tonal(onPressed:()=>action(()=>service.printWithDialog(d,
              printerName:preferredPrinter)),
            child:const Text('Imprimer…')),
        ]))])),
      ]);
    });
}
