import 'package:flutter/material.dart';

/// Phone-first layout helpers for the school demo.
class PhoneLayout {
  PhoneLayout._(this.context);

  factory PhoneLayout.of(BuildContext context) => PhoneLayout._(context);

  final BuildContext context;

  Size get size => MediaQuery.sizeOf(context);
  EdgeInsets get padding => MediaQuery.paddingOf(context);
  double get shortest => size.shortestSide;
  bool get isPhone => shortest < 600;
  bool get isCompactHeight => size.height < 720;
  bool get isWide => size.width >= 720;

  double get horizontalPadding => isWide ? 56 : (isPhone ? 20 : 28);

  double brandSize(double phone, double tablet) => isWide ? tablet + 8 : phone;

  double headlineSize(double phone, double tablet) => isWide ? tablet : phone;
}
