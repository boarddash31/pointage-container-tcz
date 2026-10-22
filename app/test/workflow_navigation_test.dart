import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/data/pointage_repository.dart';
import 'package:pointage_container/main.dart';
import 'package:pointage_container/ui/pointage_screens.dart';
import 'package:pointage_container/ui/truck_diagram.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QueueFixture extends PointageRepository {
  QueueFixture() : super(SupabaseClient('https://example.supabase.co', 'publishable-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false)));
  @override Future<List<String>> roles() async => ['entree', 'engin', 'sortie'];
  @override Future<List<OperatorRecord>> operators() async =>
      [const OperatorRecord('MAE', 'Maersk', 'MAEU')];
  @override Future<List<TruckVisit>> visits({bool insideOnly = true}) async => [];
}

class QueueFixtureWithTrucks extends PointageRepository {
  QueueFixtureWithTrucks(this.mockVisits) : super(SupabaseClient('https://example.supabase.co', 'publishable-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final List<TruckVisit> mockVisits;
  @override Future<List<String>> roles() async => ['entree', 'sortie'];
  @override Future<List<OperatorRecord>> operators() async =>
      [const OperatorRecord('MAE', 'Maersk', 'MAEU')];
  @override Future<List<TruckVisit>> visits({bool insideOnly = true}) async => mockVisits;
}

class SingleRoleFixture extends QueueFixture {
  SingleRoleFixture(this.role);
  final String role;
  @override Future<List<String>> roles() async => [role];
}

class NoRoleFixture extends QueueFixture {
  @override Future<List<String>> roles() async => [];
}

void main() {
  testWidgets('inactive account can leave the access screen', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PointageShell(repository: NoRoleFixture())));
    await tester.pumpAndSettle();
    expect(find.text('Ce compte est désactivé ou n’a aucun rôle actif.'), findsOneWidget);
    expect(find.text('Se déconnecter'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('single-role agents open only their permitted gate', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PointageShell(key: const ValueKey('sortie'),
      repository: SingleRoleFixture('sortie'))));
    await tester.pumpAndSettle();
    expect(find.text('Validation de la sortie'), findsOneWidget);
    expect(find.text('Enregistrement de l’entrée'), findsNothing);
    await tester.pumpWidget(MaterialApp(home: PointageShell(key: const ValueKey('entree'),
      repository: SingleRoleFixture('entree'))));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrement de l’entrée'), findsOneWidget);
    expect(find.text('Validation de la sortie'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('operator navigates Entrée and Sortie directly; Sortie requires search before verification',
      (tester) async {
    final sampleVisit = TruckVisit(
      id: 'test-visit-1',
      plate: '12345-A-06',
      cin: 'AB123456',
      entryKind: 'loaded',
      container: 'CSQU3054383',
      booking: null,
      iso: '45G1',
      armateur: 'MAE',
      enteredAt: DateTime.now(),
      enginAt: null,
      exitedAt: null,
      canceledAt: null,
    );
    final repository = QueueFixtureWithTrucks([sampleVisit]);
    await tester.pumpWidget(MaterialApp(home: PointageShell(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('Enregistrement de l’entrée'), findsOneWidget);
    expect(tester.widgetList<TextField>(find.byType(TextField))
        .where((field) => field.inputFormatters?.any(
          (formatter) => formatter is SingleCharOverrideFormatter) == true).length, 11);

    // Engin is hidden from header
    expect(find.text('Engin'), findsNothing);

    // Navigate to Sortie
    await tester.tap(find.text('Sortie'));
    await tester.pumpAndSettle();

    expect(find.text('Validation de la sortie'), findsOneWidget);
    expect(find.text('Plaque ou Conteneur *'), findsOneWidget);

    // Without search, truck details are not shown upfront
    expect(find.text('Saisie requise pour valider la sortie'), findsOneWidget);
    expect(find.text('Données du camion à vérifier'), findsNothing);

    // Enter plate or container in search
    await tester.enterText(find.widgetWithText(TextFormField, 'Plaque ou Conteneur *'), '12345');
    await tester.pumpAndSettle();

    // Verification card is now displayed
    expect(find.text('Données du camion à vérifier'), findsOneWidget);
    expect(find.text('12345-A-06'), findsOneWidget);
    expect(find.text('AB123456'), findsOneWidget);
    expect(find.text('CSQU3054383'), findsOneWidget);
    expect(find.text('45G1'), findsOneWidget);
    expect(find.text('MAE'), findsOneWidget);
    expect(find.text('Valider la sortie du camion'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('VisitActionSheet for loaded truck does not show position field', (tester) async {
    final repository = QueueFixture();
    final visit = TruckVisit(
      id: 'test-visit-1',
      plate: '12345-A-06',
      cin: 'AB123456',
      entryKind: 'loaded',
      container: 'MSCU1234567',
      booking: null,
      iso: '45G1',
      armateur: 'MAE',
      enteredAt: DateTime.now(),
      enginAt: null,
      exitedAt: null,
      canceledAt: null,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VisitActionSheet(
      repository: repository,
      visit: visit,
      canCancel: false,
      exitMode: false,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Position réelle de dépose *'), findsNothing);
    expect(find.text('Valider la dépose'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('EntryScreen supports Twin 2x20 mode with two container inputs', (tester) async {
    final repository = QueueFixture();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EntryScreen(
      repository: repository,
      canCorrect: false,
    ))));
    await tester.pumpAndSettle();

    expect(find.text('Déposer avec 1 conteneur'), findsOneWidget);
    expect(find.text('Déposer avec 2 conteneurs'), findsOneWidget);
    expect(find.text('Prendre avec 1 conteneur'), findsOneWidget);
    expect(find.text('Prendre avec 2 conteneurs'), findsOneWidget);

    // Switch to Twin mode
    await tester.ensureVisible(find.byKey(const ValueKey('gate-loaded-true')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gate-loaded-true')));
    await tester.pumpAndSettle();

    expect(find.text('Premier Conteneur (20\')'), findsOneWidget);
    if (find.byKey(const ValueKey('twin-tab-1')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('twin-tab-1')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Deuxième Conteneur (20\') · Compagnie différente autorisée'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('gate-empty-true')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gate-empty-true')));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('twin-tab-0')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('twin-tab-0')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Booking Conteneur 1 *'), findsOneWidget);
    if (find.byKey(const ValueKey('twin-tab-1')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('twin-tab-1')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Booking Conteneur 2 *'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('truck picture takes the operator to the plate and container fields', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EntryScreen(
      repository: QueueFixture(), canCorrect: false))));
    await tester.pumpAndSettle();
    final preview = find.byWidgetPredicate((widget) =>
      widget is TruckScene && widget.onContainerTap != null);
    Future<void> touch(double x, double y) async {
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      final size = tester.getSize(preview);
      final origin = tester.getTopLeft(preview);
      final scale = size.width / 300 < size.height / 120
        ? size.width / 300 : size.height / 120;
      await tester.tapAt(origin + Offset((size.width - 300 * scale) / 2 + x * scale,
        (size.height - 120 * scale) / 2 + y * scale));
      await tester.pump();
    }
    await touch(35, 82);
    final plateField = tester.widget<TextField>(find.descendant(
      of: find.widgetWithText(TextFormField, 'Plaque camion *'),
      matching: find.byType(TextField)));
    expect(plateField.focusNode!.hasFocus, isTrue);
    await touch(130, 50);
    expect(plateField.focusNode!.hasFocus, isFalse);
    expect(tester.binding.focusManager.primaryFocus?.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Twin container forms are side by side on web and slide tabs on mobile', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EntryScreen(
      repository: QueueFixture(), canCorrect: false))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gate-loaded-true')));
    await tester.pumpAndSettle();
    final first = find.text("Premier Conteneur (20')");
    final second = find.text("Deuxième Conteneur (20') · Compagnie différente autorisée");
    final left = tester.getTopLeft(first);
    final right = tester.getTopLeft(second);
    expect(right.dx, greaterThan(left.dx + 300));
    expect((right.dy - left.dy).abs(), lessThan(10));

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.physicalSize = const Size(390, 1000);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EntryScreen(
      repository: QueueFixture(), canCorrect: false))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('gate-loaded-true')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gate-loaded-true')));
    await tester.pumpAndSettle();

    // On mobile: tabs are shown, first container is on page 0
    expect(find.byKey(const ValueKey('twin-tab-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('twin-tab-1')), findsOneWidget);
    expect(find.text("Premier Conteneur (20')"), findsOneWidget);

    // Tapping tab 1 slides to second container
    await tester.tap(find.byKey(const ValueKey('twin-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text("Deuxième Conteneur (20') · Compagnie différente autorisée"), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Sortie handles empty-entered truck with chassis check and ki dkhal ki khraj option', (tester) async {
    final emptyVisit = TruckVisit(
      id: 'visit-empty-1',
      plate: '99999-B-01',
      cin: 'CD987654',
      entryKind: 'empty',
      container: null,
      booking: 'BOOK-7788',
      iso: '22G1',
      armateur: 'MAE',
      enteredAt: DateTime.now(),
      enginAt: null,
      exitedAt: null,
      canceledAt: null,
    );
    final repository = QueueFixtureWithTrucks([emptyVisit]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExitScreen(
      repository: repository,
      canCancel: false,
    ))));
    await tester.pumpAndSettle();

    // Search empty truck
    await tester.enterText(find.widgetWithText(TextFormField, 'Plaque ou Conteneur *'), '99999');
    await tester.pumpAndSettle();

    expect(find.text('Données du camion à vérifier'), findsOneWidget);
    expect(find.text('99999-B-01'), findsOneWidget);
    expect(find.text('CD987654'), findsOneWidget);
    expect(find.text('BOOK-7788'), findsOneWidget);
    expect(find.text('Contrôle châssis : Le camion a-t-il chargé un conteneur ?'), findsOneWidget);
    expect(find.text('OUI · Conteneur chargé'), findsOneWidget);
    expect(find.text('NON · Sortie à vide'), findsOneWidget);

    // Default is OUI -> Mono / Twin options
    expect(find.text('1 Conteneur (Mono)'), findsOneWidget);
    expect(find.text('Twin (2 x 20\')'), findsOneWidget);

    // Switch to NON (ki dkhal ki khraj)
    await tester.ensureVisible(find.text('NON · Sortie à vide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NON · Sortie à vide'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ki dkhal ki khraj'), findsWidgets);
    expect(find.text('Confirmer la sortie à vide (Annuler la visite)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('BonPdfScreen displays PDF preview with print action', (tester) async {
    final samplePdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
    await tester.pumpWidget(MaterialApp(
      home: BonPdfScreen(
        bytes: samplePdf,
        kind: 'ENTRÉE',
        visitId: 'test-visit-1',
        autoPrint: false,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Bon ENTRÉE'), findsOneWidget);
    expect(find.byIcon(Icons.print), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Sortie search matches plate without dashes or spaces (e.g. 5262H1 matches 15262-H-1)', (tester) async {
    final visit = TruckVisit(
      id: 'visit-test-plate',
      plate: '15262-H-1',
      cin: 'AB123456',
      entryKind: 'loaded',
      container: 'MSCU9876543',
      booking: null,
      iso: '22G1',
      armateur: 'MAE',
      enteredAt: DateTime.now(),
      enginAt: null,
      exitedAt: null,
      canceledAt: null,
    );
    final repository = QueueFixtureWithTrucks([visit]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExitScreen(
      repository: repository,
      canCancel: false,
    ))));
    await tester.pumpAndSettle();

    // Search without dashes: 5262H1
    await tester.enterText(find.widgetWithText(TextFormField, 'Plaque ou Conteneur *'), '5262H1');
    await tester.pumpAndSettle();

    expect(find.text('Données du camion à vérifier'), findsOneWidget);
    expect(find.text('15262-H-1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('BonConfirmationDialog presents print-and-new, print, download and triggers onNewTruck', (tester) async {
    final samplePdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
    var printOverrideCalled = false;
    var newTruckCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BonConfirmationDialog(
          bytes: samplePdf,
          kind: 'ENTRÉE',
          visitId: 'test-visit-42',
          plate: '12345-A-1',
          containerNumber: 'MSCU1234567',
          containerNumber2: 'TGHU7654321',
          onPrintOverride: () async {
            printOverrideCalled = true;
          },
          onNewTruck: () {
            newTruckCalled = true;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Entrée enregistrée !'), findsOneWidget);
    expect(find.text('12345-A-1'), findsOneWidget);
    expect(find.text('MSCU1234567'), findsOneWidget);
    expect(find.text('TGHU7654321'), findsOneWidget);

    expect(find.byKey(const ValueKey('btn-print-and-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('btn-print-only')), findsOneWidget);
    expect(find.byKey(const ValueKey('btn-download-pdf')), findsOneWidget);
    expect(find.text('Aperçu PDF'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('btn-print-and-new')));
    await tester.pumpAndSettle();

    expect(printOverrideCalled, isTrue);
    expect(newTruckCalled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Mobile F11 mode hides redundant truck titles, pins plate/cin and displays compact bottom bar', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var fullscreenToggled = false;
    var processSwitched = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EntryScreen(
          repository: QueueFixture(),
          canCorrect: false,
          isFullScreen: true,
          onToggleFullScreen: () => fullscreenToggled = true,
          onSwitchProcess: () => processSwitched = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Redundant titles are hidden in mobile F11
    expect(find.text('État du camion à l’arrivée'), findsNothing);
    expect(find.textContaining('Glissez pour changer de mode'), findsNothing);

    // Plaque and CIN are pinned at top in mobile F11
    expect(find.widgetWithText(TextFormField, 'Plaque camion *'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'CIN chauffeur *'), findsOneWidget);

    // Bottom action bar contains page label, Enregistrer button, direct Print button and F11 button
    expect(find.text('ENTRÉE'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-f11-submit-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-f11-print-btn')), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget);
    expect(find.text('Print'), findsOneWidget);
    expect(find.text('F11'), findsOneWidget);

    // Tapping F11 calls onToggleFullScreen
    await tester.tap(find.text('F11'));
    await tester.pumpAndSettle();
    expect(fullscreenToggled, isTrue);

    // Tapping ENTRÉE badge calls onSwitchProcess
    await tester.tap(find.text('ENTRÉE'));
    await tester.pumpAndSettle();
    expect(processSwitched, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());

    // Test ExitScreen bottom bar in mobile F11
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExitScreen(
          repository: QueueFixture(),
          canCancel: false,
          isFullScreen: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('SORTIE'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-f11-exit-submit-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-f11-exit-print-btn')), findsOneWidget);
    expect(find.text('F11'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
