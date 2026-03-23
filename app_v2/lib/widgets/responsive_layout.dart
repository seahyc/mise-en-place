import 'package:flutter/material.dart';

enum DeviceType { phone, tablet, largeTablet }

DeviceType getDeviceType(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 600) return DeviceType.phone;
  if (width <= 1024) return DeviceType.tablet;
  return DeviceType.largeTablet;
}

class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.phone,
    this.tablet,
    this.largeTablet,
  });

  final Widget phone;
  final Widget? tablet;
  final Widget? largeTablet;

  @override
  Widget build(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.largeTablet:
        return largeTablet ?? tablet ?? phone;
      case DeviceType.tablet:
        return tablet ?? phone;
      case DeviceType.phone:
        return phone;
    }
  }
}
