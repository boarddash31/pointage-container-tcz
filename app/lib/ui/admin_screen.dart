import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/pointage_repository.dart';
import '../domain/container_number.dart';
import 'pointage_screens.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.repository});
  final PointageRepository repository;
  @override State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  DateTime day = DateTime.now();
  String? selectedClient, selectedArmateur;
  late Future<List<Map<String, dynamic>>> activity, profiles, clients, armateurs, audit, forced;
  late Future<List<TruckVisit>> visits;

  String dateString(DateTime x) =>
      '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

  String formattedFrenchDate(DateTime d) {
    const months = [
      'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
      'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    final db = widget.repository.client;
    setState(() {
      activity = db.rpc('hourly_activity', params: {'p_day': dateString(day)})
          .then((x) => List<Map<String, dynamic>>.from(x as List));
      profiles = db.from('profiles').select('id,display_name,first_name,last_name,phone,avatar_url,initial_password,active,created_at,user_roles(role)').order('created_at', ascending: false)
          .then((x) => List<Map<String, dynamic>>.from(x));
      clients = db.from('clients').select('id,code,name').order('name')
          .then((x) => List<Map<String, dynamic>>.from(x));
      armateurs = db.from('armateurs').select('id,name').order('name')
          .then((x) => List<Map<String, dynamic>>.from(x));
      audit = db.from('audit_logs').select('entity,entity_id,action,actor_id,occurred_at,reason')
          .order('occurred_at', ascending: false).limit(100)
          .then((x) => List<Map<String, dynamic>>.from(x));
      forced = widget.repository.forcedActions();
      visits = widget.repository.visits(insideOnly: false);
    });
  }

  Future<void> pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      day = d;
      refresh();
    }
  }

  Future<void> setRole(String user, String role, bool enabled) async {
    try {
      await widget.repository.client.rpc('set_user_role', params: {
        'p_user': user,
        'p_role': role,
        'p_enabled': enabled,
      });
      refresh();
    } catch (e) {
      if (mounted) message(context, 'Rôle refusé : $e');
    }
  }

  void sendWhatsAppInvite({
    required String name,
    required String phone,
    required String role,
    required String password,
  }) {
    final cleanPhone = PointageRepository.normalizePhone(phone).replaceAll(RegExp(r'^0'), '');
    final msg = Uri.encodeComponent(
      '🇲🇦 *Terminal Conteneur Zenata (TCZ)*\n'
      'Bonjour *$name*,\n\n'
      'Voici vos identifiants d\'accès au système de Pointage Container TCZ :\n'
      '📱 *Téléphone :* $phone\n'
      '🔑 *Mot de passe :* $password\n'
      '🏢 *Poste affecté :* ${role.toUpperCase()}\n'
      '🌐 *Lien d\'accès :* http://localhost:8085 (ou https://pointage-tcz-test.netlify.app)\n\n'
      'Connectez-vous directement avec votre numéro de téléphone et votre mot de passe.'
    );
    launchUrl(Uri.parse('https://wa.me/212$cleanPhone?text=$msg'), mode: LaunchMode.externalApplication);
  }

  Future<void> inviteUser() async {
    final firstName = TextEditingController();
    final lastName = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController(text: 'tcz123');
    final avatar = TextEditingController();
    String role = 'entree';

    try {
      final res = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.person_add_rounded, color: Color(0xff075a8d)),
                SizedBox(width: 8),
                Text('Ajouter un collaborateur'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Renseignez les détails du collaborateur. Le numéro de téléphone servira d\'identifiant.',
                    style: TextStyle(fontSize: 12, color: Color(0xff64748b))),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: firstName,
                          decoration: const InputDecoration(
                            labelText: 'Prénom *',
                            prefixIcon: Icon(Icons.badge_outlined, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: lastName,
                          decoration: const InputDecoration(
                            labelText: 'Nom *',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone (WhatsApp) *',
                      hintText: 'Ex: 0661998877',
                      prefixIcon: Icon(Icons.phone_android_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(
                      labelText: 'Poste / Habilitation *',
                      prefixIcon: Icon(Icons.shield_outlined, size: 20),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'entree', child: Text('AGENT ENTRÉE (Gate-In)')),
                      DropdownMenuItem(value: 'sortie', child: Text('AGENT SORTIE (Gate-Out)')),
                      DropdownMenuItem(value: 'admin', child: Text('SUPERVISEUR TCZ (Admin)')),
                      DropdownMenuItem(value: 'engin', child: Text('AGENT ENGIN (Manutention)')),
                    ],
                    onChanged: (val) {
                      if (val != null) update(() => role = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: password,
                          decoration: const InputDecoration(
                            labelText: 'Mot de passe initial *',
                            prefixIcon: Icon(Icons.key_rounded, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Générer mot de passe facile',
                        icon: const Icon(Icons.refresh_rounded, color: Color(0xff075a8d)),
                        onPressed: () {
                          final rnd = 100 + (DateTime.now().millisecondsSinceEpoch % 900);
                          update(() => password.text = 'tcz$rnd');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: avatar,
                    decoration: const InputDecoration(
                      labelText: 'Photo / Avatar URL (Optionnel)',
                      prefixIcon: Icon(Icons.image_outlined, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Annuler')),
              FilledButton.icon(
                icon: const Icon(Icons.save_rounded, size: 16),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xff075a8d)),
                onPressed: () async {
                  if (firstName.text.trim().isEmpty || lastName.text.trim().isEmpty) {
                    message(dialog, 'Nom et Prénom obligatoires.');
                    return;
                  }
                  if (phone.text.trim().length < 8) {
                    message(dialog, 'Numéro de téléphone invalide.');
                    return;
                  }
                  if (password.text.trim().length < 4) {
                    message(dialog, 'Mot de passe trop court.');
                    return;
                  }
                  try {
                    final agentRes = await widget.repository.createAgent(
                      phone: phone.text.trim(),
                      firstName: firstName.text.trim(),
                      lastName: lastName.text.trim(),
                      role: role,
                      password: password.text.trim(),
                      avatarUrl: avatar.text.trim().isNotEmpty ? avatar.text.trim() : null,
                      adminCode: '01010909',
                    );
                    if (dialog.mounted) Navigator.pop(dialog, agentRes);
                  } catch (e) {
                    if (dialog.mounted) message(dialog, 'Erreur création : $e');
                  }
                },
                label: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      );

      if (res != null && mounted) {
        refresh();
        final agentName = res['full_name'] as String? ?? '${firstName.text} ${lastName.text}';
        final agentPhone = res['phone'] as String? ?? phone.text;
        final agentRole = res['role'] as String? ?? role;
        final agentPwd = res['password'] as String? ?? password.text;

        await showDialog(
          context: context,
          builder: (waDialog) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xff16a34a)),
                SizedBox(width: 8),
                Text('Collaborateur enregistré !'),
              ],
            ),
            content: Text(
              'Le collaborateur $agentName ($agentPhone) a été créé avec succès.\n\n'
              'Mot de passe : $agentPwd\n'
              'Rôle : ${agentRole.toUpperCase()}\n\n'
              'Souhaitez-vous lui envoyer ses accès sur WhatsApp dès maintenant ?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(waDialog), child: const Text('Plus tard')),
              FilledButton.icon(
                icon: const Icon(Icons.message_rounded, size: 16),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xff16a34a)),
                onPressed: () {
                  Navigator.pop(waDialog);
                  sendWhatsAppInvite(
                    name: agentName,
                    phone: agentPhone,
                    role: agentRole,
                    password: agentPwd,
                  );
                },
                label: const Text('Envoyer sur WhatsApp'),
              ),
            ],
          ),
        );
      }
    } finally {
      firstName.dispose();
      lastName.dispose();
      phone.dispose();
      password.dispose();
      avatar.dispose();
    }
  }

  Future<void> addClient() async {
    final code = TextEditingController(), name = TextEditingController();
    await showDialog(
      context: context,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.business_rounded, color: Color(0xff075a8d)),
            SizedBox(width: 8),
            Text('Nouveau client'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: code, decoration: const InputDecoration(labelText: 'Code client (ex: MAERSK)')),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom complet du client')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xff075a8d)),
            onPressed: () async {
              try {
                await widget.repository.client.rpc('create_client', params: {
                  'p_code': code.text,
                  'p_name': name.text,
                });
                if (d.mounted) Navigator.pop(d);
                refresh();
              } catch (e) {
                if (d.mounted) message(d, 'Client refusé : $e');
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    code.dispose();
    name.dispose();
  }

  Future<void> assignClient() async {
    if (selectedClient == null || selectedArmateur == null) {
      message(context, 'Choisissez à la fois un client et un armateur.');
      return;
    }
    try {
      await widget.repository.client.rpc('assign_client_armateur', params: {
        'p_client': selectedClient,
        'p_armateur': selectedArmateur,
        'p_from': dateString(day),
      });
      if (mounted) message(context, 'Affectation enregistrée.');
    } catch (e) {
      if (mounted) message(context, 'Affectation refusée : $e');
    }
  }

  Future<void> reconcileForced(Map<String, dynamic> action) async {
    final controller = TextEditingController();
    final reference = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rapprochement exception externe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xfffef3c7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xfffde68a)),
              ),
              child: Text(
                'Conteneur : ${action['container_number']}\nMotif : ${action['reason']}',
                style: const TextStyle(fontSize: 12, color: Color(0xff92400e), fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Référence dans le système externe (ex: TOS-12345) *',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xff075a8d)),
            onPressed: () => Navigator.pop(dialog, controller.text.trim()),
            child: const Text('Valider le rapprochement'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reference == null || reference.isEmpty) return;
    try {
      await widget.repository.resolveForcedAction(action['id'] as String, reference);
      if (mounted) {
        message(context, 'Exception rapprochée avec référence $reference.');
        refresh();
      }
    } catch (e) {
      if (mounted) message(context, 'Rapprochement refusé : $e');
    }
  }

  Future<void> registerObservedContainer() async {
    final number = TextEditingController(), iso = TextEditingController();
    try {
      final lines = await armateurs;
      if (!mounted) return;
      String? line = selectedArmateur;
      await showDialog(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Conteneur observé hors référentiel'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: number,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 11,
                    decoration: const InputDecoration(labelText: 'Numéro ISO 6346 (11 car.) *'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: iso,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 4,
                    decoration: const InputDecoration(labelText: 'Code ISO (ex: 22G1, 45G1) *'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: line,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Armateur *'),
                    items: [
                      for (final x in lines)
                        DropdownMenuItem<String>(
                          value: x['id'] as String,
                          child: Text(x['name'].toString(), overflow: TextOverflow.ellipsis),
                        )
                    ],
                    onChanged: (v) => update(() => line = v),
                  ),
                  const SizedBox(height: 10),
                  const Text('Note : L\'ajout au catalogue n\'injecte pas de stock yard fictif.',
                    style: TextStyle(fontSize: 11, color: Color(0xff64748b))),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Annuler')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xff075a8d)),
                onPressed: () async {
                  final canonical = ContainerNumber.normalize(number.text);
                  if (!ContainerNumber.isValid(canonical) ||
                      line == null ||
                      !RegExp(r'^[0-9A-Z]{4}$').hasMatch(iso.text.trim().toUpperCase())) {
                    message(dialog, 'Numéro, code ISO ou armateur invalide.');
                    return;
                  }
                  try {
                    await widget.repository.client.rpc('register_observed_container', params: {
                      'p_number': canonical,
                      'p_iso': iso.text.trim().toUpperCase(),
                      'p_armateur': line,
                    });
                    if (dialog.mounted) Navigator.pop(dialog);
                    if (mounted) {
                      message(context, 'Conteneur ajouté au référentiel avec succès.');
                      refresh();
                    }
                  } catch (e) {
                    if (dialog.mounted) message(dialog, 'Ajout refusé : $e');
                  }
                },
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) message(context, 'Catalogue indisponible : $e');
    } finally {
      number.dispose();
      iso.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff8fafc),
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: Color(0xffe2e8f0)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0x14075a8d),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.tune_rounded, color: Color(0xff075a8d), size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Administration · TCZ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xff0f172a))),
              Text('Supervision des flux & contrôle des accès',
                style: TextStyle(fontSize: 11, color: Color(0xff64748b))),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Color(0xff475569)),
          tooltip: 'Actualiser les données',
          onPressed: refresh,
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      children: [
        // Top Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xffe2e8f0)),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xfff1f5f9),
                  side: const BorderSide(color: Color(0xffcbd5e1)),
                  foregroundColor: const Color(0xff0f172a),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
                onPressed: pickDate,
                icon: const Icon(Icons.calendar_month_rounded, size: 18, color: Color(0xff075a8d)),
                label: Text(formattedFrenchDate(day), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              if (dateString(day) != dateString(DateTime.now()))
                TextButton.icon(
                  onPressed: () {
                    day = DateTime.now();
                    refresh();
                  },
                  icon: const Icon(Icons.today_rounded, size: 16),
                  label: const Text('Aujourd\'hui'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xfff0fdfa),
                  side: const BorderSide(color: Color(0xff99f6e4)),
                  foregroundColor: const Color(0xff0f766e),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FreepoolScreen(repository: widget.repository)),
                ),
                icon: const Icon(Icons.table_chart_rounded, size: 18),
                label: const Text('Freepool (Stock)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              if (kIsWeb)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff063e66),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  ),
                  onPressed: () => launchUrl(
                    Uri.base.resolve('dashboard.html'),
                    mode: LaunchMode.platformDefault,
                  ),
                  icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
                  label: const Text('Dashboard Web Externe', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // KPI Metric Cards
        FutureBuilder<List<TruckVisit>>(
          future: visits,
          builder: (c, s) {
            if (!s.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final filtered = s.data!.where((v) =>
                (selectedArmateur == null || v.armateur == selectedArmateur) &&
                (v.enteredAt.toLocal().year == day.year &&
                 v.enteredAt.toLocal().month == day.month &&
                 v.enteredAt.toLocal().day == day.day)).toList();
            final inside = s.data!.where((v) => v.isInside).length;
            final needEngin = s.data!.where((v) => v.isInside && v.needsEngin).length;
            final dwell = filtered.where((v) => v.exitedAt != null).map((v) =>
                DateTime.parse(v.exitedAt!).difference(v.enteredAt).inMinutes).toList();

            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _metricCard(
                  title: 'Entrées du jour',
                  value: '${filtered.length}',
                  subtitle: 'Camions enregistrés',
                  icon: Icons.login_rounded,
                  color: const Color(0xff0284c7),
                  bgColor: const Color(0xffe0f2fe),
                ),
                _metricCard(
                  title: 'Camions présents',
                  value: '$inside',
                  subtitle: 'Dans l\'enceinte terminal',
                  icon: Icons.local_shipping_rounded,
                  color: const Color(0xff16a34a),
                  bgColor: const Color(0xffdcfce7),
                  isLive: true,
                ),
                _metricCard(
                  title: 'Attente Engin',
                  value: '$needEngin',
                  subtitle: 'À charger / décharger',
                  icon: Icons.precision_manufacturing_rounded,
                  color: const Color(0xffea580c),
                  bgColor: const Color(0xffffedd5),
                ),
                _metricCard(
                  title: 'Séjour moyen',
                  value: dwell.isEmpty ? '—' : '${dwell.reduce((a, b) => a + b) ~/ dwell.length} min',
                  subtitle: 'Délai d\'escale moyen',
                  icon: Icons.timer_outlined,
                  color: const Color(0xff8b5cf6),
                  bgColor: const Color(0xfff3e8ff),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 26),

        // Hourly Activity Table / Heatmap Card
        FutureBuilder<List<Map<String, dynamic>>>(
          future: activity,
          builder: (c, s) {
            if (s.hasError) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xfffef2f2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xfffecaca)),
                ),
                child: Text('Erreur chargement activité : ${s.error}',
                    style: const TextStyle(color: Color(0xffb91c1c))),
              );
            }
            if (!s.hasData) return const LinearProgressIndicator();

            final byStage = {
              for (final stage in ['ENTREE', 'ENGIN', 'SORTIE'])
                stage: {
                  for (final row in s.data!.where((x) => x['stage'] == stage))
                    row['hour'] as int: row['total'] as int
                }
            };

            int sumStage(String stage) {
              final m = byStage[stage] ?? {};
              return m.values.fold(0, (a, b) => a + b);
            }

            final stageConfigs = {
              'ENTREE': (
                name: 'ENTRÉE',
                icon: Icons.login_rounded,
                color: const Color(0xff0284c7),
                bg: const Color(0xffe0f2fe),
              ),
              'ENGIN': (
                name: 'ENGIN',
                icon: Icons.handyman_rounded,
                color: const Color(0xffea580c),
                bg: const Color(0xffffedd5),
              ),
              'SORTIE': (
                name: 'SORTIE',
                icon: Icons.logout_rounded,
                color: const Color(0xff16a34a),
                bg: const Color(0xffdcfce7),
              ),
            };

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xffe2e8f0)),
                boxShadow: const [
                  BoxShadow(color: Color(0x060f172a), blurRadius: 10, offset: Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0x14075a8d),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.bar_chart_rounded, color: Color(0xff075a8d), size: 18),
                            ),
                            const SizedBox(width: 10),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Activité horaire par étape',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xff0f172a))),
                                Text('Flux de conteneurs & camions · Heures 00h à 23h (Maroc)',
                                  style: TextStyle(fontSize: 11, color: Color(0xff64748b))),
                              ],
                            ),
                          ],
                        ),
                        // Legend
                        Wrap(
                          spacing: 12,
                          children: [
                            _legendDot('Entrée', const Color(0xff0284c7)),
                            _legendDot('Engin', const Color(0xffea580c)),
                            _legendDot('Sortie', const Color(0xff16a34a)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xfff1f5f9)),

                  // Scrollable Heatmap Table
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Table(
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        defaultColumnWidth: const FixedColumnWidth(42),
                        columnWidths: const {
                          0: FixedColumnWidth(130), // Stage column
                          25: FixedColumnWidth(65), // Total column
                        },
                        children: [
                          // Header Row (Hours)
                          TableRow(
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xffe2e8f0), width: 1.5)),
                            ),
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                child: Text('Étape', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xff475569))),
                              ),
                              for (var h = 0; h < 24; h++)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    h.toString().padLeft(2, '0'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                      color: (h >= 8 && h <= 18) ? const Color(0xff0f172a) : const Color(0xff94a3b8),
                                    ),
                                  ),
                                ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Total', textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xff075a8d))),
                              ),
                            ],
                          ),

                          // Data Rows
                          for (final stage in ['ENTREE', 'ENGIN', 'SORTIE'])
                            TableRow(
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: Color(0xfff1f5f9))),
                              ),
                              children: [
                                // Stage Label Cell
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: stageConfigs[stage]!.bg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(stageConfigs[stage]!.icon, size: 14, color: stageConfigs[stage]!.color),
                                        const SizedBox(width: 5),
                                        Text(
                                          stageConfigs[stage]!.name,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: stageConfigs[stage]!.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // 24 Hours Cells (Heatmap styled)
                                for (var h = 0; h < 24; h++)
                                  Builder(builder: (_) {
                                    final count = byStage[stage]?[h] ?? 0;
                                    if (count == 0) {
                                      return const Center(
                                        child: Text('·', style: TextStyle(color: Color(0xffcbd5e1), fontSize: 16)),
                                      );
                                    }
                                    return Center(
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: stageConfigs[stage]!.bg,
                                          border: Border.all(color: stageConfigs[stage]!.color.withValues(alpha: 0.4)),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '$count',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: stageConfigs[stage]!.color,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),

                                // Total Cell
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xfff1f5f9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${sumStage(stage)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xff0f172a),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 26),

        // Users & Roles Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.badge_outlined, color: Color(0xff075a8d), size: 20),
                SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Utilisateurs et rôles',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xff0f172a))),
                    Text('Gestion des habilitations & accès par agent',
                      style: TextStyle(fontSize: 11, color: Color(0xff64748b))),
                  ],
                ),
              ],
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff075a8d),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: inviteUser,
              icon: const Icon(Icons.person_add_rounded, size: 16),
              label: const Text('Inviter un agent', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        FutureBuilder<List<Map<String, dynamic>>>(
          future: profiles,
          builder: (c, s) {
            if (s.hasError) return Text('Erreur : ${s.error}');
            if (!s.hasData) return const LinearProgressIndicator();

            return Column(
              children: [
                for (final p in s.data!)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xffe2e8f0)),
                      boxShadow: const [
                        BoxShadow(color: Color(0x040f172a), blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0x1f075a8d),
                          foregroundColor: const Color(0xff075a8d),
                          radius: 19,
                          child: Text(
                            ((p['display_name'] as String?)?.isNotEmpty ?? false)
                                ? p['display_name'][0].toUpperCase()
                                : 'U',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              ((p['display_name'] as String?)?.isEmpty ?? true) ? p['id'] : p['display_name'],
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xff0f172a)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: (p['active'] == true) ? const Color(0xffdcfce7) : const Color(0xfff1f5f9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                (p['active'] == true) ? '● Actif' : '● Inactif',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: (p['active'] == true) ? const Color(0xff166534) : const Color(0xff64748b),
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (p['phone'] != null && (p['phone'] as String).isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xfff0fdf4),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xffbbf7d0)),
                                  ),
                                  child: Text(
                                    '📱 ${p['phone']}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xff166534)),
                                  ),
                                ),
                              if (p['initial_password'] != null && (p['initial_password'] as String).isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xfff8fafc),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xffe2e8f0)),
                                  ),
                                  child: Text(
                                    '🔑 ${p['initial_password']}',
                                    style: const TextStyle(fontSize: 10, color: Color(0xff475569)),
                                  ),
                                ),
                              for (final r in (p['user_roles'] as List))
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xfff1f5f9),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xffcbd5e1)),
                                  ),
                                  child: Text(
                                    (r['role'] as String).toUpperCase(),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xff334155)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (p['phone'] != null && (p['phone'] as String).isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.message_rounded, color: Color(0xff16a34a), size: 20),
                                tooltip: 'Envoyer identifiants sur WhatsApp',
                                onPressed: () {
                                  final roles = (p['user_roles'] as List).map((x) => x['role'].toString()).join(', ');
                                  sendWhatsAppInvite(
                                    name: p['display_name'] ?? 'Agent',
                                    phone: p['phone'] ?? '',
                                    role: roles.isNotEmpty ? roles : 'entree',
                                    password: p['initial_password'] ?? 'tcz123',
                                  );
                                },
                              ),
                            const Icon(Icons.expand_more_rounded, color: Color(0xff94a3b8)),
                          ],
                        ),
                        children: [
                          const Divider(height: 1, color: Color(0xfff1f5f9)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Column(
                              children: [
                                for (final role in [
                                  ('entree', 'Poste Entrée (Contrôle & saisie Gate-In)', Icons.login_rounded, const Color(0xff0284c7)),
                                  ('engin', 'Engin (Levage & manutention Yard)', Icons.handyman_rounded, const Color(0xffea580c)),
                                  ('sortie', 'Poste Sortie (Contrôle Gate-Out & impression Bon)', Icons.logout_rounded, const Color(0xff16a34a)),
                                  ('viewer', 'Consultation (Lecture seule & rapports)', Icons.visibility_outlined, const Color(0xff64748b)),
                                  ('admin', 'Administration (Accès complet & rôles)', Icons.admin_panel_settings_outlined, const Color(0xff8b5cf6)),
                                ])
                                  SwitchListTile(
                                    dense: true,
                                    secondary: Icon(role.$3, size: 20, color: role.$4),
                                    title: Text(role.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    activeThumbColor: role.$4,
                                    activeTrackColor: role.$4.withValues(alpha: 0.35),
                                    value: (p['user_roles'] as List).any((x) => x['role'] == role.$1),
                                    onChanged: (v) => setRole(p['id'] as String, role.$1, v),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),

        const SizedBox(height: 26),

        // Clients et Armateurs Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xffe2e8f0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.apartment_rounded, color: Color(0xff075a8d), size: 20),
                      SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Clients et Armateurs',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xff0f172a))),
                          Text('Affectation des lignes maritimes',
                            style: TextStyle(fontSize: 11, color: Color(0xff64748b))),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: addClient,
                    icon: const Icon(Icons.add_circle_outline, color: Color(0xff075a8d)),
                    tooltip: 'Créer un nouveau client',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: clients,
                      builder: (c, s) => s.hasData
                          ? DropdownButtonFormField<String>(
                              initialValue: selectedClient,
                              decoration: const InputDecoration(labelText: 'Client'),
                              items: [
                                for (final x in s.data!)
                                  DropdownMenuItem(value: x['id'], child: Text(x['name']))
                              ],
                              onChanged: (v) => setState(() => selectedClient = v),
                            )
                          : const LinearProgressIndicator(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: armateurs,
                      builder: (c, s) => s.hasData
                          ? DropdownButtonFormField<String>(
                              initialValue: selectedArmateur,
                              decoration: const InputDecoration(labelText: 'Armateur'),
                              items: [
                                for (final x in s.data!)
                                  DropdownMenuItem(value: x['id'], child: Text(x['name']))
                              ],
                              onChanged: (v) => setState(() => selectedArmateur = v),
                            )
                          : const LinearProgressIndicator(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xffe0f2fe),
                    foregroundColor: const Color(0xff0369a1),
                  ),
                  onPressed: assignClient,
                  icon: const Icon(Icons.link_rounded, size: 16),
                  label: const Text('Affecter à partir de la date choisie'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 26),

        // Exceptions / Prises forcées
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xffe2e8f0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xffd97706), size: 20),
                      SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Prises forcées à rapprocher',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xff0f172a))),
                          Text('Exceptions auditables sans inventaire fictif dans le yard',
                            style: TextStyle(fontSize: 11, color: Color(0xff64748b))),
                        ],
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: registerObservedContainer,
                    icon: const Icon(Icons.add_box_outlined, size: 16),
                    label: const Text('Ajouter un conteneur observé', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: forced,
                builder: (c, s) {
                  if (s.hasError) return Text('Erreur : ${s.error}');
                  if (!s.hasData) return const LinearProgressIndicator();
                  final open = s.data!.where((x) => x['resolved_at'] == null).toList();
                  if (open.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xfff0fdf4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xffbbf7d0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: Color(0xff16a34a), size: 18),
                          SizedBox(width: 8),
                          Text('Toutes les prises sont en règle. Aucune exception en attente.',
                            style: TextStyle(fontSize: 12, color: Color(0xff15803d), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final x in open)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xfffffbeb),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xfffde68a)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.report_problem_outlined, color: Color(0xffd97706)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      x['container_number'].toString(),
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, fontFamily: 'monospace'),
                                    ),
                                    Text(
                                      '${x['occurred_at']} · ${x['reason']}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xff92400e)),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton.tonal(
                                onPressed: () => reconcileForced(x),
                                child: const Text('Rapprocher'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 26),

        // Journal d'audit
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xffe2e8f0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_rounded, color: Color(0xff075a8d), size: 20),
                  SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Journal d’audit système',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xff0f172a))),
                      Text('Traçabilité des 100 dernières actions',
                        style: TextStyle(fontSize: 11, color: Color(0xff64748b))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: audit,
                builder: (c, s) {
                  if (s.hasError) return Text('Erreur : ${s.error}');
                  if (!s.hasData) return const LinearProgressIndicator();
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: s.data!.length > 15 ? 15 : s.data!.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xfff1f5f9)),
                    itemBuilder: (c, i) {
                      final x = s.data![i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xfff1f5f9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                (x['action'] ?? '').toString().toUpperCase(),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xff334155)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${x['entity']} · ${x['entity_id'] ?? ''}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xff0f172a))),
                                  Text('${x['occurred_at']} · Agent: ${x['actor_id'] ?? 'système'}',
                                    style: const TextStyle(fontSize: 11, color: Color(0xff94a3b8))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),
      ],
    ),
  );

  Widget _legendDot(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xff475569))),
    ],
  );

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
    bool isLive = false,
  }) {
    return Container(
      width: 215,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffe2e8f0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060f172a),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (isLive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xffdcfce7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fiber_manual_record, size: 8, color: Color(0xff16a34a)),
                      SizedBox(width: 4),
                      Text('Direct',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xff166534))),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xff0f172a),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xff475569),
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xff94a3b8),
            ),
          ),
        ],
      ),
    );
  }
}
