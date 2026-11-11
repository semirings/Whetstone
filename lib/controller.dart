/// Connects the Speakeasy runtime to the UI. No widgets here, so it can be
/// tested without a screen.
library;

import 'package:flutter/foundation.dart';
import 'package:speakeasy/speakeasy.dart';

import 'home.dart';
import 'model/model.dart';
import 'storage/card_store.dart';
import 'storage/scene_client.dart';

/// The runtime's [Io], with `save` routed to the controller's card store.
class _ControllerIo extends Io {
  _ControllerIo(this.inner, this.onSave, this.scene);

  final Io inner;
  final SceneOperate? scene;
  final Future<void> Function(HostObject card) onSave;

  @override
  Future<String?> ask(String prompt, String defaultAnswer) =>
      inner.ask(prompt, defaultAnswer);

  @override
  Future<String> answer(String message, List<String> buttons) =>
      inner.answer(message, buttons);

  @override
  void beep(int count) => inner.beep(count);

  @override
  Future<void> wait(Duration duration) => inner.wait(duration);

  @override
  Future<void> save(HostObject card) => onSave(card);

  @override
  void showMessageBox(bool show) => inner.showMessageBox(show);

  @override
  Future<String> operate(Map<String, Object?> op) =>
      scene == null ? super.operate(op) : scene!(op);
}

class WhetstoneController extends ChangeNotifier {
  /// [store] is where `save` writes; null means saving is not available.
  /// [stored] are the cards that came from the store, so that deleting one
  /// deletes it there too.
  WhetstoneController(
    this.app, {
    Io io = const Io(),
    this.store,
    SceneOperate? scene,
    Iterable<RecipeCard> stored = const <RecipeCard>[],
  }) {
    _known.addAll(stored.map((RecipeCard c) => c.id));
    runtime = Runtime(app, io: _ControllerIo(io, saveCard, scene))..onChange = _changed;
    _sync();
  }

  final WhetstoneApp app;
  final CardStore? store;
  late final Runtime runtime;

  /// Ids of cards the store has. A card that disappears from the app is
  /// deleted from the store.
  final Set<String> _known = <String>{};

  /// The last script error, or null.
  String? error;

  /// The built-in Home card, or null if the app has none.
  HomeCard? get home {
    for (final HostObject s in app.children) {
      for (final HostObject c in s.children) {
        if (c is HomeCard) return c;
      }
    }
    return null;
  }

  bool get onHome => currentCard is HomeCard;

  /// Shows the Home card.
  void goHome() {
    final HomeCard? h = home;
    if (h == null) return;
    error = null;
    runtime.goToCard(h);
    _sync();
    notifyListeners();
  }

  /// Puts [message] in the error line.
  void complain(String message) {
    error = message;
    notifyListeners();
  }

  /// The message box output (`msg`).
  String get msg => runtime.msg;

  HostObject? get currentCard => runtime.currentCard;

  /// True while viewing the results of a `find cards where`.
  bool get viewingSubstack => runtime.substack != null;

  /// Name of the substack being viewed, or null.
  String? get substackName => runtime.substack?.name;

  /// The cards in the current view: the substack if viewing one, else the
  /// current stack. A substack holds references; these are the real cards.
  List<HostObject> get cards {
    final SubStack? sub = runtime.substack;
    if (sub != null) return List<HostObject>.unmodifiable(sub.cards);
    final HostObject? stack = runtime.currentStack;
    if (stack == null) return const <HostObject>[];
    return <HostObject>[
      for (final HostObject c in stack.children)
        if (c.kind == 'card') c
    ];
  }

  /// 1-based position of the current card in [cards]; 0 when there is none.
  int get cardNumber {
    final HostObject? cur = currentCard;
    if (cur == null) return 0;
    return cards.indexWhere((HostObject c) => identical(c, cur)) + 1;
  }

  /// Find: cards of the current stack with [text] in any field. The hits become
  /// the substack `found` and the first one is shown.
  Future<void> findText(String text) async {
    final String t = text.trim().replaceAll('"', '');
    if (t.isEmpty) return;
    final HostObject? stack = runtime.currentStack;
    if (stack == null) return;
    final Set<String> names = <String>{
      for (final HostObject card in stack.children)
        if (card.kind == 'card')
          for (final HostObject f in card.children)
            if (f is CardField) f.name
    };
    if (names.isEmpty) return;
    final String where = names.map((String n) => 'field "$n" contains "$t"').join(' or ');
    await submit('find cards where $where');
    if (error != null) return;
    await submit('go to stack "found"');
    if (cards.isEmpty) {
      await showAllCards();
      error = null;
      runtime.msg = 'no card has "$t" in a field';
      notifyListeners();
    }
  }

  void _sync() {
    final HostObject? s = runtime.currentStack;
    if (s is CardStack) app.currentStack = s;
    final HostObject? c = runtime.currentCard;
    app.currentCard = c is RecipeCard ? c : null;
  }

  void _changed() {
    _sync();
    notifyListeners();
  }

