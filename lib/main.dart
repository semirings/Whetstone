import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speakeasy/speakeasy.dart';

import 'controller.dart';
import 'dialog_io.dart';
import 'model/model.dart';
import 'storage/card_store.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Sample data until storage exists (milestone 1).
WhetstoneApp sampleApp() {
  final WhetstoneApp app = WhetstoneApp();
  final CardStack stack = CardStack('Recipes');
  app.addStack(stack);
  RecipeCard add(String title, String symptom, String status) {
    final RecipeCard c = RecipeCard(title);
    c.field('symptom')!.text = symptom;
    c.field('status')!.text = status;
    stack.addCard(c);
    return c;
  }

  add('Camera points nowhere', 'camera view is empty after adding a camera', 'stuck');
  add('Grease pencil has no fill', 'grease pencil strokes show no fill', 'solved');
  final RecipeCard third =
      add('Render takes forever', 'render is very slow on a simple scene', 'stuck');
  third.add(CardButton('Mark solved',
      script: 'on mouseUp\n  put "solved" into field "status"\nend mouseUp\n'));
  return app;
}

/// Where the Whetstone backend listens (see run.sh; override with
/// --dart-define=WHETSTONE_BACKEND_URL=...).
const String backendUrl =
    String.fromEnvironment('WHETSTONE_BACKEND_URL', defaultValue: 'http://127.0.0.1:8402');

