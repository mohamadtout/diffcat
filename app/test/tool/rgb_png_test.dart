import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/store/rgb_png.dart';

void main() {
  test('writes a 24-bit PNG (no alpha) that decodes to the same pixels', () async {
    const w = 7, h = 5;
    final rgba = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      rgba
        ..[i * 4] = (i * 37) & 0xFF
        ..[i * 4 + 1] = (i * 11 + 200) & 0xFF
        ..[i * 4 + 2] = (255 - i * 5) & 0xFF
        ..[i * 4 + 3] = 255;
    }
    final png = encodeRgbPng(w, h, rgba);

    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    expect(png[25], 2, reason: 'IHDR colour type 2 = RGB without alpha');

    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    expect((image.width, image.height), (w, h));
    final decoded = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    expect(decoded, rgba);
  });
}
