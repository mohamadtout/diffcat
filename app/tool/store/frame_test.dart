import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/fonts.dart';
import 'rgb_png.dart';

/// Turns raw store screenshots into captioned store images, plus the App
/// Store header and search-results artwork and the Play feature graphic and
/// 512 px icon: `make store-frames`.
///
/// Reads `app/build/store/raw/<device>/` (from `make store-screenshots`),
/// writes `store/screenshots/<store>/<slot>/` at the repo root, one folder per
/// upload slot, named like the slot in the store's console. Captions are
/// listed here and in store/README.md; keep them in sync.
///
/// Images are written as 24-bit PNGs (no alpha channel): App Store Connect
/// rejects images with one, and so does Play for screenshots and the feature
/// graphic. Only Play's 512 px icon keeps its alpha channel, as Play asks.
const _brandTop = Color(0xFF8957E5);
const _brandMid = Color(0xFF4C2F9E);
const _brandBottom = Color(0xFF1B1446);
const _lavender = Color(0xFFD8C7FF);
const _bezel = Color(0xFF0D1117);

typedef _Shot = (String raw, String title, String subtitle);

const _phone = <_Shot>[
  ('01_repos', 'All your repos,\nin your pocket', 'Pin favorites. Open any public repo.'),
  ('03_diff', 'Diffs made for\nsmall screens', 'Wrapped lines and line numbers.'),
  ('04_pull', 'Review pull requests\nanywhere', 'Overview, changed files and commits.'),
  ('07_offline_mode', 'Download once,\nread offline', 'For flights, trains and slow networks.'),
  ('09_terminal', 'Your own machine,\nover SSH', 'Run git, tests and lazygit in a real terminal.'),
  ('06_changed_since', 'Everything since\nthe last release', 'Compare any branch, tag or commit.'),
  ('10_console', 'Git commands,\nno clone needed', 'log, branches and PRs, straight from GitHub.'),
  ('11_diff_dark', 'Easy on the eyes\nat night', 'Light and dark themes.'),
];

const _tablet = <_Shot>[
  ('02_commit_split', 'Commits and diffs,\nside by side', 'Built for iPad and tablets.'),
  ('03_diff_full_width', 'Go full width', 'Hide the list when you need the space.'),
  ('04_pull', 'Review pull requests\nanywhere', 'Overview, changed files and commits.'),
  ('05_file', 'Browse code at\nany branch or tag', 'With file history one tap away.'),
  ('07_offline_mode', 'Download once,\nread offline', 'For flights, trains and slow networks.'),
  ('09_terminal', 'Your own machine,\nover SSH', 'Run git, tests and lazygit in a real terminal.'),
  ('06_changed_since', 'Everything since\nthe last release', 'Compare any branch, tag or commit.'),
  ('11_diff_dark', 'Easy on the eyes\nat night', 'Light and dark themes.'),
];

/// (raw device folder, output folder, canvas size in px, shots)
const _targets = <(String, String, Size, List<_Shot>)>[
  // App Store Connect requires "iPhone with Dynamic Island (medium display)"
  // (iPhone 17 Pro: 1206 × 2622) and, for iPad apps, "iPad 13-inch display".
  // The large display (iPhone 17 Pro Max) is optional.
  ('iphone-6.3', 'app-store/iphone-dynamic-island-medium', Size(1206, 2622), _phone),
  ('iphone-6.9', 'app-store/iphone-dynamic-island-large', Size(1320, 2868), _phone),
  ('ipad-13', 'app-store/ipad-13', Size(2064, 2752), _tablet),
  ('android-phone', 'google-play/phone', Size(1080, 1920), _phone),
  // Android tablets are shot in landscape: in portrait they're narrower than
  // the 840dp split-view breakpoint.
  ('android-tablet-7', 'google-play/tablet-7', Size(1920, 1200), _tablet),
  ('android-tablet-10', 'google-play/tablet-10', Size(2560, 1600), _tablet),
];

final _repoRoot = Directory.current.path.endsWith('/app') ? Directory.current.parent.path : Directory.current.path;
final _rawRoot = '$_repoRoot/app/build/store/raw';
final _outRoot = '$_repoRoot/store/screenshots';

