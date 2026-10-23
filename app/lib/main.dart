import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data/pointage_repository.dart';
import 'ui/pointage_screens.dart';
import 'ui/admin_screen.dart';
import 'ui/tcz_brand.dart';
import 'utils/fullscreen_helper.dart';

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://iparzfqxopcvwqelxlad.supabase.co',
);
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_AgyGT1cfJz9gkXTpVrLsXg_B3VNWHGs',
);
const authSiteUrl = String.fromEnvironment(
  'AUTH_SITE_URL',
  defaultValue: 'https://marsa.digital',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  }
  runApp(const PointageApp());
}

class PointageApp extends StatelessWidget {
  const PointageApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pointage Container · TCZ',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff075a8d),
        primary: const Color(0xff075a8d), secondary: const Color(0xff087e79)),
      scaffoldBackgroundColor: const Color(0xfff2f6fa),
      cardTheme: CardThemeData(color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
    ),
    home: supabaseUrl.isEmpty || supabasePublishableKey.isEmpty
      ? const Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(24),
          child: Text('Configuration Supabase manquante. Fournissez SUPABASE_URL et '
            'SUPABASE_PUBLISHABLE_KEY via --dart-define.'))))
      : const AuthGate(),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _subscription;
  bool recoveryFlow = kIsWeb && Uri.base.queryParameters['auth'] == 'recovery';
  @override void initState() {
    super.initState();
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (mounted) {
        setState(() {
          if (state.event == AuthChangeEvent.passwordRecovery) {
            recoveryFlow = true;
          }
          if (state.event == AuthChangeEvent.signedOut) {
            recoveryFlow = false;
          }
        });
      }
    });
  }
  @override void dispose() { _subscription.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final auth=Supabase.instance.client.auth;
    if(auth.currentSession==null)return const LoginScreen();
    if(recoveryFlow || auth.currentUser?.userMetadata?['must_set_password']==true){
      return PasswordSetupScreen(onComplete: () => setState(() => recoveryFlow = false));
    }
    return PointageShell(key: ValueKey(auth.currentUser!.id),
      repository: PointageRepository(Supabase.instance.client));
  }
}

