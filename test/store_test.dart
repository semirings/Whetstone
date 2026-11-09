import 'package:flutter_test/flutter_test.dart';
import 'package:whetstone/controller.dart';
import 'package:whetstone/model/model.dart';
import 'package:whetstone/storage/card_codec.dart';
import 'package:whetstone/storage/card_store.dart';

void main() {
  group('codec', () {
    test('required flags survive', () {
      final RecipeCard c = RecipeCard('R', id: 'r1');
      c.add(CardField('extra')..isRequired = true);
      final RecipeCard back = cardFromJson(cardToJson(c));
      expect(back.field('extra')!.isRequired, isTrue);
    });

    test('a card survives to JSON and back', () {
      final RecipeCard c = RecipeCard('Cam', id: 'x1');
      c.field('symptom')!.text = 'line one\nline two';
      c.add(CardField('extra', text: 'e'));
      c.add(CardButton('Go', script: 'on mouseUp\nend mouseUp'));
      c.script = 'on a\nend a';
      CardStack('Recipes').addCard(c);

      final Map<String, Object?> json = cardToJson(c);
      expect(json['stack'], 'Recipes');
      expect(json['id'], 'x1');

      final RecipeCard back = cardFromJson(json);
      expect(back.id, 'x1');
      expect(back.name, 'Cam');
      expect(back.script, 'on a\nend a');
      expect(back.field('symptom')!.text, 'line one\nline two');
      expect(back.field('extra')!.text, 'e', reason: 'unknown fields are kept');
      expect(back.children.whereType<CardButton>().single.script,
          'on mouseUp\nend mouseUp');
      expect(cardToJson(back, stack: 'Recipes'), json);
    });

    test('new cards get ids that differ from each other', () {
      expect(RecipeCard('a').id, isNot(RecipeCard('b').id));
    });
  });

  group('controller and store', () {
    late WhetstoneApp app;
    late CardStack stack;
    late RecipeCard camera;
    late RecipeCard render;
    late MemoryCardStore store;

    WhetstoneController make({CardStore? s, bool preloaded = false}) {
      return WhetstoneController(
        app,
        store: s,
        stored: preloaded ? <RecipeCard>[camera, render] : const <RecipeCard>[],
      );
    }

    setUp(() {
      app = WhetstoneApp();
      stack = CardStack('Recipes');
      app.addStack(stack);
      camera = RecipeCard('Camera fix');
      render = RecipeCard('Render slow');
      stack.addCard(camera);
      stack.addCard(render);
      store = MemoryCardStore();
      for (final RecipeCard c in <RecipeCard>[camera, render]) {
        store.saved[c.id] = cardToJson(c);
      }
    });

    test('the save command writes the current card', () async {
      final WhetstoneController c = make(s: store);
      camera.field('symptom')!.text = 'changed';
      await c.submit('save');
      expect(c.error, isNull);
      expect(c.msg, 'saved "Camera fix"');
      expect((store.saved[camera.id]!['fields']! as Map<String, String>)['symptom'],
          'changed');
    });

    test('save without a store is an error, not a crash', () async {
      final WhetstoneController c = make();
      await c.submit('save');
      expect(c.error, contains('no card store'));
    });

    test('a store failure shows as an error', () async {
      final WhetstoneController c = make(s: store);
      store.failWith = 'backend down';
      await c.submit('save');
      expect(c.error, contains('backend down'));
    });

    test('a new card is saved only when asked', () async {
      final WhetstoneController c = make(s: store, preloaded: true);
      await c.submit('create card "New one"');
      final String id = c.currentCard!.id;
      expect(store.saved.containsKey(id), isFalse);
      await c.submit('save');
      expect(store.saved.containsKey(id), isTrue);
    });

    test('deleting a stored card deletes it from the store', () async {
      final WhetstoneController c = make(s: store, preloaded: true);
      await c.submit('delete card "Render slow"');
      expect(store.saved.containsKey(render.id), isFalse);
      expect(store.saved.containsKey(camera.id), isTrue);
    });

    test('deleting an unsaved card does not touch the store', () async {
      final WhetstoneController c = make(s: store, preloaded: true);
      await c.submit('create card "Scratch"');
      final int before = store.saved.length;
      await c.submit('delete this card');
      expect(store.saved.length, before);
      expect(c.error, isNull);
    });

    test('drop does not delete from the store', () async {
      final WhetstoneController c = make(s: store, preloaded: true);
      await c.submit('find cards where true into stack "all"');
      await c.submit('go to stack "all"');
      await c.submit('drop this card');
      expect(store.saved.length, 2);
    });

    test('a failed delete is reported and retried next time', () async {
      final WhetstoneController c = make(s: store, preloaded: true);
      store.failWith = 'backend down';
      await c.submit('delete card "Render slow"');
      expect(c.error, contains('backend down'));
      store.failWith = null;
      await c.submit('put 1 into msg');
      expect(store.saved.containsKey(render.id), isFalse);
    });
  });
}
