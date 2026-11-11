/// Whetstone's object model: what scripts see as stack, card, field, button.
/// No Flutter imports; widgets come later. See doc/design.md.
library;

import 'package:speakeasy/speakeasy.dart';

int _cardSerial = 0;

/// A card id that stays unique across runs. (BaseHostObject's own counter
/// restarts at 1 each launch, which would collide with ids already stored.)
String newCardId() =>
    'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_cardSerial++}';

/// A named text slot on a card. Adds the `text` property.
class CardField extends BaseHostObject {
  CardField(String name, {this.isRequired = false, String text = ''})
      : _text = text,
        super('field', name);

  bool isRequired;
  String _text;

  String get text => _text;
  set text(String value) => _text = value;
  bool get isFilled => _text.trim().isNotEmpty;

  @override
  Object? getProperty(String property) =>
      property.toLowerCase() == 'text' ? _text : super.getProperty(property);

  @override
  void setProperty(String property, Object? value) {
    if (property.toLowerCase() == 'text') {
      _text = '$value';
    } else {
      super.setProperty(property, value);
    }
  }
}

/// A named action with a Speakeasy script.
class CardButton extends BaseHostObject {
  CardButton(String name, {String script = ''})
      : super('button', name, script: script);
}

/// One recipe. The card's name is the recipe title. Fields are created from
/// [fieldSpecs] (name, required); symptom comes first because that is how
/// recipes are looked up.
class RecipeCard extends BaseHostObject {
  /// [standardFields] false makes a card with no fields (the built-in Home card).
  RecipeCard(String title, {String? id, bool standardFields = true})
      : super('card', title, id: id ?? newCardId()) {
    if (standardFields) {
      for (final (String, bool) spec in fieldSpecs) {
        add(CardField(spec.$1, isRequired: spec.$2));
      }
    }
  }

  static const List<(String, bool)> fieldSpecs = <(String, bool)>[
    ('symptom', true),
    ('expected', true),
    ('observed', false),
    ('context', false),
    ('summary', false),
    ('narration', false),
    ('calls', true), // raw captured calls, SECONDS<TAB>CALL per line: source of truth
    ('steps', false), // calls translated to Speakeasy where possible (derived)
    ('clip', false), // path to the screen capture
    ('blender_info', false), // version, mode, scene summary at start of recording
    ('tool', true), // what the recipe is about: blender, d4m, julia, ...
    ('version', true), // version of that tool it was verified on
    ('applies_from', false),
    ('applies_until', false),
    ('superseded_by', false),
    ('keywords', false),
    ('status', true), // 'stuck' or 'solved'
  ];

  CardField? field(String name) {
    final HostObject? f = find('field', name);
    return f is CardField ? f : null;
  }

  /// Names of required items that are still empty. Empty list = complete.
  List<String> missingRequired() => <String>[
        if (name.trim().isEmpty) 'title',
        for (final HostObject c in children)
          if (c is CardField && c.isRequired && !c.isFilled) c.name,
      ];

  bool get isSolved => field('status')?.text.trim().toLowerCase() == 'solved';
}

/// An ordered collection of cards.
class CardStack extends BaseHostObject {
  CardStack(String name) : super('stack', name);

  List<RecipeCard> get cards =>
      children.whereType<RecipeCard>().toList(growable: false);

  void addCard(RecipeCard card) => add(card);

  /// `create card "x"` in a script makes a full recipe card.
  @override
  HostObject createChild(String kind, String name) {
    if (kind != 'card') return super.createChild(kind, name);
    final RecipeCard card = RecipeCard(name);
    add(card);
    return card;
  }
}

/// Top of the message path: the application itself.
class WhetstoneApp extends BaseHostObject {
  WhetstoneApp() : super('app', 'Whetstone');

  CardStack? currentStack;
  RecipeCard? currentCard;

  void addStack(CardStack stack) {
    add(stack);
    currentStack ??= stack;
  }
}