void main() {
  setUpAll(loadSdkFonts);

  for (final (raw, out, canvas, shots) in _targets) {
    testWidgets('frame $raw', (tester) async {
      final dir = Directory('$_rawRoot/$raw');
      if (!dir.existsSync()) {
        markTestSkipped('no raw screenshots in ${dir.path}; run make store-screenshots first');
        return;
      }
      var i = 0;
      for (final (name, title, subtitle) in shots) {
        final file = File('${dir.path}/$name.png');
        if (!file.existsSync()) {
          debugPrint('missing ${file.path}, skipped');
          continue;
        }
        final shot = (await tester.runAsync(() => _decode(file)))!;
        i++;
        await _render(
          tester,
          canvas,
          _Frame(shot: shot, title: title, subtitle: subtitle),
          '$_outRoot/$out/${i.toString().padLeft(2, '0')}_${name.substring(3)}.png',
        );
      }
    });
  }

  testWidgets('feature graphic and Play icon', (tester) async {
    final icon = (await tester.runAsync(() => _decode(File('$_repoRoot/app/assets/icon/icon.png'))))!;
    await _render(
      tester,
      const Size(1024, 500),
      _FeatureGraphic(icon: icon),
      '$_outRoot/google-play/feature-graphic.png',
    );
    await _render(
      tester,
      const Size(512, 512),
      RawImage(image: icon, fit: BoxFit.cover, filterQuality: FilterQuality.high),
      '$_outRoot/google-play/icon-512.png',
      alpha: true, // Play asks for a 32-bit PNG icon
    );
  });

  // Product page header (21:9) and search results (3:2) artwork. App Store
  // Connect lists them under "Header and Search Results". They are optional
  // and show on iOS/iPadOS 27 and later. Apple's guidance: one clear idea,
  // focal artwork centered (edges may be cropped), short text.
  testWidgets('App Store header and search results', (tester) async {
    final raw = Directory('$_rawRoot/iphone-6.3').existsSync() ? 'iphone-6.3' : 'iphone-6.9';
    Future<ui.Image?> load(String name) async {
      final f = File('$_rawRoot/$raw/$name.png');
      return f.existsSync() ? tester.runAsync(() => _decode(f)) : null;
    }

    final icon = (await tester.runAsync(() => _decode(File('$_repoRoot/app/assets/icon/icon.png'))))!;
    final diff = await load('03_diff');
    final pull = await load('04_pull');
    final repos = await load('01_repos');
    if (diff == null || pull == null || repos == null) {
      markTestSkipped('no raw iPhone screenshots; run make store-screenshots first');
      return;
    }
    await _render(
      tester,
      const Size(3840, 1646),
      _Header(icon: icon, left: diff, right: pull),
      '$_outRoot/app-store/header-and-search/product-page-header.png',
    );
    await _render(
      tester,
      const Size(3840, 2560),
      _SearchResult(shots: [repos, diff, pull]),
      '$_outRoot/app-store/header-and-search/search-results.png',
    );
  });
}

Future<ui.Image> _decode(File f) async {
  final codec = await ui.instantiateImageCodec(await f.readAsBytes());
  return (await codec.getNextFrame()).image;
}

final _boundary = GlobalKey();

Future<void> _render(WidgetTester tester, Size size, Widget child, String path, {bool alpha = false}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _boundary,
        child: SizedBox.fromSize(size: size, child: child),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final out = File(path);
    await out.parent.create(recursive: true);
    if (alpha) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await out.writeAsBytes(png!.buffer.asUint8List());
    } else {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      await out.writeAsBytes(encodeRgbPng(image.width, image.height, rgba!.buffer.asUint8List()));
    }
  });
  debugPrint('wrote $path (${size.width.toInt()}×${size.height.toInt()})');
}

const _gradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_brandTop, _brandMid, _brandBottom],
  stops: [0, 0.55, 1],
);

/// A caption plus the screenshot in a simple device bezel.
class _Frame extends StatelessWidget {
  const _Frame({required this.shot, required this.title, required this.subtitle});

