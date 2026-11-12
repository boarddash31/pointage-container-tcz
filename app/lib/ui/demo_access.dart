import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../data/demo_store.dart';
import '../data/pointage_repository.dart' show OperatorRecord;
import 'tcz_brand.dart';
import 'truck_diagram.dart';

class DemoAccessHome extends StatefulWidget {
  const DemoAccessHome({
    super.key,
    required this.productionBuilder,
    this.store,
    this.initialProduction = false,
  });
  final Widget Function(VoidCallback onBack) productionBuilder;
  final DemoStore? store;
  final bool initialProduction;
  @override
  State<DemoAccessHome> createState() => _DemoAccessHomeState();
}

class _DemoAccessHomeState extends State<DemoAccessHome> {
  late final Future<DemoStore> loaded;
  late bool production;
  String? selected;
  @override
  void initState() {
    super.initState();
    production = widget.initialProduction;
    loaded = widget.store == null
        ? DemoStore.load()
        : Future.value(widget.store);
  }

  @override
  Widget build(BuildContext context) {
    if (production) {
      return widget.productionBuilder(() => setState(() => production = false));
    }
    return FutureBuilder<DemoStore>(
      future: loaded,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Démo locale indisponible : ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final store = snapshot.data!;
        return AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final profiles = store.profiles
                .where((p) => p.id == selected && p.active)
                .toList();
            if (profiles.isNotEmpty) {
              return DemoWorkspace(
                key: ValueKey(profiles.first.id),
                store: store,
                profile: profiles.first,
                onBack: () => setState(() => selected = null),
              );
            }
            return Scaffold(
              body: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      children: [
                        const TczBrand(width: 240),
                        const SizedBox(height: 18),
                        Text(
                          'Accès démo',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Choisissez votre profil · ouverture directe',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 26),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final role in ['admin', 'entree', 'sortie'])
                              Builder(
                                builder: (context) {
                                  final available = store.profiles
                                      .where((p) => p.active && p.role == role)
                                      .toList();
                                  final label = switch (role) {
                                    'admin' => 'Admin',
                                    'entree' => 'Entrée',
                                    _ => 'Sortie',
                                  };
                                  return SizedBox(
                                    width: 235,
                                    height: 140,
                                    child: FilledButton.tonal(
                                      key: ValueKey('demo-open-$role'),
                                      style: FilledButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                      ),
                                      onPressed: available.isEmpty
                                          ? null
                                          : () => setState(
                                              () =>
                                                  selected = available.first.id,
                                            ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(switch (role) {
                                            'admin' =>
                                              Icons
                                                  .admin_panel_settings_outlined,
                                            'entree' => Icons.login_rounded,
                                            _ => Icons.logout_rounded,
                                          }, size: 36),
                                          const SizedBox(height: 10),
                                          Text(
                                            label,
                                            style: const TextStyle(
                                              fontSize: 21,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            role == 'admin'
                                                ? 'Créer et gérer les profils'
                                                : 'Pointage conteneurs',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        if (store.profiles.any(
                          (p) =>
                              ![
                                'demo-admin',
                                'demo-entree',
                                'demo-sortie',
                              ].contains(p.id) &&
                              p.active,
                        )) ...[
                          const SizedBox(height: 24),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Profils créés en démo',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          for (final profile in store.profiles.where(
                            (p) =>
                                ![
                                  'demo-admin',
                                  'demo-entree',
                                  'demo-sortie',
                                ].contains(p.id) &&
                                p.active,
                          ))
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: Text(profile.name),
                                subtitle: Text(profile.roleLabel),
                                trailing: const Icon(Icons.arrow_forward),
                                onTap: () =>
                                    setState(() => selected = profile.id),
                              ),
                            ),
                        ],
                        const SizedBox(height: 24),
                        const Chip(
                          avatar: Icon(Icons.science_outlined, size: 18),
                          label: Text(
                            'Données fictives · enregistrées sur cet appareil',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          key: const ValueKey('open-production'),
                          onPressed: () => setState(() => production = true),
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('Connexion production'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// Keep controllers alive until the dialog reverse animation has unmounted.
Future<T?> _lastingDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(context).push(route);
  await route.completed;
  return result;
}

void _notice(BuildContext context, Object message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message.toString().replaceFirst('Bad state: ', '')),
        ),
      );

class DemoWorkspace extends StatefulWidget {
  const DemoWorkspace({
    super.key,
    required this.store,
    required this.profile,
    required this.onBack,
  });
  final DemoStore store;
  final DemoProfile profile;
  final VoidCallback onBack;
  @override
  State<DemoWorkspace> createState() => _DemoWorkspaceState();
}

class _DemoWorkspaceState extends State<DemoWorkspace> {
  int tab = 0;
  late String workflow;
  @override
  void initState() {
    super.initState();
    workflow = widget.profile.role;
  }

  bool get admin => widget.profile.role == 'admin';
  Future<void> createProfile() async {
    final name = TextEditingController();
    var role = 'entree';
    String? error;
    await _lastingDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Créer un profil démo'),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('demo-profile-name'),
                  controller: name,
                  autofocus: true,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Nom du profil'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Rôle'),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'entree', child: Text('Entrée')),
                    DropdownMenuItem(value: 'sortie', child: Text('Sortie')),
                  ],
                  onChanged: (value) => update(() => role = value!),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Le profil apparaît sur cet appareil avec un accès direct.',
                  style: TextStyle(fontSize: 12),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('demo-save-profile'),
              onPressed: () async {
                try {
                  await widget.store.createProfile(
                    widget.profile,
                    name.text,
                    role,
                  );
                  if (dialog.mounted) Navigator.pop(dialog);
                } catch (e) {
                  if (dialog.mounted) {
                    update(
                      () =>
                          error = e.toString().replaceFirst('Bad state: ', ''),
                    );
                  }
                }
              },
              child: const Text('Créer le profil'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
  }

  Future<void> reset() async {
    final confirmed = await _lastingDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Réinitialiser la démo ?'),
        content: const Text(
          'Les profils et pointages de démonstration de ce navigateur seront remplacés par les exemples.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.store.reset(widget.profile);
      widget.onBack();
    }
  }

  Widget metric(String label, int count, IconData icon) => SizedBox(
    width: 210,
    child: Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(
          '$count',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(label),
      ),
    ),
  );
  Widget adminPage() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Administration démo',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          metric(
            'Camions présents',
            widget.store.inside.length,
            Icons.local_shipping_outlined,
          ),
          metric(
            'Conteneurs au parc',
            widget.store.stock.length,
            Icons.inventory_2_outlined,
          ),
          metric('Profils', widget.store.profiles.length, Icons.people_outline),
        ],
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Profils & rôles',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
          ),
          FilledButton.icon(
            key: const ValueKey('demo-add-profile'),
            onPressed: createProfile,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Créer un profil'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      for (final profile in widget.store.profiles)
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(profile.name),
            subtitle: Text(profile.roleLabel),
            trailing: Switch(
              value: profile.active,
              onChanged: (active) async {
                try {
                  await widget.store.setProfileActive(
                    widget.profile,
                    profile,
                    active,
                  );
                } catch (e) {
                  if (mounted) _notice(context, e);
                }
              },
            ),
          ),
        ),
      const SizedBox(height: 18),
      TextButton.icon(
        onPressed: reset,
        icon: const Icon(Icons.restart_alt),
        label: const Text('Réinitialiser les exemples de démo'),
      ),
    ],
  );
  Future<void> move(Map<String, dynamic> item) async {
    final position = TextEditingController(text: item['position'] as String?);
    final value = await _lastingDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Position · ${item['container_number']}'),
        content: TextField(
          controller: position,
          decoration: const InputDecoration(
            labelText: 'Bloc / travée / niveau',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, position.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    position.dispose();
    if (value != null) {
      try {
        await widget.store.moveContainer(
          widget.profile,
          item['container_number'] as String,
          value,
        );
      } catch (e) {
        if (mounted) _notice(context, e);
      }
    }
  }

  Widget stockPage() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Stock démo · ${widget.store.stock.length} conteneur(s)',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 14),
      if (widget.store.stock.isEmpty)
        const Text('Le parc de démonstration est vide.'),
      for (final item in widget.store.stock)
        Card(
          child: ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(item['container_number'] as String),
            subtitle: Text(
              '${item['iso_code']} · ${item['armateur_id']} · YARD',
            ),
            trailing: TextButton.icon(
              onPressed: admin ? () => move(item) : null,
              icon: const Icon(Icons.place_outlined),
              label: Text(item['position'] as String? ?? 'À placer'),
            ),
          ),
        ),
    ],
  );
  Future<void> download(Map<String, dynamic> visit) async {
    final bytes = await DemoBonPdf.build(visit);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'DEMO-TCZ-${visit['id']}.pdf',
    );
  }

  Widget documentsPage() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Bons & historique démo',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 10),
      for (final visit in widget.store.visits.reversed)
        Card(
          child: ListTile(
            leading: Icon(
              visit['exited_at'] == null
                  ? Icons.local_shipping_outlined
                  : Icons.check_circle_outline,
            ),
            title: Text(
              '${visit['plate']} · ${visit['exited_at'] == null ? 'Présent' : 'Sorti'}',
            ),
            subtitle: Text(
              '${visit['container_number'] ?? visit['carrier_booking_reference'] ?? ''}${visit['is_twin'] == true ? ' / ${visit['container_number_2'] ?? 'Twin'}' : ''}\n${visit['creator_name']}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Télécharger le bon démo',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => download(visit),
            ),
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: const Color(0xff063e66),
      foregroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TCZ · Démo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(widget.profile.name, style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('demo-switch-profile'),
          onPressed: widget.onBack,
          icon: const Icon(Icons.switch_account_outlined, color: Colors.white),
          label: const Text('Profils', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
    body: Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xffe0f2fe),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: const Text(
            'DÉMO · Données fictives conservées dans ce navigateur',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        if (admin && tab == 0)
          Padding(
            padding: const EdgeInsets.all(10),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'admin', label: Text('Admin')),
                ButtonSegment(value: 'entree', label: Text('Entrée')),
                ButtonSegment(value: 'sortie', label: Text('Sortie')),
              ],
              selected: {workflow},
              onSelectionChanged: (v) => setState(() => workflow = v.first),
            ),
          ),
        Expanded(
          child: switch (tab) {
            1 => stockPage(),
            2 => documentsPage(),
            _ => switch (workflow) {
              'admin' => adminPage(),
              'entree' => DemoEntryPage(
                store: widget.store,
                profile: widget.profile,
              ),
              _ => DemoExitPage(store: widget.store, profile: widget.profile),
            },
          },
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (value) => setState(() => tab = value),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.rule), label: 'Pointage'),
        NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          label: 'Stock',
        ),
        NavigationDestination(
          icon: Icon(Icons.description_outlined),
          label: 'Bons',
        ),
      ],
    ),
  );
}

