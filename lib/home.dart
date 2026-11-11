/// The Home card: the first thing shown once Whetstone is up. A 5 x 3 grid of
/// tiles; each live tile is a button on the card whose script takes you
/// somewhere. Empty slots are left for templates that do not exist yet.
library;

import 'package:flutter/material.dart';

import 'controller.dart';
import 'model/model.dart';

/// One tile of the Home grid. [slot] is 0..14, row by row from the top left.
class HomeTile {
  const HomeTile({
    required this.slot,
    required this.name,
    required this.blurb,
    required this.tag,
    required this.accent,
    required this.script,
  });

  final int slot;
  final String name;
  final String blurb;
  final String tag;
  final Color accent;
  final String script;
}

const Color tileGreen = Color(0xFF007F00); // recipes and templates
const Color tileBlue = Color(0xFF5B8DEF); // browsing and admin

/// The built-in Home card. It is never stored and cannot be edited or saved.
class HomeCard extends RecipeCard {
  HomeCard(Iterable<HomeTile> tileList)
      : tiles = List<HomeTile>.unmodifiable(tileList),
        super('Home', id: homeId, standardFields: false) {
    for (final HomeTile t in tiles) {
      add(CardButton(t.name, script: t.script));
    }
  }

  /// The tiles Whetstone has today. [recipes] is the stack "All cards" opens.
  /// Template tiles (Problem & fix, How-to, ...) join this list when their
  /// master cards exist.
  factory HomeCard.standard({required String recipes}) => HomeCard(<HomeTile>[
        HomeTile(
          slot: 13,
          name: 'All cards',
          blurb: 'browse, search',
          tag: 'BROWSE',
          accent: tileBlue,
          script: 'on mouseUp\n  go to stack "${recipes.replaceAll('"', '')}"\nend mouseUp\n',
        ),
      ]);

  static const String homeId = 'home';
  static const int columns = 5;
  static const int rows = 3;

  final List<HomeTile> tiles;

  CardButton? buttonFor(HomeTile t) {
    final Object? b = find('button', t.name);
    return b is CardButton ? b : null;
  }
}

/// Draws [HomeCard] on a fixed 1000 x 600 (5:3) face and scales it to fit.
class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.controller, required this.card});

  final WhetstoneController controller;
  final HomeCard card;

  static const double _w = 1000;
  static const double _h = 600;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(width: _w, height: _h, child: _face(context)),
      ),
    );
  }

  Widget _face(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const double gap = 16;
    const double left = 32;
    const double top = 96;
    const double bottomRoom = 50;
    final double tileW = (_w - 2 * left - (HomeCard.columns - 1) * gap) / HomeCard.columns;
    final double tileH = (_h - top - bottomRoom - (HomeCard.rows - 1) * gap) / HomeCard.rows;
    final Map<int, HomeTile> bySlot = <int, HomeTile>{for (final HomeTile t in card.tiles) t.slot: t};
    final int count = controller.app.children
        .where((o) => o.kind == 'stack' && o.name != 'Home')
        .fold<int>(0, (int n, o) => n + o.children.where((c) => c.kind == 'card').length);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant, width: 2),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: left,
            top: 22,
            child: Text('Home',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          ),
          for (int i = 0; i < HomeCard.columns * HomeCard.rows; i++)
            Positioned(
              left: left + (i % HomeCard.columns) * (tileW + gap),
              top: top + (i ~/ HomeCard.columns) * (tileH + gap),
              width: tileW,
              height: tileH,
              child: bySlot[i] == null
                  ? CustomPaint(painter: _DashedBorder(scheme.outlineVariant))
                  : _tile(context, bySlot[i]!),
            ),
          Positioned(
            left: left,
            bottom: 18,
            child: Text('$count ${count == 1 ? 'card' : 'cards'}',
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, HomeTile t) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final CardButton? button = card.buttonFor(t);
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: t.accent, width: 3),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: button == null ? null : () => controller.press(button),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface)),
              const SizedBox(height: 6),
              Text(t.blurb, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const Spacer(),
              Text(t.tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.accent)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed rounded rectangle: an empty slot.
class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final Path outline = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)));
    for (final metric in outline.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 14) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
