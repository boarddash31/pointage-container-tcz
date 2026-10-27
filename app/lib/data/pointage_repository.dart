import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/transport_order.dart';

class OperatorRecord {
  const OperatorRecord(this.id, this.name, this.bic);
  final String id;
  final String name;
  final String bic;
  factory OperatorRecord.fromJson(Map<String, dynamic> json) => OperatorRecord(
        json['id'] as String,
        json['name'] as String,
        (json['bic'] as String?) ?? '',
      );
}

class TruckVisit {
  const TruckVisit({required this.id, required this.plate, required this.cin,
    required this.entryKind, required this.iso, required this.armateur,
    required this.enteredAt, this.container, this.booking, this.enginAt,
    this.exitedAt, this.canceledAt, this.isTwin = false,
    this.container2, this.iso2, this.armateur2, this.booking2});
  final String id, plate, cin, entryKind, iso, armateur;
  final String? container, booking, enginAt, exitedAt, canceledAt;
  final DateTime enteredAt;
  final bool isTwin;
  final String? container2, iso2, armateur2, booking2;
  bool get needsEngin => enginAt == null;
  bool get isInside => exitedAt == null && canceledAt == null;

  factory TruckVisit.fromJson(Map<String, dynamic> j) => TruckVisit(
    id: j['id'] as String,
    plate: j['plate'] as String,
    cin: j['driver_cin'] as String,
    entryKind: j['entry_kind'] as String,
    iso: j['iso_code'] as String,
    armateur: j['armateur_id'] as String,
    container: j['container_number'] as String?,
    booking: (j['carrier_booking_reference'] ?? (j['bookings'] as Map<String, dynamic>?)?['reference']) as String?,
    enteredAt: DateTime.parse(j['entered_at'] as String),
    enginAt: j['engin_at'] as String?,
    exitedAt: j['exited_at'] as String?,
    canceledAt: j['canceled_at'] as String?,
    isTwin: (j['is_twin'] as bool?) ?? false,
    container2: j['container_number_2'] as String?,
    iso2: j['iso_code_2'] as String?,
    armateur2: j['armateur_id_2'] as String?,
    booking2: j['booking_reference_2'] as String?,
  );
}

class PointageRepository {
  PointageRepository(this.client);
  final SupabaseClient client;

  Future<List<TransportOrderItem>> transportOrderItems() async {
    final rows=await client.rpc('transport_order_items_status');
    return [for(final row in rows as List) TransportOrderItem.fromJson(Map<String,dynamic>.from(row as Map))];
  }

  Future<String> createTransportOrder({required String kind, required String direction,
    required String reference, required String armateur, required List<Map<String,dynamic>> items}) async =>
      await client.rpc('create_transport_order',params:{'p_kind':kind,'p_direction':direction,
        'p_reference':reference,'p_armateur':armateur,'p_items':items}) as String;

  Future<int> updateTransportOrder({required String orderId, required int expectedVersion,
    required List<Map<String,dynamic>> items}) async =>
      (await client.rpc('update_transport_order',params:{'p_order':orderId,
        'p_expected_version':expectedVersion,'p_items':items}) as num).toInt();

  Future<int> increaseTransportOrderQuantity({required String itemId, required int quantity}) async =>
      (await client.rpc('increase_transport_order_quantity',params:{'p_item':itemId,
        'p_quantity':quantity}) as num).toInt();

  Future<List<DataTransaction>> transactions() async {
    final rows = await client.rpc('data_transactions');
    return [for (final row in rows as List)
      DataTransaction.fromJson(Map<String, dynamic>.from(row as Map))];
  }

  User? get user => client.auth.currentUser;
  Future<List<String>> roles() async {
    final id = user?.id;
    if (id == null) return [];
    final profile = await client.from('profiles').select('active').eq('id', id).maybeSingle();
    if (profile?['active'] != true) return [];
    final rows = await client.from('user_roles').select('role').eq('user_id', id);
    return [for (final row in rows) row['role'] as String];
  }

  Future<List<OperatorRecord>> operators() async {
    final rows = await client.from('armateurs').select('id,name,bic').eq('active', true).order('name');
    return [for (final row in rows) OperatorRecord.fromJson(row)];
  }

