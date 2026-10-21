import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data/pointage_repository.dart';
import 'ui/pointage_screens.dart';
import 'ui/admin_screen.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const authSiteUrl = String.fromEnvironment('AUTH_SITE_URL');

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
  bool busy = false; String? error, notice;
  @override void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  Future<void> signIn() async {
    final targetEmail = email.text.trim();
    final targetPassword = password.text;
    setState(() { busy=true; error=null; notice=null; });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: targetEmail, password: targetPassword);
    } catch (e) {
      if (mounted) {
        final raw = e.toString();
        if (raw.contains('Invalid login credentials')) {
          setState(() => error = 'Identifiants incorrects. Vérifiez l’e-mail et le mot de passe.');
        } else {
          setState(() => error = raw);
        }
      }
    }
    finally { if (mounted) setState(() => busy=false); }
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
      const Icon(Icons.local_shipping_rounded,size:52,color:Color(0xff075a8d)),
      const SizedBox(height:14),
      Text('Pointage Container',textAlign:TextAlign.center,style:Theme.of(context).textTheme.headlineMedium),
      const Text('Terminal TCZ · Connexion agent',textAlign:TextAlign.center),
      const SizedBox(height:28),
      TextField(controller:email,keyboardType:TextInputType.emailAddress,
        decoration:const InputDecoration(labelText:'E-mail professionnel')),
      const SizedBox(height:12),
      TextField(controller:password,obscureText:true,onSubmitted:(_)=>signIn(),
        decoration:const InputDecoration(labelText:'Mot de passe')),
      if(error!=null) Padding(padding:const EdgeInsets.only(top:12),
        child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      if(notice!=null) Padding(padding:const EdgeInsets.only(top:12),
        child:Text(notice!,style:TextStyle(color:Theme.of(context).colorScheme.primary))),
      const SizedBox(height:16),
      FilledButton(onPressed:busy?null:()=>signIn(),child:Text(busy?'Connexion…':'Se connecter')),
      TextButton(onPressed:busy?null:requestRecovery,
        child:const Text('Mot de passe oublié ?')),
      const SizedBox(height:10),
      const Text('Utilisez le compte et le rôle attribués par votre administrateur.',
        textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:Color(0xff49677e))),
      if(kIsWeb) Padding(padding:const EdgeInsets.only(top:10),
        child:TextButton.icon(onPressed:()=>launchUrl(
          Uri.base.resolve('downloads/pointage-tcz.apk'),
          mode:LaunchMode.externalApplication),
          icon:const Icon(Icons.android),label:const Text('Télécharger l’APK Android'))),
    ])))))));
}

