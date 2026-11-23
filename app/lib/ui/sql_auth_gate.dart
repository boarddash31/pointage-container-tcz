part of '../main.dart';

class SqlAuthGate extends StatefulWidget {
  const SqlAuthGate({super.key, this.api});
  final SqlServerApi? api;
  @override
  State<SqlAuthGate> createState() => _SqlAuthGateState();
}

class _SqlAuthGateState extends State<SqlAuthGate> {
  late final SqlServerApi api;
  late final PointageRepository repository;
  late final StreamSubscription<SqlSessionInfo?> subscription;
  bool restoring = true;
  Object? restoreError;
  @override
  void initState() {
    super.initState();
    api =
        widget.api ??
        SqlServerApi(
          baseUri: Uri.base.resolve('/'),
          allowInsecureHttp: const bool.fromEnvironment('POINTAGE_ALLOW_HTTP'),
          storage: browserSessionStorage(),
        );
    repository = PointageRepository.sql(api);
    subscription = api.sessionChanges.listen((_) {
      if (mounted) setState(() {});
    });
    restore();
  }

  Future<void> restore() async {
    setState(() {
      restoring = true;
      restoreError = null;
    });
    try {
      await api.restoreSession();
    } catch (e) {
      if (mounted) setState(() => restoreError = e);
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  @override
  void dispose() {
    subscription.cancel();
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (restoring) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Vérification de la session',
          ),
        ),
      );
    }
    if (restoreError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Impossible de vérifier votre session pour le moment.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: restore,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final info = api.session;
    if (info == null) return SqlLoginScreen(api: api);
    if (info.mustChangePassword) {
      return SqlLoginScreen(
        key: const ValueKey('change-password'),
        api: api,
        changePassword: true,
      );
    }
    return PointageShell(key: ValueKey(info.userId), repository: repository);
  }
}

class SqlLoginScreen extends StatefulWidget {
  const SqlLoginScreen({
    super.key,
    required this.api,
    this.changePassword = false,
  });
  final SqlServerApi api;
  final bool changePassword;
  @override
  State<SqlLoginScreen> createState() => _SqlLoginScreenState();
}

class _SqlLoginScreenState extends State<SqlLoginScreen> {
  final identifier = TextEditingController(),
      password = TextEditingController(),
      next = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false, obscure = true;
  String? error;
  @override
  void dispose() {
    identifier.dispose();
    password.dispose();
    next.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (widget.changePassword &&
        (next.text.length < 12 || next.text != confirmation.text)) {
      setState(
        () => error =
            'Saisissez deux mots de passe identiques, de 12 caractères minimum.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.changePassword) {
        await widget.api.changePassword(
          currentPassword: password.text,
          newPassword: next.text,
        );
      } else {
        await widget.api.login(
          username: identifier.text.trim(),
          password: password.text,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: TczBrand(width: 220)),
                  const SizedBox(height: 18),
                  Text(
                    widget.changePassword
                        ? 'Choisir votre mot de passe'
                        : 'Gestion des flux',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  if (!widget.changePassword)
                    TextField(
                      controller: identifier,
                      decoration: const InputDecoration(
                        labelText: 'Identifiant',
                        hintText: 'Nom d’utilisateur ou e-mail',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: obscure,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: widget.changePassword
                          ? 'Mot de passe temporaire ou actuel'
                          : 'Mot de passe',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                  if (widget.changePassword) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: next,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText:
                            'Nouveau mot de passe (12 caractères minimum)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmation,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmer le nouveau mot de passe',
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(
                      busy
                          ? 'Veuillez patienter…'
                          : widget.changePassword
                          ? 'Enregistrer et se reconnecter'
                          : 'Se connecter',
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => widget.changePassword
                              ? widget.api.logout()
                              : showDialog<void>(
                                  context: context,
                                  builder: (d) => AlertDialog(
                                    title: const Text('Mot de passe oublié'),
                                    content: const Text(
                                      'Demandez à un administrateur de réinitialiser votre mot de passe.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(d),
                                        child: const Text('Fermer'),
                                      ),
                                    ],
                                  ),
                                ),
                    child: Text(
                      widget.changePassword
                          ? 'Se déconnecter'
                          : 'Mot de passe oublié ?',
                    ),
                  ),
                  const Text(
                    'Utilisez le compte attribué par votre administrateur.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