  final ui.Image shot;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, c) => c.maxWidth > c.maxHeight ? _landscape(c) : _portrait(c));

  /// Portrait captions keep their hand-placed line breaks; the narrow
  /// landscape column wraps on its own.
  Widget _caption(double scale, TextAlign align) => Column(
    crossAxisAlignment: align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        align == TextAlign.center ? title : title.replaceAll('\n', ' '),
        textAlign: align,
        maxLines: 4,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          fontSize: scale * 0.08,
          height: 1.12,
          color: Colors.white,
          letterSpacing: -scale * 0.0015,
        ),
      ),
      SizedBox(height: scale * 0.03),
      Text(
        subtitle,
        textAlign: align,
        maxLines: 3,
        style: TextStyle(fontFamily: 'Roboto', fontSize: scale * 0.04, height: 1.3, color: _lavender),
      ),
    ],
  );

  Widget _device(double width, {required double bezel, required double radius}) =>
      _deviceFrame(shot, width, bezel: bezel, radius: radius);

  /// Landscape tablets: caption on the left, the device on the right.
  Widget _landscape(BoxConstraints c) {
    final w = c.maxWidth, h = c.maxHeight;
    final deviceW = w * 0.64;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: _gradient),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: w * 0.05,
            width: w * 0.27,
            top: 0,
            bottom: 0,
            child: Center(child: _caption(h * 0.95, TextAlign.left)),
          ),
          Positioned(
            right: w * 0.04,
            top: (h - (deviceW - 2 * deviceW * 0.018) * shot.height / shot.width - 2 * deviceW * 0.018) / 2,
            child: _device(deviceW, bezel: deviceW * 0.018, radius: deviceW * 0.035),
          ),
        ],
      ),
    );
  }

  /// Portrait: caption on top, the device below, running off the bottom edge.
  Widget _portrait(BoxConstraints c) {
    final w = c.maxWidth, h = c.maxHeight;
    final scale = w < h * 0.56 ? w : h * 0.56;
    final tablet = shot.width / shot.height > 0.6;
    final deviceW = w * (tablet ? 0.86 : 0.8);
    final top = scale * 0.43;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: _gradient),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: w * 0.07,
            right: w * 0.07,
            top: scale * 0.1,
            height: top - scale * 0.1,
            child: Align(alignment: Alignment.topCenter, child: _caption(scale, TextAlign.center)),
          ),
          Positioned(
            top: top,
            left: (w - deviceW) / 2,
            child: _device(
              deviceW,
              bezel: deviceW * (tablet ? 0.022 : 0.03),
              radius: deviceW * (tablet ? 0.045 : 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Play Store feature graphic (1024×500): icon, name and tagline.
class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic({required this.icon});

  final ui.Image icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: _gradient),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 72),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(64),
            child: SizedBox.square(
              dimension: 280,
              child: RawImage(image: icon, fit: BoxFit.cover, filterQuality: FilterQuality.high),
            ),
          ),
          const SizedBox(width: 56),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diffcat',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 72,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Review GitHub code changes\nfrom your phone or tablet',
                  style: TextStyle(fontFamily: 'Roboto', fontSize: 34, height: 1.3, color: _lavender),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// [shot] in a simple dark device bezel with a soft shadow, [width] wide.
Widget _deviceFrame(ui.Image shot, double width, {required double bezel, required double radius}) => DecoratedBox(
  decoration: BoxDecoration(
    color: _bezel,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.45),
        blurRadius: width * 0.06,
        offset: Offset(0, width * 0.025),
      ),
    ],
  ),
  child: Padding(
    padding: EdgeInsets.all(bezel),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius - bezel),
      child: SizedBox(
        width: width - 2 * bezel,
        child: AspectRatio(
          aspectRatio: shot.width / shot.height,
          child: RawImage(image: shot, fit: BoxFit.cover, filterQuality: FilterQuality.high),
        ),
      ),
    ),
  ),
);

/// A phone screenshot in a bezel, sized for the header and search artwork.
Widget _phoneFrame(ui.Image shot, double width) => _deviceFrame(shot, width, bezel: width * 0.03, radius: width * 0.12);

/// Product page header, 3840 × 1646 (21:9): icon, name and a short phrase in
/// the center, where Apple says focal artwork belongs; two phones at the
/// sides, which can be cropped on narrow screens without losing anything.
class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.left, required this.right});

  final ui.Image icon;
  final ui.Image left;
  final ui.Image right;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: _gradient),
    child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          left: 3840 * 0.14 - 330,
          top: 240,
          child: Transform.rotate(angle: -0.07, child: _phoneFrame(left, 660)),
        ),
        Positioned(
          left: 3840 * 0.86 - 330,
          top: 240,
          child: Transform.rotate(angle: 0.07, child: _phoneFrame(right, 660)),
        ),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: SizedBox.square(
                  dimension: 440,
                  child: RawImage(image: icon, fit: BoxFit.cover, filterQuality: FilterQuality.high),
                ),
              ),
              const SizedBox(width: 90),
              const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Diffcat',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 240,
                      height: 1,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 36),
                  Text(
                    'Code review in your pocket',
                    style: TextStyle(fontFamily: 'Roboto', fontSize: 100, color: _lavender),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Search results artwork, 3840 × 2560 (3:2): what the app does in a few
/// words, then the interface itself, as Apple's guidance suggests.
class _SearchResult extends StatelessWidget {
  const _SearchResult({required this.shots});

  final List<ui.Image> shots;

  @override
  Widget build(BuildContext context) {
    const phoneW = 940.0, gap = 170.0;
    const start = (3840 - 3 * phoneW - 2 * gap) / 2;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: _gradient),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned(
            left: 0,
            right: 0,
            top: 150,
            child: Column(
              children: [
                Text(
                  'Review GitHub code on the go',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 190,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 30),
                Text(
                  'Diffs, pull requests and offline repos',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Roboto', fontSize: 96, color: _lavender),
                ),
              ],
            ),
          ),
          for (final (i, shot) in shots.take(3).indexed)
            Positioned(left: start + i * (phoneW + gap), top: i == 1 ? 640 : 760, child: _phoneFrame(shot, phoneW)),
        ],
      ),
    );
  }
}