class PointageShell extends StatefulWidget {
  const PointageShell({super.key,required this.repository});
  final PointageRepository repository;
  @override State<PointageShell> createState() => _PointageShellState();
}
class _PointageShellState extends State<PointageShell> {
  int section=0,process=0;
  late Future<List<String>> roleFuture;
  @override void initState(){super.initState();roleFuture=widget.repository.roles();}
  @override Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future:roleFuture,builder:(context,snapshot){
      if(snapshot.hasError){return Scaffold(
        appBar:AppBar(title:const Text('Accès indisponible')),
        body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Impossible de vérifier les rôles de ce compte.'),
          const SizedBox(height:12),
          FilledButton(onPressed:()=>setState((){roleFuture=widget.repository.roles();}),
            child:const Text('Réessayer')),
        ])));}
      if(!snapshot.hasData) return const Scaffold(body:Center(child:CircularProgressIndicator()));
      final roles=snapshot.data!;
      if(roles.isEmpty) {
        return Scaffold(appBar:AppBar(title:const Text('Accès indisponible'),actions:[
          IconButton(tooltip:'Déconnexion',icon:const Icon(Icons.logout),
            onPressed:()=>Supabase.instance.client.auth.signOut()),
        ]),body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Padding(padding:EdgeInsets.symmetric(horizontal:24),
            child:Text('Ce compte est désactivé ou n’a aucun rôle actif.',textAlign:TextAlign.center)),
          const SizedBox(height:12),
          FilledButton.icon(onPressed:()=>Supabase.instance.client.auth.signOut(),
            icon:const Icon(Icons.logout),label:const Text('Se déconnecter')),
        ])));
      }
      final admin=roles.contains('admin');
      bool allowed(String role)=>admin||roles.contains(role);
      final canEnter=allowed('entree'),canExit=allowed('sortie');
      final activeProcess=canEnter&&canExit?process:(canEnter?0:1);
      final repo=widget.repository;
      final screens=<Widget>[
        switch(activeProcess){
          0=>allowed('entree')?EntryScreen(repository:repo,canCorrect:admin)
              :const PermissionScreen(role:'Entrée'),
          _=>allowed('sortie')?ExitScreen(repository:repo,canCancel:admin)
              :const PermissionScreen(role:'Sortie'),
        },
        DataScreen(repository:repo),
        BonsScreen(repository:repo),
      ];
      final body=SafeArea(child:KeyedSubtree(
        key:ValueKey('$section-$process'),
        child:screens[section]));
      final destinations=const [NavigationDestination(icon:Icon(Icons.rule),label:'Pointage'),
        NavigationDestination(icon:Icon(Icons.dataset),label:'Data'),
        NavigationDestination(icon:Icon(Icons.description),label:'Bons')];
      return Scaffold(
        appBar:AppBar(
          titleSpacing:8,
          centerTitle:true,
          title:section==0
            ? (canEnter&&canExit?Container(
                height:38,
                constraints:const BoxConstraints(maxWidth:240),
                padding:const EdgeInsets.all(3),
                decoration:BoxDecoration(
                  color:Colors.black.withValues(alpha:0.25),
                  borderRadius:BorderRadius.circular(9)),
                child:Row(children:[
                  for(var i=0;i<2;i++)
                    Expanded(child:InkWell(
                      borderRadius:BorderRadius.circular(7),
                      onTap:()=>setState(()=>process=i),
                      child:Container(
                        alignment:Alignment.center,
                        decoration:BoxDecoration(
                          color:activeProcess==i?Colors.white:Colors.transparent,
                          borderRadius:BorderRadius.circular(7)),
                        child:Text(['Entrée','Sortie'][i],
                          style:TextStyle(
                            fontSize:13,
                            fontWeight:activeProcess==i?FontWeight.bold:FontWeight.w500,
                            color:activeProcess==i?const Color(0xff063e66):Colors.white)),
                      ))),
                ])):Text(canEnter?'Entrée':'Sortie'))
            : Text(section==1?'Data · Référentiel':'Bons · Documents'),
          backgroundColor:const Color(0xff063e66),foregroundColor:Colors.white,
          actions:[
            if(admin)IconButton(tooltip:'Administration',icon:const Icon(Icons.admin_panel_settings),
              onPressed:()=>Navigator.push(context,MaterialPageRoute(
                builder:(_)=>AdminScreen(repository:repo)))),
            IconButton(tooltip:'Déconnexion',icon:const Icon(Icons.logout),
              onPressed:()=>Supabase.instance.client.auth.signOut()),
          ]),
        body:LayoutBuilder(builder:(context,c)=>c.maxWidth>900?
          Row(children:[NavigationRail(selectedIndex:section,
            onDestinationSelected:(i)=>setState(()=>section=i),labelType:NavigationRailLabelType.all,
            destinations:const [NavigationRailDestination(icon:Icon(Icons.rule),label:Text('Pointage')),
              NavigationRailDestination(icon:Icon(Icons.dataset),label:Text('Data')),
              NavigationRailDestination(icon:Icon(Icons.description),label:Text('Bons'))]),
            const VerticalDivider(width:1),Expanded(child:body)]):body),
        bottomNavigationBar:MediaQuery.sizeOf(context).width>900?null:
          NavigationBar(selectedIndex:section,destinations:destinations,
            onDestinationSelected:(i)=>setState(()=>section=i)),
      );
    });
}

class PermissionScreen extends StatelessWidget {
  const PermissionScreen({super.key,required this.role}); final String role;
  @override Widget build(BuildContext context) => Center(child:Text('Accès $role non autorisé pour ce compte.'));
}
