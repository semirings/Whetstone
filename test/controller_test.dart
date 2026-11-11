import 'package:flutter_test/flutter_test.dart';
import 'package:speakeasy/speakeasy.dart';
import 'package:whetstone/controller.dart';
import 'package:whetstone/model/model.dart';

void main() {
  late WhetstoneApp app;
  late CardStack stack;
  late RecipeCard camera;
  late RecipeCard grease;
  late RecipeCard render;
  late WhetstoneController c;

  RecipeCard card(String title, String symptom) {
    final RecipeCard r = RecipeCard(title);
    r.field('symptom')!.text = symptom;
    stack.addCard(r);
    return r;
  }

  setUp(() {
    app = WhetstoneApp();
    stack = CardStack('Recipes');
    app.addStack(stack);
    camera = card('Camera fix', 'camera points nowhere');
    grease = card('Grease fill', 'no fill on grease pencil');
    render = card('Render slow', 'render takes forever');
    c = WhetstoneController(app);
  });

  test('starts on the first card', () {
    expect(c.currentCard, same(camera));
    expect(c.cards.length, 3);
    expect(app.currentCard, same(camera));
  });

  test('submit runs a script line and notifies', () async {
    int n = 0;
    c.addListener(() => n++);
    await c.submit('go to card "Render slow"');
    expect(c.currentCard, same(render));
    expect(app.currentCard, same(render));
    expect(n, greaterThan(0));
  });

  test('errors are kept, not thrown', () async {
    await c.submit('go to card "nope"');
    expect(c.error, contains('nope'));
    await c.submit('put 1 into msg');
    expect(c.error, isNull);
    expect(c.msg, '1');
  });

  test('syntax errors are kept too', () async {
    await c.submit('put into');
    expect(c.error, isNotNull);
  });

  test('find into a substack changes the card list', () async {
    await c.submit(
        'find cards where field "symptom" contains "grease" into stack "hits"');
    expect(c.viewingSubstack, isFalse);
    await c.submit('go to stack "hits"');
    expect(c.viewingSubstack, isTrue);
    expect(c.substackName, 'hits');
    expect(c.cards, <HostObject>[grease]);
    await c.showAllCards();
    expect(c.viewingSubstack, isFalse);
    expect(c.cards.length, 3);
  });

  test('drop removes from the results, not the stack', () async {
    await c.submit('find cards where true into stack "all"');
    await c.submit('go to stack "all"');
    await c.submit('drop this card');
    expect(c.cards.length, 2);
    expect(stack.children.length, 3);
  });

  test('create card makes a full recipe card', () async {
    await c.submit('create card "New one"');
    expect(stack.children.length, 4);
    expect(c.currentCard, isA<RecipeCard>());
    await c.submit('put "it hurts" into field "symptom"');
    expect((c.currentCard! as RecipeCard).field('symptom')!.text, 'it hurts');
  });

  test('pressing a button sends mouseUp', () async {
    final CardButton b = CardButton('Mark solved',
        script: 'on mouseUp\n  put "solved" into field "status"\nend mouseUp\n');
    camera.add(b);
    await c.press(b);
    expect(camera.isSolved, isTrue);
  });

  test('picking a card in the list', () {
    c.open(grease);
    expect(c.currentCard, same(grease));
  });

  test('editing a field notifies', () {
    int n = 0;
    c.addListener(() => n++);
    c.editField(camera.field('symptom')!, 'changed');
    expect(camera.field('symptom')!.text, 'changed');
    expect(n, 1);
  });

  group('editing objects', () {
    test('addObject adds a field and refuses duplicates', () async {
      final HostObject? f = await c.addObject('field', 'notes');
      expect(f, isNotNull);
      expect(camera.field('notes'), isNotNull);
      expect(await c.addObject('field', 'notes'), isNull);
      expect(c.error, contains('already'));
    });

    test('rename works on custom objects, not standard fields', () async {
      final HostObject b = (await c.addObject('button', 'Go'))!;
      await c.renameObject(b, 'Run');
      expect(b.name, 'Run');
      await c.renameObject(camera.field('symptom')!, 'x');
      expect(camera.field('symptom'), isNotNull);
      expect(c.error, contains('standard'));
    });

    test('deleteObject removes a custom field, not a standard one', () async {
      final HostObject f = (await c.addObject('field', 'notes'))!;
      await c.deleteObject(f);
      expect(camera.field('notes'), isNull);
      await c.deleteObject(camera.field('symptom')!);
      expect(camera.field('symptom'), isNotNull);
      expect(c.error, contains('standard'));
    });

    test('setRequired changes the flag', () async {
      final CardField f = (await c.addObject('field', 'notes'))! as CardField;
      await c.setRequired(f, true);
      expect(f.isRequired, isTrue);
    });
  });

  test('a scene command goes to the scene hook and its summary is the result', () async {
    final List<Map<String, Object?>> got = <Map<String, Object?>>[];
    final WhetstoneController w = WhetstoneController(app, scene: (Map<String, Object?> op) async {
      got.add(op);
      return 'created Eye';
    });
    await w.submit('create sphere "Eye" at 0, 0, 1');
    expect(w.error, isNull);
    expect(got.single['shape'], 'sphere');
    expect(w.runtime.result, 'created Eye');
  });

  test('a scene command without Blender shows a plain error', () async {
    await c.submit('create cube');
    expect(c.error, contains('no 3D application'));
  });
}
