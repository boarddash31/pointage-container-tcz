import 'package:flutter/material.dart';
import '../data/pointage_repository.dart';
import '../domain/transport_order.dart';

class TransportOrdersScreen extends StatefulWidget {
  const TransportOrdersScreen({
    super.key,
    required this.repository,
    required this.direction,
  });
  final PointageRepository repository;
  final String direction;
  @override
  State<TransportOrdersScreen> createState() => _TransportOrdersScreenState();
}

class _TransportOrdersScreenState extends State<TransportOrdersScreen> {
  List<TransportOrderItem> items = [];
  String query = '';
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await widget.repository.transportOrderItems();
      if (mounted) setState(() => items = rows);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([TransportOrder? order]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateTransportOrderScreen(
          repository: widget.repository,
          direction: widget.direction,
          order: order,
        ),
      ),
    );
    if (saved == true) await load();
  }

  Future<void> increase(TransportOrderItem item) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _IncreaseQuantityDialog(repository: widget.repository, item: item),
    );
    if (saved == true) await load();
  }

  @override
  Widget build(BuildContext context) {
    final orders = TransportOrder.group(items)
        .where(
          (o) =>
              o.direction == widget.direction &&
              '${o.kind} ${o.reference} ${o.items.map((i) => '${i.armateur} ${i.iso}').join(' ')}'
                  .toUpperCase()
                  .contains(query.toUpperCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Ordres · ${widget.direction == 'LIVRAISON' ? 'Livraison' : 'Restitution'}',
        ),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('Créer un ordre'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Référence EDO / ERO, armateur ou ISO',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text('Chargement impossible : $error'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                children: [
                  if (!loading && error == null && orders.isEmpty)
                    const ListTile(
                      title: Text('Aucun ordre. Créez un EDO ou un ERO.'),
                    ),
                  for (final o in orders)
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: Text('${o.kind} ${o.reference}'),
                            subtitle: Text(
                              '${o.items.length} article(s) · Quantité totale : ${o.items.fold<int>(0, (n, i) => n + i.quantity)}',
                            ),
                            trailing: TextButton.icon(
                              onPressed: () => edit(o),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Modifier'),
                            ),
                          ),
                          for (final i in o.items)
                            ListTile(
                              title: Text('${i.armateur} · ISO ${i.iso}'),
                              subtitle: Text(
                                'Autorisés : ${i.quantity}\nRéservés : ${i.reserved} · Effectués : ${i.completed} · Disponibles : ${i.remaining}',
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Ajouter de la quantité',
                                    onPressed: i.active && i.quantity < 1000000
                                        ? () => increase(i)
                                        : null,
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                  IconButton(
                                    tooltip: 'Sélectionner cet article',
                                    onPressed: i.active && i.remaining > 0
                                        ? () => Navigator.pop(context, i)
                                        : null,
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncreaseQuantityDialog extends StatefulWidget {
  const _IncreaseQuantityDialog({required this.repository, required this.item});
  final PointageRepository repository;
  final TransportOrderItem item;
  @override
  State<_IncreaseQuantityDialog> createState() =>
      _IncreaseQuantityDialogState();
}

class _IncreaseQuantityDialogState extends State<_IncreaseQuantityDialog> {
  final quantity = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    quantity.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.increaseTransportOrderQuantity(
        itemId: widget.item.id,
        quantity: int.parse(quantity.text.trim()),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Ajouter de la quantité'),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.item.reference} · ${widget.item.armateur} · ${widget.item.iso}\nQuantité actuelle : ${widget.item.quantity}',
            ),
            TextFormField(
              controller: quantity,
              autofocus: true,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantité à ajouter',
              ),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return n != null && n > 0 && n <= 1000000 - widget.item.quantity
                    ? null
                    : 'Entier positif, total maximal : 1 000 000';
              },
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Enregistrement…' : 'Ajouter'),
        ),
      ],
    ),
  );
}

class _OrderRow {
  _OrderRow({
    this.id,
    this.armateur,
    String iso = '',
    int quantity = 1,
    this.allocated = 0,
    this.used = false,
  }) : iso = TextEditingController(text: iso),
       quantity = TextEditingController(text: '$quantity');
  final String? id;
  String? armateur;
  final TextEditingController iso, quantity;
  final armateurText = TextEditingController();
  final int allocated;
  final bool used;
  void dispose() {
    iso.dispose();
    quantity.dispose();
    armateurText.dispose();
  }
}