/// Loads the cards from the backend. On a first run (nothing stored) the
/// sample cards are saved there. If the backend cannot be reached, the sample
/// cards are shown without a store and [warning] says so.
Future<({WhetstoneApp app, CardStore? store, List<RecipeCard> stored, String? warning})>
    startUp(CardStore store) async {
  try {
    final List<StoredCard> loaded = await store.loadAll();
    if (loaded.isNotEmpty) {
      final WhetstoneApp app = WhetstoneApp();
      final Map<String, CardStack> stacks = <String, CardStack>{};
      for (final StoredCard s in loaded) {
        final CardStack stack =
            stacks.putIfAbsent(s.stack, () => CardStack(s.stack)..parent = app);
        stack.addCard(s.card);
      }
      for (final CardStack s in stacks.values) {
        app.addStack(s);
      }
      return (
        app: app,
        store: store,
        stored: <RecipeCard>[for (final StoredCard s in loaded) s.card],
        warning: null
      );
    }
    final WhetstoneApp app = sampleApp();
    final List<RecipeCard> cards = <RecipeCard>[
      for (final HostObject s in app.children)
        for (final HostObject c in s.children)
          if (c is RecipeCard) c
    ];
    for (final RecipeCard c in cards) {
      await store.save(c);
    }
    return (app: app, store: store, stored: cards, warning: null);
  } on StoreException catch (e) {
    return (
      app: sampleApp(),
      store: null,
      stored: const <RecipeCard>[],
      warning: '$e. Showing sample cards; nothing will be saved.'
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final start = await startUp(HttpCardStore(Uri.parse(backendUrl)));
  final WhetstoneController controller = WhetstoneController(
    start.app,
    io: DialogIo(navigatorKey),
    store: start.store,
    stored: start.stored,
  )..error = start.warning;
  runApp(WhetstoneWindow(controller: controller));
}

class WhetstoneWindow extends StatefulWidget {
  const WhetstoneWindow({super.key, required this.controller});

  final WhetstoneController controller;

  @override
  State<WhetstoneWindow> createState() => _WhetstoneWindowState();
}

class _WhetstoneWindowState extends State<WhetstoneWindow> {
  /// Dark by default; the button in the title bar switches.
  ThemeMode _mode = ThemeMode.dark;

  static ThemeData _theme(Brightness brightness) => ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: brightness,
        useMaterial3: true,
      );

  void _toggleTheme() => setState(() {
        _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      });

  Future<void> _deleteCard() async {
    final BuildContext? ctx = navigatorKey.currentContext;
    final HostObject? card = widget.controller.currentCard;
    if (ctx == null || card == null) return;
    final bool? ok = await showDialog<bool>(
      context: ctx,
      builder: (BuildContext c) => AlertDialog(
        title: Text('Delete "${card.name}"?'),
        content: const Text('The card is removed for good, including from storage.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await widget.controller.submit('delete this card');
  }

  Future<void> _newObject(String kind) async {
    final BuildContext? ctx = navigatorKey.currentContext;
    if (ctx == null || widget.controller.currentCard == null) return;
    final TextEditingController text = TextEditingController();
    final String? name = await showDialog<String>(
      context: ctx,
      builder: (BuildContext c) => AlertDialog(
        title: Text('New $kind'),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: InputDecoration(labelText: '$kind name'),
          onSubmitted: (String v) => Navigator.pop(c, v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, text.text), child: const Text('Create')),
        ],
      ),
    );
    text.dispose();
    if (name != null) await widget.controller.addObject(kind, name);
  }

  Future<void> _editScript(HostObject? object) async {
    final BuildContext? ctx = navigatorKey.currentContext;
    if (ctx == null || object == null) return;
    final WhetstoneController c = widget.controller;
    final TextEditingController text = TextEditingController(text: object.script);
    final String? result = await showDialog<String>(
      context: ctx,
      builder: (BuildContext dc) {
        String? problem;
        return StatefulBuilder(
          builder: (BuildContext dc, StateSetter set) => AlertDialog(
            title: Text('Script of ${object.kind} "${object.name}"'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: text,
                    autofocus: true,
                    minLines: 10,
                    maxLines: 18,
                    style: const TextStyle(fontFamily: 'Menlo', fontSize: 13),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  if (problem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(problem!,
                          style: TextStyle(color: Theme.of(dc).colorScheme.error)),
                    ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final String? err = c.checkScript(text.text);
                  if (err == null) {
                    Navigator.pop(dc, text.text);
                  } else {
                    set(() => problem = err);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    text.dispose();
    if (result != null) await c.setScript(object, result);
  }

  /// A submenu listing the current card's [kind]s; picking one runs [action].
  /// With [mark], required fields show a check.
  PlatformMenu _pick(String label, String kind, Future<void> Function(HostObject) action,
      {bool mark = false}) {
    final HostObject? card = widget.controller.currentCard;
    return PlatformMenu(label: label, menus: <PlatformMenuItem>[
      for (final HostObject o in card?.children ?? const <HostObject>[])
        if (o.kind == kind)
          PlatformMenuItem(
            label: mark && o is CardField && o.isRequired ? '\u2713 ${o.name}' : o.name,
            onSelected: () => action(o),
          ),
    ]);
  }

  Future<void> _renameObject(HostObject object) async {
    final BuildContext? ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final TextEditingController text = TextEditingController(text: object.name);
    final String? name = await showDialog<String>(
      context: ctx,
      builder: (BuildContext c) => AlertDialog(
        title: Text('Rename ${object.kind} "${object.name}"'),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'new name'),
          onSubmitted: (String v) => Navigator.pop(c, v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, text.text), child: const Text('Rename')),
        ],
      ),
    );
    text.dispose();
    if (name != null) await widget.controller.renameObject(object, name);
  }

  Future<void> _confirmDelete(HostObject object) async {
    final BuildContext? ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final bool? ok = await showDialog<bool>(
      context: ctx,
      builder: (BuildContext c) => AlertDialog(
        title: Text('Delete ${object.kind} "${object.name}"?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await widget.controller.deleteObject(object);
  }

  /// The menu bar. Each item sends a Speakeasy command, as HyperCard's did.
  List<PlatformMenu> _menus() {
    final WhetstoneController c = widget.controller;
    PlatformMenuItem item(String label, VoidCallback run, [MenuSerializableShortcut? key]) =>
        PlatformMenuItem(label: label, shortcut: key, onSelected: run);
    SingleActivator cmd(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, meta: true, shift: shift);
    return <PlatformMenu>[
      const PlatformMenu(label: 'Whetstone', menus: <PlatformMenuItem>[
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
      ]),
      PlatformMenu(label: 'File', menus: <PlatformMenuItem>[
        item('New Card', () => c.submit('create card "Untitled"'),
            cmd(LogicalKeyboardKey.keyN)),
        item('Save', c.saveCurrent, cmd(LogicalKeyboardKey.keyS)),
        item('Delete Card\u2026', _deleteCard,
            cmd(LogicalKeyboardKey.backspace)),
      ]),
      PlatformMenu(label: 'Go', menus: <PlatformMenuItem>[
        item('First', () => c.submit('go to first card'), cmd(LogicalKeyboardKey.digit1)),
        item('Previous', () => c.submit('go to previous card'), cmd(LogicalKeyboardKey.digit2)),
        item('Next', () => c.submit('go to next card'), cmd(LogicalKeyboardKey.digit3)),
        item('Last', () => c.submit('go to last card'), cmd(LogicalKeyboardKey.digit4)),
        item('All Cards', c.showAllCards, cmd(LogicalKeyboardKey.keyA, shift: true)),
      ]),
      PlatformMenu(label: 'Objects', menus: <PlatformMenuItem>[
        item('New Field\u2026', () => _newObject('field')),
        item('New Button\u2026', () => _newObject('button')),
        PlatformMenuItemGroup(members: <PlatformMenuItem>[
          item('Card Script\u2026', () => _editScript(c.currentCard),
              cmd(LogicalKeyboardKey.keyE)),
          PlatformMenu(label: 'Button Script', menus: <PlatformMenuItem>[
            for (final HostObject b in c.currentCard?.children ?? const <HostObject>[])
              if (b.kind == 'button') item(b.name, () => _editScript(b)),
          ]),
        ]),
      PlatformMenuItemGroup(members: <PlatformMenuItem>[
        _pick('Rename Field', 'field', _renameObject),
        _pick('Rename Button', 'button', _renameObject),
        _pick('Delete Field', 'field', _confirmDelete),
        _pick('Delete Button', 'button', _confirmDelete),
        _pick('Required Fields', 'field', (HostObject f) =>
            c.setRequired(f as CardField, !f.isRequired), mark: true),
      ]),
      ]),
      PlatformMenu(label: 'View', menus: <PlatformMenuItem>[
        item(_mode == ThemeMode.dark ? 'Light Theme' : 'Dark Theme', _toggleTheme,
            cmd(LogicalKeyboardKey.keyT, shift: true)),
      ]),
      const PlatformMenu(label: 'Window', menus: <PlatformMenuItem>[
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? _) => PlatformMenuBar(
      menus: _menus(),
      child: MaterialApp(
        title: 'Whetstone',
        navigatorKey: navigatorKey,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: _mode,
        home: HomePage(controller: widget.controller, onToggleTheme: _toggleTheme),
      ),
    ));
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller, required this.onToggleTheme});

  final WhetstoneController controller;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Whetstone'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Save card',
                icon: const Icon(Icons.save_outlined),
                onPressed: controller.saveCurrent,
              ),
              IconButton(
                tooltip: Theme.of(context).brightness == Brightness.dark
                    ? 'Light theme'
                    : 'Dark theme',
                icon: Icon(Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode
                    : Icons.dark_mode),
                onPressed: onToggleTheme,
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    SizedBox(width: 280, child: CardList(controller: controller)),
                    const VerticalDivider(width: 1),
                    Expanded(child: CardView(controller: controller)),
                  ],
                ),
              ),
              const Divider(height: 1),
              MessageBox(controller: controller),
            ],
          ),
        );
      },
    );
  }
}

