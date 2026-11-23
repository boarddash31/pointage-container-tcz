import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/reports_api.dart';

typedef Json = Map<String, dynamic>;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.api});
  final ReportsApi? api;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportsApi api = widget.api ?? ReportsApi(Supabase.instance.client);
  Json? state;
  List<Json> clients = [];
  List<Json> operators = [];
  String? error;
  bool busy = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) { if (!busy) load(silent: true); });
  }
  @override
  void dispose() { timer?.cancel(); api.close(); super.dispose(); }

  Future<void> load({bool silent = false}) async {
    try {
      final values = await Future.wait([api.json('GET', 'state'), api.json('GET', 'clients'), api.json('GET', 'operators')]);
      if (!mounted) return;
      setState(() { state = Json.from(values[0] as Map); clients = List<Json>.from(values[1] as List); operators = List<Json>.from(values[2] as List); error = null; });
    } catch (e) { if (mounted && !silent) setState(() => error = '$e'.replaceFirst('Bad state: ', '')); }
  }
  Future<void> action(Future<void> Function() work, {String? success}) async {
    setState(() => busy = true);
    try {
      await work();
      if (!mounted) return;
      if (success != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Bad state: ', ''))));
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> share(Uint8List bytes) async { await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
    fileNameOverrides: ['Zenata-rapport.xlsx'],
  )); }
  bool get ready {
    final r = state?['ready'] as Map?;
    return r?['source'] == true && r?['smtp'] == true && r?['smtp_driver'] == true;
  }
  Future<void> editJob([Json? job]) async {
    final result = await showDialog<Json>(context: context, builder: (_) => _JobDialog(job: job, clients: clients, operators: operators, ready: ready, preview: (value) => shareBytes(value)));
    if (result == null || !mounted) return;
    await action(() async { await api.json(job == null ? 'POST' : 'PUT', job == null ? 'jobs' : 'jobs/${job['id']}', {'version': job?['version'] ?? 0, 'job': result}); }, success: 'Programmation enregistrée.');
  }
  Future<void> shareBytes(Json job) async => share(await api.download('preview', job));
  Future<void> smtp() async {
    final result = await showDialog<Json>(context: context, builder: (_) => _SmtpDialog(value: Json.from(state!['smtp'] as Map)));
    if (result != null && mounted) await action(() async { await api.json('PUT', 'smtp', result); }, success: 'Paramètres SMTP enregistrés.');
  }
  String date(dynamic value) => value == null ? '—' : value.toString().replaceFirst('T', ' ').replaceFirst('.000Z', ' UTC').replaceFirst('Z', ' UTC');
  static const statuses = {'queued': 'En attente', 'extracting': 'Extraction', 'sending': 'Envoi en cours', 'accepted': 'Accepté par le relais', 'partial': 'Acceptation partielle', 'failed': 'Échec confirmé', 'delivery_unknown': 'Envoi incertain : vérifier le relais', 'canceled': 'Annulé'};
  @override
  Widget build(BuildContext context) {
    if (state == null) return Center(child: error == null ? const CircularProgressIndicator() : Column(mainAxisSize: MainAxisSize.min, children: [Text(error!, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton(onPressed: load, child: const Text('Réessayer'))]));
    final jobs = List<Json>.from(state!['jobs'] as List), runs = List<Json>.from(state!['runs'] as List), r = state!['ready'] as Map;
    return ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Rapports programmés', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('États des entrées, sorties et stock par client métier, envoyés par e-mail avec un classeur Excel. Les horaires sont ceux du Maroc. Le serveur doit rester en marche.'),
      const SizedBox(height: 20),
      Wrap(spacing: 16, runSpacing: 12, children: [
        FilledButton.icon(onPressed: busy ? null : () => editJob(), icon: const Icon(Icons.add), label: const Text('Nouveau rapport')),
        OutlinedButton.icon(onPressed: busy ? null : smtp, icon: const Icon(Icons.settings), label: const Text('Configuration e-mail')),
        OutlinedButton(onPressed: busy || r['smtp'] != true || r['smtp_driver'] != true ? null : () => action(() async { await api.json('POST', 'smtp/verify'); }, success: 'Connexion SMTP vérifiée. Aucun e-mail envoyé.'), child: const Text('Vérifier le SMTP')),
        IconButton(onPressed: busy ? null : load, tooltip: 'Actualiser', icon: const Icon(Icons.refresh)),
      ]),
      if (busy) const LinearProgressIndicator(),
      if (!ready) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text([
        if (r['smtp'] != true) 'Renseigner le relais SMTP dans Configuration e-mail.',
        if (r['source'] != true) 'IT : configurer la clé de lecture serveur pour les exécutions en arrière-plan.',
        if (r['smtp_driver'] != true) 'IT : installer le connecteur Nodemailer approuvé sur le serveur.',
        'Les brouillons et les aperçus Excel restent disponibles.',
      ].join('\n'))),
      const SizedBox(height: 20),
      if (jobs.isEmpty) const Text('Aucun rapport enregistré.'),
      ...jobs.map((job) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(job['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Text('${job['enabled'] == true ? 'Actif' : 'En pause'} · ${_JobDialog.kinds[(job['schedule'] as Map)['kind']]}'),
        Text('Prochaine exécution : ${date(job['next_due'])}'),
        Text('Destinataires : ${(job['recipients'] as List).join(', ')}'),
        Text('Armateur destinataire : ${job['line_id'] == null || job['line_id'] == '' ? 'Tous (état consolidé)' : job['line_id']}'),
        if (job['period'] == 'shift') Text('Shift : ${job['shift_start']} → ${job['shift_end']} (Maroc)'),
        Text((job['client_ids'] as List).isEmpty ? 'Tous les clients' : '${(job['client_ids'] as List).length} client(s) sélectionné(s)'),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, children: [
          OutlinedButton(onPressed: busy ? null : () => editJob(job), child: const Text('Modifier')),
          OutlinedButton(onPressed: busy ? null : () => action(() async { await shareBytes(_payload(job)); }), child: const Text('Aperçu Excel')),
          OutlinedButton(onPressed: busy || (!ready && job['enabled'] != true) ? null : () => action(() async {
            await api.json('PUT', 'jobs/${job['id']}', {'version': job['version'], 'job': {..._payload(job), 'enabled': job['enabled'] != true}});
          }), child: Text(job['enabled'] == true ? 'Mettre en pause' : 'Activer')),
          FilledButton(onPressed: busy || !ready ? null : () => action(() async { await api.json('POST', 'jobs/${job['id']}/run'); }, success: 'Envoi ajouté à la file d’attente.'), child: const Text('Envoyer maintenant')),
        ]),
      ])))),
      const SizedBox(height: 24),
      const Text('Historique des 200 dernières exécutions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('« Accepté par le relais » ne confirme pas la réception en boîte e-mail. Un envoi incertain ou partiel doit être contrôlé avant toute nouvelle émission.'),
      if (runs.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune exécution.')),
      ...runs.map((run) => Card(child: ListTile(
        title: Text('${run['name'] ?? 'Rapport'} · ${statuses[run['state']] ?? run['state']}'),
        subtitle: Text('${date(run['scheduled_at'])}\n${run['summary'] == null ? '' : '${run['summary']['entries']} entrées · ${run['summary']['exits']} sorties · ${run['summary']['stock']} en stock\n'}${run['error_code'] ?? ''}'),
        trailing: Wrap(children: [
          if (run['artifact'] == true) IconButton(tooltip: 'Télécharger Excel', onPressed: busy ? null : () => action(() async { await share(await api.download('runs/${run['id']}/download')); }), icon: const Icon(Icons.download)),
          if (run['state'] == 'failed') IconButton(tooltip: 'Réessayer', onPressed: busy || !ready ? null : () => action(() async { await api.json('POST', 'runs/${run['id']}/retry'); }), icon: const Icon(Icons.replay)),
        ]),
      ))),
    ]);
  }
}