  Future<Map<String, dynamic>?> container(String number) async => client
      .from('containers').select('number,iso_code,armateur_id').eq('number', number)
      .maybeSingle();

  Future<String> enter({required String plate, required String cin,
      required String kind, required String iso, required String armateur,
      String? containerNumber, String? booking, bool isTwin = false,
      String? containerNumber2, String? iso2, String? armateur2, String? booking2,
      String? orderItemId, String? orderItemId2}) async {
    final result = await client.rpc('enter_transport_visit', params: {
      'p_plate': plate, 'p_cin': cin, 'p_entry_kind': kind,
      'p_container': containerNumber, 'p_order_item':orderItemId,
      'p_iso': iso, 'p_armateur': armateur,
      'p_is_twin': isTwin,
      'p_container_2': containerNumber2,
      'p_iso_2': iso2,
      'p_armateur_2': armateur2,
      'p_order_item_2':orderItemId2,
    });
    return result as String;
  }

  Future<List<TruckVisit>> visits({bool insideOnly = true}) async {
    var query = client.from('truck_visits').select(
      'id,plate,driver_cin,entry_kind,container_number,iso_code,armateur_id,'
      'entered_at,engin_at,exited_at,canceled_at,is_twin,container_number_2,'
      'iso_code_2,armateur_id_2,booking_reference_2,carrier_booking_reference,bookings(reference)',
    );
    if (insideOnly) query = query.isFilter('exited_at', null).isFilter('canceled_at', null);
    final rows = await query.order('entered_at', ascending: true).limit(500);
    return [for (final row in rows) TruckVisit.fromJson(row)];
  }

  Future<List<Map<String, dynamic>>> stock({String? iso, String? armateur}) async {
    var query = client.from('container_stock_intervals').select(
      'id,container_number,iso_code,armateur_id,arrived_at,position,client_id',
    ).isFilter('departed_at', null);
    if (iso != null) query = query.eq('iso_code', iso);
    if (armateur != null) query = query.eq('armateur_id', armateur);
    return List<Map<String, dynamic>>.from(await query.order('arrived_at'));
  }

  Future<void> engin(String visitId, {String? containerNumber, String? position}) async {
    await client.rpc('perform_engin', params: {
      'p_visit': visitId,
      'p_container': containerNumber,
      'p_position': position,
    });
  }

  Future<String> forcePickup(String visitId, String containerNumber, String reason) async {
    final result = await client.rpc('force_pickup_without_stock', params: {
      'p_visit': visitId,
      'p_container': containerNumber,
      'p_reason': reason,
    });
    return result as String;
  }

  Future<List<Map<String, dynamic>>> forcedActions() async =>
      List<Map<String, dynamic>>.from(await client.from('forced_container_actions')
          .select('id,visit_id,container_number,action,reason,actor_id,occurred_at,'
              'resolved_at,external_reference')
          .isFilter('resolved_at', null)
          .order('occurred_at', ascending: true).limit(500));

  Future<void> resolveForcedAction(String id, String externalReference) async {
    await client.rpc('resolve_forced_action', params: {
      'p_action': id,
      'p_external_reference': externalReference,
    });
  }

  Future<void> exit(String visitId) async {
    await client.rpc('exit_truck', params: {'p_visit': visitId});
  }

  Future<void> exitWithDetails(String visitId, {
    String? pickupContainer,
    String? pickupIso,
    String? pickupArmateur,
    bool isTwin = false,
    String? pickupContainer2,
    String? pickupIso2,
    String? pickupArmateur2,
    bool emptyExitWithoutPickup = false,
  }) async {
    await client.rpc('exit_truck_with_details', params: {
      'p_visit': visitId,
      'p_pickup_container': pickupContainer,
      'p_pickup_iso': pickupIso,
      'p_pickup_armateur': pickupArmateur,
      'p_is_twin': isTwin,
      'p_pickup_container_2': pickupContainer2,
      'p_pickup_iso_2': pickupIso2,
      'p_pickup_armateur_2': pickupArmateur2,
      'p_empty_exit_without_pickup': emptyExitWithoutPickup,
    });
  }

