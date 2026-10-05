import 'package:flutter/material.dart';

import '../core/app_icon_registry.dart';
import '../models/open_app.dart';

class OpenAppIconAvatar extends StatelessWidget {
  const OpenAppIconAvatar({
    super.key,
    required this.app,
    required this.match,
    this.size = 46,
  });

  final OpenApp app;
  final AppIconMatch match;
  final double size;

  @override
  Widget build(BuildContext context) {
    final favicon =
        app.isBrowserItem ? AppIconRegistry.faviconUrl(app, size: 96) : null;
    final backgroundColor = match.color.withValues(alpha: .12);
    final fallback = Icon(match.icon, color: match.color, size: size * .52);

    Widget icon;
    if (favicon != null) {
      icon = Image.network(
        favicon.toString(),
        width: size * .68,
        height: size * .68,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _assetOrFallback(fallback),
      );
    } else {
      icon = _assetOrFallback(fallback);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: Border.all(color: match.color.withValues(alpha: .16)),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: icon,
    );
  }

  Widget _assetOrFallback(Widget fallback) {
    final asset = match.assetPath;
    if (asset == null || asset.isEmpty) return fallback;
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
