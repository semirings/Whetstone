/// Speakeasy's `ask`, `answer` and `beep` as Flutter dialogs.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speakeasy/speakeasy.dart';

class DialogIo extends Io {
  const DialogIo(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  BuildContext? get _context => navigatorKey.currentState?.overlay?.context;

  @override
  Future<String?> ask(String prompt, String defaultAnswer) async {
    final BuildContext? context = _context;
    if (context == null) return null;
    final TextEditingController text = TextEditingController(text: defaultAnswer);
    final String? reply = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(prompt),
        content: TextField(
          controller: text,
          autofocus: true,
          onSubmitted: (String v) => Navigator.of(ctx).pop(v),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(text.text),
              child: const Text('OK')),
        ],
      ),
    );
    text.dispose();
    return reply;
  }

  @override
  Future<String> answer(String message, List<String> buttons) async {
    final BuildContext? context = _context;
    final List<String> labels = buttons.isEmpty ? <String>['OK'] : buttons;
    if (context == null) return labels.first;
    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        content: Text(message),
        actions: <Widget>[
          for (final String b in labels)
            TextButton(onPressed: () => Navigator.of(ctx).pop(b), child: Text(b)),
        ],
      ),
    );
    return choice ?? labels.first;
  }

  @override
  void beep(int count) => SystemSound.play(SystemSoundType.alert);

  @override
  Future<void> wait(Duration duration) => Future<void>.delayed(duration);
}
