import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/document_service.dart';
import '../data/freepool_export.dart';
import '../data/pointage_repository.dart';
import '../domain/container_number.dart';
import '../domain/container_iso.dart';
import '../domain/truck_plate.dart';
import 'truck_diagram.dart';

void message(BuildContext context,String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()..showSnackBar(SnackBar(content:Text(text)));

Future<OperatorRecord?> showOperatorPicker(BuildContext context, List<OperatorRecord> operators) async {
  var query = '';
  return showModalBottomSheet<OperatorRecord>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, update) {
        final filtered = operators
            .where((o) => '${o.name} ${o.id} ${o.bic}'.toLowerCase().contains(query.toLowerCase()))
            .toList();
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
            child: SizedBox(
              height: 500,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Rechercher parmi 95 armateurs',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => update(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final o = filtered[i];
                        return ListTile(
                          title: Text(o.name),
                          subtitle: Text('${o.id} · ${o.bic}'),
                          leading: CircleAvatar(child: Text(o.name.isEmpty ? '?' : o.name[0])),
                          onTap: () => Navigator.pop(sheet, o),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key,required this.repository,required this.canCorrect,this.isFullScreen=false});
  final PointageRepository repository;final bool canCorrect;final bool isFullScreen;
  @override State<EntryScreen> createState()=>_EntryScreenState();
}
class _EntryScreenState extends State<EntryScreen> {
  final form=GlobalKey<FormState>();
  final plate=TextEditingController(),cin=TextEditingController(),booking=TextEditingController();
  final booking2=TextEditingController();
  final plateFocus=FocusNode(),cinFocus=FocusNode(),bookingFocus=FocusNode(),bookingFocus2=FocusNode();
  final isoFocus=FocusNode(),iso2Focus=FocusNode();
  final modeScrollController=ScrollController();
  final boxes=List.generate(11,(_)=>TextEditingController());
  final focus=List.generate(11,(_)=>FocusNode());
  final boxes2=List.generate(11,(_)=>TextEditingController());
  final focus2=List.generate(11,(_)=>FocusNode());
  List<OperatorRecord> operators=[];
  OperatorRecord? operator, operator2;
  final isoController = TextEditingController();
  final iso2Controller = TextEditingController();
  String iso='', iso2='', kind='loaded';
  bool isTwin=false, busy=false;
  int _activeTwinIndex = 0;
  final PageController _twinPageController = PageController();
  bool _isPickerOpen=false;
  String? lookupHint, lookupHint2;
  void selectGateMode(String selectedKind, bool selectedTwin) {
    setState(() {
      kind = selectedKind;
      isTwin = selectedTwin;
      if (selectedTwin) {
        _activeTwinIndex = 0;
        if (_twinPageController.hasClients) _twinPageController.jumpToPage(0);
      }
    });
  }
  @override void initState(){
    super.initState();
    loadOperators();
    _initBoxKeyEvents();
  }
  void _initBoxKeyEvents() {
    for (int i = 0; i < 11; i++) {
      final idx = i;
      focus[idx].onKeyEvent = (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
          if (boxes[idx].text.isEmpty && idx > 0) {
            focus[idx - 1].requestFocus();
            boxes[idx - 1].selection = TextSelection(baseOffset: 0, extentOffset: boxes[idx - 1].text.length);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      };
      focus2[idx].onKeyEvent = (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
          if (boxes2[idx].text.isEmpty && idx > 0) {
            focus2[idx - 1].requestFocus();
            boxes2[idx - 1].selection = TextSelection(baseOffset: 0, extentOffset: boxes2[idx - 1].text.length);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      };
    }
  }
  void _advanceBox(int index, bool second) {
    final f = second ? focus2 : focus;
    final b = second ? boxes2 : boxes;
    if (index < 10) {
      f[index + 1].requestFocus();
      b[index + 1].selection = TextSelection(
        baseOffset: 0,
        extentOffset: b[index + 1].text.length,
      );
    } else {
      if (second) {
        lookup2();
        iso2Focus.requestFocus();
        iso2Controller.selection = TextSelection(baseOffset: 0, extentOffset: iso2Controller.text.length);
      } else {
        lookup();
        isoFocus.requestFocus();
        isoController.selection = TextSelection(baseOffset: 0, extentOffset: isoController.text.length);
      }
    }
  }
  Future<void> loadOperators() async {
    try{
      final records=await widget.repository.operators();
      if(mounted){
        setState((){
          operators=records;
        });
      }
    }catch(_){
      try{
        final raw=await rootBundle.loadString('assets/operators.json');
        if(mounted) {
          final list=(jsonDecode(raw) as List).map((x)=>OperatorRecord.fromJson(x)).toList();
          setState((){
            operators=list;
          });
        }
      }catch(_){ if(mounted)message(context,'Catalogue des armateurs indisponible.'); }
    }
  }
  @override void dispose(){for(final c in [plate,cin,booking,booking2,isoController,iso2Controller,...boxes,...boxes2]){c.dispose();}
    for(final f in [plateFocus,cinFocus,bookingFocus,bookingFocus2,isoFocus,iso2Focus,...focus,...focus2]){f.dispose();}
    _twinPageController.dispose();
    modeScrollController.dispose();super.dispose();}
  void _focusAndScroll(FocusNode node) {
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (node.context != null) {
        Scrollable.ensureVisible(
          node.context!,
          duration: const Duration(milliseconds: 260),
          alignment: 0.25,
          curve: Curves.easeInOut,
        );
      }
    });
  }
  void focusGateField(int index){
    if (isTwin) {
      if (_twinPageController.hasClients && _activeTwinIndex != index) {
        _twinPageController.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
      }
      setState(() => _activeTwinIndex = index);
    }
    final target=kind=='loaded'?(index==0?focus[0]:focus2[0]):
      (index==0?bookingFocus:bookingFocus2);
    _focusAndScroll(target);
  }
  String get number=>boxes.map((x)=>x.text).join().toUpperCase();
  String get number2=>boxes2.map((x)=>x.text).join().toUpperCase();
  Future<void> lookup() async {
    final requestedNumber=number;
    if(requestedNumber.length!=11||!ContainerNumber.isValid(requestedNumber))return;
    try{
      final row=await widget.repository.container(requestedNumber);
      if(!mounted||number!=requestedNumber)return;
      if(row==null){if(mounted)setState(()=>lookupHint='Conteneur absent du référentiel : vérification en zone requise.');return;}
      setState((){
        iso=row['iso_code'] as String;
        isoController.text=iso;
        operator=operators.where((o)=>o.id==row['armateur_id']).firstOrNull??operator;
        lookupHint='ISO et armateur repris du référentiel.';
      });
    }catch(e){if(mounted)setState(()=>lookupHint='Recherche indisponible : $e');}
  }
  Future<void> lookup2() async {
    final requestedNumber=number2;
    if(requestedNumber.length!=11||!ContainerNumber.isValid(requestedNumber))return;
    try{
      final row=await widget.repository.container(requestedNumber);
      if(!mounted||number2!=requestedNumber)return;
      if(row==null){if(mounted)setState(()=>lookupHint2='Conteneur absent du référentiel : vérification en zone requise.');return;}
      setState((){
        iso2=row['iso_code'] as String;
        iso2Controller.text=iso2;
        operator2=operators.where((o)=>o.id==row['armateur_id']).firstOrNull??operator2;
        lookupHint2='ISO et armateur repris du référentiel.';
      });
    }catch(e){if(mounted)setState(()=>lookupHint2='Recherche indisponible : $e');}
  }
  Future<void> pasteFromClipboard({bool second = false}) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) {
        if (mounted) message(context, 'Presse-papier vide.');
        return;
      }
      if (second) {
        setContainerText2(text);
      } else {
        setContainerText(text);
      }
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
  void setContainerText2(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    for (var i = 0; i < 11; i++) {
      if (i < cleaned.length) {
        boxes2[i].text = cleaned[i];
      } else {
        boxes2[i].clear();
      }
    }
    setState(() {});
    if (number2.length == 11) {
      FocusScope.of(context).unfocus();
      lookup2();
    } else if (cleaned.isNotEmpty && cleaned.length < 11) {
      focus2[cleaned.length].requestFocus();
    }
  }
  void clearBoxes() {
    for (final b in boxes) {
      b.clear();
    }
    setState(() => lookupHint = null);
    focus[0].requestFocus();
  }
  void clearBoxes2() {
    for (final b in boxes2) {
      b.clear();
    }
    setState(() => lookupHint2 = null);
    focus2[0].requestFocus();
  }
  Future<void> pickOperator({bool forSecond = false}) async {
    if (_isPickerOpen) return;
    _isPickerOpen = true;
    try {
      final chosen = await showOperatorPicker(context, operators);
      if(chosen!=null&&mounted) {
        setState(() => forSecond ? operator2 = chosen : operator = chosen);
        if (!forSecond && isTwin) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_twinPageController.hasClients) {
              _twinPageController.animateToPage(1, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
            }
            setState(() => _activeTwinIndex = 1);
            if (kind == 'loaded') {
              focus2[0].requestFocus();
            } else {
              bookingFocus2.requestFocus();
            }
          });
        }
      }
    } finally {
      _isPickerOpen = false;
    }
  }
  Future<void> submit() async {
    if(!form.currentState!.validate())return;
    if(operator==null){message(context,'Choisissez un armateur.');return;}
    if(iso.trim().isEmpty || !RegExp(r'^[0-9A-Z]{4}$').hasMatch(iso.trim())){
      message(context,'Code ISO requis (4 caractères, ex: 22G1, 45G1).');
      return;
    }
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
      if(isTwin){
        if(number2.length < 11){
          message(context,'Veuillez saisir les 11 caractères du 2ème conteneur Twin.');
          return;
        }
        if(!ContainerNumber.isValid(number2)){
          final expected2 = ContainerNumber.expectedCheckDigit(number2);
          if(expected2 != null){
            message(context,'Chiffre de contrôle du 2ème conteneur invalide. Attendu : $expected2.');
          } else {
            message(context,'Numéro du 2ème conteneur ISO 6346 invalide (4 lettres + 7 chiffres requis).');
          }
          return;
        }
        if(iso2.trim().isEmpty || !RegExp(r'^[0-9A-Z]{4}$').hasMatch(iso2.trim())){
          message(context,'Code ISO requis pour le 2ème conteneur Twin.');
          return;
        }
        if(operator2==null){
          message(context,'Choisissez l’armateur du 2ème conteneur Twin.');
          return;
        }
      }
    }
    setState(()=>busy=true);
    try{
      final visitId=await widget.repository.enter(
        plate:TruckPlate.format(plate.text),cin:cin.text.trim(),kind:kind,
        iso:iso.trim(),armateur:operator!.id,
        containerNumber:kind=='loaded'?number:null,
        booking:kind=='empty'?booking.text.trim():null,
        isTwin:isTwin,
        containerNumber2:(isTwin&&kind=='loaded')?number2:null,
        iso2:isTwin?iso2.trim():null,
        armateur2:isTwin?(operator2?.id??operator!.id):null,
        booking2:(isTwin&&kind=='empty')?booking2.text.trim():null,
      );
      if(!mounted)return;
      DocumentOutcome? outcome;
      try{
        final documents=DocumentService(widget.repository.client);
        outcome=await documents.finalizeLatest(visitId,'ENTREE');
        if(mounted){message(context,outcome.warning!=null?
          'Entrée enregistrée et bon cloud archivé. ${outcome.warning}':(outcome.printed?
          'Entrée enregistrée, bon archivé et impression demandée.':
          'Entrée enregistrée avec succès.'));}
      }catch(error){
        if(mounted)message(context,'Entrée enregistrée. Bon PDF à réessayer dans Bons : $error');
      }
      final savedPlate = TruckPlate.format(plate.text);
      final savedContainer1 = kind == 'loaded' ? number : (booking.text.isNotEmpty ? booking.text : null);
      final savedContainer2 = isTwin ? (kind == 'loaded' ? number2 : (booking2.text.isNotEmpty ? booking2.text : null)) : null;

      form.currentState!.reset();for(final c in [plate,cin,booking,booking2,isoController,iso2Controller,...boxes,...boxes2]){c.clear();}
      setState((){
        operator=null;
        operator2=null;
        lookupHint=null;lookupHint2=null;kind='loaded';isTwin=false;iso='';iso2='';
      });
      if(mounted && outcome?.bytes != null){
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => BonConfirmationDialog(
            bytes: outcome!.bytes!,
            kind: 'ENTRÉE',
            visitId: visitId,
            plate: savedPlate,
            containerNumber: savedContainer1,
            containerNumber2: savedContainer2,
            onNewTruck: () {
              if (mounted) {
                plateFocus.requestFocus();
              }
            },
          ),
        );
      }
    }catch(e){
      if(mounted){
        final raw = e.toString();
        String msg = 'Entrée refusée : $raw';
        if(raw.contains('one_active_container_on_truck') || raw.contains('one_active_container_2_on_truck')){
          msg = 'Un des conteneurs est déjà sur un camion actif dans le terminal. Terminez sa sortie d’abord.';
        } else if(raw.contains('plate')){
          msg = 'Plaque d’immatriculation non valide ou déjà active.';
        }
        message(context, msg);
      }
    }
    finally{if(mounted)setState(()=>busy=false);}
  }

  Widget containerBoxes({bool second = false}){
    final currentNumber = second ? number2 : number;
    final b = second ? boxes2 : boxes;
    final f = second ? focus2 : focus;
    final isValid = currentNumber.length == 11 && ContainerNumber.isValid(currentNumber);
    final expected = currentNumber.length >= 10 ? ContainerNumber.expectedCheckDigit(currentNumber) : null;
    final has11 = currentNumber.length == 11;
    final checkDigitMismatch = has11 && !isValid && expected != null;

    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child:Text(second ? '2ème Conteneur (20\') · ISO 6346 *' : (isTwin ? '1er Conteneur (20\') · ISO 6346 *' : 'Numéro du conteneur · ISO 6346 *'),
            maxLines:2,overflow:TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700))),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => pasteFromClipboard(second: second),
                icon: const Icon(Icons.paste_rounded, size: 16),
                label: const Text('Coller', style: TextStyle(fontSize: 12)),
              ),
              if (currentNumber.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: 'Effacer',
                  onPressed: second ? clearBoxes2 : clearBoxes,
                ),
            ],
          ),
        ],
      ),
      const SizedBox(height:6),
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyV, control: true): () => pasteFromClipboard(second: second),
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () => pasteFromClipboard(second: second),
        },
        child: SingleChildScrollView(scrollDirection:Axis.horizontal,
          child:Row(children:List.generate(11,(i){
            final isLetter = i < 4;
            final isCheckDigit = i == 10;
            return Padding(
              padding: EdgeInsets.only(right: isLetter && i == 3 ? 10 : (isCheckDigit ? 0 : 3)),
              child: SizedBox(width:32, child: TextFormField(controller:b[i],focusNode:f[i],
                textAlign:TextAlign.center,
                textInputAction:TextInputAction.next,
                inputFormatters:[SingleCharOverrideFormatter(isLetter:isLetter, onAdvance:()=>_advanceBox(i, second))],
                keyboardType:isLetter?TextInputType.text:TextInputType.number,
                onTap:(){
                  b[i].selection=TextSelection(baseOffset:0, extentOffset:b[i].text.length);
                },
                onFieldSubmitted:(_)=>_advanceBox(i, second),
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
                  if(second ? (lookupHint2!=null) : (lookupHint!=null)){
                    setState(() => second ? lookupHint2=null : lookupHint=null);
                  }
                  setState((){});
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
            Text('Chiffre calculé : $expected (saisi : ${b[10].text})',
                style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text('Corriger en $expected', style: const TextStyle(fontSize: 11)),
              onPressed: () {
                b[10].text = expected.toString();
                setState(() {});
                if(second) {
                  lookup2();
                  iso2Focus.requestFocus();
                  iso2Controller.selection = TextSelection(baseOffset: 0, extentOffset: iso2Controller.text.length);
                } else {
                  lookup();
                  isoFocus.requestFocus();
                  isoController.selection = TextSelection(baseOffset: 0, extentOffset: isoController.text.length);
                }
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
                b[10].text = expected.toString();
                setState(() {});
                if(second) {
                  lookup2();
                  iso2Focus.requestFocus();
                  iso2Controller.selection = TextSelection(baseOffset: 0, extentOffset: iso2Controller.text.length);
                } else {
                  lookup();
                  isoFocus.requestFocus();
                  isoController.selection = TextSelection(baseOffset: 0, extentOffset: isoController.text.length);
                }
              },
            ),
          ],
        )
      else
        const Text('4 lettres + 7 chiffres, avec chiffre de contrôle',style:TextStyle(fontSize:11, color: Colors.grey)),
    ]);
  }

  @override Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.isFullScreen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Icon(Icons.login, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Enregistrement de l’entrée',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        // PINNED / FIXED TOP: État du camion à l’arrivée (horizontal scroll)
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
            ],
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('État du camion à l’arrivée',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xff063e66))),
              const SizedBox(height: 2),
              const Text('↔ Glissez pour changer de mode · Touchez la plaque ou le conteneur pour saisir',
                style: TextStyle(fontSize: 10, color: Color(0xff49677e), fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              SizedBox(
                height: 198,
                child: Scrollbar(
                  controller: modeScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: modeScrollController,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final option in [
                          ('loaded', false, 'Avec 1 conteneur'),
                          ('loaded', true, 'Avec 2 conteneurs'),
                          ('empty', false, 'Sans · 1 à prendre'),
                          ('empty', true, 'Sans · 2 à prendre'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8, bottom: 8),
                            child: InkWell(
                              key: ValueKey('gate-${option.$1}-${option.$2}'),
                              borderRadius: BorderRadius.circular(12),
                              onTap: kind == option.$1 && isTwin == option.$2
                                  ? null
                                  : () => selectGateMode(option.$1, option.$2),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                onEnd: () {
                                  if (kind == option.$1 && isTwin == option.$2 && modeScrollController.hasClients) {
                                    final index = (option.$1 == 'empty' ? 2 : 0) + (option.$2 ? 1 : 0);
                                    modeScrollController.animateTo(
                                      (index * 232.0).clamp(0.0, modeScrollController.position.maxScrollExtent),
                                      duration: const Duration(milliseconds: 180),
                                      curve: Curves.easeOut,
                                    );
                                  }
                                },
                                width: kind == option.$1 && isTwin == option.$2
                                    ? (MediaQuery.sizeOf(context).width < 600 ? 310 : 390)
                                    : 224,
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                                decoration: BoxDecoration(
                                  color: kind == option.$1 && isTwin == option.$2
                                      ? const Color(0xfff0f8fd)
                                      : const Color(0xfffafcfe),
                                  border: Border.all(
                                    color: kind == option.$1 && isTwin == option.$2
                                        ? const Color(0xff168dcc)
                                        : const Color(0xffdfe8ef),
                                    width: kind == option.$1 && isTwin == option.$2 ? 1.8 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          option.$1 == 'loaded' ? Icons.south_west_rounded : Icons.north_east_rounded,
                                          size: 15,
                                          color: const Color(0xff176b93),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          option.$1 == 'loaded' ? 'DÉPOSER' : 'PRENDRE',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            letterSpacing: 1.1,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xff176b93),
                                          ),
                                        ),
                                        const Spacer(),
                                        if (kind == option.$1 && isTwin == option.$2)
                                          const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xff168dcc))
                                        else
                                          Text(
                                            option.$2 ? '2 × 20′' : '1',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xff71899c),
                                            ),
                                          ),
                                      ],
                                    ),
                                    Expanded(
                                      child: TruckScene(
                                        kind: option.$1,
                                        isTwin: option.$2,
                                        width: double.infinity,
                                        height: 120,
                                        plate: kind == option.$1 && isTwin == option.$2 ? plate.text : null,
                                        driverCin: kind == option.$1 && isTwin == option.$2 ? cin.text : null,
                                        containerNumber: kind == option.$1 && isTwin == option.$2 && option.$1 == 'loaded' ? number : null,
                                        iso: kind == option.$1 && isTwin == option.$2 ? iso : null,
                                        operator: kind == option.$1 && isTwin == option.$2 ? (operator?.name ?? operator?.id) : null,
                                        containerNumber2: kind == option.$1 && isTwin == option.$2 && option.$2 && option.$1 == 'loaded' ? number2 : null,
                                        iso2: kind == option.$1 && isTwin == option.$2 && option.$2 ? iso2 : null,
                                        operator2: kind == option.$1 && isTwin == option.$2 && option.$2 ? (operator2?.name ?? operator2?.id) : null,
                                        booking: kind == option.$1 && isTwin == option.$2 && option.$1 == 'empty' ? booking.text : null,
                                        booking2: kind == option.$1 && isTwin == option.$2 && option.$2 && option.$1 == 'empty' ? booking2.text : null,
                                        highlightMissing: kind == option.$1 && isTwin == option.$2,
                                        activeContainerIndex: (kind == option.$1 && isTwin == option.$2 && option.$2) ? _activeTwinIndex : null,
                                        onPlateTap: kind == option.$1 && isTwin == option.$2 ? () => _focusAndScroll(plateFocus) : null,
                                        onCinTap: kind == option.$1 && isTwin == option.$2 ? () => _focusAndScroll(cinFocus) : null,
                                        onContainerNumberTap: kind == option.$1 && isTwin == option.$2 ? focusGateField : null,
                                        onIsoTap: kind == option.$1 && isTwin == option.$2
                                            ? (idx) {
                                                if (isTwin) {
                                                  if (_twinPageController.hasClients && _activeTwinIndex != idx) {
                                                    _twinPageController.animateToPage(idx, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
                                                  }
                                                  setState(() => _activeTwinIndex = idx);
                                                }
                                                _focusAndScroll(idx == 0 ? isoFocus : iso2Focus);
                                              }
                                            : null,
                                        onLineTap: kind == option.$1 && isTwin == option.$2
                                            ? (idx) {
                                                if (isTwin) {
                                                  if (_twinPageController.hasClients && _activeTwinIndex != idx) {
                                                    _twinPageController.animateToPage(idx, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
                                                  }
                                                  setState(() => _activeTwinIndex = idx);
                                                }
                                                pickOperator(forSecond: idx == 1);
                                              }
                                            : null,
                                        onContainerTap: kind == option.$1 && isTwin == option.$2 ? focusGateField : null,
                                      ),
                                    ),
                                    Text(
                                      option.$3,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xff173c5b),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // SCROLLABLE FORM AREA
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 2. Plaque camion & CIN chauffeur (Même ligne / Same Row)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: TextFormField(
                          controller: plate,
                          focusNode: plateFocus,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Plaque camion *',
                            hintText: 'Ex: 12345-A-1',
                            prefixIcon: Icon(Icons.pin, size: 18),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z -]')), UpperCaseFormatter()],
                          onChanged: (_) => setState(() {}),
                          onFieldSubmitted: (_) {
                            plate.text = TruckPlate.format(plate.text);
                            cinFocus.requestFocus();
                          },
                          validator: (v) => TruckPlate.isValid(v ?? '') ? null : 'Format marocain requis : 12345-A-06',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          controller: cin,
                          focusNode: cinFocus,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: (_) => setState(() {}),
                          onFieldSubmitted: (_) {
                            if (kind == 'loaded') {
                              focus[0].requestFocus();
                              boxes[0].selection = TextSelection(baseOffset: 0, extentOffset: boxes[0].text.length);
                            } else {
                              bookingFocus.requestFocus();
                            }
                          },
                          decoration: const InputDecoration(
                            labelText: 'CIN chauffeur *',
                            hintText: 'Ex: AB123456',
                            prefixIcon: Icon(Icons.badge_outlined, size: 18),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                          validator: (v) => (v?.trim().length ?? 0) < 2 ? 'CIN requis' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 4. Conteneur 1 (ou Mono)
                  if (isTwin) ...[
                    LayoutBuilder(builder: (context, space) {
                      final first = Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xfff8fafc),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (space.maxWidth < 900 && _activeTwinIndex == 0) ? const Color(0xff0284c7) : Colors.blueGrey.shade200,
                            width: (space.maxWidth < 900 && _activeTwinIndex == 0) ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Premier Conteneur (20\')',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xff075a8d)),
                            ),
                            const SizedBox(height: 8),
                            if (kind == 'loaded')
                              containerBoxes()
                            else
                              TextFormField(
                                controller: booking,
                                focusNode: bookingFocus,
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => setState(() {}),
                                onFieldSubmitted: (_) {
                                  isoFocus.requestFocus();
                                  isoController.selection = TextSelection(baseOffset: 0, extentOffset: isoController.text.length);
                                },
                                textCapitalization: TextCapitalization.characters,
                                decoration: const InputDecoration(
                                  labelText: 'Booking Conteneur 1 *',
                                  prefixIcon: Icon(Icons.receipt_long, size: 20),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Booking requis' : null,
                              ),
                            if (lookupHint != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(lookupHint!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                              ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: isoController,
                              focusNode: isoFocus,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Code ISO Conteneur 1 *',
                                helperText: 'Ex: 22G1',
                                prefixIcon: Icon(Icons.qr_code, size: 20),
                              ),
                              maxLength: 4,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')), UpperCaseFormatter()],
                              onChanged: (v) {
                                iso = v.trim().toUpperCase();
                                setState(() {});
                                if (iso.length == 4) {
                                  pickOperator(forSecond: false);
                                }
                              },
                              onFieldSubmitted: (_) => pickOperator(forSecond: false),
                              validator: (v) => RegExp(r'^[0-9A-Z]{4}$').hasMatch(v ?? '') ? null : 'Code ISO invalide',
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                alignment: Alignment.centerLeft,
                              ),
                              onPressed: () => pickOperator(forSecond: false),
                              icon: const Icon(Icons.business, size: 20),
                              label: Text(
                                operator == null ? 'Armateur Conteneur 1 *' : '${operator!.name} (${operator!.id})',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (space.maxWidth < 900) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () {
                                    if (_twinPageController.hasClients) {
                                      _twinPageController.animateToPage(1, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
                                    }
                                    setState(() => _activeTwinIndex = 1);
                                  },
                                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                  label: const Text('2ème Conteneur →', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );

                      // Conteneur 2 (Twin)
                      final second = Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xfff8fafc),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (space.maxWidth < 900 && _activeTwinIndex == 1) ? const Color(0xff0284c7) : Colors.blueGrey.shade200,
                            width: (space.maxWidth < 900 && _activeTwinIndex == 1) ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Deuxième Conteneur (20\') · Compagnie différente autorisée',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xff075a8d)),
                            ),
                            const SizedBox(height: 8),
                            if (kind == 'loaded')
                              containerBoxes(second: true)
                            else
                              TextFormField(
                                controller: booking2,
                                focusNode: bookingFocus2,
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => setState(() {}),
                                onFieldSubmitted: (_) {
                                  iso2Focus.requestFocus();
                                  iso2Controller.selection = TextSelection(baseOffset: 0, extentOffset: iso2Controller.text.length);
                                },
                                textCapitalization: TextCapitalization.characters,
                                decoration: const InputDecoration(
                                  labelText: 'Booking Conteneur 2 *',
                                  prefixIcon: Icon(Icons.receipt_long, size: 20),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Booking requis' : null,
                              ),
                            if (lookupHint2 != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(lookupHint2!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                              ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: iso2Controller,
                              focusNode: iso2Focus,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Code ISO Conteneur 2 *',
                                helperText: 'Ex: 22G1',
                                prefixIcon: Icon(Icons.qr_code, size: 20),
                              ),
                              maxLength: 4,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')), UpperCaseFormatter()],
                              onChanged: (v) {
                                iso2 = v.trim().toUpperCase();
                                setState(() {});
                                if (iso2.length == 4) {
                                  pickOperator(forSecond: true);
                                }
                              },
                              onFieldSubmitted: (_) => pickOperator(forSecond: true),
                              validator: (v) => RegExp(r'^[0-9A-Z]{4}$').hasMatch(v ?? '') ? null : 'Code ISO invalide',
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                alignment: Alignment.centerLeft,
                              ),
                              onPressed: () => pickOperator(forSecond: true),
                              icon: const Icon(Icons.business, size: 20),
                              label: Text(
                                operator2 == null ? 'Armateur Conteneur 2 *' : '${operator2!.name} (${operator2!.id})',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (space.maxWidth < 900) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () {
                                    if (_twinPageController.hasClients) {
                                      _twinPageController.animateToPage(0, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
                                    }
                                    setState(() => _activeTwinIndex = 0);
                                  },
                                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                                  label: const Text('← 1er Conteneur', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                      if (space.maxWidth >= 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: first),
                            const SizedBox(width: 14),
                            Expanded(child: second),
                          ],
                        );
                      }

                      final tabs = Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xffe2e8f0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(3),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                key: const ValueKey('twin-tab-0'),
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  if (_twinPageController.hasClients) {
                                    _twinPageController.animateToPage(0, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
                                  }
                                  setState(() => _activeTwinIndex = 0);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _activeTwinIndex == 0 ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: _activeTwinIndex == 0 ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        (number.length == 11 && iso.length == 4 && operator != null)
                                            ? Icons.check_circle_rounded
                                            : Icons.looks_one_rounded,
                                        size: 16,
                                        color: _activeTwinIndex == 0
                                            ? const Color(0xff075a8d)
                                            : ((number.length == 11 && iso.length == 4 && operator != null) ? const Color(0xff16a34a) : const Color(0xff64748b)),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          '1er Conteneur (Av.)',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: _activeTwinIndex == 0 ? FontWeight.bold : FontWeight.w600,
                                            color: _activeTwinIndex == 0 ? const Color(0xff075a8d) : const Color(0xff64748b),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: InkWell(
                                key: const ValueKey('twin-tab-1'),
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  if (_twinPageController.hasClients) {
                                    _twinPageController.animateToPage(1, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
                                  }
                                  setState(() => _activeTwinIndex = 1);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _activeTwinIndex == 1 ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: _activeTwinIndex == 1 ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        (number2.length == 11 && iso2.length == 4 && operator2 != null)
                                            ? Icons.check_circle_rounded
                                            : Icons.looks_two_rounded,
                                        size: 16,
                                        color: _activeTwinIndex == 1
                                            ? const Color(0xff075a8d)
                                            : ((number2.length == 11 && iso2.length == 4 && operator2 != null) ? const Color(0xff16a34a) : const Color(0xff64748b)),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          '2ème Conteneur (Ar.)',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: _activeTwinIndex == 1 ? FontWeight.bold : FontWeight.w600,
                                            color: _activeTwinIndex == 1 ? const Color(0xff075a8d) : const Color(0xff64748b),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          tabs,
                          SizedBox(
                            height: 380,
                            child: PageView(
                              controller: _twinPageController,
                              onPageChanged: (page) => setState(() => _activeTwinIndex = page),
                              children: [
                                SingleChildScrollView(
                                  key: const ValueKey('twin-page-0'),
                                  physics: const ClampingScrollPhysics(),
                                  child: first,
                                ),
                                SingleChildScrollView(
                                  key: const ValueKey('twin-page-1'),
                                  physics: const ClampingScrollPhysics(),
                                  child: second,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }),
                  ] else ...[
                    // 4. Numéro de conteneur ou Booking (Mono)
                    if (kind == 'loaded')
                      containerBoxes()
                    else
                      TextFormField(
                        controller: booking,
                        focusNode: bookingFocus,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) {
                          isoFocus.requestFocus();
                          isoController.selection = TextSelection(baseOffset: 0, extentOffset: isoController.text.length);
                        },
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Booking / ordre libre *',
                          helperText: 'Le booking n’est pas un numéro ISO de conteneur',
                          prefixIcon: Icon(Icons.receipt_long, size: 20),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Booking requis' : null,
                      ),
                    if (lookupHint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text(lookupHint!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                      ),
                    const SizedBox(height: 14),
                    // 5. Code ISO
                    TextFormField(
                      controller: isoController,
                      focusNode: isoFocus,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Code ISO *',
                        helperText: '4 caractères alphanumériques (ex: 22G1, 45G1, 45R1)',
                        prefixIcon: Icon(Icons.qr_code, size: 20),
                      ),
                      maxLength: 4,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')), UpperCaseFormatter()],
                      readOnly: !widget.canCorrect && lookupHint == 'ISO et armateur repris du référentiel.',
                      onChanged: (v) {
                        iso = v.trim().toUpperCase();
                        setState(() {});
                        if (iso.length == 4) {
                          pickOperator(forSecond: false);
                        }
                      },
                      onFieldSubmitted: (_) => pickOperator(forSecond: false),
                      validator: (v) => RegExp(r'^[0-9A-Z]{4}$').hasMatch(v ?? '') ? null : 'Code ISO invalide',
                    ),
                    const SizedBox(height: 12),
                    // 6. Armateur
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: widget.canCorrect || lookupHint != 'ISO et armateur repris du référentiel.'
                          ? () => pickOperator(forSecond: false)
                          : null,
                      icon: const Icon(Icons.business, size: 20),
                      label: Text(
                        operator == null ? 'Choisir armateur *' : '${operator!.name} (${operator!.id})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // 7. Bouton enregistrer
                  FilledButton.icon(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: busy ? null : submit,
                    icon: const Icon(Icons.save),
                    label: Text(
                      busy ? 'Enregistrement…' : 'Enregistrer l’entrée',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class UpperCaseFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue oldValue,TextEditingValue newValue)=>
    newValue.copyWith(text:newValue.text.toUpperCase(), selection:newValue.selection);
}

class SingleCharOverrideFormatter extends TextInputFormatter {
  final bool isLetter;
  final VoidCallback? onAdvance;
  SingleCharOverrideFormatter({required this.isLetter, this.onAdvance});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final allowedPattern = isLetter ? RegExp('[a-zA-Z]') : RegExp('[0-9]');

    if (newValue.text.length == 1) {
      if (allowedPattern.hasMatch(newValue.text)) {
        if (oldValue.text.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onAdvance?.call());
        }
        return TextEditingValue(
          text: newValue.text.toUpperCase(),
          selection: const TextSelection.collapsed(offset: 1),
        );
      }
      return oldValue;
    }

    String? targetChar;
    final cursor = newValue.selection.baseOffset;
    if (cursor > 0 && cursor <= newValue.text.length) {
      final typed = newValue.text[cursor - 1];
      if (allowedPattern.hasMatch(typed)) {
        targetChar = typed.toUpperCase();
      }
    }

    if (targetChar == null) {
      for (int i = newValue.text.length - 1; i >= 0; i--) {
        if (allowedPattern.hasMatch(newValue.text[i])) {
          targetChar = newValue.text[i].toUpperCase();
          break;
        }
      }
    }

    if (targetChar != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onAdvance?.call());
      return TextEditingValue(
        text: targetChar,
        selection: const TextSelection.collapsed(offset: 1),
      );
    }

    return oldValue;
  }
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

class SupervisorApproval {
  final String code;
  final String reason;
  const SupervisorApproval({required this.code, required this.reason});
}

Future<SupervisorApproval?> showSupervisorApprovalDialog(
  BuildContext context, {
  required String title,
  required String visitPlate,
  required String defaultReason,
}) async {
  final codeCtrl = TextEditingController();
  final reasonCtrl = TextEditingController(text: defaultReason);
  String? errorMsg;

  return showDialog<SupervisorApproval>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            icon: const Icon(Icons.shield, color: Color(0xffdc2626), size: 40),
            title: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xfffef2f2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xfffecaca)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CAMION : $visitPlate',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xff991b1b),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Cette operation exceptionnelle annule la rotation et autorise le camion a sortir avec son chargement. Le visa du superviseur (Code 01010909) est obligatoire.',
                          style: TextStyle(fontSize: 11, color: Color(0xff7f1d1d)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Motif d\'annulation *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: codeCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Code Superviseur (01010909) *',
                      prefixIcon: const Icon(Icons.lock),
                      errorText: errorMsg,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Fermer / Retour'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xffdc2626),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.verified_user),
                label: const Text('Valider l\'annulation'),
                onPressed: () {
                  final code = codeCtrl.text.trim();
                  final reason = reasonCtrl.text.trim();
                  if (reason.length < 5) {
                    setDialogState(() {
                      errorMsg = 'Motif d\'au moins 5 caracteres requis.';
                    });
                    return;
                  }
                  if (code != '01010909') {
                    setDialogState(() {
                      errorMsg = 'Code superviseur incorrect (01010909 requis).';
                    });
                    return;
                  }
                  Navigator.pop(ctx, SupervisorApproval(code: code, reason: reason));
                },
              ),
            ],
          );
        },
      );
    },
  );
}

