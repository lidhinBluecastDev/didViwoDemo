import 'package:flutter/material.dart';

/// Al Rabeeh Academy mark used in the app header.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.height = 40,
    this.width,
  });

  final double height;

  /// When set (e.g. [double.infinity] inside [Expanded]), the logo scales to
  /// fit without clipping the wide landscape asset.
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      height: height,
      width: width,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      filterQuality: FilterQuality.high,
    );
  }
}
