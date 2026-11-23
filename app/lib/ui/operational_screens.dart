import 'package:flutter/material.dart';
import '../data/pointage_repository.dart';
import '../domain/container_number.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.repository});
  final PointageRepository repository;
  @override State<HistoryScreen> createState() => _HistoryScreenState();
}
class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<DataTransaction>> visits;
  String query = '';
  @override void initState() { super.initState(); visits = widget.repository.transactions(); }
  void details(DataTransaction visit) => showDialog<void>(context: context, builder: (_) => AlertDialog(
    title: Text('Historique · ${visit.visit.plate}'),
    content: SizedBox(width: 600, child: Column(mainAxisSize: MainAxisSize.min, children: [
      for(final entry in visit.visit.operationalDetails.entries)
        if(entry.value.toString().isNotEmpty) Padding(padding: const EdgeInsets.only(bottom:6),
          child: Align(alignment: Alignment.centerLeft, child: SelectableText('${{
            'haulier':'Transporteur','lane':'Voie','lane_2':'Voie TC2',
            'damage_reservations':'Réserves / dommages TC1','damage_reservations_2':'Réserves / dommages TC2',
            'seal_number':'Scellé TC1','seal_number_2':'Scellé TC2',
          }[entry.key] ?? entry.key} : ${entry.value}'))),
      Flexible(child: FutureBuilder<List<Map<String,dynamic>>>(
      future: widget.repository.events(visit.visit.id), builder: (context, state) {
        if (state.hasError) return const Text('Historique indisponible. Réessayez.');
        if (!state.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(shrinkWrap: true, children: [for (final event in state.data!)
          ListTile(title: Text('${event['action']} · ${event['occurred_at']}'),
            subtitle: SelectableText('Agent : ${event['actor_id']}\n${event['details']}')),
        ]);
      },
    )), ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
  ));
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    Row(children: [Expanded(child: Text('Historique des flux', style: Theme.of(context).textTheme.headlineSmall)),
      IconButton(tooltip: 'Actualiser', icon: const Icon(Icons.refresh), onPressed: () => setState(() => visits = widget.repository.transactions())),
    ]), const SizedBox(height: 12),
    TextField(decoration: const InputDecoration(labelText: 'Camion, conteneur, EDO/ERO ou agent', prefixIcon: Icon(Icons.search)),
      onChanged: (value) => setState(() => query = value.trim().toLowerCase())),
    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('500 dernières visites maximum · Ouvrez une visite pour consulter ses événements.')),
    FutureBuilder<List<DataTransaction>>(future: visits, builder: (context, state) {
      if (state.hasError) return const Text('Historique indisponible. Actualisez pour réessayer.');
      if (!state.hasData) return const Center(child: CircularProgressIndicator());
      final rows = state.data!.where((v) => v.matches(query)).toList();
      return Column(children: [
        if (rows.isEmpty) const ListTile(title: Text('Aucune visite trouvée')),
        for (final row in rows) Card(child: ListTile(
          leading: const Icon(Icons.history), title: Text('${row.number} · ${row.visit.plate} · ${row.status}'),
          subtitle: Text('${row.containers}\n${row.bookings} · Créateur : ${row.creator} · ${row.visit.enteredAt.toLocal()}'),
          isThreeLine: true, trailing: const Icon(Icons.chevron_right), onTap: () => details(row),
        )),
      ]);
    }),
  ]);
}

class ContainerBlocksScreen extends StatefulWidget {
  const ContainerBlocksScreen({super.key, required this.repository});
  final PointageRepository repository;
  @override State<ContainerBlocksScreen> createState() => _ContainerBlocksScreenState();
}
class _ContainerBlocksScreenState extends State<ContainerBlocksScreen> {
  final number = TextEditingController(), reason = TextEditingController();
  late Future<List<Map<String,dynamic>>> blocks;
  Map<String,dynamic>? selected;
  bool busy = false;
  String? error;
  @override void initState() { super.initState(); blocks = widget.repository.containerBlocks(); }
  @override void dispose() { number.dispose(); reason.dispose(); super.dispose(); }
  Future<void> save(bool blocked) async {
    final container = number.text.trim().toUpperCase();
    if (!ContainerNumber.isValid(container) || reason.text.trim().length < 3) {
      setState(() => error = 'Renseignez un numéro ISO 6346 valide et un motif d’au moins 3 caractères.'); return;
    }
    setState(() { busy = true; error = null; });
    try {
      await widget.repository.setContainerBlock(container, blocked, reason.text.trim(), expectedVersion: (selected?['version'] as num?)?.toInt() ?? 0);
      if (!mounted) return;
      setState(() { selected = null; number.clear(); reason.clear(); blocks = widget.repository.containerBlocks(); });
    } catch (_) {
      if (mounted) setState(() => error = 'Modification refusée. Actualisez la liste et vérifiez votre rôle ainsi que la mise à jour de la base.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Blocages conteneurs')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Un conteneur bloqué ne peut pas être livré. Le blocage et sa levée sont réservés à l’administrateur et conservent leur motif.'),
      const SizedBox(height: 16),
      TextField(controller: number, readOnly: busy, textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Conteneur *'), onChanged: (_) => setState(() => selected = null)),
      const SizedBox(height: 12),
      TextField(controller: reason, readOnly: busy, maxLength: 1000, minLines: 2, maxLines: 3,
        decoration: const InputDecoration(labelText: 'Motif du blocage ou de sa levée *')),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      Wrap(spacing: 12, children: [
        FilledButton.icon(onPressed: busy ? null : () => save(true), icon: const Icon(Icons.block), label: const Text('Bloquer')),
        OutlinedButton(onPressed: busy || selected?['blocked'] != true ? null : () => save(false), child: const Text('Lever le blocage sélectionné')),
        TextButton(onPressed: busy ? null : () => setState(() { blocks = widget.repository.containerBlocks(); selected = null; }), child: const Text('Actualiser')),
      ]), const SizedBox(height: 20),
      FutureBuilder<List<Map<String,dynamic>>>(future: blocks, builder: (context, state) {
        if (state.hasError) return const Text('Liste indisponible. La mise à jour ops de la base doit être appliquée avant utilisation.');
        if (!state.hasData) return const Center(child: CircularProgressIndicator());
        return Column(children: [for (final row in state.data!) Card(child: ListTile(
          leading: Icon(row['blocked'] == true ? Icons.block : Icons.check_circle_outline),
          title: Text('${row['container_number']} · ${row['blocked'] == true ? 'Bloqué' : 'Blocage levé'}'),
          subtitle: Text('${row['reason']}\n${row['changed_at']} · ${row['changed_by']}'),
          onTap: busy ? null : () => setState(() { selected = row; number.text = row['container_number'].toString(); reason.clear(); }),
        ))]);
      }),
    ]),
  );
}
