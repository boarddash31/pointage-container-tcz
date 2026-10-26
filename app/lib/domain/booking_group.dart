import '../data/pointage_repository.dart';

String normalizeReference(String? value) => (value ?? '').trim().toUpperCase();

class BookingVisitPart {
  const BookingVisitPart(this.transaction, {this.second = false});
  final DataTransaction transaction;
  final bool second;
  String get armateur => second
      ? transaction.bookingArmateur2 ?? transaction.visit.armateur2 ?? transaction.visit.armateur
      : transaction.bookingArmateur ?? transaction.visit.armateur;
  String get reference => normalizeReference(second && normalizeReference(transaction.visit.booking2).isNotEmpty
      ? transaction.visit.booking2 : transaction.visit.booking);
  String? get container => second ? transaction.visit.container2 : transaction.visit.container;
  String get iso => second ? transaction.visit.iso2 ?? transaction.visit.iso : transaction.visit.iso;
}

class CarrierBookingGroup {
  CarrierBookingGroup(this.armateur, this.reference);
  final String armateur, reference;
  final List<BookingVisitPart> parts = [];
  List<DataTransaction> get transactions => {
    for (final part in parts) part.transaction.visit.id: part.transaction,
  }.values.toList();
  int get containerCount => parts.map((p) => p.container).whereType<String>()
      .where((c) => c.isNotEmpty).toSet().length;
}

class ClientOrderGroup {
  ClientOrderGroup(this.clientId, this.clientName, this.reference);
  final String? clientId, clientName;
  final String reference;
  final Map<(String, String), CarrierBookingGroup> _bookings = {};
  List<CarrierBookingGroup> get bookings => _bookings.values.toList();
  List<DataTransaction> get transactions => {
    for (final booking in bookings)
      for (final row in booking.transactions) row.visit.id: row,
  }.values.toList();
  int get containerCount => bookings.expand((b) => b.parts).map((p) => p.container)
      .whereType<String>().where((c) => c.isNotEmpty).toSet().length;
  int get inside => transactions.where((t) => t.visit.isInside).length;
  int get canceled => transactions.where((t) => t.visit.canceledAt != null).length;
  int get exited => transactions.where((t) => t.visit.exitedAt != null && t.visit.canceledAt == null).length;
  bool matches(String query) => '${clientName ?? ''} $reference'.toLowerCase()
      .contains(query.trim().toLowerCase()) || transactions.any((t) => t.matches(query));

  static List<ClientOrderGroup> fromTransactions(List<DataTransaction> rows) {
    final groups = <(String?, String), ClientOrderGroup>{};
    for (final row in rows) {
      final reference = normalizeReference(row.clientOrder);
      final group = groups.putIfAbsent((row.clientId, reference),
          () => ClientOrderGroup(row.clientId, row.clientName, reference));
      for (final part in [BookingVisitPart(row), if (row.visit.isTwin) BookingVisitPart(row, second:true)]) {
        final key = part.reference.isEmpty ? 'visit:${row.visit.id}' : part.reference;
        group._bookings.putIfAbsent((part.armateur,key),
            () => CarrierBookingGroup(part.armateur,part.reference)).parts.add(part);
      }
    }
    return groups.values.toList();
  }
}
