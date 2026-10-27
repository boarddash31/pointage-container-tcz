/// Gate-out form values. Archived facts take priority over the current visit.
class GateOutContainer {
  const GateOutContainer(
    this.number,
    this.iso,
    this.line,
    this.status,
    this.weight,
  );
  final String number, iso, line, status, weight;
}

class GateOutSlip {
  GateOutSlip._({
    required this.date,
    required this.reference,
    required this.plate,
    required this.cin,
    required this.agent,
    required this.emptyChassis,
    required this.containers,
    required this.fields,
    required this.orders,
  });
  final String date, reference, plate, cin, agent;
  final bool emptyChassis;
  final List<GateOutContainer> containers;
  final Map<String, String> fields;
  final List<String> orders;
  static Map<String, dynamic> map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  static String text(dynamic value) => value?.toString().trim() ?? '';
  static String first(Iterable<dynamic> values) =>
      values.map(text).firstWhere((v) => v.isNotEmpty, orElse: () => '');
  static String status(dynamic value) => switch (text(value).toUpperCase()) {
    'MTY' || 'EMPTY' || 'VIDE' => 'Vide',
    'FULL' || 'PLEIN' || 'FCL' => 'Plein',
    _ => text(value),
  };
  factory GateOutSlip.fromDocument(
    Map<String, dynamic> document, {
    Map<String, dynamic>? visitData,
  }) {
    final snapshot = map(document['snapshot']),
        context = map(document['print_context']);
    final v = {...?visitData, ...snapshot};
    final event = map(snapshot['event']);
    final exit = map(snapshot['exit_document']);
    final emptyChassis = v['entry_kind'] == 'loaded';
    final containers = <GateOutContainer>[];
    if (!emptyChassis) {
      for (final suffix in ['', if (v['is_twin'] == true) '_2']) {
        containers.add(
          GateOutContainer(
            text(v['container_number$suffix']),
            text(v['iso_code$suffix']),
            text(v['armateur_id$suffix']),
            status(
              exit['load_status$suffix'] ?? snapshot['load_status$suffix'],
            ),
            text(
              exit['gross_weight_kg$suffix'] ??
                  snapshot['gross_weight_kg$suffix'],
            ),
          ),
        );
      }
    }
    var date = text(context['created_at_local']);
    if (date.isEmpty) {
      final raw = first([document['created_at'], snapshot['exited_at']]);
      final parsed = DateTime.tryParse(raw)?.toUtc();
      if (parsed == null) {
        date = raw;
      } else {
        String pad(int n) => n.toString().padLeft(2, '0');
        date =
            '${parsed.year}-${pad(parsed.month)}-${pad(parsed.day)} ${pad(parsed.hour)}:${pad(parsed.minute)}:${pad(parsed.second)} UTC';
      }
    }
    final fields = <String, String>{};
    for (final key in [
      'customs_office',
      'declaration_number',
      'bill_of_lading',
      'ecor_name',
      'ecor_ppr',
      'ecor_date',
      'ecor_time',
      'seal_number',
      'gate_agent_name',
      'gate_agent_ppr',
      'gate_date',
      'gate_time',
      'gate_number',
    ]) {
      // Customs/control fields must be explicitly archived, never inferred from a booking or ISO.
      fields[key] = text(exit[key] ?? snapshot[key]);
    }
    final orders = <String>{
      first([
        v['carrier_booking_reference'],
        map(v['bookings'])['reference'],
        event['booking'],
      ]),
      if (v['is_twin'] == true) text(v['booking_reference_2']),
    }..remove('');
    return GateOutSlip._(
      date: date,
      reference: first([
        exit['authorization_number'],
        snapshot['authorization_number'],
        document['event_id'],
        document['id'],
      ]),
      plate: text(v['plate']),
      cin: text(v['driver_cin']),
      agent: first([
        snapshot['agent_name'],
        context['agent_name'],
        document['agent_name'],
        snapshot['exited_by'],
      ]),
      emptyChassis: emptyChassis,
      containers: containers,
      fields: fields,
      orders: orders.toList(),
    );
  }
  String containerValues(String Function(GateOutContainer) value) =>
      containers.length < 2
      ? containers.map(value).join()
      : [
          for (var i = 0; i < containers.length; i++)
            if (value(containers[i]).isNotEmpty)
              '${i + 1} : ${value(containers[i])}',
        ].join(' / ');
}
