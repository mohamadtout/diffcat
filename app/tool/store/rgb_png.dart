import 'dart:io';
import 'dart:typed_data';

/// Encodes RGBA pixels ([width] × [height], 4 bytes each, as from
/// `Image.toByteData(format: rawRgba)`) as a 24-bit RGB PNG, dropping alpha.
///
/// Flutter's own PNG encoder always writes an alpha channel, which App Store
/// Connect rejects ("Images can't include alpha channels") and Play rejects for
/// screenshots and the feature graphic. Assumes opaque pixels.
Uint8List encodeRgbPng(int width, int height, Uint8List rgba) {
  assert(rgba.length == width * height * 4);
  // Each row: filter type 1 ("Sub", each byte minus the byte one pixel to its
  // left), which shrinks gradients and flat UI a lot.
  final rows = Uint8List(height * (1 + width * 3));
  var o = 0;
  for (var y = 0; y < height; y++) {
    rows[o++] = 1;
    final row = y * width * 4;
    for (var x = 0; x < width; x++) {
      for (var c = 0; c < 3; c++) {
        final v = rgba[row + x * 4 + c];
        final left = x == 0 ? 0 : rgba[row + (x - 1) * 4 + c];
        rows[o++] = (v - left) & 0xFF;
      }
    }
  }
  final out = BytesBuilder(copy: false)..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2); // colour type 2: RGB, no alpha (compression, filter, interlace: 0)
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(out, 'IDAT', Uint8List.fromList(ZLibEncoder(level: 9).convert(rows)));
  _chunk(out, 'IEND', Uint8List(0));
  return out.takeBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  out
    ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
    ..add(typeBytes)
    ..add(data)
    ..add((ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]))).buffer.asUint8List());
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
