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

  group('background', () {
    test('Problem & fix lists the standard fields, same names and order', () {
      expect(Background.problemAndFix.fields.map((FieldSpec f) => f.name).toList(),
          RecipeCard.fieldSpecs.map(((String, bool) s) => s.$1).toList());
    });

    test('Problem & fix marks the same fields required', () {
      expect(
          <String>[
            for (final FieldSpec f in Background.problemAndFix.fields)
              if (f.required) f.name
          ],
          <String>[
            for (final (String, bool) s in RecipeCard.fieldSpecs)
              if (s.$2) s.$1
          ]);
    });

    test('face and back follow the sketches', () {
      List<String> side(CardSide s) => <String>[
            for (final FieldSpec f in Background.problemAndFix.fields)
              if (f.side == s) f.name
          ];
      expect(side(CardSide.back), <String>[
        'narration', 'calls', 'steps', 'clip', 'blender_info',
        'applies_from', 'applies_until', 'superseded_by',
      ]);
      expect(side(CardSide.face), <String>[
        'symptom', 'expected', 'observed', 'context', 'summary',
        'tool', 'version', 'keywords', 'status',
      ]);
    });

    test('a new card uses Problem & fix; an unknown id falls back to it', () {
      expect(RecipeCard('t').backgroundId, Background.problemAndFixId);
      expect(Background.byId(null), same(Background.problemAndFix));
      expect(Background.byId('nope'), same(Background.problemAndFix));
      expect(Background.byId(Background.problemAndFixId), same(Background.problemAndFix));
    });
  });
}