class ExitScreen extends StatefulWidget {
  const ExitScreen({super.key, required this.repository, required this.canCancel, this.isFullScreen = false});
  final PointageRepository repository;
  final bool canCancel;
  final bool isFullScreen;
  @override State<ExitScreen> createState() => _ExitScreenState();
}

class _ExitScreenState extends State<ExitScreen> {
  final searchController = TextEditingController();
  final reasonController = TextEditingController();
  late Future<List<TruckVisit>> visitsFuture;
  TruckVisit? selectedVisit;
  bool busy = false;
  bool _isPickerOpen = false;
  List<OperatorRecord> operators = [];

  // Active visit inspection & pickup state
  String? currentVisitId;
  bool isDeposited = true; // For loaded: container deposited in yard
  bool isPickedUp = true;  // For empty: container picked up on chassis
  bool isTwin = false;     // For empty pickup: Mono vs Twin (2x20')

  // Pickup container 1
  final List<TextEditingController> boxes1 = List.generate(11, (_) => TextEditingController());
  final List<FocusNode> focus1 = List.generate(11, (_) => FocusNode());
  final iso1Controller = TextEditingController();
  final iso1Focus = FocusNode();
  String iso1 = '';
  OperatorRecord? operator1;

  // Pickup container 2 (Twin)
  final List<TextEditingController> boxes2 = List.generate(11, (_) => TextEditingController());
  final List<FocusNode> focus2 = List.generate(11, (_) => FocusNode());
  final iso2Controller = TextEditingController();
  final iso2Focus = FocusNode();
  String iso2 = '';
  OperatorRecord? operator2;