class CreateTransportOrderScreen extends StatefulWidget {
  const CreateTransportOrderScreen({
    super.key,
    required this.repository,
    required this.direction,
    this.order,
  });
  final PointageRepository repository;
  final String direction;
  final TransportOrder? order;
  @override
  State<CreateTransportOrderScreen> createState() =>
      _CreateTransportOrderScreenState();
}

class _CreateTransportOrderScreenState
    extends State<CreateTransportOrderScreen> {
  final form = GlobalKey<FormState>();
  final reference = TextEditingController();
  final rows = <_OrderRow>[];
  List<OperatorRecord> operators = [];
  TransportOrder? order, duplicate;
  late String kind;
  bool busy = false, conflict = false;
  String? error;
  @override
  void initState() {
    super.initState();
    kind = widget.direction == 'LIVRAISON' ? 'EDO' : 'ERO';
    order = widget.order;
    fillRows();
    loadOperators();
  }

  void fillRows() {
    for (final r in rows) {
      r.dispose();
    }
    rows.clear();
    if (order case final o?) {
      reference.text = o.reference;
      kind = o.kind;
      for (final i in o.items) {
        rows.add(
          _OrderRow(
            id: i.id,
            armateur: i.armateur,
            iso: i.iso,
            quantity: i.quantity,
            allocated: i.reserved + i.completed,
            used: i.hasHistory,
          ),
        );
      }
    } else {
      rows.add(_OrderRow());
    }
  }

  Future<void> loadOperators() async {
    try {
      final result = await widget.repository.operators();
      if (mounted) {
        setState(() {
          for (final r in rows) {
            final previous = operators
                .where((o) => o.id == r.armateur)
                .firstOrNull;
            final previousLabel = previous == null
                ? r.armateur
                : '${previous.id} · ${previous.name}';
            final current = result.where((o) => o.id == r.armateur).firstOrNull;
            if (current != null &&
                (r.armateurText.text.isEmpty ||
                    r.armateurText.text == previousLabel)) {
              r.armateurText.text = '${current.id} · ${current.name}';
            }
          }
          operators = result;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> refreshOrder() async {
    setState(() => busy = true);
    try {
      final all = await widget.repository.transportOrderItems();
      final updated = TransportOrder.group(
        all,
      ).where((o) => o.id == order!.id).firstOrNull;
      if (updated == null) throw StateError('Ordre introuvable');
      if (mounted) {
        setState(() {
          order = updated;
          fillRows();
          error = null;
          conflict = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<TransportOrder?> existingOrder() async {
    final all = await widget.repository.transportOrderItems();
    final ref = reference.text.trim().toUpperCase();
    return TransportOrder.group(
      all,
    ).where((o) => o.reference.trim().toUpperCase() == ref).firstOrNull;
  }

  @override
  void dispose() {
    reference.dispose();
    for (final r in rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final keys = rows
        .map((r) => '${r.armateur}|${r.iso.text.trim().toUpperCase()}')
        .toList();
    if (keys.toSet().length != keys.length) {
      setState(
        () => error =
            'Un seul article par armateur et code ISO. Modifiez sa quantité.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      duplicate = null;
    });
    try {
      final payload = [
        for (final r in rows)
          <String, dynamic>{
            if (r.id != null) 'id': r.id,
            'iso_code': r.iso.text.trim().toUpperCase(),
            'armateur_id': r.armateur,
            'quantity': int.parse(r.quantity.text.trim()),
          },
      ];
      if (order == null) {
        final found = await existingOrder();
        if (found != null) {
          if (mounted) {
            setState(() {
              duplicate = found;
              error =
                  'Cette référence désigne déjà un ordre. Ouvrez-le pour ajouter de la quantité.';
            });
          }
          return;
        }
        await widget.repository.createTransportOrder(
          kind: kind,
          direction: widget.direction,
          reference: reference.text.trim().toUpperCase(),
          armateur: rows.first.armateur!,
          items: payload,
        );
      } else {
        await widget.repository.updateTransportOrder(
          orderId: order!.id,
          expectedVersion: order!.version,
          items: payload,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (e.toString().contains('23505') && order == null) {
        try {
          duplicate = await existingOrder();
        } catch (_) {
          /* Keep the original error. */
        }
      }
      if (mounted) {
        setState(() {
          conflict = e.toString().contains('40001');
          error = conflict
              ? 'Ordre modifié par un autre utilisateur. Actualisez avant de réappliquer vos changements.'
              : e.toString().contains('23505')
              ? 'Cette référence existe déjà. Ouvrez l’ordre existant.'
              : e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openDuplicate() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateTransportOrderScreen(
          repository: widget.repository,
          direction: duplicate!.direction,
          order: duplicate,
        ),
      ),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        order == null
            ? 'Créer EDO / ERO'
            : 'Modifier ${order!.kind} ${order!.reference}',
      ),
    ),
    body: AbsorbPointer(
      absorbing: busy,
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (order == null)
              DropdownMenuFormField<String>(
                key: const ValueKey('order-type'),
                enabled: false,
                initialSelection: kind,
                label: const Text('Type d’ordre'),
                expandedInsets: EdgeInsets.zero,
                selectOnly: true,
                dropdownMenuEntries: const [
                  DropdownMenuEntry(value: 'EDO', label: 'EDO · Livraison'),
                  DropdownMenuEntry(value: 'ERO', label: 'ERO · Restitution'),
                ],
              ),
            if (order == null) const SizedBox(height: 32),
            TextFormField(
              controller: reference,
              readOnly: order != null,
              maxLength: 150,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Référence *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Référence requise' : null,
            ),
            const SizedBox(height: 24),
            const Text(
              'Articles et quantités totales autorisées',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < rows.length; index++)
              itemForm(rows[index], index),
            if (rows.length < 50)
              TextButton.icon(
                onPressed: () => setState(
                  () => rows.add(_OrderRow(armateur: rows.last.armateur)),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un article'),
              ),
            const Text(
              'Une visite réserve 1 unité par conteneur. Les articles déjà utilisés conservent leur ISO et leur armateur.',
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (duplicate != null)
              TextButton(
                onPressed: openDuplicate,
                child: const Text('Ouvrir l’ordre existant'),
              ),
            if (conflict)
              TextButton(
                onPressed: refreshOrder,
                child: const Text('Actualiser et remplacer le formulaire'),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy || conflict ? null : save,
              child: Text(
                busy
                    ? 'Enregistrement…'
                    : order == null
                    ? 'Créer l’ordre'
                    : 'Enregistrer les modifications',
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget itemForm(_OrderRow r, int index) {
    final choices = {for (final o in operators) o.id: '${o.id} · ${o.name}'};
    if (r.armateur != null) choices.putIfAbsent(r.armateur!, () => r.armateur!);
    return Card(
      key: ObjectKey(r),
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text('Article ${index + 1}')),
                if (rows.length > 1 && !r.used)
                  IconButton(
                    tooltip: 'Supprimer l’article',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() {
                      rows.remove(r);
                      r.dispose();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            DropdownMenuFormField<String>(
              controller: r.armateurText,
              initialSelection: r.armateur,
              enabled: !r.used,
              expandedInsets: EdgeInsets.zero,
              menuHeight: 280,
              enableFilter: true,
              enableSearch: true,
              requestFocusOnTap: true,
              label: const Text('Armateur *'),
              hintText: 'Saisir un code ou un nom',
              dropdownMenuEntries: [
                for (final c in choices.entries)
                  DropdownMenuEntry(value: c.key, label: c.value),
              ],
              onSelected: (v) => setState(() => r.armateur = v),
              validator: (v) =>
                  v == null || r.armateurText.text.trim() != choices[v]
                  ? 'Sélectionnez un armateur de la liste'
                  : null,
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: r.iso,
                    readOnly: r.used,
                    decoration: InputDecoration(
                      labelText: 'ISO article ${index + 1}',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) =>
                        RegExp(
                          r'^[0-9A-Z]{4}$',
                        ).hasMatch((v ?? '').trim().toUpperCase())
                        ? null
                        : 'ISO : 4 caractères',
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: TextFormField(
                    controller: r.quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantité totale *',
                    ),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      final min = r.allocated > 0 ? r.allocated : 1;
                      return n != null && n >= min && n <= 1000000
                          ? null
                          : 'De $min à 1 000 000';
                    },
                  ),
                ),
              ],
            ),
            if (r.used)
              Text('Article utilisé · Quantité engagée : ${r.allocated}'),
          ],
        ),
      ),
    );
  }
}
