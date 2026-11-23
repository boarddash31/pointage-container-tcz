import 'package:flutter/material.dart';
import '../data/pointage_repository.dart';

class SqlDashboard extends StatefulWidget {
  const SqlDashboard({super.key, required this.repository});
  final PointageRepository repository;
  @override
  State<SqlDashboard> createState() => _SqlDashboardState();
}

class _SqlDashboardState extends State<SqlDashboard> {
  late Future<Map<String, dynamic>> data = widget.repository.dashboardKpis();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tableau de bord'),
      actions: [
        IconButton(
          onPressed: () =>
              setState(() => data = widget.repository.dashboardKpis()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (context, s) {
        if (s.hasError) return Center(child: Text(s.error.toString()));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final d = s.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final metric in const {
                  'entries_today': 'Entrées du jour',
                  'exits_today': 'Sorties du jour',
                  'trucks_in_yard': 'Camions présents',
                  'containers_in_stock': 'Conteneurs en stock',
                  'agents_count': 'Comptes actifs',
                }.entries)
                  SizedBox(
                    width: 230,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(metric.value),
                            Text(
                              '${d[metric.key] ?? 0}',
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Dernières visites'),
            for (final v in d['recent_visits'] as List? ?? [])
              ListTile(
                title: Text('${v['truck_plate']} — ${v['status']}'),
                subtitle: Text(
                  '${v['container_number'] ?? ''} ${v['container_number_2'] ?? ''}',
                ),
              ),
          ],
        );
      },
    ),
  );
}
