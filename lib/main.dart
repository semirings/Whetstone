import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speakeasy/speakeasy.dart';

import 'controller.dart';
import 'dialog_io.dart';
import 'home.dart';
import 'model/model.dart';
import 'storage/card_store.dart';
import 'storage/scene_client.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Where the Whetstone backend listens (see run.sh; override with
/// --dart-define=WHETSTONE_BACKEND_URL=...).
const String backendUrl =
    String.fromEnvironment('WHETSTONE_BACKEND_URL', defaultValue: 'http://127.0.0.1:8402');

/// How long the splash stays up at least, so it is seen even when the backend
/// answers at once. Set to Duration.zero to show it only while loading.
const Duration splashMinimum = Duration(milliseconds: 1200);

/// Loads the cards from the backend and builds the app: the Home card first,
/// then one stack per stored stack. If the backend cannot be reached the app
/// still opens on Home, with an empty "Recipes" stack, and [warning] says that
/// nothing will be saved.
Future<({WhetstoneApp app, CardStore? store, List<RecipeCard> stored, String? warning})>
    startUp(CardStore store) async {
  List<StoredCard> loaded = const <StoredCard>[];
  CardStore? usable = store;
  String? warning;
  try {
    loaded = await store.loadAll();
  } on StoreException catch (e) {
    usable = null;
    warning = '$e. Nothing will be saved.';
  }
  final WhetstoneApp app = WhetstoneApp();
  final Map<String, CardStack> stacks = <String, CardStack>{};
  for (final StoredCard s in loaded) {
    stacks.putIfAbsent(s.stack, () => CardStack(s.stack)).addCard(s.card);
  }
  if (stacks.isEmpty) stacks['Recipes'] = CardStack('Recipes');
  // The Home stack goes in first, so it is the current stack and Home the current card.
  final CardStack homeStack = CardStack('Home')
    ..addCard(HomeCard.standard(recipes: stacks.keys.first));
  app.addStack(homeStack);
  for (final CardStack s in stacks.values) {
    app.addStack(s);
  }
  return (
    app: app,
    store: usable,
    stored: <RecipeCard>[for (final StoredCard s in loaded) s.card],
    warning: warning,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

/// Shows the splash image until the backend has answered and the cards are
/// loaded, then opens the window on the Home card.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  WhetstoneController? _controller;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final Stopwatch clock = Stopwatch()..start();
    final start = await startUp(HttpCardStore(Uri.parse(backendUrl)));
    final Duration left = splashMinimum - clock.elapsed;
    if (left > Duration.zero) await Future<void>.delayed(left);
    if (!mounted) return;
    setState(() {
      _controller = WhetstoneController(
        start.app,
        io: DialogIo(navigatorKey),
        store: start.store,
        scene: HttpScene(Uri.parse(backendUrl)).operate,
        stored: start.stored,
      )..error = start.warning;
    });
  }

  @override
  Widget build(BuildContext context) {
    final WhetstoneController? c = _controller;
    return c == null ? const SplashScreen() : WhetstoneWindow(controller: c);
  }
}

