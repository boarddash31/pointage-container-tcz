import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointage_container/data/pointage_repository.dart';
import 'package:pointage_container/domain/transport_order.dart';
import 'package:pointage_container/ui/transport_orders_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

TransportOrderItem article(
  String id,
  String arm, {
  String order = 'order-a',
  String ref = 'EDO-A',
  String direction = 'LIVRAISON',
  int used = 1,
  int quantity = 1,
  int version = 3,
}) => TransportOrderItem(
  id: id,
  orderId: order,
  version: version,
  reference: ref,
  kind: direction == 'LIVRAISON' ? 'EDO' : 'ERO',
  direction: direction,
  armateur: arm,
  iso: '22G1',
  quantity: quantity,
  reserved: used,
  completed: 0,
  remaining: quantity - used,
  active: true,
  everUsed: used,
);

class OrderFixture extends PointageRepository {
  OrderFixture()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  List<TransportOrderItem> rows = [
    article('item-a', 'MAE'),
    article('item-b', 'MSC', used: 0),
    article(
      'item-c',
      'MAE',
      order: 'order-b',
      ref: 'ERO-B',
      direction: 'RESTITUTION',
      used: 0,
    ),
  ];
  List<Map<String, dynamic>>? savedItems;
  String? savedKind, savedDirection, updatedOrder, increasedItem;
  int? expectedVersion, increment;
  bool stale = false;
  @override
  Future<List<OperatorRecord>> operators() async => [
    const OperatorRecord('MAE', 'Maersk', 'MAEU'),
    const OperatorRecord('MSC', 'MSC', 'MSCU'),
  ];
  @override
  Future<List<TransportOrderItem>> transportOrderItems() async => rows;
  @override
  Future<String> createTransportOrder({
    required String kind,
    required String direction,
    required String reference,
    required String armateur,
    required List<Map<String, dynamic>> items,
  }) async {
    savedKind = kind;
    savedDirection = direction;
    savedItems = items;
    return 'saved';
  }

  @override
  Future<int> updateTransportOrder({
    required String orderId,
    required int expectedVersion,
    required List<Map<String, dynamic>> items,
  }) async {
    if (stale) {
      throw const PostgrestException(message: 'conflict', code: '40001');
    }
    updatedOrder = orderId;
    this.expectedVersion = expectedVersion;
    savedItems = items;
    return expectedVersion + 1;
  }

  @override
  Future<int> increaseTransportOrderQuantity({
    required String itemId,
    required int quantity,
  }) async {
    increasedItem = itemId;
    increment = quantity;
    return 1 + quantity;
  }
}

