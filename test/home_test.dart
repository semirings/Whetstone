import 'package:flutter_test/flutter_test.dart';
import 'package:speakeasy/speakeasy.dart';
import 'package:whetstone/controller.dart';
import 'package:whetstone/home.dart';
import 'package:whetstone/main.dart';
import 'package:whetstone/model/model.dart';
import 'package:whetstone/storage/card_store.dart';

class FakeStore implements CardStore {
  FakeStore(this.cards, {this.fail = false});
  final List<StoredCard> cards;
  final bool fail;
  final List<String> saved = <String>[];

  @override
  Future<List<StoredCard>> loadAll() async {
    if (fail) throw StoreException('cannot reach the Whetstone backend');
    return cards;
  }

  @override
  Future<void> save(RecipeCard card) async => saved.add(card.name);

  @override
  Future<void> delete(String id) async {}
}

void main() {
  test('the app opens on the Home card, not on a sample card', () async {
    final start = await startUp(FakeStore(<StoredCard>[
      StoredCard(RecipeCard('Camera fix'), 'Recipes'),
    ]));
    final WhetstoneController c = WhetstoneController(start.app, stored: start.stored);
    expect(c.currentCard, isA<HomeCard>());
    expect(c.onHome, isTrue);
    expect(start.app.children.first.name, 'Home');
    expect(start.warning, isNull);
  });

  test('an empty store gets an empty Recipes stack and no sample cards', () async {
    final store = FakeStore(<StoredCard>[]);
    final start = await startUp(store);
    final List<String> names = start.app.children.map((HostObject s) => s.name).toList();
    expect(names, <String>['Home', 'Recipes']);
    expect(start.app.children.last.children, isEmpty);
    expect(store.saved, isEmpty);
  });

  test('an unreachable backend still opens on Home, with a warning and no store', () async {
    final start = await startUp(FakeStore(<StoredCard>[], fail: true));
    expect(start.store, isNull);
    expect(start.warning, contains('Nothing will be saved'));
    expect(WhetstoneController(start.app).currentCard, isA<HomeCard>());
  });

  test('the All cards tile goes to the first stored stack', () async {
    final start = await startUp(FakeStore(<StoredCard>[
      StoredCard(RecipeCard('Camera fix'), 'Blender'),
    ]));
    final WhetstoneController c = WhetstoneController(start.app, stored: start.stored);
    final HomeCard home = c.home!;
    await c.press(home.buttonFor(home.tiles.single)!);
    expect(c.error, isNull);
    expect(c.currentCard!.name, 'Camera fix');
    expect(c.onHome, isFalse);
    c.goHome();
    expect(c.onHome, isTrue);
  });

  test('the Home card cannot be saved or changed', () async {
    final start = await startUp(FakeStore(<StoredCard>[]));
    final store = FakeStore(<StoredCard>[]);
    final WhetstoneController c = WhetstoneController(start.app, store: store);
    await c.submit('save');
    expect(c.error, contains('built in'));
    expect(store.saved, isEmpty);
    expect(await c.addObject('field', 'x'), isNull);
    expect(c.error, contains('built in'));
  });

  test('Home has five columns and three rows, and its tiles fit them', () async {
    final HomeCard h = HomeCard.standard(recipes: 'Recipes');
    expect(HomeCard.columns * HomeCard.rows, 15);
    for (final HomeTile t in h.tiles) {
      expect(t.slot, inInclusiveRange(0, 14));
    }
  });
}