class CardList extends StatelessWidget {
  const CardList({super.key, required this.controller});

  final WhetstoneController controller;

  @override
  Widget build(BuildContext context) {
    final List<HostObject> cards = controller.cards;
    return Column(
      children: <Widget>[
        if (controller.viewingSubstack)
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              dense: true,
              title: Text('Results: ${controller.substackName} (${cards.length})'),
              trailing: const Icon(Icons.close),
              onTap: controller.showAllCards,
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: cards.length,
            itemBuilder: (BuildContext context, int i) {
              final HostObject card = cards[i];
              final HostObject? symptom = card.find('field', 'symptom');
              return ListTile(
                selected: identical(card, controller.currentCard),
                title: Text(card.name.isEmpty ? '(untitled)' : card.name),
                subtitle: symptom == null
                    ? null
                    : Text('${symptom.getProperty('text')}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => controller.open(card),
              );
            },
          ),
        ),
      ],
    );
  }
}

class CardView extends StatelessWidget {
  const CardView({super.key, required this.controller});

  final WhetstoneController controller;

  @override
  Widget build(BuildContext context) {
    final HostObject? card = controller.currentCard;
    if (card == null) {
      return const Center(child: Text('No card. Type: create card "Title"'));
    }
    final List<HostObject> buttons = <HostObject>[
      for (final HostObject c in card.children)
        if (c.kind == 'button') c
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(card.name.isEmpty ? '(untitled)' : card.name,
            style: Theme.of(context).textTheme.headlineSmall),
        if (buttons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                for (final HostObject b in buttons)
                  FilledButton(
                      onPressed: () => controller.press(b), child: Text(b.name)),
              ],
            ),
          ),
        for (final HostObject f in card.children)
          if (f is CardField)
            FieldEditor(
              key: ValueKey<String>('${card.id}/${f.id}'),
              field: f,
              onChanged: (String t) => controller.editField(f, t),
            ),
      ],
    );
  }
}

/// A text box for one field. Follows the model when a script changes the
/// field, unless the user is typing in it.
class FieldEditor extends StatefulWidget {
  const FieldEditor({super.key, required this.field, required this.onChanged});

  final CardField field;
  final ValueChanged<String> onChanged;

  @override
  State<FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<FieldEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.field.text);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(FieldEditor old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _text.text != widget.field.text) {
      _text.text = widget.field.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool multiline = const <String>{'calls', 'steps', 'narration', 'summary'}
        .contains(widget.field.name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _text,
        focusNode: _focus,
        minLines: 1,
        maxLines: multiline ? 8 : 3,
        decoration: InputDecoration(
          labelText: widget.field.isRequired
              ? '${widget.field.name} *'
              : widget.field.name,
          border: const OutlineInputBorder(),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class MessageBox extends StatefulWidget {
  const MessageBox({super.key, required this.controller});

  final WhetstoneController controller;

  @override
  State<MessageBox> createState() => _MessageBoxState();
}

class _MessageBoxState extends State<MessageBox> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final List<String> _history = <String>[];

  Future<void> _submit(String line) async {
    if (line.trim().isNotEmpty) _history.add(line);
    _text.clear();
    await widget.controller.submit(line);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WhetstoneController c = widget.controller;
    final String? error = c.error;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (error != null)
            Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (c.msg.isNotEmpty)
            Text(c.msg),
          const SizedBox(height: 6),
          TextField(
            controller: _text,
            focusNode: _focus,
            autofocus: true,
            decoration: const InputDecoration(
              prefixText: '> ',
              hintText: 'Speakeasy, e.g.  find cards where field "symptom" contains "render"',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: _submit,
          ),
        ],
      ),
    );
  }
}
