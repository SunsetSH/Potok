import 'package:flutter/material.dart';

/// Общая палитра проектов и тегов. Порядок стабилен: сохранённые ARGB не
/// зависят от темы и одинаково предлагаются во всех редакторах сущностей.
const entityPresetColors = <int>[
  0xFF2563EB, // blue
  0xFFEA580C, // orange
  0xFFDC2626, // red
  0xFF0F766E, // teal
  0xFF15803D, // green
  0xFF7E22CE, // purple
  0xFFD97706, // amber
  0xFF475569, // slate
  0xFFBE185D, // magenta
  0xFF0891B2, // cyan
  0xFF4D7C0F, // olive
  0xFF92400E, // brown
  0xFFDB2777, // pink
  0xFF4338CA, // indigo
  0xFF65A30D, // lime
  0xFFC2410C, // deep orange
];

Color entityColorForeground(int argb) {
  final color = Color(argb);
  return color.computeLuminance() > 0.42 ? Colors.black : Colors.white;
}