Json _payload(Json job) => {for (final k in ['name', 'enabled', 'recipients', 'client_ids', 'schedule', 'period', 'hours', 'line_id', 'layout', 'shift_start', 'shift_end']) if (job.containsKey(k)) k: job[k]};

class _JobDialog extends StatefulWidget {
  const _JobDialog({this.job, required this.clients, required this.operators, required this.ready, required this.preview});
  final Json? job;
  final List<Json> clients;
  final List<Json> operators;
  final bool ready;
  final Future<void> Function(Json) preview;
  static const kinds = {'daily': 'Chaque jour', 'weekly': 'Chaque semaine', 'monthly': 'Chaque mois', 'interval': 'À intervalle régulier', 'once': 'Une seule fois'};
  @override
  State<_JobDialog> createState() => _JobDialogState();
}

class _JobDialogState extends State<_JobDialog> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.job?['name'] as String? ?? 'État des mouvements et du stock');
  late final recipients = TextEditingController(text: (widget.job?['recipients'] as List? ?? []).join('; '));
  late final schedule = Json.from(widget.job?['schedule'] as Map? ?? {'kind': 'daily', 'time': '08:00', 'timezone': 'Africa/Casablanca'});
  late final time = TextEditingController(text: schedule['time'] as String? ?? '08:00');
  late final interval = TextEditingController(text: '${schedule['minutes'] ?? 60}');
  late final monthDay = TextEditingController(text: '${schedule['day'] ?? 1}');
  late final once = TextEditingController(text: schedule['at_local'] as String? ?? (schedule['at'] == null ? '' : _morocco(schedule['at'] as String)));
  late final hours = TextEditingController(text: '${widget.job?['hours'] ?? 24}');
  late final shiftStart = TextEditingController(text: widget.job?['shift_start'] as String? ?? '');
  late final shiftEnd = TextEditingController(text: widget.job?['shift_end'] as String? ?? '');
  late String line = widget.job?['line_id'] as String? ?? '', layout = widget.job?['layout'] as String? ?? (widget.job == null ? 'shift_client' : 'standard');
  late String kind = schedule['kind'] as String, period = widget.job?['period'] as String? ?? 'previous_day';
  late bool enabled = widget.job?['enabled'] == true, allClients = (widget.job?['client_ids'] as List? ?? []).isEmpty;
  late final selected = Set<String>.from(widget.job?['client_ids'] as List? ?? []);
  late final days = Set<int>.from(schedule['days'] as List? ?? [1]);
  bool working = false;
  String? error;
  // Keep the saved instant unchanged unless the administrator edits its local representation.
  static String _morocco(String value) => value; // Existing once schedules display their explicit UTC instant.
  @override
  void dispose() { for (final c in [name, recipients, time, interval, monthDay, once, hours, shiftStart, shiftEnd]) { c.dispose(); } super.dispose(); }
  Json value() => {
    'name': name.text.trim(), 'enabled': enabled,
    'recipients': recipients.text.split(RegExp(r'[;,\s]+')).where((s) => s.isNotEmpty).toList(),
    'client_ids': allClients ? <String>[] : selected.toList(),
    'line_id': line, 'layout': layout,
    if (period == 'shift') ...{'shift_start': shiftStart.text.trim(), 'shift_end': shiftEnd.text.trim()},
    'period': period, 'hours': int.tryParse(hours.text) ?? 0,
    'schedule': {'kind': kind, 'timezone': 'Africa/Casablanca',
      if (kind == 'once') ...{(RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(once.text.trim()) ? 'at' : 'at_local'): once.text.trim()},
      if (kind == 'interval') 'minutes': int.tryParse(interval.text) ?? 0,
      if (['daily', 'weekly', 'monthly'].contains(kind)) 'time': time.text.trim(),
      if (kind == 'weekly') 'days': days.toList(),
      if (kind == 'monthly') 'day': int.tryParse(monthDay.text) ?? -1,
    },
  };
  bool valid() {
    if (!form.currentState!.validate()) return false;
    if ((!allClients && selected.isEmpty) || (kind == 'weekly' && days.isEmpty)) { setState(() => error = 'Sélectionner au moins un client ou un jour.'); return false; }
    return true;
  }
  Widget field(TextEditingController c, String label, {String? hint, bool required = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 20), child: TextFormField(controller: c, decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()), validator: (v) => required && (v ?? '').trim().isEmpty ? 'Champ requis' : null));
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.job == null ? 'Nouveau rapport' : 'Modifier le rapport'),
    content: SizedBox(width: 640, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      field(name, 'Nom du rapport'), field(recipients, 'Destinataires e-mail', hint: 'adresse@exemple.ma ; autre@exemple.ma', required: false),
      DropdownButtonFormField<String>(isExpanded: true, initialValue: layout, decoration: const InputDecoration(labelText: 'Présentation Excel', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'shift_client', child: Text('Rapport client : stock par type + RECAP')), DropdownMenuItem(value: 'standard', child: Text('État consolidé entrées / sorties / stock'))], onChanged: (v) => setState(() => layout = v!)),
      const SizedBox(height: 20),
      DropdownButtonFormField<String>(isExpanded: true, initialValue: line, decoration: const InputDecoration(labelText: 'Armateur destinataire (MSC, CMA CGM…)', border: OutlineInputBorder()), items: [const DropdownMenuItem(value: '', child: Text('Choisir un armateur / tous pour le consolidé')), ...{for (final o in widget.operators) o['id'] as String: o['name'] as String, if (line.isNotEmpty && !widget.operators.any((o) => o['id'] == line)) line: line}.entries.map((e) => DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}')))], validator: (v) => layout == 'shift_client' && (v ?? '').isEmpty ? 'Choisir l’armateur de ce rapport dédié' : null, onChanged: (v) => setState(() => line = v!)),
      const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Un rapport dédié contient uniquement les conteneurs de cet armateur. Créer un rapport séparé pour chaque liste de diffusion. Le filtre client métier ci-dessous reste indépendant.')),
      DropdownButtonFormField<String>(isExpanded: true, initialValue: kind, decoration: const InputDecoration(labelText: 'Fréquence', border: OutlineInputBorder()), items: _JobDialog.kinds.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v) => setState(() => kind = v!)),
      const SizedBox(height: 20),
      if (kind == 'once') field(once, 'Date et heure Maroc', hint: '2026-11-25T08:00 (ou instant UTC avec Z)'),
      if (kind == 'interval') field(interval, 'Intervalle en minutes (5 à 10 080)'),
      if (['daily', 'weekly', 'monthly'].contains(kind)) field(time, 'Heure Maroc (HH:mm)'),
      if (kind == 'monthly') field(monthDay, 'Jour du mois (1 à 31 ; 0 = dernier jour)'),
      if (kind == 'weekly') Padding(padding: const EdgeInsets.only(bottom: 20), child: Wrap(spacing: 8, runSpacing: 8, children: [for (final d in [1, 2, 3, 4, 5, 6, 0]) FilterChip(label: Text(['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'][d]), selected: days.contains(d), onSelected: (v) => setState(() { v ? days.add(d) : days.remove(d); }))])),
      DropdownButtonFormField<String>(isExpanded: true, initialValue: period, decoration: const InputDecoration(labelText: 'Période des mouvements', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'shift', child: Text('Dernier shift terminé')), DropdownMenuItem(value: 'previous_day', child: Text('Journée précédente')), DropdownMenuItem(value: 'previous_month', child: Text('Mois précédent')), DropdownMenuItem(value: 'rolling', child: Text('Dernières heures'))], onChanged: (v) => setState(() => period = v!)),
      const SizedBox(height: 20),
      if (period == 'shift') ...[field(shiftStart, 'Début du shift Maroc (HH:mm)'), field(shiftEnd, 'Fin du shift Maroc (HH:mm)'), const Padding(padding: EdgeInsets.only(bottom: 20), child: Text('Programmer l’envoi à la fin du shift ou quelques minutes après. Un shift de nuit peut finir le lendemain. Créer une programmation par shift et par armateur.'))],
      if (period == 'rolling') field(hours, 'Nombre d’heures (1 à 744)'),
      const Text('Le stock correspond à la fin de la période sélectionnée.'),
      CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Tous les clients métier, y compris sans attribution'), value: allClients, onChanged: (v) => setState(() => allClients = v!)),
      if (!allClients) SizedBox(height: 180, child: ListView(children: widget.clients.map((c) => CheckboxListTile(title: Text(c['name'] as String), value: selected.contains(c['id']), onChanged: (v) => setState(() { v! ? selected.add(c['id'] as String) : selected.remove(c['id']); }))).toList())),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activer les envois programmés'), subtitle: widget.ready ? null : const Text('Enregistrer en pause tant que la configuration serveur est incomplète.'), value: enabled, onChanged: widget.ready || enabled ? (v) => setState(() => enabled = v) : null),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (working) const LinearProgressIndicator(),
    ])))),
    actions: [
      TextButton(onPressed: working ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      OutlinedButton(onPressed: working ? null : () async {
        if (!valid()) return;
        setState(() { working = true; error = null; });
        try { await widget.preview(value()); } catch (e) { if (mounted) setState(() => error = '$e'.replaceFirst('Bad state: ', '')); }
        finally { if (mounted) setState(() => working = false); }
      }, child: const Text('Aperçu Excel sans envoi')),
      FilledButton(onPressed: working ? null : () { if (valid()) Navigator.pop(context, value()); }, child: const Text('Enregistrer')),
    ],
  );
}

