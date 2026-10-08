import 'package:flutter/material.dart';

/// Bottom sheet with a text-size slider. [onChanged] fires while dragging, and
/// the barrier is transparent, so the content behind resizes live.
Future<void> showTextSizeSheet(
  BuildContext context, {
  required double value,
  required double min,
  required double max,
  required ValueChanged<double> onChanged,
  double step = 0.5,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true, // cover the shell navigation bar/rail
  showDragHandle: true,
  barrierColor: Colors.transparent,
  builder: (_) => TextSizeSlider(value: value, min: min, max: max, step: step, onChanged: onChanged),
);

class TextSizeSlider extends StatefulWidget {
  const TextSizeSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 0.5,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  @override
  State<TextSizeSlider> createState() => _TextSizeSliderState();
}

class _TextSizeSliderState extends State<TextSizeSlider> {
  late double _value = widget.value.clamp(widget.min, widget.max);

  String get _label => _value == _value.roundToDouble() ? '${_value.round()}' : _value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Text size', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text(_label, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.text_decrease, size: 18),
              Expanded(
                child: Slider(
                  value: _value,
                  min: widget.min,
                  max: widget.max,
                  divisions: ((widget.max - widget.min) / widget.step).round(),
                  label: _label,
                  onChanged: (v) {
                    setState(() => _value = v);
                    widget.onChanged(v);
                  },
                ),
              ),
              const Icon(Icons.text_increase, size: 24),
            ],
          ),
        ],
      ),
    ),
  );
}
