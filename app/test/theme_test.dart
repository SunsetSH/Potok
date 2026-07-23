import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/presentation/theme.dart';

void main() {
  test('theme mode and IDs use safe defaults for unknown storage values', () {
    expect(PotokThemeMode.fromStorage('system'), PotokThemeMode.system);
    expect(PotokThemeMode.fromStorage('broken'), PotokThemeMode.fixed);
    expect(PotokThemeId.fromStorage('terminal'), PotokThemeId.terminal);
    expect(PotokThemeId.fromStorage('broken'), PotokThemeId.studio);
  });

  test('every selectable theme keeps its own brightness and token palette', () {
    expect(buildPotokTheme(PotokThemeId.studio).brightness, Brightness.light);
    expect(buildPotokTheme(PotokThemeId.paper).brightness, Brightness.light);
    expect(
      buildPotokTheme(PotokThemeId.studioNight).brightness,
      Brightness.dark,
    );
    expect(buildPotokTheme(PotokThemeId.terminal).brightness, Brightness.dark);
  });
}