class _SmtpDialog extends StatefulWidget {
  const _SmtpDialog({required this.value});
  final Json value;
  @override
  State<_SmtpDialog> createState() => _SmtpDialogState();
}
class _SmtpDialogState extends State<_SmtpDialog> {
  final form = GlobalKey<FormState>();
  late final host = TextEditingController(text: widget.value['host'] as String);
  late final port = TextEditingController(text: '${widget.value['port']}');
  late final from = TextEditingController(text: widget.value['from'] as String);
  late final username = TextEditingController(text: widget.value['username'] as String);
  final password = TextEditingController();
  late String security = widget.value['security'] as String;
  bool clear = false;
  @override
  void dispose() { for (final c in [host, port, from, username, password]) { c.dispose(); } super.dispose(); }
  Widget field(TextEditingController c, String label, {bool secret = false, bool required = true}) => Padding(padding: const EdgeInsets.only(bottom: 20), child: TextFormField(controller: c, obscureText: secret, autocorrect: false, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()), validator: (v) => required && (v ?? '').trim().isEmpty ? 'Champ requis' : null));
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('Configuration e-mail'), content: SizedBox(width: 560, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
    field(host, 'Serveur / adresse du relais SMTP'), field(port, 'Port'), field(from, 'Adresse e-mail expéditrice'),
    DropdownButtonFormField<String>(isExpanded: true, initialValue: security, decoration: const InputDecoration(labelText: 'Sécurité SMTP', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'starttls', child: Text('STARTTLS (souvent port 587)')), DropdownMenuItem(value: 'tls', child: Text('TLS direct (souvent port 465)')), DropdownMenuItem(value: 'relay', child: Text('Relais interne sans authentification'))], onChanged: (v) => setState(() => security = v!)),
    const SizedBox(height: 20),
    if (security != 'relay') ...[
      field(username, 'Identifiant SMTP (si demandé)', required: false),
      field(password, widget.value['has_password'] == true ? 'Nouveau mot de passe (vide = conserver)' : 'Mot de passe SMTP', secret: true, required: false),
      CheckboxListTile(value: clear, onChanged: (v) => setState(() => clear = v!), title: const Text('Supprimer le mot de passe enregistré')),
    ],
    const Text('Le mot de passe enregistré n’est jamais renvoyé à l’écran. Enregistrer puis utiliser « Vérifier le SMTP » pour tester la connexion sans envoyer d’e-mail.'),
  ])))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')), FilledButton(onPressed: () {
    if (!form.currentState!.validate()) return;
    Navigator.pop(context, {'version': widget.value['version'], 'host': host.text.trim(), 'port': int.tryParse(port.text) ?? 0, 'from': from.text.trim(), 'security': security, 'username': security == 'relay' ? '' : username.text.trim(), 'password': security == 'relay' ? '' : password.text, 'clear_password': clear});
  }, child: const Text('Enregistrer'))]);
}