  String get number1 => boxes1.map((c) => c.text).join().toUpperCase();
  String get number2 => boxes2.map((c) => c.text).join().toUpperCase();

  @override
  void initState() {
    super.initState();
    loadVisits();
    loadOperators();
    _initBoxKeyEvents();
  }

  void _initBoxKeyEvents() {
    for (int i = 0; i < 11; i++) {
      final idx = i;
      focus1[idx].onKeyEvent = (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
          if (boxes1[idx].text.isEmpty && idx > 0) {
            focus1[idx - 1].requestFocus();
            boxes1[idx - 1].selection = TextSelection(baseOffset: 0, extentOffset: boxes1[idx - 1].text.length);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      };
      focus2[idx].onKeyEvent = (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
          if (boxes2[idx].text.isEmpty && idx > 0) {
            focus2[idx - 1].requestFocus();
            boxes2[idx - 1].selection = TextSelection(baseOffset: 0, extentOffset: boxes2[idx - 1].text.length);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      };
    }
  }

  void _advanceExitBox(int index, bool second) {
    final f = second ? focus2 : focus1;
    final b = second ? boxes2 : boxes1;
    if (index < 10) {
      f[index + 1].requestFocus();
      b[index + 1].selection = TextSelection(
        baseOffset: 0,
        extentOffset: b[index + 1].text.length,
      );
    } else {
      if (second) {
        iso2Focus.requestFocus();
        iso2Controller.selection = TextSelection(baseOffset: 0, extentOffset: iso2Controller.text.length);
      } else {
        iso1Focus.requestFocus();
        iso1Controller.selection = TextSelection(baseOffset: 0, extentOffset: iso1Controller.text.length);
      }
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    reasonController.dispose();
    iso1Controller.dispose();
    iso2Controller.dispose();
    iso1Focus.dispose();
    iso2Focus.dispose();
    for (final c in [...boxes1, ...boxes2]) {
      c.dispose();
    }
    for (final f in [...focus1, ...focus2]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> loadOperators() async {
    try {
      final list = await widget.repository.operators();
      if (mounted) setState(() => operators = list);
    } catch (_) {}
  }

  void loadVisits() {
    setState(() {
      visitsFuture = widget.repository.visits(insideOnly: true);
    });
  }

  void syncVisitState(TruckVisit visit) {
    if (currentVisitId == visit.id) return;
    currentVisitId = visit.id;
    isDeposited = true;
    isPickedUp = true;
    isTwin = false;
    iso1 = visit.iso;
    iso1Controller.text = iso1;
    iso2 = visit.iso2 ?? '';
    iso2Controller.text = iso2;
    operator1 = operators.where((o) => o.id == visit.armateur).firstOrNull;
    operator2 = visit.armateur2 != null ? operators.where((o) => o.id == visit.armateur2).firstOrNull : null;
    for (final b in [...boxes1, ...boxes2]) {
      b.clear();
    }
  }

  Future<void> pickOperator({bool forSecond = false}) async {
    if (_isPickerOpen) return;
    _isPickerOpen = true;
    try {
      final chosen = await showOperatorPicker(context, operators);
      if (chosen != null && mounted) {
        setState(() {
          if (forSecond) {
            operator2 = chosen;
          } else {
            operator1 = chosen;
            operator2 ??= chosen;
          }
        });
        if (!forSecond && isTwin) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            focus2[0].requestFocus();
          });
        }
      }
    } finally {
      _isPickerOpen = false;
    }
  }

  Future<void> pasteFromClipboard({bool second = false}) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.replaceAll(RegExp(r'\s+'), '').toUpperCase() ?? '';
    if (text.isEmpty) return;
    final b = second ? boxes2 : boxes1;
    final f = second ? focus2 : focus1;
    for (int i = 0; i < 11 && i < text.length; i++) {
      b[i].text = text[i];
    }
    setState(() {});
    if (text.length >= 11) {
      FocusScope.of(context).unfocus();
    } else {
      f[text.length].requestFocus();
    }
  }

  Future<void> exitTruck(TruckVisit visit) async {
    setState(() => busy = true);
    DocumentOutcome? outcome;
    try {
      await widget.repository.exit(visit.id);
      try {
        final documents = DocumentService(widget.repository.client);
        outcome = await documents.finalizeLatest(visit.id, 'SORTIE');
      } catch (_) {
        /* Retry in Bons. */
      }
      if (!mounted) return;
      message(context, 'Sortie confirmée pour le camion ${visit.plate}.');
      final visitId = visit.id;
      final pdfBytes = outcome?.bytes;
      setState(() {
        selectedVisit = null;
        currentVisitId = null;
        searchController.clear();
      });
      loadVisits();

      if (mounted && pdfBytes != null) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => BonConfirmationDialog(
            bytes: pdfBytes,
            kind: 'SORTIE',
            visitId: visitId,
            plate: visit.plate,
            containerNumber: visit.container,
            containerNumber2: visit.container2,
            onNewTruck: () {
              if (mounted) searchController.clear();
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) message(context, 'Sortie refusée : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> exitTruckWithPickup(TruckVisit visit) async {
    final isoError = ContainerIso.pickupError(expected: visit.iso, actual: iso1,
      expectedSecond: visit.iso2, actualSecond: iso2, twin: isTwin);
    if (isoError != null) {
      message(context, isoError);
      return;
    }
    if (iso1.trim().isEmpty || !RegExp(r'^[0-9A-Z]{4}$').hasMatch(iso1.trim())) {
      message(context, 'Code ISO requis pour le conteneur 1 (4 caractères, ex: 22G1, 45G1).');
      return;
    }
    if (operator1 == null) {
      message(context, 'Choisissez l’armateur du conteneur 1.');
      return;
    }
    final c1 = number1;
    if (c1.length < 11 || !ContainerNumber.isValid(c1)) {
      final expected = ContainerNumber.expectedCheckDigit(c1);
      if (expected != null && c1.length == 11) {
        message(context, 'Chiffre de contrôle ISO invalide pour le conteneur 1 (attendu: $expected).');
      } else {
        message(context, 'Numéro de conteneur 1 ISO 6346 invalide (4 lettres + 7 chiffres requis).');
      }
      return;
    }
    final c2 = number2;
    if (isTwin) {
      if (c2.length < 11 || !ContainerNumber.isValid(c2)) {
        final expected2 = ContainerNumber.expectedCheckDigit(c2);
        if (expected2 != null && c2.length == 11) {
          message(context, 'Chiffre de contrôle ISO invalide pour le 2ème conteneur (attendu: $expected2).');
        } else {
          message(context, 'Numéro du 2ème conteneur Twin ISO 6346 invalide (4 lettres + 7 chiffres requis).');
        }
        return;
      }
      if (iso2.trim().isEmpty || !RegExp(r'^[0-9A-Z]{4}$').hasMatch(iso2.trim())) {
        message(context, 'Code ISO requis pour le 2ème conteneur Twin.');
        return;
      }
      if (operator2 == null) {
        message(context, 'Choisissez l’armateur du 2ème conteneur Twin.');
        return;
      }
    }

    setState(() => busy = true);
    DocumentOutcome? outcome;
    try {
      await widget.repository.exitWithDetails(
        visit.id,
        pickupContainer: c1,
        pickupIso: iso1,
        pickupArmateur: operator1?.id ?? visit.armateur,
        isTwin: isTwin,
        pickupContainer2: isTwin ? c2 : null,
        pickupIso2: isTwin ? iso2 : null,
        pickupArmateur2: isTwin ? (operator2?.id ?? operator1?.id ?? visit.armateur) : null,
      );
      try {
        final documents = DocumentService(widget.repository.client);
        outcome = await documents.finalizeLatest(visit.id, 'SORTIE');
      } catch (_) {
        /* Retry in Bons. */
      }
      if (!mounted) return;
      message(context, 'Sortie et prise conteneur confirmées pour le camion ${visit.plate}.');
      final visitId = visit.id;
      final pdfBytes = outcome?.bytes;
      final savedPlate = visit.plate;
      final savedContainer1 = c1.isNotEmpty ? c1 : visit.container;
      final savedContainer2 = isTwin ? c2 : visit.container2;
      setState(() {
        selectedVisit = null;
        currentVisitId = null;
        searchController.clear();
      });
      loadVisits();

      if (mounted && pdfBytes != null) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => BonConfirmationDialog(
            bytes: pdfBytes,
            kind: 'SORTIE',
            visitId: visitId,
            plate: savedPlate,
            containerNumber: savedContainer1,
            containerNumber2: savedContainer2,
            onNewTruck: () {
              if (mounted) searchController.clear();
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) message(context, 'Sortie refusée : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> exitEmptyWithoutPickup(TruckVisit visit) async {
    setState(() => busy = true);
    try {
      await widget.repository.exitWithDetails(
        visit.id,
        emptyExitWithoutPickup: true,
      );
      if (!mounted) return;
      message(context, 'Sortie à vide confirmée pour le camion ${visit.plate} (visite clôturée sans conteneur).');
      setState(() {
        selectedVisit = null;
        currentVisitId = null;
        searchController.clear();
      });
      loadVisits();
    } catch (e) {
      if (mounted) message(context, 'Erreur lors de la clôture à vide : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancelTruckWithoutDeposit(TruckVisit visit) async {
    final approval = await showSupervisorApprovalDialog(
      context,
      title: 'Sortie Sans Dépose (Annulation)',
      visitPlate: visit.plate,
      defaultReason: 'Sortie sans décharge de conteneur (ressorti avec son chargement)',
    );
    if (approval == null) return;

    setState(() => busy = true);
    DocumentOutcome? outcome;
    try {
      await widget.repository.cancel(
        visit.id,
        approval.reason,
        adminCode: approval.code,
      );

      try {
        final documents = DocumentService(widget.repository.client);
        outcome = await documents.finalizeLatest(visit.id, 'ANNULATION');
      } catch (_) {
        /* Retry in Bons. */
      }

      if (!mounted) return;
      message(context, 'Sortie sans dépose enregistrée pour le camion ${visit.plate} (Visite annulée).');
      final visitId = visit.id;
      final pdfBytes = outcome?.bytes;

      setState(() {
        selectedVisit = null;
        currentVisitId = null;
        searchController.clear();
      });
      loadVisits();

      if (mounted && pdfBytes != null) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => BonConfirmationDialog(
            bytes: pdfBytes,
            kind: 'ANNULATION',
            visitId: visitId,
            plate: visit.plate,
            containerNumber: visit.container,
            containerNumber2: visit.container2,
            onNewTruck: () {
              if (mounted) searchController.clear();
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) message(context, 'Erreur lors de l’annulation : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancelTruck(TruckVisit visit) async {
    final approval = await showSupervisorApprovalDialog(
      context,
      title: 'Annuler la visite',
      visitPlate: visit.plate,
      defaultReason: reasonController.text.trim().isNotEmpty
          ? reasonController.text.trim()
          : 'Annulation demandée par le superviseur',
    );
    if (approval == null) return;

    setState(() => busy = true);
    DocumentOutcome? outcome;
    try {
      await widget.repository.cancel(
        visit.id,
        approval.reason,
        adminCode: approval.code,
      );
      try {
        final documents = DocumentService(widget.repository.client);
        outcome = await documents.finalizeLatest(visit.id, 'ANNULATION');
      } catch (_) {
        /* Retry in Bons. */
      }
      if (!mounted) return;
      message(context, 'Visite annulée avec visa responsable.');
      final visitId = visit.id;
      final pdfBytes = outcome?.bytes;

      setState(() {
        selectedVisit = null;
        currentVisitId = null;
        searchController.clear();
        reasonController.clear();
      });
      loadVisits();

      if (mounted && pdfBytes != null) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => BonConfirmationDialog(
            bytes: pdfBytes,
            kind: 'ANNULATION',
            visitId: visitId,
            plate: visit.plate,
            containerNumber: visit.container,
            containerNumber2: visit.container2,
            onNewTruck: () {
              if (mounted) {
                searchController.clear();
                reasonController.clear();
              }
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) message(context, 'Annulation refusée : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void showCancelDialog(BuildContext context, TruckVisit v) {
    cancelTruck(v);
  }

  Widget infoTile({
    required IconData icon,
    required String label,
    required String value,
    bool isHighlighted = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xff075a8d)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Color(0xff64748b), fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: isHighlighted ? 17 : 14,
                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
                  color: isHighlighted ? const Color(0xff063e66) : const Color(0xff1e293b),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget exitContainerBoxes({bool second = false}) {
    final currentNumber = second ? number2 : number1;
    final b = second ? boxes2 : boxes1;
    final f = second ? focus2 : focus1;
    final isValid = currentNumber.length == 11 && ContainerNumber.isValid(currentNumber);
    final expected = currentNumber.length >= 10 ? ContainerNumber.expectedCheckDigit(currentNumber) : null;
    final has11 = currentNumber.length == 11;
    final checkDigitMismatch = has11 && !isValid && expected != null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            second ? '2ème Conteneur (20\') · ISO 6346 *' : (isTwin ? '1er Conteneur (20\') · ISO 6346 *' : 'Numéro du conteneur · ISO 6346 *'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => pasteFromClipboard(second: second),
                icon: const Icon(Icons.paste_rounded, size: 16),
                label: const Text('Coller', style: TextStyle(fontSize: 12)),
              ),
              if (currentNumber.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: 'Effacer',
                  onPressed: () {
                    for (final c in b) {
                      c.clear();
                    }
                    setState(() {});
                  },
                ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 6),
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyV, control: true): () => pasteFromClipboard(second: second),
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () => pasteFromClipboard(second: second),
        },
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(11, (i) {
              final isLetter = i < 4;
              final isCheckDigit = i == 10;
              return Padding(
                padding: EdgeInsets.only(right: isLetter && i == 3 ? 10 : (isCheckDigit ? 0 : 3)),
                child: SizedBox(
                  width: 32,
                  child: TextFormField(
                    controller: b[i],
                    focusNode: f[i],
                    textAlign: TextAlign.center,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      SingleCharOverrideFormatter(
                        isLetter: isLetter,
                        onAdvance: () => _advanceExitBox(i, second),
                      ),
                    ],
                    keyboardType: isLetter ? TextInputType.text : TextInputType.number,
                    onTap: () {
                      b[i].selection = TextSelection(baseOffset: 0, extentOffset: b[i].text.length);
                    },
                    onFieldSubmitted: (_) => _advanceExitBox(i, second),
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      filled: true,
                      fillColor: isLetter
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
                    onChanged: (v) {
                      setState(() {});
                    },
                  ),
                ),
              );
            }),
          ),
        ),
      ),
      const SizedBox(height: 6),
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
            Text('Chiffre calculé : $expected (saisi : ${b[10].text})',
                style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text('Corriger en $expected', style: const TextStyle(fontSize: 11)),
              onPressed: () {
                b[10].text = expected.toString();
                setState(() {});
                if (second) {
                  iso2Focus.requestFocus();
                  iso2Controller.selection = TextSelection(baseOffset: 0, extentOffset: iso2Controller.text.length);
                } else {
                  iso1Focus.requestFocus();
                  iso1Controller.selection = TextSelection(baseOffset: 0, extentOffset: iso1Controller.text.length);
                }
              },
            ),
          ],
        )
      else if (currentNumber.length == 10 && expected != null)
        Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xff075a8d), size: 16),
            const SizedBox(width: 6),
            Text('Chiffre de contrôle attendu : $expected',
                style: const TextStyle(fontSize: 12, color: Color(0xff075a8d), fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text('Appliquer $expected', style: const TextStyle(fontSize: 11)),
              onPressed: () {
                b[10].text = expected.toString();
                setState(() {});
                if (second) {
                  iso2Focus.requestFocus();
                  iso2Controller.selection = TextSelection(baseOffset: 0, extentOffset: iso2Controller.text.length);
                } else {
                  iso1Focus.requestFocus();
                  iso1Controller.selection = TextSelection(baseOffset: 0, extentOffset: iso1Controller.text.length);
                }
              },
            ),
          ],
        )
      else
        const Text('4 lettres + 7 chiffres, avec chiffre de contrôle', style: TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        loadVisits();
        await visitsFuture;
      },
      child: FutureBuilder<List<TruckVisit>>(
        future: visitsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  title: Text('Erreur : ${snapshot.error}'),
                  trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: loadVisits),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final insideVisits = (snapshot.data ?? []).where((v) => v.isInside).toList();
          final query = searchController.text.trim().toUpperCase();
          final cleanQuery = query.replaceAll(RegExp(r'[^A-Z0-9]'), '');

          List<TruckVisit> matches = [];
          if (query.isNotEmpty) {
            matches = insideVisits.where((v) {
              final plate = v.plate.toUpperCase();
              final cleanPlate = plate.replaceAll(RegExp(r'[^A-Z0-9]'), '');
              final cont = v.container?.toUpperCase() ?? '';
              final cleanCont = cont.replaceAll(RegExp(r'[^A-Z0-9]'), '');
              final cont2 = v.container2?.toUpperCase() ?? '';
              final cleanCont2 = cont2.replaceAll(RegExp(r'[^A-Z0-9]'), '');
              final book = v.booking?.toUpperCase() ?? '';
              final cleanBook = book.replaceAll(RegExp(r'[^A-Z0-9]'), '');

              final rawMatch = plate.contains(query) || cont.contains(query) || cont2.contains(query) || book.contains(query);
              final cleanMatch = cleanQuery.isNotEmpty && (
                cleanPlate.contains(cleanQuery) ||
                cleanCont.contains(cleanQuery) ||
                cleanCont2.contains(cleanQuery) ||
                cleanBook.contains(cleanQuery)
              );

              return rawMatch || cleanMatch;
            }).toList();
          }

          TruckVisit? activeVisit = selectedVisit;
          if (activeVisit != null && !insideVisits.any((v) => v.id == activeVisit!.id)) {
            activeVisit = null;
          }
          if (activeVisit == null && matches.length == 1) {
            activeVisit = matches.first;
          }
          if (activeVisit != null) {
            syncVisitState(activeVisit);
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              if (!widget.isFullScreen)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('Validation de la sortie',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Actualiser',
                        onPressed: loadVisits,
                      ),
                    ],
                  ),
                ),

              // Search field
              Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: searchController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [UpperCaseFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Plaque ou Conteneur *',
                          hintText: 'Ex: 15262-H-1, 5262H1 ou CSQU3054383',
                          helperText: 'Recherche libre : tirets et espaces facultatifs (ex: 5262H1)',
                          prefixIcon: const Icon(Icons.search, size: 22),
                          suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                tooltip: 'Effacer la recherche',
                                onPressed: () {
                                  searchController.clear();
                                  setState(() => selectedVisit = null);
                                },
                              )
                            : null,
                        ),
                        onChanged: (_) => setState(() => selectedVisit = null),
                      ),
                    ],
                  ),
                ),
              ),

              // State 1: Search query is empty -> DO NOT show truck list upfront
              if (query.isEmpty)
                Card(
                  elevation: 0,
                  color: const Color(0xfff8fafc),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                    child: Column(
                      children: [
                        Icon(Icons.search_rounded, size: 48, color: Colors.blueGrey.shade300),
                        const SizedBox(height: 12),
                        const Text(
                          'Saisie requise pour valider la sortie',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xff1e293b)),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Saisissez la plaque ou le numéro de conteneur ci-dessus. Les données du camion s’afficheront pour vérification avant la sortie.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Color(0xff64748b)),
                        ),
                        const SizedBox(height: 16),
                        Chip(
                          avatar: const Icon(Icons.local_shipping, size: 16, color: Color(0xff075a8d)),
                          label: Text(
                            insideVisits.isEmpty
                              ? 'Aucun camion actuellement sur parc'
                              : '${insideVisits.length} camion(s) actuellement sur parc',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xff075a8d)),
                          ),
                          backgroundColor: const Color(0xffe7f3ff),
                        ),
                      ],
                    ),
                  ),
                )

              // State 2: Query entered, but no matching inside truck found
              else if (matches.isEmpty)
                Card(
                  color: const Color(0xfffff5f5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xfffed7d7)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.redAccent),
                        const SizedBox(height: 10),
                        Text(
                          'Aucun camion actif trouvé pour "$query"',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xff9b2c2c)),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Vérifiez la plaque d’immatriculation ou le numéro de conteneur. Seuls les camions entrés et non encore sortis sont éligibles.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xff742a2a)),
                        ),
                      ],
                    ),
                  ),
                )

              // State 3: Multiple matches found and none selected yet
              else if (activeVisit == null && matches.length > 1)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Text(
                        '${matches.length} camions correspondent à "$query" : choisissez le camion',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xff334155)),
                      ),
                    ),
                    for (final v in matches)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.local_shipping, color: Color(0xff075a8d)),
                          title: Text(v.plate, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${v.container ?? v.booking ?? 'Sans conteneur'}${v.isTwin ? ' + ${v.container2 ?? 'Twin'}' : ''} · ${v.armateur} · ${v.iso}'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => setState(() => selectedVisit = v),
                        ),
                      ),
                  ],
                )

              // State 4: Truck matched or selected -> Full verification & action form (styled like Entrée)
              else if (activeVisit != null)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Verification header badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xffe7f3ff),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_user, size: 16, color: Color(0xff075a8d)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Données du camion à vérifier',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xff075a8d)),
                                  ),
                                ],
                              ),
                            ),
                            if (matches.length > 1)
                              TextButton.icon(
                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: () => setState(() => selectedVisit = null),
                                icon: const Icon(Icons.swap_horiz, size: 16),
                                label: const Text('Changer', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 1. Truck visual scene
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xfff8fafc),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TruckScene(
                                kind: activeVisit.entryKind == 'loaded'
                                    ? (isDeposited ? 'empty' : 'loaded')
                                    : (isPickedUp ? 'loaded' : 'empty'),
                                height: 65, width: 135,
                                plate: activeVisit.plate,
                                driverCin: activeVisit.cin,
                                isTwin: activeVisit.isTwin,
                                containerNumber: activeVisit.container,
                                containerNumber2: activeVisit.container2,
                                iso: activeVisit.iso, iso2: activeVisit.iso2,
                                operator: activeVisit.armateur,
                                operator2: activeVisit.armateur2,
                                showUnknown: true,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      activeVisit.entryKind == 'loaded'
                                          ? (isDeposited ? 'Camion entré chargé · Sort VIDE' : 'Camion entré chargé · Ressort AVEC conteneur')
                                          : (isPickedUp ? 'Camion entré vide · Sort CHARGÉ' : 'Camion entré vide · Ressort VIDE (ki dkhal ki khraj)'),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Arrivée : ${activeVisit.enteredAt.toLocal().toString().substring(0, 16)}',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 2. Plaque d'immatriculation (pre-filled)
                        infoTile(
                          icon: Icons.pin_outlined,
                          label: 'Plaque d’immatriculation',
                          value: activeVisit.plate,
                          isHighlighted: true,
                        ),
                        const Divider(height: 16),

                        // 3. CIN Chauffeur (pre-filled)
                        infoTile(
                          icon: Icons.badge_outlined,
                          label: 'CIN chauffeur',
                          value: activeVisit.cin.isNotEmpty ? activeVisit.cin : '—',
                        ),
                        const Divider(height: 16),

                        // 4. Données d'arrivée (Conteneur / Booking / Armateur / ISO)
                        if (activeVisit.entryKind == 'loaded') ...[
                          infoTile(
                            icon: Icons.inventory_2_outlined,
                            label: activeVisit.isTwin ? 'Premier Conteneur (d’entrée)' : 'Conteneur (d’entrée)',
                            value: activeVisit.container ?? '—',
                            isHighlighted: true,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: infoTile(
                                  icon: Icons.qr_code,
                                  label: 'Code ISO',
                                  value: activeVisit.iso,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: infoTile(
                                  icon: Icons.business,
                                  label: 'Armateur',
                                  value: activeVisit.armateur,
                                ),
                              ),
                            ],
                          ),
                          if (activeVisit.isTwin && activeVisit.container2 != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xfff8fafc),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blueGrey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  infoTile(
                                    icon: Icons.inventory_2_outlined,
                                    label: 'Deuxième Conteneur (Twin)',
                                    value: activeVisit.container2!,
                                    isHighlighted: true,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: infoTile(
                                          icon: Icons.qr_code,
                                          label: 'Code ISO 2',
                                          value: activeVisit.iso2 ?? '22G1',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: infoTile(
                                          icon: Icons.business,
                                          label: 'Armateur 2',
                                          value: activeVisit.armateur2 ?? activeVisit.armateur,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ] else ...[
                          infoTile(
                            icon: Icons.receipt_long,
                            label: 'Booking d’entrée (chargement prévu)',
                            value: activeVisit.booking ?? '—',
                            isHighlighted: true,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: infoTile(
                                  icon: Icons.qr_code,
                                  label: 'Code ISO prévu',
                                  value: activeVisit.iso,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: infoTile(
                                  icon: Icons.business,
                                  label: 'Armateur prévu',
                                  value: activeVisit.armateur,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),

                        // 5. INSPECTION & CONTROLE CHECK ("7ato ola la" / "haz conatiner ola la")
                        if (activeVisit.entryKind == 'loaded') ...[
                          // Case A: Entered LOADED -> Check if deposited or not
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDeposited ? const Color(0xfff0fdf4) : const Color(0xfffffbeb),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDeposited ? Colors.green.shade300 : Colors.amber.shade300,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isDeposited ? Icons.task_alt : Icons.help_outline,
                                      size: 20,
                                      color: isDeposited ? const Color(0xff168846) : Colors.amber.shade900,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Contrôle décharge : Conteneur déposé au terminal ?',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ChoiceChip(
                                        avatar: Icon(isDeposited ? Icons.check_circle : Icons.circle_outlined, size: 16),
                                        label: const Text('OUI · Conteneur déposé', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        selected: isDeposited,
                                        selectedColor: const Color(0xffdcfce7),
                                        onSelected: (sel) {
                                          if (sel) setState(() => isDeposited = true);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ChoiceChip(
                                        avatar: Icon(!isDeposited ? Icons.cancel : Icons.circle_outlined, size: 16),
                                        label: const Text('NON · Non déposé', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        selected: !isDeposited,
                                        selectedColor: const Color(0xfffef3c7),
                                        onSelected: (sel) {
                                          if (sel) setState(() => isDeposited = false);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (isDeposited)
                                  const Text(
                                    '✓ Le conteneur est enregistré en stock du parc. Le camion ressort vide.',
                                    style: TextStyle(fontSize: 12, color: Color(0xff168846), fontWeight: FontWeight.w500),
                                  )
                                else
                                  const Text(
                                    '⚠ Le camion quitte le terminal sans avoir déchargé son conteneur. La visite sera annulée.',
                                    style: TextStyle(fontSize: 12, color: Color(0xff92400e), fontWeight: FontWeight.w500),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Action button for loaded truck
                          if (isDeposited)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xff168846),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: busy ? null : () => exitTruck(activeVisit!),
                              icon: busy
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.exit_to_app, size: 22),
                              label: Text(
                                busy ? 'Validation de la sortie…' : 'Valider la sortie du camion',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            )
                          else
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: busy ? null : () => cancelTruckWithoutDeposit(activeVisit!),
                              icon: const Icon(Icons.cancel_outlined, size: 22),
                              label: Text(
                                busy ? 'Annulation en cours…' : 'Confirmer la sortie sans dépose (Annuler la visite)',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ] else ...[
                          // Case B: Entered EMPTY -> Check if loaded on chassis
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isPickedUp ? const Color(0xfff0fdf4) : const Color(0xfffffbeb),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isPickedUp ? Colors.green.shade300 : Colors.amber.shade300,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isPickedUp ? Icons.local_shipping : Icons.help_outline,
                                      size: 20,
                                      color: isPickedUp ? const Color(0xff168846) : Colors.amber.shade900,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Contrôle châssis : Le camion a-t-il chargé un conteneur ?',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ChoiceChip(
                                        avatar: Icon(isPickedUp ? Icons.check_circle : Icons.circle_outlined, size: 16),
                                        label: const Text('OUI · Conteneur chargé', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        selected: isPickedUp,
                                        selectedColor: const Color(0xffdcfce7),
                                        onSelected: (sel) {
                                          if (sel) setState(() => isPickedUp = true);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ChoiceChip(
                                        avatar: Icon(!isPickedUp ? Icons.cancel : Icons.circle_outlined, size: 16),
                                        label: const Text('NON · Sortie à vide', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        selected: !isPickedUp,
                                        selectedColor: const Color(0xfffef3c7),
                                        onSelected: (sel) {
                                          if (sel) setState(() => isPickedUp = false);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          if (isPickedUp) ...[
                            // Mode Mono vs Twin 2x20'
                            Row(children: [
                              Expanded(
                                child: ChoiceChip(
                                  avatar: Icon(!isTwin ? Icons.check_circle : Icons.circle_outlined, size: 16),
                                  label: const Text('1 Conteneur (Mono)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  selected: !isTwin,
                                  onSelected: (sel) {
                                    if (sel) setState(() => isTwin = false);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  avatar: Icon(isTwin ? Icons.check_circle : Icons.circle_outlined, size: 16),
                                  label: const Text('Twin (2 x 20\')', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  selected: isTwin,
                                  onSelected: (sel) {
                                    if (sel) {
                                      setState(() {
                                        isTwin = true;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ]),
                            const SizedBox(height: 14),

                            // Conteneur 1 (Prise)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xfff8fafc),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blueGrey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    isTwin ? 'Premier Conteneur (20\') chargé *' : 'Conteneur chargé *',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xff075a8d)),
                                  ),
                                  const SizedBox(height: 8),
                                  exitContainerBoxes(second: false),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    controller: iso1Controller,
                                    focusNode: iso1Focus,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      labelText: 'Code ISO Conteneur 1 *',
                                      helperText: 'ISO réservé : ${activeVisit.iso} · même longueur requise',
                                      prefixIcon: const Icon(Icons.qr_code, size: 20),
                                    ),
                                    maxLength: 4,
                                    textCapitalization: TextCapitalization.characters,
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')), UpperCaseFormatter()],
                                    onChanged: (v) {
                                      iso1 = v.trim().toUpperCase();
                                      setState(() {});
                                      if (iso1.length == 4) {
                                        pickOperator(forSecond: false);
                                      }
                                    },
                                    onFieldSubmitted: (_) => pickOperator(forSecond: false),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      alignment: Alignment.centerLeft,
                                    ),
                                    onPressed: () => pickOperator(forSecond: false),
                                    icon: const Icon(Icons.business, size: 20),
                                    label: Text(
                                      operator1 == null ? 'Armateur Conteneur 1 *' : '${operator1!.name} (${operator1!.id})',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Conteneur 2 (Twin - Prise)
                            if (isTwin) ...[
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xfff8fafc),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blueGrey.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'Deuxième Conteneur (20\') · Compagnie différente autorisée *',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xff075a8d)),
                                    ),
                                    const SizedBox(height: 8),
                                    exitContainerBoxes(second: true),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: iso2Controller,
                                      focusNode: iso2Focus,
                                      textInputAction: TextInputAction.next,
                                      decoration: const InputDecoration(
                                        labelText: 'Code ISO Conteneur 2 *',
                                        helperText: 'Ex: 22G1',
                                        prefixIcon: Icon(Icons.qr_code, size: 20),
                                      ),
                                      maxLength: 4,
                                      textCapitalization: TextCapitalization.characters,
                                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')), UpperCaseFormatter()],
                                      onChanged: (v) {
                                        iso2 = v.trim().toUpperCase();
                                        setState(() {});
                                        if (iso2.length == 4) {
                                          pickOperator(forSecond: true);
                                        }
                                      },
                                      onFieldSubmitted: (_) => pickOperator(forSecond: true),
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        alignment: Alignment.centerLeft,
                                      ),
                                      onPressed: () => pickOperator(forSecond: true),
                                      icon: const Icon(Icons.business, size: 20),
                                      label: Text(
                                        operator2 == null ? 'Armateur Conteneur 2 *' : '${operator2!.name} (${operator2!.id})',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

                            // Action button: Confirmer chargement et valider sortie
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xff168846),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: busy ? null : () => exitTruckWithPickup(activeVisit!),
                              icon: busy
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check_circle, size: 22),
                              label: Text(
                                busy ? 'Validation de la prise…' : 'Valider la sortie du camion',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ] else ...[
                            // Empty exit without pickup ("ki dkhal ki khraj")
                            Card(
                              color: const Color(0xfffffbeb),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: Colors.amber.shade300),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text(
                                  'Le camion quitte le terminal à vide sans avoir chargé de conteneur (ki dkhal ki khraj). La visite sera clôturée/annulée sans mouvement de stock.',
                                  style: TextStyle(fontSize: 13, color: Color(0xff92400e), fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.amber.shade900,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: busy ? null : () => exitEmptyWithoutPickup(activeVisit!),
                              icon: const Icon(Icons.exit_to_app, size: 22),
                              label: Text(
                                busy ? 'Clôture en cours…' : 'Confirmer la sortie à vide (Annuler la visite)',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],

                        // Option Annulation (Admin)
                        if (widget.canCancel) ...[
                          const SizedBox(height: 10),
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                            onPressed: busy ? null : () => showCancelDialog(context, activeVisit!),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Annuler cette visite (Admin)'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class BonConfirmationDialog extends StatelessWidget {
  const BonConfirmationDialog({
    super.key,
    required this.bytes,
    required this.kind,
    required this.visitId,
    this.plate,
    this.containerNumber,
    this.containerNumber2,
    this.onNewTruck,
    this.onPrintOverride,
  });

  final Uint8List bytes;
  final String kind;
  final String visitId;
  final String? plate;
  final String? containerNumber;
  final String? containerNumber2;
  final VoidCallback? onNewTruck;
  final Future<void> Function()? onPrintOverride;

  Future<void> _print() async {
    if (onPrintOverride != null) {
      await onPrintOverride!();
      return;
    }
    final fileName = 'TCZ-$kind-$visitId.pdf';
    try {
      final printed = await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: fileName,
      );
      if (!printed) {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (_) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }

  Future<void> _download() async {
    final fileName = 'TCZ-$kind-$visitId.pdf';
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 36, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with success icon and title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xff16a34a).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: Color(0xff16a34a), size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${kind == 'ENTRÉE' ? 'Entrée' : (kind == 'SORTIE' ? 'Sortie' : kind)} enregistrée !',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xff063e66),
                          ),
                        ),
                        Text(
                          'Bon #${visitId.length > 8 ? visitId.substring(0, 8) : visitId}',
                          style: const TextStyle(fontSize: 12, color: Color(0xff64748b)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Color(0xff94a3b8)),
                    tooltip: 'Fermer',
                    onPressed: () {
                      Navigator.pop(context);
                      onNewTruck?.call();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Summary Card (Plate, Container, Time)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xfff8fafc),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xffe2e8f0)),
                ),
                child: Column(
                  children: [
                    if (plate != null && plate!.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Plaque camion', style: TextStyle(fontSize: 12, color: Color(0xff64748b))),
                          Text(plate!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xff0f172a))),
                        ],
                      ),
                    if (containerNumber != null && containerNumber!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Conteneur 1', style: TextStyle(fontSize: 12, color: Color(0xff64748b))),
                          Text(containerNumber!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xff075a8d))),
                        ],
                      ),
                    ],
                    if (containerNumber2 != null && containerNumber2!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Conteneur 2 (Twin)', style: TextStyle(fontSize: 12, color: Color(0xff64748b))),
                          Text(containerNumber2!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xff075a8d))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Button 1: Lancer l'impression et nouveau (Primary action)
              FilledButton.icon(
                key: const ValueKey('btn-print-and-new'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff16a34a),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                ),
                icon: const Icon(Icons.print_rounded, size: 20),
                label: const Text(
                  'Lancer l\'impression & Nouveau',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _print();
                  onNewTruck?.call();
                },
              ),
              const SizedBox(height: 10),

              // Button 2: Lancer l'impression seule
              FilledButton.tonalIcon(
                key: const ValueKey('btn-print-only'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff075a8d).withValues(alpha: 0.12),
                  foregroundColor: const Color(0xff075a8d),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.print_outlined, size: 19),
                label: const Text(
                  'Lancer l\'impression',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                onPressed: _print,
              ),
              const SizedBox(height: 10),

              // Button 3: Télécharger le PDF
              OutlinedButton.icon(
                key: const ValueKey('btn-download-pdf'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Color(0xffcbd5e1)),
                ),
                icon: const Icon(Icons.download_rounded, size: 19, color: Color(0xff334155)),
                label: const Text(
                  'Télécharger le PDF',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xff334155)),
                ),
                onPressed: _download,
              ),
              const SizedBox(height: 12),

              // Secondary actions: Aperçu PDF & Nouveau camion
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BonPdfScreen(
                              bytes: bytes,
                              kind: kind,
                              visitId: visitId,
                              autoPrint: false,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16, color: Color(0xff64748b)),
                      label: const Text(
                        'Aperçu PDF',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
                      ),
                    ),
                  ),
                  Flexible(
                    child: TextButton(
                      key: const ValueKey('btn-new-truck-dismiss'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        onNewTruck?.call();
                      },
                      child: const Text(
                        'Nouveau camion →',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xff075a8d)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BonPdfScreen extends StatefulWidget {
  const BonPdfScreen({
    super.key,
    required this.bytes,
    required this.kind,
    required this.visitId,
    this.autoPrint = true,
  });
  final Uint8List bytes;
  final String kind, visitId;
  final bool autoPrint;

  @override
  State<BonPdfScreen> createState() => _BonPdfScreenState();
}

class _BonPdfScreenState extends State<BonPdfScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.autoPrint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _print();
      });
    }
  }

  Future<void> _print() async {
    final fileName = 'TCZ-${widget.kind}-${widget.visitId}.pdf';
    try {
      final printed = await Printing.layoutPdf(
        onLayout: (_) => widget.bytes,
        name: fileName,
      );
      if (!printed && mounted) {
        await Printing.sharePdf(
          bytes: widget.bytes,
          filename: fileName,
        );
      }
    } catch (_) {
      await Printing.sharePdf(
        bytes: widget.bytes,
        filename: fileName,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = 'TCZ-${widget.kind}-${widget.visitId}.pdf';
    return Scaffold(
      appBar: AppBar(
        title: Text('Bon ${widget.kind}'),
        backgroundColor: const Color(0xff063e66),
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.download, color: Colors.white, size: 18),
            label: const Text('Télécharger', style: TextStyle(color: Colors.white)),
            onPressed: () => Printing.sharePdf(
              bytes: widget.bytes,
              filename: fileName,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff16a34a),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.print, size: 18),
              label: const Text('Imprimer'),
              onPressed: _print,
            ),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => widget.bytes,
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
        pdfFileName: fileName,
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xffcbd5e1), width: 1)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Télécharger PDF'),
                  onPressed: () => Printing.sharePdf(
                    bytes: widget.bytes,
                    filename: fileName,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff075a8d),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.print),
                  label: const Text('Lancer l\'impression', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _print,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VisitQueue extends StatelessWidget {
  const VisitQueue({super.key,required this.title,required this.repository,
    required this.queue,required this.onRefresh,required this.canCancel,required this.exitMode});
  final String title;final PointageRepository repository;final Future<List<TruckVisit>> queue;
  final VoidCallback onRefresh;final bool canCancel,exitMode;
  Future<void> open(BuildContext context,TruckVisit visit) async {
    final outcome = await showModalBottomSheet<DocumentOutcome?>(
      context:context,isScrollControlled:true,showDragHandle:true,
      builder:(_)=>VisitActionSheet(repository:repository,visit:visit,canCancel:canCancel,exitMode:exitMode));
    onRefresh();
    if(context.mounted && outcome?.bytes != null){
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => BonConfirmationDialog(
          bytes: outcome!.bytes!,
          kind: 'SORTIE',
          visitId: visit.id,
          plate: visit.plate,
          containerNumber: visit.container,
          containerNumber2: visit.container2,
        ),
      );
    }
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
        return ListView(padding:const EdgeInsets.symmetric(horizontal:12, vertical:8),children:[
          Padding(
            padding:const EdgeInsets.only(left:4, bottom:4),
            child:Row(children:[
              Icon(exitMode?Icons.exit_to_app:Icons.precision_manufacturing, size:20, color:Theme.of(context).colorScheme.primary),
              const SizedBox(width:8),
              Text(title, style:const TextStyle(fontWeight:FontWeight.bold, fontSize:16)),
            ]),
          ),
          const Padding(
            padding:EdgeInsets.only(left:4),
            child:Text('FIFO · du plus ancien au plus récent', style:TextStyle(fontSize:12, color:Colors.grey)),
          ),
          const SizedBox(height:60),
          const Center(child:Text('Aucun camion dans la file.')),
        ]);
      }
      return ListView(padding:const EdgeInsets.symmetric(horizontal:12, vertical:8),children:[
        Padding(
          padding:const EdgeInsets.only(left:4, bottom:2),
          child:Row(children:[
            Icon(exitMode?Icons.exit_to_app:Icons.precision_manufacturing, size:20, color:Theme.of(context).colorScheme.primary),
            const SizedBox(width:8),
            Text(title, style:const TextStyle(fontWeight:FontWeight.bold, fontSize:16)),
          ]),
        ),
        const Padding(
          padding:EdgeInsets.only(left:4, bottom:8),
          child:Text('FIFO · du plus ancien au plus récent', style:TextStyle(fontSize:12, color:Colors.grey)),
        ),
        for(final v in visits)Card(child:InkWell(onTap:()=>open(context,v),
          child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
            TruckScene(kind:v.needsEngin?(v.entryKind=='loaded'?'loaded':'empty'):
              (v.entryKind=='loaded'?'empty':'loaded'),height:70,width:110,
              plate:v.plate,
              driverCin:v.cin,
              isTwin:v.isTwin,containerNumber:v.container,containerNumber2:v.container2,
              iso:v.iso,iso2:v.iso2,operator:v.armateur,operator2:v.armateur2,
              showUnknown:true),
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
  final container=TextEditingController(),reason=TextEditingController();
  bool busy=false,completedMissing=false;
  @override void dispose(){container.dispose();reason.dispose();super.dispose();}
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
    await run(()async {await widget.repository.engin(widget.visit.id,
      containerNumber:widget.visit.entryKind=='empty'?ContainerNumber.normalize(container.text):null,
      position:null);
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
  Future<void> exitTruck() async {
    setState(()=>busy=true);
    DocumentOutcome? outcome;
    try {
      await widget.repository.exit(widget.visit.id);
      try {
        final documents=DocumentService(widget.repository.client);
        outcome=await documents.finalizeLatest(widget.visit.id,'SORTIE');
      } catch(_) {/* Retry in Bons. */}
      if(!mounted)return;
      message(context,'Sortie confirmée.');
      Navigator.pop(context, outcome);
    } catch(e) {
      if(mounted) message(context,'Opération refusée : $e');
    } finally {
      if(mounted) setState(()=>busy=false);
    }
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
        (v.entryKind=='loaded'?'empty':'loaded'),height:165,
        plate:v.plate,
        driverCin:v.cin,
        isTwin:v.isTwin,containerNumber:v.container,containerNumber2:v.container2,
        iso:v.iso,iso2:v.iso2,operator:v.armateur,operator2:v.armateur2,
        showUnknown:true),
      Text(pending?(v.entryKind=='loaded'?'DÉPOSE · conteneur au sol':'PRISE · conteneur sur châssis'):
        'Engin validé',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:14),
      if(pending && v.entryKind=='empty') TextField(controller:container,
        inputFormatters:[UpperCaseFormatter()],maxLength:11,
        decoration:const InputDecoration(labelText:'Numéro du conteneur pris *')),
      if(pending)FilledButton.icon(onPressed:busy?null:engin,icon:const Icon(Icons.check),
        label:Text(v.entryKind=='loaded'?'Valider la dépose':'Valider la prise')),
      if(widget.exitMode) ...[
        if(pending)const Padding(padding:EdgeInsets.symmetric(vertical:8),
          child:Text('Complétez Engin ici, puis rouvrez le camion pour valider la sortie.')),
        FilledButton.icon(onPressed:pending||busy?null:exitTruck,
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
        TextButton.icon(
          onPressed: busy ? null : () async {
            final approval = await showSupervisorApprovalDialog(
              context,
              title: 'Annuler cette visite',
              visitPlate: v.plate,
              defaultReason: reason.text.trim().isNotEmpty ? reason.text.trim() : 'Annulation demandée par le superviseur',
            );
            if (approval == null) return;
            DocumentOutcome? outcome;
            await run(() async {
              await widget.repository.cancel(v.id, approval.reason, adminCode: approval.code);
              try {
                final documents = DocumentService(widget.repository.client);
                outcome = await documents.finalizeLatest(v.id, 'ANNULATION');
              } catch (_) {}
            }, 'Visite annulée avec visa responsable.');
            if (context.mounted && outcome?.bytes != null) {
              await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => BonConfirmationDialog(
                  bytes: outcome!.bytes!,
                  kind: 'ANNULATION',
                  visitId: v.id,
                  plate: v.plate,
                  containerNumber: v.container,
                  containerNumber2: v.container2,
                ),
              );
            }
          },
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Annuler cette visite'),
        ),
      ],
    ])));
  }
}

class DataScreen extends StatefulWidget {
  const DataScreen({super.key,required this.repository});final PointageRepository repository;
  @override State<DataScreen> createState()=>_DataScreenState();
}
class _DataScreenState extends State<DataScreen> {
  String query='';late Future<List<DataTransaction>> visits;
  @override void initState(){super.initState();visits=widget.repository.transactions();}
  void refresh() => setState(() => visits = widget.repository.transactions());
  void details(DataTransaction row) => showDialog<void>(context:context,
    builder:(context)=>AlertDialog(
      title:Text('Transaction ${row.number} · ${row.visit.plate}'),
      content:SizedBox(width:600,child:SingleChildScrollView(child:Column(
        mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Créateur : ${row.creator}'),
          Text('Dernier modificateur : ${row.changer}'),
          if(row.visit.enginAt!=null)Text('Mouvement : ${DateTime.parse(row.visit.enginAt!).toLocal()}'),
          if(row.visit.exitedAt!=null)Text('Durée : ${DateTime.parse(row.visit.exitedAt!).difference(row.visit.enteredAt).inMinutes} min'),
          FutureBuilder<List<Map<String,dynamic>>>(future:widget.repository.events(row.visit.id),
            builder:(context,snapshot){
              if(snapshot.hasError)return Text('${snapshot.error}');
              if(!snapshot.hasData)return const CircularProgressIndicator();
              return Column(children:[for(final event in snapshot.data!)ListTile(
                title:Text(event['action'].toString()),
                subtitle:Text('${event['occurred_at']} · ${event['actor_id']}'))]);
            }),
        ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Fermer'))],
    ));
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
    Text('Data · visites & stock',style:Theme.of(context).textTheme.headlineSmall),
    Align(alignment:Alignment.centerRight,child:IconButton(
      tooltip:'Actualiser',onPressed:refresh,icon:const Icon(Icons.refresh))),
    const SizedBox(height:12),TextField(decoration:const InputDecoration(labelText:'Rechercher numéro, type, camion, conteneur, booking ou agent',
      prefixIcon:Icon(Icons.search)),onChanged:(x)=>setState(()=>query=x.toLowerCase())),
    FutureBuilder<List<DataTransaction>>(future:visits,builder:(context,s){
      if(s.hasError)return ListTile(title:Text('${s.error}'));
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final rows=s.data!.where((row)=>row.matches(query)).toList();
      return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(
          '${rows.length} transaction(s) affichée(s) sur ${s.data!.length} chargée(s) · 500 dernières visites maximum')),
        if(rows.isEmpty)const ListTile(title:Text('Aucune transaction trouvée')),
        if(rows.isNotEmpty)SingleChildScrollView(scrollDirection:Axis.horizontal,
          child:DataTable(columns:[
            for(final label in ['Numéro','Type de transaction','Camion','Conteneur(s)',
              'Booking / Order','Armateur(s)','Statut','Créateur','Dernier modificateur',
              'Créée le','Modifiée le']) DataColumn(label:Text(label)),
          ],rows:[for(final row in rows)DataRow(cells:[
            DataCell(Text(row.number),onTap:()=>details(row)),DataCell(Text(row.type)),
            DataCell(Text(row.visit.plate)),
            DataCell(SelectableText(row.containers.isEmpty?'—':row.containers)),
            DataCell(Text(row.bookings.isEmpty?'—':row.bookings)),
            DataCell(Text([row.visit.armateur,row.visit.armateur2].whereType<String>().join(' / '))),
            DataCell(Text(row.status)),DataCell(Text(row.creator)),DataCell(Text(row.changer)),
            DataCell(Text(row.visit.enteredAt.toLocal().toString().split('.').first)),
            DataCell(Text(row.changedAt.toLocal().toString().split('.').first)),
          ])])),
      ]);
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
    if (kIsWeb) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xff075a8d)),
              SizedBox(width: 8),
              Text('Imprimantes sur le Web'),
            ],
          ),
          content: const Text(
            'Sur un navigateur Web (Chrome, Edge), les règles de sécurité Internet empêchent un site web de scanner directement la liste des imprimantes de votre appareil.\n\n'
            '• Pour imprimer : Cliquez sur « Imprimer » pour ouvrir la boîte de dialogue de votre navigateur où toutes vos imprimantes sont accessibles.\n\n'
            '• Pour une détection directe des imprimantes Bluetooth/WiFi/USB sans passer par le navigateur : Utilisez l’application Android (APK).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
      return;
    }
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
      await Navigator.push(context,MaterialPageRoute(builder:(_)=>BonPdfScreen(
        bytes:bytes,
        kind:doc['kind'] as String? ?? 'TCZ',
        visitId:doc['visit_id'] as String? ?? '',
        autoPrint:false,
      )));
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
          title:Text(kIsWeb
            ? 'Impression : Gérée par la boîte système du navigateur'
            : (preferredPrinter.isEmpty?'Imprimante préférée : aucune':
              'Imprimante préférée : $preferredPrinter')),
          subtitle:Text(kIsWeb
            ? 'Sur le web, choisissez votre imprimante dans la boîte d’impression Chrome/Edge.'
            : 'Impression directe après pointage si disponible; sinon dialogue système.'),
          trailing:Icon(kIsWeb ? Icons.info_outline : Icons.edit),
          onTap:choosePrinter),
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
