import 'package:flutter/material.dart';

enum PotokThemeMode {
  fixed,
  system;

  static PotokThemeMode fromStorage(String? value) =>
      value == system.name ? system : fixed;
}

/// Четыре темы прототипа (ТЗ 0.6.6). Идентификаторы совпадают с
/// data-theme из HTML-прототипа и хранятся в app_meta под ключом 'theme'.
enum PotokThemeId {
  studio('studio', 'Studio', 'Основная светлая тема'),
  studioNight('studio-night', 'Studio Night', 'Ночной вариант Studio'),
  paper('paper', 'Paper', 'Тёплая редакционная'),
  terminal('terminal', 'Terminal', 'Контрастная техническая');

  final String storageKey;
  final String title;
  final String subtitle;

  const PotokThemeId(this.storageKey, this.title, this.subtitle);

  static PotokThemeId fromStorage(String? key) {
    for (final id in values) {
      if (id.storageKey == key) return id;
    }
    return PotokThemeId.studio;
  }

  bool get isDark => this == studioNight || this == terminal;
}

/// Дизайн-токены прототипа (CSS-переменные) как ThemeExtension:
/// виджеты берут точные цвета, не полагаясь на Material-палитру.
@immutable
class PotokColors extends ThemeExtension<PotokColors> {
  final Color canvas;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color text;
  final Color muted;
  final Color line;
  final Color accent;
  final Color accentSoft;
  final Color accentText;
  final Color danger;
  final Color risk;
  final Color question;
  final Color decision;
  final Color idea;
  final double radius;
  final double radiusSmall;

  const PotokColors({
    required this.canvas,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.text,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.accentText,
    required this.danger,
    required this.risk,
    required this.question,
    required this.decision,
    required this.idea,
    required this.radius,
    required this.radiusSmall,
  });

  static PotokColors of(BuildContext context) =>
      Theme.of(context).extension<PotokColors>()!;

  @override
  PotokColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? text,
    Color? muted,
    Color? line,
    Color? accent,
    Color? accentSoft,
    Color? accentText,
    Color? danger,
    Color? risk,
    Color? question,
    Color? decision,
    Color? idea,
    double? radius,
    double? radiusSmall,
  }) {
    return PotokColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentText: accentText ?? this.accentText,
      danger: danger ?? this.danger,
      risk: risk ?? this.risk,
      question: question ?? this.question,
      decision: decision ?? this.decision,
      idea: idea ?? this.idea,
      radius: radius ?? this.radius,
      radiusSmall: radiusSmall ?? this.radiusSmall,
    );
  }

  @override
  PotokColors lerp(covariant PotokColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => a + (b - a) * t;
    return PotokColors(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surface2: c(surface2, other.surface2),
      surface3: c(surface3, other.surface3),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      line: c(line, other.line),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      accentText: c(accentText, other.accentText),
      danger: c(danger, other.danger),
      risk: c(risk, other.risk),
      question: c(question, other.question),
      decision: c(decision, other.decision),
      idea: c(idea, other.idea),
      radius: d(radius, other.radius),
      radiusSmall: d(radiusSmall, other.radiusSmall),
    );
  }
}

// Точные значения CSS-переменных прототипа.

const _studio = PotokColors(
  canvas: Color(0xFFE9EDF2),
  surface: Color(0xFFFFFFFF),
  surface2: Color(0xFFF5F7FA),
  surface3: Color(0xFFEDF1F5),
  text: Color(0xFF18212F),
  muted: Color(0xFF647084),
  line: Color(0xFFDCE2EA),
  accent: Color(0xFF3457D5),
  accentSoft: Color(0xFFE9EDFF),
  accentText: Color(0xFFFFFFFF),
  danger: Color(0xFFC53C4B),
  risk: Color(0xFFB85C16),
  question: Color(0xFF2364C4),
  decision: Color(0xFF23825E),
  idea: Color(0xFF7656BD),
  radius: 16,
  radiusSmall: 10,
);

