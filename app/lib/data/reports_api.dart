import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sqlserver_api.dart';

class ReportsApi {
  ReportsApi(this.auth, {http.Client? transport, Uri? origin})
      : transport = transport ?? http.Client(), origin = origin ?? Uri.base,sql=null;
  ReportsApi.sql(this.sql,{http.Client? transport,Uri? origin}):auth=null,transport=transport??http.Client(),origin=origin??Uri.base;
  final SupabaseClient? auth;
  final SqlServerApi? sql;
  final http.Client transport;
  final Uri origin;

  Future<http.Response> request(String method, String route, [Object? body]) async {
    var session = auth?.auth.currentSession;
    if (session != null && session.isExpired) session = (await auth!.auth.refreshSession()).session;
    final token = sql?.sessionToken ?? session?.accessToken;
    if (token == null) throw StateError('Veuillez vous reconnecter.');
    final request = http.Request(method, origin.resolve('/api/reports/$route'));
    request.headers.addAll({'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await transport.send(request)).timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String code = 'reports_unavailable';
      try { code = (jsonDecode(response.body) as Map)['error'] as String? ?? code; } catch (_) {}
      throw StateError(messages[code] ?? 'Opération impossible ($code).');
    }
    return response;
  }

  Future<dynamic> json(String method, String route, [Object? body]) async => jsonDecode((await request(method, route, body)).body);
  Future<Uint8List> download(String route, [Object? body]) async => (await request(body == null ? 'GET' : 'POST', route, body)).bodyBytes;
  void close() => transport.close();
  static const messages = {
    'invalid_shift': 'Vérifier le début et la fin du shift au format HH:mm ; les deux heures doivent différer.',
    'invalid_line': 'Armateur invalide.',
    'dedicated_line_required': 'Choisir l’armateur destinataire du rapport dédié.',
    'reports_unavailable': 'Rubrique indisponible. Vérifier la mise à jour du runtime sur le serveur.',
    'configuration_required': 'Configurer le SMTP, le connecteur e-mail et la source serveur avant les envois.',
    'report_source_not_configured': 'La clé de lecture serveur reste à configurer par l’IT.',
    'smtp_driver_unavailable': 'Le connecteur Nodemailer doit être installé par l’IT sur le serveur.',
    'smtp_auth_failed': 'Authentification SMTP refusée.',
    'smtp_connection_failed': 'Connexion SMTP impossible. Vérifier le relais et les accès réseau.',
    'invalid_session': 'Session expirée. Veuillez vous reconnecter.',
    'admin_required': 'Cette rubrique est réservée aux administrateurs actifs.',
    'version_conflict': 'Les paramètres ont changé. Actualiser avant de les modifier.',
    'invalid_recipients': 'Indiquer au moins une adresse e-mail valide (50 au maximum).',
    'invalid_job': 'Vérifier le nom et les paramètres du rapport.',
    'invalid_smtp': 'Vérifier les paramètres SMTP.',
    'smtp_password_required': 'Un mot de passe SMTP est requis pour cet identifiant.',
    'smtp_auth_requires_tls': 'Utiliser STARTTLS ou TLS pour une connexion avec identifiant.',
    'schedule_in_past': 'Choisir une date d’exécution future.',
    'invalid_schedule_date': 'Date ou heure locale invalide.',
    'invalid_schedule_days': 'Vérifier les jours de programmation.',
    'invalid_interval': 'L’intervalle doit être compris entre 5 et 10 080 minutes.',
    'invalid_period': 'La période doit être comprise entre 1 et 744 heures.',
    'data_source_unavailable': 'Source de données indisponible. Vérifier les accès du serveur.',
    'retry_not_allowed': 'Seuls les échecs confirmés peuvent être relancés.',
    'preview_busy': 'Un aperçu est déjà en cours. Réessayer après sa génération.',
  };
}