  Future<void> cancel(String visitId, String reason, {String? adminCode}) async {
    final params = <String, dynamic>{
      'p_visit': visitId,
      'p_reason': reason,
    };
    if (adminCode != null && adminCode.isNotEmpty) {
      params['p_admin_code'] = adminCode;
    }
    await client.rpc('cancel_visit', params: params);
  }

  Future<List<Map<String, dynamic>>> events(String visitId) async =>
      List<Map<String, dynamic>>.from(await client.from('visit_events')
          .select('action,occurred_at,actor_id,details').eq('visit_id', visitId)
          .order('occurred_at'));

  Future<List<Map<String, dynamic>>> documents() async =>
      List<Map<String, dynamic>>.from(await client.from('generated_documents')
          .select('id,visit_id,event_id,kind,status,storage_path,created_at,snapshot')
          .order('created_at', ascending: false).limit(200));

  Future<Map<String, dynamic>> createAgent({
    required String phone,
    required String firstName,
    required String lastName,
    required String role,
    required String password,
    String? avatarUrl,
    String? adminCode,
  }) async {
    final res = await client.rpc('admin_create_agent', params: {
      'p_phone': phone,
      'p_first_name': firstName,
      'p_last_name': lastName,
      'p_role': role,
      'p_password': password,
      'p_avatar_url': avatarUrl,
      'p_admin_code': adminCode ?? '01010909',
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> listAgents() async {
    final rows = await client.rpc('admin_list_agents');
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
  }

  Future<Map<String, dynamic>> updateAgent({
    required String userId,
    required String phone,
    required String firstName,
    required String lastName,
    required String role,
    String? password,
    bool active = true,
    String? adminCode,
  }) async {
    final res = await client.rpc('admin_update_agent', params: {
      'p_user_id': userId,
      'p_phone': phone,
      'p_first_name': firstName,
      'p_last_name': lastName,
      'p_role': role,
      'p_password': password,
      'p_active': active,
      'p_admin_code': adminCode ?? '01010909',
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> dashboardKpis([DateTime? day]) async {
    final target = day ?? DateTime.now();
    final dStr = '${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
    final res = await client.rpc('admin_dashboard_kpis', params: {'p_day': dStr});
    return Map<String, dynamic>.from(res as Map);
  }

  static String normalizePhone(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 9 && (digits.startsWith('6') || digits.startsWith('7'))) {
      return '0$digits';
    } else if (digits.length == 12 && digits.startsWith('212')) {
      return '0${digits.substring(3)}';
    } else if (digits.length == 10 && digits.startsWith('0')) {
      return digits;
    }
    return digits;
  }
}

class DataTransaction {
  DataTransaction.fromJson(Map<String, dynamic> json)
      : visit = TruckVisit.fromJson(json),
        number = json['transaction_number']?.toString() ?? json['id'] as String,
        creator = json['creator_name'] as String,
        changer = json['changer_name'] as String,
        changedAt = DateTime.parse(json['changed_at'] as String),
        clientId = json['client_id'] as String?,
        clientName = json['client_name'] as String?,
        clientOrder = json['client_order_reference'] as String?,
        bookingArmateur = json['carrier_booking_armateur_id'] as String?,
        bookingArmateur2 = json['carrier_booking_armateur_id_2'] as String?;

  final TruckVisit visit;
  final String number, creator, changer;
  final DateTime changedAt;
  final String? clientId, clientName, clientOrder, bookingArmateur, bookingArmateur2;
  String get type => visit.entryKind == 'loaded' ? 'Réception' : 'Livraison';
  String get status => visit.canceledAt != null ? 'Annulée'
      : visit.exitedAt != null ? 'Sorti' : 'Présent';
  String get containers => [visit.container, visit.container2]
      .whereType<String>().where((s) => s.isNotEmpty).join(' / ');
  String get bookings => [visit.booking, visit.booking2]
      .whereType<String>().where((s) => s.isNotEmpty).join(' / ');
  bool matches(String query) => [number, type, status, creator, changer,
      visit.plate, containers, bookings, visit.armateur, visit.armateur2 ?? '',
      clientName ?? '', clientOrder ?? '']
      .join(' ').toLowerCase().contains(query.trim().toLowerCase());
}
