import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (max(x, y) + 0.05) / (min(x, y) + 0.05);
}

void main() {
  for (final b in Brightness.values) {
    group('$b', () {
      final s = AppTheme.schemeFor(b);
      final diff = b == Brightness.light ? DiffColors.light : DiffColors.dark;
      final status = StatusColors.of(b);

      test('text roles reach 4.5:1 on their backgrounds', () {
        final pairs = {
          'primary on surface': (s.primary, s.surface),
          'onPrimary on primary': (s.onPrimary, s.primary),
          'onPrimaryContainer on primaryContainer': (s.onPrimaryContainer, s.primaryContainer),
          'onSecondaryContainer on secondaryContainer': (s.onSecondaryContainer, s.secondaryContainer),
          'tertiary on surface': (s.tertiary, s.surface),
          'onTertiary on tertiary': (s.onTertiary, s.tertiary),
          'onTertiaryContainer on tertiaryContainer': (s.onTertiaryContainer, s.tertiaryContainer),
          'onError on error': (s.onError, s.error),
          'line numbers on surface': (diff.gutter, s.surface),
        };
        for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
          expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
        }
      });

      test('primary stays close to the brand blue', () {
        // tonalSpot turned it slate (saturation 0.37); fidelity keeps it vivid.
        expect(HSLColor.fromColor(s.primary).saturation, greaterThan(0.6));
        expect(HSLColor.fromColor(s.primary).hue, inInclusiveRange(205, 225));
      });

      test('code stays readable on diff rows', () {
        for (final bg in [diff.addBg, diff.delBg]) {
          expect(_contrast(s.onSurface, bg), greaterThanOrEqualTo(7));
        }
      });

      // Light tints differ from the page in hue; dark ones were too close to it in brightness.
      if (b == Brightness.dark) {
        test('dark diff rows stand apart from the surface', () {
          for (final bg in [diff.addBg, diff.delBg]) {
            expect(_contrast(bg, s.surface), greaterThanOrEqualTo(1.15));
          }
        });
      }

      test('status icons reach 3:1 on the surface', () {
        for (final c in [status.success, status.failure, status.warning, status.merged, status.neutral]) {
          expect(_contrast(c, s.surface), greaterThanOrEqualTo(3));
        }
      });
    });
  }
}
