class TransportOrderItem {
  const TransportOrderItem({
    required this.id,
    required this.reference,
    required this.kind,
    required this.direction,
    required this.armateur,
    required this.iso,
    required this.quantity,
    required this.reserved,
    required this.completed,
    required this.remaining,
    required this.active,
    this.orderId,
    this.version = 1,
    this.everUsed = 0,
  });
  final String? orderId;
  final int version, everUsed;
  bool get hasHistory => everUsed > 0 || reserved + completed > 0;
  final String id, reference, kind, direction, armateur, iso;
  final int quantity, reserved, completed, remaining;
  final bool active;
  factory TransportOrderItem.fromJson(Map<String, dynamic> j) =>
      TransportOrderItem(
        id: j['id'] as String,
        orderId: j['order_id'] as String?,
        version: (j['version'] as num?)?.toInt() ?? 1,
        everUsed: (j['ever_used'] as num?)?.toInt() ?? 0,
        reference: j['reference'] as String,
        kind: j['kind'] as String,
        direction: j['direction'] as String,
        armateur: j['armateur_id'] as String,
        iso: j['iso_code'] as String,
        quantity: (j['quantity'] as num).toInt(),
        reserved: (j['reserved'] as num).toInt(),
        completed: (j['completed'] as num).toInt(),
        remaining: (j['remaining'] as num).toInt(),
        active: j['active'] == true,
      );
}

class TransportOrder {
  TransportOrder(this.items) : assert(items.isNotEmpty);
  final List<TransportOrderItem> items;
  String get id => items.first.orderId ?? items.first.id;
  String get reference => items.first.reference;
  String get kind => items.first.kind;
  String get direction => items.first.direction;
  int get version => items.first.version;
  static List<TransportOrder> group(List<TransportOrderItem> items) {
    final groups = <String, List<TransportOrderItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.orderId ?? item.id, () => []).add(item);
    }
    return groups.values.map(TransportOrder.new).toList();
  }
}