/// The image in img/splash.png on a dark background.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Whetstone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        // The edge colour of img/splash.png, so the image has no visible border.
        backgroundColor: const Color(0xFF121316),
        body: Center(
          child: Image.asset(
            'img/splash.png',
            fit: BoxFit.contain,
            errorBuilder: (BuildContext c, Object e, StackTrace? st) => const Text(
              'Whetstone',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w600, color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

class WhetstoneWindow extends StatefulWidget {
  const WhetstoneWindow({super.key, required this.controller});

  final WhetstoneController controller;

  @override
  State<WhetstoneWindow> createState() => _WhetstoneWindowState();
}

class _WhetstoneWindowState extends State<WhetstoneWindow> {
  /// Dark by default; View > Light/Dark Theme switches.
  ThemeMode _mode = ThemeMode.dark;

  /// HyperCard showed one card and hid the message box until asked. Both extras
  /// start hidden: View > Card List and View > Message Box.
  bool _showList = false;
  bool _showMessage = false;

  static ThemeData _theme(Brightness brightness) => ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: brightness,
        useMaterial3: true,
      );

  void _toggleTheme() => setState(() {
        _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      });

  void _toggleList() => setState(() => _showList = !_showList);
  void _toggleMessage() => setState(() => _showMessage = !_showMessage);

  Future<void> _deleteCard() async {
    final BuildContext? ctx = navigatorKey.currentContext;
    final HostObject? card = widget.controller.currentCard;
    if (ctx == null || card == null) return;
    if (card is HomeCard) {
      widget.controller.complain('the Home card is built in and cannot be deleted');
      return;
    }
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

  Future<void> _find() async {
    final BuildContext? ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final TextEditingController text = TextEditingController();
    final String? query = await showDialog<String>(
      context: ctx,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Find'),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'text to find in any field'),
          onSubmitted: (String v) => Navigator.pop(c, v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, text.text), child: const Text('Find')),
        ],
      ),
    );
    text.dispose();
    if (query != null) await widget.controller.findText(query);
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

  /// The menu bar at the top of the screen (macOS). Each item sends a
  /// Speakeasy command, as HyperCard's did.
  List<PlatformMenu> _menus() {
    final WhetstoneController c = widget.controller;
    PlatformMenuItem item(String label, VoidCallback? run, [MenuSerializableShortcut? key]) =>
        PlatformMenuItem(label: label, shortcut: key, onSelected: run);
    SingleActivator cmd(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, meta: true, shift: shift);

    // The current card's fields or buttons as menu items. An empty list becomes
    // one disabled "(none)" so no submenu is ever empty.
    List<PlatformMenuItem> pick(String kind, Future<void> Function(HostObject) action,
        {bool mark = false}) {
      final List<PlatformMenuItem> items = <PlatformMenuItem>[
        for (final HostObject o in c.currentCard?.children ?? const <HostObject>[])
          if (o.kind == kind)
            item(mark && o is CardField && o.isRequired ? '\u2713 ${o.name}' : o.name,
                () => action(o)),
      ];
      return items.isEmpty ? <PlatformMenuItem>[item('(none)', null)] : items;
    }

    return <PlatformMenu>[
      const PlatformMenu(label: 'Whetstone', menus: <PlatformMenuItem>[
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
      ]),
      PlatformMenu(label: 'File', menus: <PlatformMenuItem>[
        item('New Card', () => c.submit('create card "Untitled"'),
            cmd(LogicalKeyboardKey.keyN)),
        item('Save', c.saveCurrent, cmd(LogicalKeyboardKey.keyS)),
        item('Delete Card\u2026', _deleteCard),
      ]),
      PlatformMenu(label: 'Go', menus: <PlatformMenuItem>[
        item('Home', c.goHome, cmd(LogicalKeyboardKey.keyH, shift: true)),
        item('First', () => c.submit('go to first card'), cmd(LogicalKeyboardKey.digit1)),
        item('Previous', () => c.submit('go to previous card'), cmd(LogicalKeyboardKey.digit2)),
        item('Next', () => c.submit('go to next card'), cmd(LogicalKeyboardKey.digit3)),
        item('Last', () => c.submit('go to last card'), cmd(LogicalKeyboardKey.digit4)),
        item('Find\u2026', _find, cmd(LogicalKeyboardKey.keyF)),
        item('All Cards', c.showAllCards, cmd(LogicalKeyboardKey.keyA, shift: true)),
      ]),
      PlatformMenu(label: 'Objects', menus: <PlatformMenuItem>[
        item('New Field\u2026', () => _newObject('field')),
        item('New Button\u2026', () => _newObject('button')),
        item('Card Script\u2026', () => _editScript(c.currentCard),
            cmd(LogicalKeyboardKey.keyE)),
        PlatformMenu(label: 'Button Script', menus: pick('button', _editScript)),
        PlatformMenu(label: 'Rename Field', menus: pick('field', _renameObject)),
        PlatformMenu(label: 'Rename Button', menus: pick('button', _renameObject)),
        PlatformMenu(label: 'Delete Field', menus: pick('field', _confirmDelete)),
        PlatformMenu(label: 'Delete Button', menus: pick('button', _confirmDelete)),
        PlatformMenu(
            label: 'Required Fields',
            menus: pick('field', (HostObject f) => c.setRequired(f as CardField, !f.isRequired),
                mark: true)),
      ]),
      PlatformMenu(label: 'View', menus: <PlatformMenuItem>[
        item(_showMessage ? 'Hide Message Box' : 'Show Message Box', _toggleMessage,
            cmd(LogicalKeyboardKey.keyM)),
        item(_showList ? 'Hide Card List' : 'Show Card List', _toggleList,
            cmd(LogicalKeyboardKey.keyL)),
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
          home: HomePage(
            controller: widget.controller,
            showList: _showList,
            showMessage: _showMessage,
          ),
        ),
      ),
    );
  }
}

/// One card fills the window, as in HyperCard. A thin strip below it shows
/// where you are (3 of 12), steps between cards, and shows the last message.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.showList,
    required this.showMessage,
  });

  final WhetstoneController controller;
  final bool showList;
  final bool showMessage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        return Scaffold(
          body: Column(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    if (showList) ...<Widget>[
                      SizedBox(width: 280, child: CardList(controller: controller)),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(child: CardView(controller: controller)),
                  ],
                ),
              ),
              const Divider(height: 1),
              StatusStrip(controller: controller),
              if (showMessage) ...<Widget>[
                const Divider(height: 1),
                MessageBox(controller: controller),
              ],
            ],
          ),
        );
      },
    );
  }
}