const _studioNight = PotokColors(
  canvas: Color(0xFF10141C),
  surface: Color(0xFF171D27),
  surface2: Color(0xFF1D2531),
  surface3: Color(0xFF263140),
  text: Color(0xFFEDF2FA),
  muted: Color(0xFF9BA9BC),
  line: Color(0xFF344154),
  accent: Color(0xFF8CA7FF),
  accentSoft: Color(0xFF26345E),
  accentText: Color(0xFF101522),
  danger: Color(0xFFFF7E8E),
  risk: Color(0xFFFFAD66),
  question: Color(0xFF7DB2FF),
  decision: Color(0xFF65D5AA),
  idea: Color(0xFFBBA1FF),
  radius: 16,
  radiusSmall: 10,
);

const _paper = PotokColors(
  canvas: Color(0xFFE8E1D5),
  surface: Color(0xFFFFFDF7),
  surface2: Color(0xFFF8F3E8),
  surface3: Color(0xFFEEE5D6),
  text: Color(0xFF302B26),
  muted: Color(0xFF756B61),
  line: Color(0xFFDED3C3),
  accent: Color(0xFF9B4B2F),
  accentSoft: Color(0xFFF5E3D9),
  accentText: Color(0xFFFFFFFF),
  danger: Color(0xFFA9353E),
  risk: Color(0xFFB85C16),
  question: Color(0xFF2364C4),
  decision: Color(0xFF23825E),
  idea: Color(0xFF7656BD),
  radius: 9,
  radiusSmall: 6,
);

const _terminal = PotokColors(
  canvas: Color(0xFF07110E),
  surface: Color(0xFF0B1713),
  surface2: Color(0xFF0F201A),
  surface3: Color(0xFF142A22),
  text: Color(0xFFC8F7DC),
  muted: Color(0xFF77A98B),
  line: Color(0xFF244936),
  accent: Color(0xFF42E788),
  accentSoft: Color(0xFF123B25),
  accentText: Color(0xFF04140A),
  danger: Color(0xFFFF6B73),
  risk: Color(0xFFFFB45B),
  question: Color(0xFF69A9FF),
  decision: Color(0xFF4BEA91),
  idea: Color(0xFFC797FF),
  radius: 2,
  radiusSmall: 2,
);

PotokColors potokTokens(PotokThemeId id) => switch (id) {
  PotokThemeId.studio => _studio,
  PotokThemeId.studioNight => _studioNight,
  PotokThemeId.paper => _paper,
  PotokThemeId.terminal => _terminal,
};

String _fontFamily(PotokThemeId id) => switch (id) {
  PotokThemeId.studio || PotokThemeId.studioNight => 'Segoe UI',
  PotokThemeId.paper => 'Georgia',
  PotokThemeId.terminal => 'Consolas',
};

ThemeData buildPotokTheme(PotokThemeId id) {
  final t = potokTokens(id);
  final dark = id == PotokThemeId.studioNight || id == PotokThemeId.terminal;
  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: t.accent,
    onPrimary: t.accentText,
    primaryContainer: t.accentSoft,
    onPrimaryContainer: dark ? t.text : t.accent,
    secondary: t.accent,
    onSecondary: t.accentText,
    error: t.danger,
    onError: Colors.white,
    surface: t.surface,
    onSurface: t.text,
    surfaceContainerHighest: t.surface3,
    surfaceContainerHigh: t.surface2,
    outline: t.line,
    outlineVariant: t.line,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _fontFamily(id),
    scaffoldBackgroundColor: t.canvas,
    canvasColor: t.surface,
    cardColor: t.surface,
    dividerColor: t.line,
    extensions: [t],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: t.surface,
      foregroundColor: t.text,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius + 4),
        side: BorderSide(color: t.line),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surface,
      textStyle: TextStyle(color: t.text, fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusSmall),
        side: BorderSide(color: t.line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.text,
      contentTextStyle: TextStyle(color: t.surface, fontSize: 12),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.accent,
      foregroundColor: t.accentText,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius + 2),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionColor: t.accent.withValues(alpha: dark ? 0.32 : 0.22),
      selectionHandleColor: t.accent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(t.radius + 8)),
      ),
    ),
  );
}
