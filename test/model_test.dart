import 'package:flutter_test/flutter_test.dart';
import 'package:speakeasy/speakeasy.dart';
import 'package:whetstone/model/model.dart';

void main() {
  test('a new recipe card has all fields and reports what is missing', () {
    final RecipeCard card = RecipeCard('Camera points nowhere');
    expect(card.children.length, RecipeCard.fieldSpecs.length);
    expect(card.missingRequired(),
        <String>['symptom', 'expected', 'calls', 'tool', 'version', 'status']);
  });

  test('filling required fields completes the card', () {
    final RecipeCard card = RecipeCard('Camera points nowhere');
    for (final String f in <String>['symptom', 'expected', 'calls', 'tool', 'version', 'status']) {
      card.field(f)!.setProperty('text', 'x');
    }
    expect(card.missingRequired(), isEmpty);
  });

  test('status solved is detected', () {
    final RecipeCard card = RecipeCard('t');
    expect(card.isSolved, isFalse);
    card.field('status')!.text = ' Solved ';
    expect(card.isSolved, isTrue);
  });

  test('message path runs button, card, stack, app', () {
    final WhetstoneApp app = WhetstoneApp();
    final CardStack stack = CardStack('Blender recipes');
    final RecipeCard card = RecipeCard('t');
    final CardButton button = CardButton('Replay');
    app.addStack(stack);
    stack.addCard(card);
    card.add(button);
    final List<String> path = <String>[];
    HostObject? o = button;
    while (o != null) {
      path.add(o.kind);
      o = o.parent;
    }
    expect(path, <String>['button', 'card', 'stack', 'app']);
    expect(app.currentStack, same(stack));
    expect(stack.cards, <RecipeCard>[card]);
  });

  test('field text is reachable as a script property', () {
    final RecipeCard card = RecipeCard('t');
    final HostObject f = card.find('field', 'Symptom')!;
    f.setProperty('TEXT', 'no fill');
    expect(f.getProperty('text'), 'no fill');
  });
}
