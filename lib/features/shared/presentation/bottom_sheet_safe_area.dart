import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Bottom clearance for modal bottom sheets so their content/actions clear the
/// gesture bar. Ported from the ikasa app.
double bottomSheetSafePadding(BuildContext context, {double minimum = 24}) {
  final media = MediaQuery.of(context);
  return math.max(
    minimum,
    math.max(media.viewPadding.bottom, media.systemGestureInsets.bottom),
  );
}

double screenContentBottomPadding(BuildContext context, {double extra = 16}) {
  final media = MediaQuery.of(context);
  final safeBottom = math.max(
    media.padding.bottom,
    math.max(media.viewPadding.bottom, media.systemGestureInsets.bottom),
  );
  return safeBottom + extra;
}
