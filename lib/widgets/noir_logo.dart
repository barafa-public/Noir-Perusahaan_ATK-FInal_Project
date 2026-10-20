import 'package:flutter/material.dart';

class NoirLogo extends StatelessWidget {
  final double width;
  const NoirLogo({super.key, this.width = 120});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/images/logo_noir_white.png', width: width);
  }
}