class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, required this.controller});

  final WhetstoneController controller;

  @override
  Widget build(BuildContext context) {
    final WhetstoneController c = controller;
    final String? error = c.error;
    final String where = c.onHome
        ? 'Home'
        : c.cards.isEmpty
            ? 'no cards'
            : '${c.cardNumber} of ${c.cards.length}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Previous card',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => c.submit('go to previous card'),
          ),
          Text(c.viewingSubstack ? 'Results "${c.substackName}": $where' : where),
          IconButton(
            tooltip: 'Next card',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => c.submit('go to next card'),
          ),
          if (c.viewingSubstack)
            TextButton(onPressed: c.showAllCards, child: const Text('All cards')),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error ?? c.msg,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: error == null
                  ? null
                  : TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
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
    if (card is HomeCard) return HomeView(controller: controller, card: card);
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

enum _Run { idle, running, done, failed }

class MessageBox extends StatefulWidget {
  const MessageBox({super.key, required this.controller});

  final WhetstoneController controller;

  @override
  State<MessageBox> createState() => _MessageBoxState();
}

class _MessageBoxState extends State<MessageBox> {
  final TextEditingController _text = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final List<String> _history = <String>[];

  /// idle: nothing run yet, or the text was edited since. running: orange.
  /// done: green. failed: red, with the reason in the status strip.
  _Run _run = _Run.idle;

  /// Return runs what is in the box; Shift+Return starts a new line. Pasted
  /// text keeps its line breaks, so several statements can be run at once.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final bool enter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (enter && !HardwareKeyboard.instance.isShiftPressed) {
      if (event is KeyDownEvent) _submit(_text.text);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Runs the text and leaves it in the box; only Clear empties it.
  Future<void> _submit(String line) async {
    if (line.trim().isEmpty || _run == _Run.running) return;
    _history.add(line);
    setState(() => _run = _Run.running);
    await widget.controller.submit(line);
    if (!mounted) return;
    setState(() => _run = widget.controller.error == null ? _Run.done : _Run.failed);
    _focus.requestFocus();
  }

  void _clear() {
    _text.clear();
    setState(() => _run = _Run.idle);
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
    // The green and orange of the action buttons in DoubleNaught and SegForge.
    final Color edge = switch (_run) {
      _Run.running => const Color(0xFFE67E00),
      _Run.failed => const Color(0xFFE5534B),
      _ => const Color(0xFF007F00),
    };
    OutlineInputBorder border(double width) =>
        OutlineInputBorder(borderSide: BorderSide(color: edge, width: width));
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              autofocus: true,
              keyboardType: TextInputType.multiline,
              minLines: 1,
              maxLines: 6,
              onChanged: (_) {
                if (_run == _Run.done || _run == _Run.failed) setState(() => _run = _Run.idle);
              },
              decoration: InputDecoration(
                prefixText: '> ',
                hintText: 'Speakeasy, e.g.  find cards where field "symptom" contains "render"',
                isDense: true,
                filled: _run != _Run.idle,
                fillColor: edge.withValues(alpha: 0.12),
                border: border(2),
                enabledBorder: border(2),
                focusedBorder: border(2.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _run == _Run.running ? null : _clear,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
