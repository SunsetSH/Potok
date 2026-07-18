import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A centered floating message that follows its single-line text instead of
/// stretching across a desktop window. Long/localized text is bounded by the
/// available viewport and may wrap normally.
PotokSnackBar compactSnackBar(BuildContext context, String message) {
  final style =
      Theme.of(context).snackBarTheme.contentTextStyle ??
      Theme.of(context).textTheme.bodyMedium ??
      const TextStyle(fontSize: 12);
  final painter = TextPainter(
    text: TextSpan(text: message, style: style),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();
  final viewport = MediaQuery.sizeOf(context).width;
  final maxWidth = math.max(160.0, math.min(520.0, viewport - 32));
  final width = (painter.width + 48).clamp(160.0, maxWidth).toDouble();
  return PotokSnackBar(content: Text(message), preferredWidth: width);
}

/// The only transient notification used by Potok. It is compact on desktop
/// and force-closes after four seconds even when accessibility navigation
/// would otherwise keep an action SnackBar indefinitely.
class PotokSnackBar extends SnackBar {
  // ignore: use_super_parameters
  PotokSnackBar({
    Key? key,
    required Widget content,
    SnackBarAction? action,
    double? preferredWidth,
  }) : super(
         key: key,
         width: preferredWidth ?? _estimateWidth(content, action),
         behavior: SnackBarBehavior.floating,
         duration: const Duration(seconds: 4),
         content: _AutoDismissContent(child: content),
         action: action,
       );

  static double _estimateWidth(Widget content, SnackBarAction? action) {
    final view = ui.PlatformDispatcher.instance.views.firstOrNull;
    final viewport = view == null
        ? 520.0
        : view.physicalSize.width / view.devicePixelRatio;
    final message = content is Text ? content.data ?? '' : '';
    final actionText = action?.label ?? '';
    final estimate =
        message.characters.length * 7.0 +
        actionText.characters.length * 7.0 +
        (action == null ? 52 : 104);
    return estimate.clamp(160.0, math.min(520.0, viewport - 32)).toDouble();
  }
}

class _AutoDismissContent extends StatefulWidget {
  final Widget child;

  const _AutoDismissContent({required this.child});

  @override
  State<_AutoDismissContent> createState() => _AutoDismissContentState();
}

class _AutoDismissContentState extends State<_AutoDismissContent> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