Future<void> press(WidgetTester tester, String label) async {
  final button = find.text(label);
  if (button.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      button,
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final scenario in [
    ('RESTITUTION', 'ERO', 'ERO · Restitution'),
    ('LIVRAISON', 'EDO', 'EDO · Livraison'),
  ]) {
    testWidgets(
      '${scenario.$1} fixes and disables ${scenario.$2}, including on hover',
      (tester) async {
        final repo = OrderFixture();
        await tester.pumpWidget(
          MaterialApp(
            home: CreateTransportOrderScreen(
              repository: repo,
              direction: scenario.$1,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Booking'), findsNothing);
        expect(find.text('BOOKING'), findsNothing);
        final typeInput = find.descendant(
          of: find.byKey(const ValueKey('order-type')),
          matching: find.byType(TextField),
        );
        expect(tester.widget<TextField>(typeInput).enabled, false);
        expect(
          tester.widget<TextField>(typeInput).controller!.text,
          scenario.$3,
        );
        expect(
          find.widgetWithText(MenuItemButton, 'EDO · Livraison'),
          findsNothing,
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(
          tester.getCenter(find.byKey(const ValueKey('order-type'))),
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(MenuItemButton, 'EDO · Livraison'),
          findsNothing,
        );
        expect(
          find.widgetWithText(MenuItemButton, 'ERO · Restitution'),
          findsNothing,
        );
        await mouse.removePointer();
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Référence *'),
          '${scenario.$2}-NEW',
        );
        await tester.tap(
          find.widgetWithText(DropdownMenuFormField<String>, 'Armateur *'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('MAE · Maersk').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'ISO article 1'),
          '22G1',
        );
        await press(tester, 'Créer l’ordre');
        expect(repo.savedKind, scenario.$2);
        expect(repo.savedDirection, scenario.$1);
      },
    );
  }
  testWidgets(
    'typing filters carriers case insensitively and Enter selects the match',
    (tester) async {
      final repo = OrderFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: CreateTransportOrderScreen(
            repository: repo,
            direction: 'RESTITUTION',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.widgetWithText(DropdownMenuFormField<String>, 'Armateur *'),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, 'm');
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(MenuItemButton, 'MAE · Maersk'),
        findsOneWidget,
      );
      expect(find.widgetWithText(MenuItemButton, 'MSC · MSC'), findsOneWidget);
      await tester.enterText(input, 'maers');
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(MenuItemButton, 'MAE · Maersk'),
        findsOneWidget,
      );
      expect(find.widgetWithText(MenuItemButton, 'MSC · MSC'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, 'MAE · Maersk');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Référence *'),
        'ERO-SEARCH',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'ISO article 1'),
        '22G1',
      );
      await press(tester, 'Créer l’ordre');
      expect(repo.savedKind, 'ERO');
      expect(repo.savedDirection, 'RESTITUTION');
      expect(repo.savedItems!.first['armateur_id'], 'MAE');
    },
  );
  testWidgets(
    'unconfirmed carrier query cannot silently submit the previous selection',
    (tester) async {
      final repo = OrderFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: CreateTransportOrderScreen(
            repository: repo,
            direction: 'LIVRAISON',
            order: TransportOrder([repo.rows[1]]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.widgetWithText(DropdownMenuFormField<String>, 'Armateur *'),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, 'unknown');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextFormField, 'Référence *'));
      await tester.pumpAndSettle();
      await press(tester, 'Enregistrer les modifications');
      expect(find.text('Sélectionnez un armateur de la liste'), findsOneWidget);
      expect(repo.savedItems, isNull);
    },
  );
  testWidgets(
    'one header groups carriers; exhausted item can receive quantity but cannot be selected',
    (tester) async {
      final repo = OrderFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: TransportOrdersScreen(repository: repo, direction: 'LIVRAISON'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('EDO EDO-A'), findsOneWidget);
      expect(find.text('ERO ERO-B'), findsNothing);
      expect(find.text('MAE · ISO 22G1'), findsOneWidget);
      expect(find.text('MSC · ISO 22G1'), findsOneWidget);
      final select = tester
          .widgetList<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Sélectionner cet article',
            ),
          )
          .toList();
      expect(select.first.onPressed, isNull);
      expect(select.last.onPressed, isNotNull);
      await tester.tap(find.byTooltip('Ajouter de la quantité').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantité à ajouter'),
        '5',
      );
      await press(tester, 'Ajouter');
      expect(repo.increasedItem, 'item-a');
      expect(repo.increment, 5);
    },
  );
  testWidgets('clerk creates one ERO with same ISO for different carriers', (
    tester,
  ) async {
    final repo = OrderFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: CreateTransportOrderScreen(
          repository: repo,
          direction: 'RESTITUTION',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Booking'), findsNothing);
    expect(find.text('ERO · Restitution'), findsWidgets);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Référence *'),
      'ero-new',
    );
    await tester.tap(
      find.widgetWithText(DropdownMenuFormField<String>, 'Armateur *').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('MAE · Maersk').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'ISO article 1'),
      '22G1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantité totale *').first,
      '3',
    );
    await press(tester, 'Ajouter un article');
    final second = find
        .widgetWithText(DropdownMenuFormField<String>, 'Armateur *')
        .last;
    await tester.ensureVisible(second);
    await tester.tap(second);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MSC · MSC').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'ISO article 2'),
      '22G1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantité totale *').last,
      '4',
    );
    await press(tester, 'Créer l’ordre');
    expect(repo.savedKind, 'ERO');
    expect(repo.savedItems, [
      {'iso_code': '22G1', 'armateur_id': 'MAE', 'quantity': 3},
      {'iso_code': '22G1', 'armateur_id': 'MSC', 'quantity': 4},
    ]);
  });
  testWidgets(
    'global duplicate across direction opens existing order instead of creating another',
    (tester) async {
      final repo = OrderFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: CreateTransportOrderScreen(
            repository: repo,
            direction: 'RESTITUTION',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Référence *'),
        ' edo-a ',
      );
      await tester.tap(
        find.widgetWithText(DropdownMenuFormField<String>, 'Armateur *'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('MAE · Maersk').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'ISO article 1'),
        '45G1',
      );
      await press(tester, 'Créer l’ordre');
      expect(repo.savedItems, isNull);
      await press(tester, 'Ouvrir l’ordre existant');
      expect(find.text('Modifier EDO EDO-A'), findsOneWidget);
    },
  );
  testWidgets('editing keeps IDs and version and locks used identity', (
    tester,
  ) async {
    final repo = OrderFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: CreateTransportOrderScreen(
          repository: repo,
          direction: 'LIVRAISON',
          order: TransportOrder(repo.rows.take(2).toList()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.widgetWithText(TextFormField, 'Référence *'),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      true,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.widgetWithText(TextFormField, 'ISO article 1'),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      true,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find
                  .widgetWithText(DropdownMenuFormField<String>, 'Armateur *')
                  .first,
              matching: find.byType(TextField),
            ),
          )
          .enabled,
      false,
    );
    expect(find.byTooltip('Supprimer l’article'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantité totale *').first,
      '10',
    );
    await press(tester, 'Enregistrer les modifications');
    expect(repo.updatedOrder, 'order-a');
    expect(repo.expectedVersion, 3);
    expect(repo.savedItems!.first, {
      'id': 'item-a',
      'iso_code': '22G1',
      'armateur_id': 'MAE',
      'quantity': 10,
    });
    expect(repo.savedItems!.last['id'], 'item-b');
  });
  testWidgets('cannot reduce total below quantities already allocated', (
    tester,
  ) async {
    final repo = OrderFixture()
      ..rows = [article('item-a', 'MAE', quantity: 5, used: 3)];
    await tester.pumpWidget(
      MaterialApp(
        home: CreateTransportOrderScreen(
          repository: repo,
          direction: 'LIVRAISON',
          order: TransportOrder(repo.rows),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantité totale *'),
      '2',
    );
    await press(tester, 'Enregistrer les modifications');
    expect(find.text('De 3 à 1 000 000'), findsOneWidget);
    expect(repo.savedItems, isNull);
  });
  testWidgets('stale edit requires explicit refresh before another save', (
    tester,
  ) async {
    final repo = OrderFixture()..stale = true;
    await tester.pumpWidget(
      MaterialApp(
        home: CreateTransportOrderScreen(
          repository: repo,
          direction: 'LIVRAISON',
          order: TransportOrder([repo.rows.first]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await press(tester, 'Enregistrer les modifications');
    expect(
      find.textContaining('Ordre modifié par un autre utilisateur'),
      findsOneWidget,
    );
    expect(repo.savedItems, isNull);
    repo.rows = [article('item-a', 'MAE', version: 4, quantity: 8)];
    repo.stale = false;
    await press(tester, 'Actualiser et remplacer le formulaire');
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Quantité totale *'),
          )
          .controller!
          .text,
      '8',
    );
    await press(tester, 'Enregistrer les modifications');
    expect(repo.expectedVersion, 4);
  });
}
