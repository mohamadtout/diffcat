import 'package:flutter/material.dart';

/// Picks an opaque color: hue / saturation / brightness sliders, a hex field
/// and a few swatches. Returns null when cancelled.
Future<Color?> showColorPicker(BuildContext context, {required Color initial, required String title}) =>
    showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(initial: initial, title: title),
    );

/// `#RRGGBB` (alpha dropped: picked colors are opaque).
String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Parses `#RGB`, `RRGGBB`, `#RRGGBB`. Null if it isn't one of those.
Color? parseHexColor(String text) {
  var h = text.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
  return Color(0xFF000000 | int.parse(h, radix: 16));
}

const _swatches = [
  Color(0xFF1A7F37), Color(0xFF3FB950), Color(0xFF0969DA), Color(0xFF58A6FF), Color(0xFF8250DF), //
  Color(0xFFCF222E), Color(0xFFF85149), Color(0xFFBC4C00), Color(0xFFD29922), Color(0xFF8C959F),
  Color(0xFFE6FFEC), Color(0xFFFFEBE9), Color(0xFFDDF4FF), Color(0xFF12261E), Color(0xFF25171C),
];

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial, required this.title});

  final Color initial;
  final String title;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial.withValues(alpha: 1));
  late final _hex = TextEditingController(text: hexOf(_hsv.toColor()).substring(1));

  void _set(HSVColor hsv, {bool updateHex = true}) {
    setState(() => _hsv = hsv);
    if (updateHex) _hex.text = hexOf(hsv.toColor()).substring(1);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Widget _slider(String label, double value, double max, List<Color> track, ValueChanged<double> onChanged) => Row(
    children: [
      SizedBox(width: 28, child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
      Expanded(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: LinearGradient(colors: track),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context)
                  .copyWith(activeTrackColor: Colors.transparent, inactiveTrackColor: Colors.transparent),
              child: Slider(value: value, max: max, onChanged: onChanged),
            ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    decoration: const InputDecoration(prefixText: '#', labelText: 'Hex', isDense: true),
                    maxLength: 6,
                    onChanged: (v) {
                      final c = v.length == 6 ? parseHexColor(v) : null;
                      if (c != null) _set(HSVColor.fromColor(c), updateHex: false);
                    },
                  ),
                ),
              ],
            ),
            _slider('H', _hsv.hue, 360, [
              for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
            ], (v) => _set(_hsv.withHue(v))),
            _slider('S', _hsv.saturation, 1, [
              _hsv.withSaturation(0).toColor(),
              _hsv.withSaturation(1).toColor(),
            ], (v) => _set(_hsv.withSaturation(v))),
            _slider('B', _hsv.value, 1, [Colors.black, _hsv.withValue(1).toColor()], (v) => _set(_hsv.withValue(v))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _swatches)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _set(HSVColor.fromColor(c)),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, color), child: const Text('Use')),
      ],
    );
  }
}