  /// Saves [card] to the store. Used by the `save` command and the Save button.
  Future<void> saveCard(HostObject card) async {
    final CardStore? s = store;
    if (s == null) throw ScriptError('no card store is connected, so nothing can be saved');
    if (card is HomeCard) throw ScriptError('the Home card is built in; there is nothing to save');
    if (card is! RecipeCard) throw ScriptError('only recipe cards can be saved');
    try {
      await s.save(card);
    } on StoreException catch (e) {
      throw ScriptError(e.message);
    }
    _known.add(card.id);
    runtime.msg = 'saved "${card.name}"';
  }

  /// Deletes from the store any card that is no longer in the app.
  Future<void> _reconcile() async {
    final CardStore? s = store;
    if (s == null) return;
    final Set<String> present = <String>{
      for (final HostObject st in app.children)
        if (st.kind == 'stack')
          for (final HostObject c in st.children)
            if (c.kind == 'card') c.id
    };
    for (final String id in _known.difference(present).toList()) {
      try {
        await s.delete(id);
        _known.remove(id);
      } on StoreException catch (e) {
        error = e.message;
      }
    }
  }

  /// The Save button.
  Future<void> saveCurrent() => submit('save');

  /// Runs a line typed in the message box.
  Future<void> submit(String line) async {
    if (line.trim().isEmpty) return;
    error = null;
    try {
      await runtime.run(line);
    } on SpeakeasyError catch (e) {
      error = e.toString();
    }
    await _reconcile();
    _sync();
    notifyListeners();
  }

  /// A button was pressed: send it `mouseUp`.
  Future<void> press(HostObject button) async {
    error = null;
    try {
      await runtime.send('mouseUp', button);
    } on SpeakeasyError catch (e) {
      error = e.toString();
    }
    await _reconcile();
    _sync();
    notifyListeners();
  }

  /// The user picked a card in the list.
  void open(HostObject card) {
    runtime.goToCard(card);
    _sync();
    notifyListeners();
  }

  /// Leave the substack and return to the whole stack.
  Future<void> showAllCards() async {
    final String? name = runtime.currentStack?.name;
    if (name == null) return;
    await submit('go to stack "$name"');
  }

  /// Adds a field or button named [name] to the current card and saves it.
  /// Returns the new object, or null (with [error] set) if it cannot be added.
  Future<HostObject?> addObject(String kind, String name) async {
    error = null;
    final HostObject? card = currentCard;
    final String n = name.trim();
    if (card is HomeCard) {
      error = 'the Home card is built in and cannot be changed';
    } else if (card is! RecipeCard) {
      error = 'there is no current card';
    } else if (n.isEmpty) {
      error = 'a $kind needs a name';
    } else if (card.find(kind, n) != null) {
      error = 'this card already has a $kind named "$n"';
    } else {
      final BaseHostObject obj = kind == 'field' ? CardField(n) : CardButton(n);
      card.add(obj);
      notifyListeners();
      await submit('save');
      return obj;
    }
    notifyListeners();
    return null;
  }

  bool _isStandard(HostObject o) =>
      o is CardField && RecipeCard.fieldSpecs.any((s) => s.$1 == o.name);

  /// Renames a custom field or a button on the current card, then saves.
  Future<void> renameObject(HostObject object, String newName) async {
    error = null;
    final HostObject? card = currentCard;
    final String n = newName.trim();
    if (card is HomeCard) {
      error = 'the Home card is built in and cannot be changed';
    } else if (_isStandard(object)) {
      error = '"${object.name}" is a standard field and keeps its name';
    } else if (n.isEmpty) {
      error = 'a ${object.kind} needs a name';
    } else if (card == null || (n != object.name && card.find(object.kind, n) != null)) {
      error = 'this card already has a ${object.kind} named "$n"';
    } else {
      object.name = n;
      notifyListeners();
      await submit('save');
      return;
    }
    notifyListeners();
  }

  /// Deletes a custom field or a button from the current card, then saves.
  Future<void> deleteObject(HostObject object) async {
    if (currentCard is HomeCard) {
      error = 'the Home card is built in and cannot be changed';
      notifyListeners();
      return;
    }
    if (_isStandard(object)) {
      error = '"${object.name}" is a standard field and cannot be deleted';
      notifyListeners();
      return;
    }
    await submit('delete ${object.kind} "${object.name}"');
    if (error == null) await submit('save');
  }

  /// Marks a field required or not, then saves.
  Future<void> setRequired(CardField field, bool value) async {
    if (currentCard is HomeCard) return;
    field.isRequired = value;
    notifyListeners();
    await submit('save');
  }

  /// Checks [text] as a script. Returns the error message, or null if it parses.
  String? checkScript(String text) {
    try {
      Parser.parseScript(text);
      return null;
    } on SpeakeasyError catch (e) {
      return e.toString();
    }
  }

  /// Sets [object]'s script (card or button) and saves the card.
  Future<void> setScript(HostObject object, String text) async {
    if (currentCard is HomeCard) {
      error = 'the Home card is built in and cannot be changed';
      notifyListeners();
      return;
    }
    object.script = text;
    notifyListeners();
    await submit('save');
  }

  /// The user typed in a field.
  void editField(CardField field, String text) {
    field.text = text;
    notifyListeners();
  }
}