class DemoEntryPage extends StatefulWidget {
  const DemoEntryPage({super.key, required this.store, required this.profile});
  final DemoStore store;
  final DemoProfile profile;
  @override
  State<DemoEntryPage> createState() => _DemoEntryPageState();
}

class _DemoEntryPageState extends State<DemoEntryPage> {
  final plate = TextEditingController(),
      cin = TextEditingController(),
      booking = TextEditingController();
  final numbers = [TextEditingController(), TextEditingController()];
  final codes = [
    TextEditingController(text: '22G1'),
    TextEditingController(text: '22G1'),
  ];
  final plateFocus = FocusNode(),
      cinFocus = FocusNode(),
      bookingFocus = FocusNode();
  final numberFocus = [FocusNode(), FocusNode()],
      codeFocus = [FocusNode(), FocusNode()];
  final lines = ['MAE', 'MAE'];
  String kind = 'loaded';
  bool twin = false, busy = false;
  late final Future<List<OperatorRecord>> operators;
  @override
  void initState() {
    super.initState();
    operators = rootBundle
        .loadString('assets/operators.json')
        .then(
          (text) => [
            for (final row in jsonDecode(text) as List)
              OperatorRecord.fromJson(Map<String, dynamic>.from(row as Map)),
          ],
        );
  }