class PasswordSetupScreen extends StatefulWidget {
  const PasswordSetupScreen({super.key,required this.onComplete});
  final VoidCallback onComplete;
  @override State<PasswordSetupScreen> createState()=>_PasswordSetupScreenState();
}
class _PasswordSetupScreenState extends State<PasswordSetupScreen> {
  final password=TextEditingController(),confirmation=TextEditingController();
  bool busy=false;String? error;
  @override void dispose(){password.dispose();confirmation.dispose();super.dispose();}
  Future<void> save() async {
    if(password.text.length<12||password.text!=confirmation.text){
      setState(()=>error='Utilisez au moins 12 caractères identiques dans les deux champs.');return;
    }
    setState((){busy=true;error=null;});
    try{
      await Supabase.instance.client.auth.updateUser(UserAttributes(
        password:password.text,data:{'must_set_password':false}));
      if(kIsWeb && Uri.base.queryParameters['auth']=='recovery') {
        await SystemNavigator.routeInformationUpdated(uri:Uri(path:'/'),replace:true);
      }
      if(mounted) widget.onComplete();
    }catch(e){if(mounted)setState(()=>error='Mot de passe refusé : $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(body:Center(child:
    SingleChildScrollView(padding:const EdgeInsets.all(16),child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:420),child:Card(child:Padding(
        padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text('Activer votre compte TCZ',style:Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height:12),const Text('Définissez votre mot de passe avant de commencer.'),
          const SizedBox(height:20),
          TextField(controller:password,obscureText:true,
            decoration:const InputDecoration(labelText:'Nouveau mot de passe')),
          const SizedBox(height:12),
          TextField(controller:confirmation,obscureText:true,onSubmitted:(_)=>save(),
            decoration:const InputDecoration(labelText:'Confirmer le mot de passe')),
          if(error!=null)Padding(padding:const EdgeInsets.only(top:12),
            child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
          const SizedBox(height:20),
          FilledButton(onPressed:busy?null:save,child:Text(busy?'Enregistrement…':'Activer le compte')),
          TextButton(onPressed:()=>Supabase.instance.client.auth.signOut(),
            child:const Text('Se déconnecter')),
        ])))))));
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(), password = TextEditingController();
  final passwordFocus = FocusNode();
  String? selectedProfile;
  bool obscurePassword = false;
  bool busy = false; String? error, notice;
  static const quickProfiles = [
    ('Admin', 'dahhaknouamane@gmail.com', Icons.admin_panel_settings_rounded),
    ('Entrée', 'dahhaknouamane+tcz-entree@gmail.com', Icons.login_rounded),
    ('Sortie', 'dahhaknouamane+tcz-sortie@gmail.com', Icons.logout_rounded),
  ];

  void chooseProfile(String label, String address) {
    setState(() {
      selectedProfile = label;
      email.value = TextEditingValue(
        text: address,
        selection: TextSelection.collapsed(offset: address.length),
      );
      password.clear();
      error = null;
      notice = null;
    });
    FocusScope.of(context).requestFocus(passwordFocus);
  }

  @override void dispose() { email.dispose(); password.dispose(); passwordFocus.dispose(); super.dispose(); }
  Future<void> signIn() async {
    final rawInput = email.text.trim();
    final targetPassword = password.text;
    if (rawInput.isEmpty || targetPassword.isEmpty) {
      setState(() => error = 'Veuillez renseigner votre téléphone (ou e-mail) et mot de passe.');
      return;
    }
    if (kIsWeb && MediaQuery.sizeOf(context).width < 800) {
      FullscreenHelper.requestBrowserFullscreen();
    }
    setState(() { busy = true; error = null; notice = null; });
    try {
      String targetEmail = rawInput;
      // If user provided a phone number (no @ symbol)
      if (!rawInput.contains('@')) {
        final clean = PointageRepository.normalizePhone(rawInput);
        try {
          final res = await Supabase.instance.client.rpc('get_login_identifier', params: {
            'p_identifier': rawInput,
          });
          if (res is Map && res['email'] != null && res['email'].toString().isNotEmpty) {
            targetEmail = res['email'].toString();
          } else {
            targetEmail = '$clean@tcz.local';
          }
        } catch (_) {
          targetEmail = '$clean@tcz.local';
        }
      }

      await Supabase.instance.client.auth.signInWithPassword(
        email: targetEmail, password: targetPassword);
    } catch (e) {
      if (mounted) {
        final raw = e.toString();
        if (raw.contains('Invalid login credentials')) {
          setState(() => error = 'Identifiants incorrects. Vérifiez votre numéro de téléphone et votre mot de passe.');
        } else {
          setState(() => error = raw);
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  Future<void> requestRecovery() async {
    final address=email.text.trim();
    if(!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
      setState(()=>error='Saisissez votre e-mail professionnel pour recevoir le lien.');
      return;
    }
    setState(() { busy=true; error=null; notice=null; });
    try {
      final base=authSiteUrl.isNotEmpty ? Uri.parse(authSiteUrl) : (kIsWeb ? Uri.base : null);
      final redirect=base?.replace(path:'/',queryParameters:{'auth':'recovery'},fragment:'');
      await Supabase.instance.client.auth.resetPasswordForEmail(address,
        redirectTo:redirect?.toString());
      if(mounted) setState(()=>notice='Si ce compte existe, un lien de réinitialisation a été envoyé. Vérifiez votre boîte e-mail.');
    } catch (_) {
      if(mounted) setState(()=>error='Envoi impossible pour le moment. Réessayez plus tard.');
    } finally { if(mounted) setState(()=>busy=false); }
  }
  @override Widget build(BuildContext context) => Scaffold(body: Center(child: SingleChildScrollView(
    padding:const EdgeInsets.all(16),child:ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 440),
    child: Card(child: Padding(padding: const EdgeInsets.all(28),child: Column(
      mainAxisSize: MainAxisSize.min,crossAxisAlignment: CrossAxisAlignment.stretch,children: [
      const Center(child:TczBrand(width:220)),
      const SizedBox(height:14),
      Text('Pointage Container',textAlign:TextAlign.center,style:Theme.of(context).textTheme.headlineMedium),
      const Text('Terminal TCZ · Connexion agent',textAlign:TextAlign.center),
      const SizedBox(height:20),

      Row(
        children: [
          for (var i = 0; i < quickProfiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonal(
                key: ValueKey('quick-profile-${quickProfiles[i].$1.toLowerCase()}'),
                style: FilledButton.styleFrom(
                  backgroundColor: selectedProfile == quickProfiles[i].$1
                      ? const Color(0xffcdebf1)
                      : const Color(0xffeef5f8),
                  foregroundColor: const Color(0xff063e66),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: busy ? null : () => chooseProfile(
                  quickProfiles[i].$1, quickProfiles[i].$2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(quickProfiles[i].$3, size: 17),
                    const SizedBox(width: 5),
                    Flexible(child: Text(quickProfiles[i].$1,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height:14),

      Column(children:[
        TextField(controller:email,keyboardType:TextInputType.text,
          onChanged:(_){if(selectedProfile!=null)setState(()=>selectedProfile=null);},
          decoration:const InputDecoration(
            labelText:'Numéro de téléphone ou e-mail',
            hintText:'Ex: 0661998877 ou agent@tcz.ma',
            prefixIcon:Icon(Icons.person_pin_rounded,size:20),
          )),
        const SizedBox(height:12),
        TextField(controller:password,focusNode:passwordFocus,
          obscureText:obscurePassword,onSubmitted:(_)=>signIn(),
          decoration:InputDecoration(
            labelText:'Mot de passe',
            prefixIcon:const Icon(Icons.lock_outline,size:20),
            suffixIcon:IconButton(
              tooltip: obscurePassword ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
              icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
              onPressed: () => setState(() => obscurePassword = !obscurePassword),
            ),
          )),
      ]),
      if(error!=null) Padding(padding:const EdgeInsets.only(top:12),
        child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      if(notice!=null) Padding(padding:const EdgeInsets.only(top:12),
        child:Text(notice!,style:TextStyle(color:Theme.of(context).colorScheme.primary))),
      const SizedBox(height:16),
      FilledButton(onPressed:busy?null:()=>signIn(),child:Text(busy?'Connexion…':'Se connecter')),
      TextButton(onPressed:busy?null:requestRecovery,
        child:const Text('Mot de passe oublié ?')),
      const SizedBox(height:8),
      if(kIsWeb) Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xff063e66),
            side: const BorderSide(color: Color(0xffc5d9e8)),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => launchUrl(Uri.base.resolve('dashboard.html'), mode: LaunchMode.platformDefault),
          icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
          label: const Text('Tableau de Bord Superviseur (Web)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ),
      const Text('Saisissez votre numéro de téléphone (ou email) et votre mot de passe attribué.',
        textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:Color(0xff49677e))),
    ])))))));
}

class PointageShell extends StatefulWidget {
  const PointageShell({super.key,required this.repository});
  final PointageRepository repository;
  @override State<PointageShell> createState() => _PointageShellState();
}
class _PointageShellState extends State<PointageShell> {
  int section = 0, process = 0;
  bool? _isFullScreenUserPref;
  late Future<List<String>> roleFuture;
  @override void initState() { super.initState(); roleFuture = widget.repository.roles(); }
  @override Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: roleFuture, builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('Accès indisponible')),
          body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Impossible de vérifier les rôles de ce compte.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => setState(() { roleFuture = widget.repository.roles(); }),
              child: const Text('Réessayer')),
          ])),
        );
      }
      if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final roles = snapshot.data!;
      if (roles.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('Accès indisponible'), actions: [
            IconButton(tooltip: 'Déconnexion', icon: const Icon(Icons.logout),
              onPressed: () => Supabase.instance.client.auth.signOut()),
          ]),
          body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('Ce compte est désactivé ou n’a aucun rôle actif.', textAlign: TextAlign.center)),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout), label: const Text('Se déconnecter')),
          ])),
        );
      }
      final admin = roles.contains('admin');
      bool allowed(String role) => admin || roles.contains(role);
      final canEnter = allowed('entree'), canExit = allowed('sortie');
      final activeProcess = canEnter && canExit ? process : (canEnter ? 0 : 1);
      final repo = widget.repository;

      final isMobile = MediaQuery.sizeOf(context).width < 800;
      // Start the operational Pointage screen in its focused layout on every
      // form factor. Data and Bons keep the regular navigation when selected.
      final isFullScreen = _isFullScreenUserPref ?? (section == 0);

      final screens = <Widget>[
        switch (activeProcess) {
          0 => allowed('entree') ? EntryScreen(
                repository: repo,
                canCorrect: admin,
                isFullScreen: isFullScreen,
                onToggleFullScreen: () {
                  FullscreenHelper.toggleBrowserFullscreen();
                  setState(() => _isFullScreenUserPref = !isFullScreen);
                },
                onSwitchProcess: (canEnter && canExit) ? () => setState(() => process = 1) : null,
              )
              : const PermissionScreen(role: 'Entrée'),
          _ => allowed('sortie') ? ExitScreen(
                repository: repo,
                canCancel: admin,
                isFullScreen: isFullScreen,
                onToggleFullScreen: () {
                  FullscreenHelper.toggleBrowserFullscreen();
                  setState(() => _isFullScreenUserPref = !isFullScreen);
                },
                onSwitchProcess: (canEnter && canExit) ? () => setState(() => process = 0) : null,
              )
              : const PermissionScreen(role: 'Sortie'),
        },
        DataScreen(repository: repo),
        BonsScreen(repository: repo),
      ];

      final currentScreen = KeyedSubtree(
        key: ValueKey('$section-$process'),
        child: screens[section],
      );

      final destinations = const [
        NavigationDestination(icon: Icon(Icons.rule), label: 'Pointage'),
        NavigationDestination(icon: Icon(Icons.dataset), label: 'Data'),
        NavigationDestination(icon: Icon(Icons.description), label: 'Bons'),
      ];

      Widget content;
      if (isFullScreen) {
        if (isMobile && section == 0) {
          content = SafeArea(child: currentScreen);
        } else {
          content = SafeArea(
            child: Column(
              children: [
                Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                color: const Color(0xff063e66),
                child: Row(
                  children: [
                    // Fullscreen toggle buttons
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        FullscreenHelper.exitBrowserFullscreen();
                        setState(() => _isFullScreenUserPref = false);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white38, width: 1),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_rounded, size: 15, color: Colors.white),
                            SizedBox(width: 3),
                            Text('Menu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => FullscreenHelper.toggleBrowserFullscreen(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.amberAccent, width: 1.2),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fullscreen_rounded, size: 16, color: Colors.amberAccent),
                            SizedBox(width: 3),
                            Text('F11', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Process toggle (Entrée / Sortie)
                    if (canEnter && canExit)
                      Container(
                        height: 32,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < 2; i++)
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => setState(() => process = i),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: activeProcess == i ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    ['Entrée', 'Sortie'][i],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: activeProcess == i ? FontWeight.bold : FontWeight.w600,
                                      color: activeProcess == i ? const Color(0xff063e66) : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      Text(
                        canEnter ? 'ENTRÉE GATE-IN' : 'SORTIE GATE-OUT',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.8),
                      ),
                    const Spacer(),
                    if (admin && kIsWeb)
                      IconButton(
                        tooltip: 'Tableau de Bord',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.dashboard_customize_rounded, size: 19, color: Colors.white),
                        onPressed: () => launchUrl(Uri.base.resolve('dashboard.html'), mode: LaunchMode.platformDefault),
                      ),
                    IconButton(
                      tooltip: 'Se déconnecter',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(Icons.logout, size: 20, color: Colors.white70),
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                    ),
                  ],
                ),
              ),
              Expanded(child: currentScreen),
            ],
          ),
        );
      }
    } else {
        content = SafeArea(child: currentScreen);
        if (MediaQuery.sizeOf(context).width > 900) {
          content = Row(children: [
            NavigationRail(
              selectedIndex: section,
              onDestinationSelected: (i) => setState(() => section = i),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.rule), label: Text('Pointage')),
                NavigationRailDestination(icon: Icon(Icons.dataset), label: Text('Data')),
                NavigationRailDestination(icon: Icon(Icons.description), label: Text('Bons')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ]);
        }
      }

      return Scaffold(
        appBar: isFullScreen ? null : AppBar(
          leadingWidth: isMobile ? 54 : 86,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Center(child: TczBrand(width: isMobile ? 44 : 72, onDark: true)),
          ),
          titleSpacing: 4,
          centerTitle: true,
          title: section == 0
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canEnter && canExit)
                    Container(
                      height: 34,
                      constraints: BoxConstraints(maxWidth: isMobile ? 140 : 220),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < 2; i++)
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => setState(() => process = i),
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: activeProcess == i ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    ['Entrée', 'Sortie'][i],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: activeProcess == i ? FontWeight.bold : FontWeight.w500,
                                      color: activeProcess == i ? const Color(0xff063e66) : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    Text(canEnter ? 'Entrée' : 'Sortie'),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      FullscreenHelper.requestBrowserFullscreen();
                      setState(() => _isFullScreenUserPref = true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.amberAccent, width: 1.2),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fullscreen_rounded, color: Colors.amberAccent, size: 18),
                          SizedBox(width: 3),
                          Text('Plein écran F11', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Text(section == 1 ? 'Data · Référentiel' : 'Bons · Documents'),
          backgroundColor: const Color(0xff063e66),
          foregroundColor: Colors.white,
          actions: [
            if (admin) ...[
              if (kIsWeb)
                IconButton(
                  tooltip: 'Tableau de Bord Superviseur (Web)',
                  icon: const Icon(Icons.dashboard_customize_rounded),
                  onPressed: () => launchUrl(Uri.base.resolve('dashboard.html'), mode: LaunchMode.platformDefault),
                ),
              if (!isMobile)
                IconButton(
                  tooltip: 'Administration',
                  icon: const Icon(Icons.admin_panel_settings),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminScreen(repository: repo))),
                ),
            ],
            IconButton(
              tooltip: 'Déconnexion',
              icon: const Icon(Icons.logout),
              onPressed: () => Supabase.instance.client.auth.signOut(),
            ),
          ],
        ),
        body: content,
        bottomNavigationBar: (isFullScreen || MediaQuery.sizeOf(context).width > 900) ? null :
          NavigationBar(
            selectedIndex: section,
            destinations: destinations,
            onDestinationSelected: (i) => setState(() => section = i),
          ),
      );
    });
}

class PermissionScreen extends StatelessWidget {
  const PermissionScreen({super.key,required this.role}); final String role;
  @override Widget build(BuildContext context) => Center(child:Text('Accès $role non autorisé pour ce compte.'));
}
