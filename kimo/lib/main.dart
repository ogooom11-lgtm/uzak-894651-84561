import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_environment.dart';
import 'repositories/device_repository.dart';
import 'repositories/telegram_device_repository.dart';
import 'screens/devices_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final DeviceRepository repository = TelegramDeviceRepository();

  runApp(
    Provider<DeviceRepository>.value(
      value: repository,
      child: const WinRemoteMobileApp(),
    ),
  );
}

class WinRemoteMobileApp extends StatelessWidget {
  const WinRemoteMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KIOM Control',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: ThemeMode.system,
      theme: _appTheme(Brightness.light),
      darkTheme: _appTheme(Brightness.dark),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: DevicesScreen(userId: AppEnvironment.demoUserId),
      ),
    );
  }
}

ThemeData _appTheme(Brightness brightness) {
  const seed = Color(0xFF2563EB);
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  ).copyWith(
    primary: const Color(0xFF2563EB),
    secondary: const Color(0xFF06B6D4),
    tertiary: const Color(0xFF8B5CF6),
    surface: isDark ? const Color(0xFF101827) : Colors.white,
    surfaceContainerHighest:
        isDark ? const Color(0xFF1A2435) : const Color(0xFFEFF6FF),
  );

  final radius = BorderRadius.circular(24);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF0B1120) : const Color(0xFFF4F7FB),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
      titleTextStyle: TextStyle(
        fontFamily: 'Tajawal',
        color: isDark ? Colors.white : const Color(0xFF0F172A),
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xFF131D31) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: .06)
              : Colors.black.withValues(alpha: .04),
          width: 1,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF131D31) : const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? const Color(0xFF101827) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? const Color(0xFF101827) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
