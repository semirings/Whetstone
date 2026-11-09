/// Cards to and from the backend's JSON (see backend/src/whetstone_be/models.py).
library;

import 'package:speakeasy/speakeasy.dart';

import '../model/model.dart';

/// JSON for [card]. [stack] is the name of the stack the card is in.
Map<String, Object?> cardToJson(RecipeCard card, {String? stack}) {
  return <String, Object?>{
    'id': card.id,
    'name': card.name,
    'kind': 'card',
    'stack': stack ?? card.parent?.name ?? 'Recipes',
    'script': card.script,
    'fields': <String, String>{
      for (final HostObject c in card.children)
        if (c is CardField) c.name: c.text
    },
    'required': <String>[
      for (final HostObject c in card.children)
        if (c is CardField && c.isRequired) c.name
    ],
    'buttons': <Map<String, String>>[
      for (final HostObject c in card.children)
        if (c.kind == 'button') <String, String>{'name': c.name, 'script': c.script}
    ],
  };
}

/// Builds a card from backend JSON. Fields listed in
/// [RecipeCard.fieldSpecs] are filled in; any other field in the JSON is
/// added as a plain field, so nothing stored is lost.
RecipeCard cardFromJson(Map<String, Object?> json) {
  final RecipeCard card = RecipeCard('${json['name'] ?? ''}', id: '${json['id']}');
  card.script = '${json['script'] ?? ''}';
  final Object? fields = json['fields'];
  if (fields is Map) {
    fields.forEach((Object? name, Object? text) {
      final CardField? f = card.field('$name');
      if (f != null) {
        f.text = '$text';
      } else {
        card.add(CardField('$name', text: '$text'));
      }
    });
  }
  final Object? required = json['required'];
  if (required is List) {
    for (final Object? n in required) {
      final CardField? f = card.field('$n');
      if (f != null) f.isRequired = true;
    }
  }
  final Object? buttons = json['buttons'];
  if (buttons is List) {
    for (final Object? b in buttons) {
      if (b is Map) {
        card.add(CardButton('${b['name']}', script: '${b['script'] ?? ''}'));
      }
    }
  }
  return card;
}

/// The stack name stored in [json], or 'Recipes'.
String stackNameOf(Map<String, Object?> json) => '${json['stack'] ?? 'Recipes'}';