  @override
  void dispose() {
    for (final c in [plate, cin, booking, ...numbers, ...codes]) {
      c.dispose();
    }
    for (final f in [
      plateFocus,
      cinFocus,
      bookingFocus,
      ...numberFocus,
      ...codeFocus,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.store.enter(
        widget.profile,
        plate: plate.text,
        cin: cin.text,
        kind: kind,
        iso: codes[0].text,
        line: lines[0],
        number: numbers[0].text,
        booking: booking.text,
        twin: twin,
        number2: numbers[1].text,
        iso2: codes[1].text,
        line2: lines[1],
      );
      if (!mounted) return;
      for (final c in [plate, cin, booking, ...numbers]) {
        c.clear();
      }
      _notice(
        context,
        'Entrée enregistrée en démo. Le camion apparaît en Sortie.',
      );
    } catch (e) {
      if (mounted) _notice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void example() => setState(() {
    plate.text = '13579-C-06';
    cin.text = 'EF123456';
    booking.text = 'DEMO-BOOK-003';
    numbers[0].text = DemoStore.sampleContainer('TSTU123456');
    numbers[1].text = DemoStore.sampleContainer('TSTU654321');
  });
  Widget containerFields(int index, List<OperatorRecord> records) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conteneur ${index + 1}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (kind == 'loaded')
            TextField(
              key: ValueKey('demo-container-$index'),
              controller: numbers[index],
              focusNode: numberFocus[index],
              textCapitalization: TextCapitalization.characters,
              maxLength: 11,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Numéro conteneur *',
                hintText: 'CSQU3054383',
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: codes[index],
            focusNode: codeFocus[index],
            textCapitalization: TextCapitalization.characters,
            maxLength: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Code ISO *'),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) => DropdownMenu<String>(
              width: constraints.maxWidth,
              enableFilter: true,
              enableSearch: true,
              initialSelection: lines[index],
              label: const Text('Armateur *'),
              dropdownMenuEntries: [
                for (final operator in records)
                  DropdownMenuEntry(
                    value: operator.id,
                    label: '${operator.name} · ${operator.id}',
                  ),
              ],
              onSelected: (value) {
                if (value != null) setState(() => lines[index] = value);
              },
            ),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<List<OperatorRecord>>(
    future: operators,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Text('Catalogue démo indisponible : ${snapshot.error}'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Enregistrement de l’entrée',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: example,
                child: const Text('Remplir un exemple'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final mode in [
                  ('loaded', false, 'Avec 1 conteneur'),
                  ('loaded', true, 'Avec 2 conteneurs'),
                  ('empty', false, 'Besoin de 1 conteneur'),
                  ('empty', true, 'Besoin de 2 conteneurs'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () => setState(() {
                        kind = mode.$1;
                        twin = mode.$2;
                      }),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 260,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: kind == mode.$1 && twin == mode.$2
                              ? const Color(0xffe0f2fe)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: kind == mode.$1 && twin == mode.$2
                                ? const Color(0xff0284c7)
                                : const Color(0xffcbd5e1),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            TruckScene(
                              kind: mode.$1,
                              isTwin: mode.$2,
                              height: 104,
                              width: 235,
                              plate: plate.text,
                              driverCin: cin.text,
                              containerNumber: numbers[0].text,
                              iso: codes[0].text,
                              operator: lines[0],
                              containerNumber2: mode.$2
                                  ? numbers[1].text
                                  : null,
                              iso2: mode.$2 ? codes[1].text : null,
                              operator2: mode.$2 ? lines[1] : null,
                              booking: booking.text,
                              showUnknown: true,
                              highlightMissing: true,
                              onPlateTap: () => plateFocus.requestFocus(),
                              onCinTap: () => cinFocus.requestFocus(),
                              onContainerNumberTap: (i) =>
                                  (kind == 'loaded'
                                          ? numberFocus[i]
                                          : bookingFocus)
                                      .requestFocus(),
                              onIsoTap: (i) => codeFocus[i].requestFocus(),
                            ),
                            Text(
                              mode.$3,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 350,
                child: TextField(
                  key: const ValueKey('demo-plate'),
                  controller: plate,
                  focusNode: plateFocus,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Plaque camion *',
                    hintText: '12345-A-06',
                  ),
                ),
              ),
              SizedBox(
                width: 350,
                child: TextField(
                  key: const ValueKey('demo-cin'),
                  controller: cin,
                  focusNode: cinFocus,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'CIN chauffeur *',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (kind == 'empty')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: booking,
                focusNode: bookingFocus,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Booking / EDO / ERO *',
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) =>
                twin && constraints.maxWidth >= 750
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < 2; i++)
                        Expanded(child: containerFields(i, snapshot.data!)),
                    ],
                  )
                : Column(
                    children: [
                      containerFields(0, snapshot.data!),
                      if (twin) containerFields(1, snapshot.data!),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('demo-save-entry'),
            onPressed: busy ? null : save,
            icon: const Icon(Icons.save_outlined),
            label: Text(busy ? 'Enregistrement…' : 'Enregistrer l’entrée démo'),
          ),
        ],
      );
    },
  );
}

class DemoExitPage extends StatefulWidget {
  const DemoExitPage({super.key, required this.store, required this.profile});
  final DemoStore store;
  final DemoProfile profile;
  @override
  State<DemoExitPage> createState() => _DemoExitPageState();
}

class _DemoExitPageState extends State<DemoExitPage> {
  String query = '';
  Future<void> validate(Map<String, dynamic> visit) async {
    final selected = <String?>[null, null];
    var empty = false;
    String? error;
    final position = TextEditingController(text: 'A-01-01');
    await _lastingDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text('Sortie · ${visit['plate']}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (visit['entry_kind'] == 'loaded') ...[
                    Text(
                      'Déposer ${visit['container_number']}${visit['is_twin'] == true ? ' + ${visit['container_number_2']}' : ''} au parc.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: position,
                      decoration: const InputDecoration(
                        labelText: 'Position au parc',
                      ),
                    ),
                  ] else ...[
                    CheckboxListTile(
                      value: empty,
                      onChanged: (value) => update(() => empty = value!),
                      title: const Text('Sortir à vide'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    for (var i = 0; i < (visit['is_twin'] == true ? 2 : 1); i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                          initialValue: selected[i],
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Conteneur ${i + 1} du stock',
                          ),
                          items: [
                            for (final item in widget.store.stock)
                              DropdownMenuItem(
                                value: item['container_number'] as String,
                                child: Text(
                                  '${item['container_number']} · ${item['iso_code']} · ${item['armateur_id']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: empty
                              ? null
                              : (value) => update(() => selected[i] = value),
                        ),
                      ),
                  ],
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.store.exit(
                    widget.profile,
                    visit['id'] as String,
                    pickup: selected.whereType<String>().toList(),
                    leaveEmpty: empty,
                    position: position.text,
                  );
                  if (dialog.mounted) Navigator.pop(dialog);
                  if (mounted) {
                    _notice(
                      context,
                      'Sortie enregistrée et stock démo mis à jour.',
                    );
                  }
                } catch (e) {
                  if (dialog.mounted) {
                    update(
                      () =>
                          error = e.toString().replaceFirst('Bad state: ', ''),
                    );
                  }
                }
              },
              child: const Text('Valider la sortie'),
            ),
          ],
        ),
      ),
    );
    position.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.store.inside
        .where(
          (v) =>
              '${v['plate']} ${v['container_number']} ${v['carrier_booking_reference']}'
                  .toLowerCase()
                  .replaceAll('-', '')
                  .contains(query.toLowerCase().replaceAll('-', '')),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Validation de la sortie',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 14),
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(
            labelText: 'Plaque, conteneur ou booking',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty) const Text('Aucun camion présent dans la démo.'),
        for (final visit in rows)
          Card(
            child: ListTile(
              onTap: () => validate(visit),
              leading: Icon(
                visit['entry_kind'] == 'loaded'
                    ? Icons.inventory_2_outlined
                    : Icons.local_shipping_outlined,
              ),
              title: Text(
                visit['plate'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${visit['container_number'] ?? visit['carrier_booking_reference']} · ${visit['iso_code']} · ${visit['armateur_id']}',
              ),
              trailing: const Icon(Icons.arrow_forward),
            ),
          ),
      ],
    );
  }
}

class DemoBonPdf {
  static Future<Uint8List> build(Map<String, dynamic> visit) async {
    final pdf = pw.Document(title: 'TCZ DEMONSTRATION', author: 'TCZ Demo');
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'TCZ - DEMONSTRATION',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'DONNEES FICTIVES - SANS VALEUR OPERATIONNELLE',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Divider(),
            for (final line in [
              'Camion : ${visit['plate']}',
              'CIN : ${visit['driver_cin']}',
              'Conteneur / Booking : ${visit['container_number'] ?? visit['carrier_booking_reference'] ?? '-'}',
              if (visit['is_twin'] == true)
                'Conteneur 2 : ${visit['container_number_2'] ?? '-'}',
              'ISO : ${visit['iso_code']}',
              'Armateur : ${visit['armateur_id']}',
              'Entree : ${visit['entered_at']}',
              'Sortie : ${visit['exited_at'] ?? 'En attente'}',
              'Agent demo : ${visit['creator_name']}',
            ])
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 5),
                child: pw.Text(line),
              ),
            pw.Spacer(),
            pw.Text(
              'Document genere localement par le mode demo.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }
}
