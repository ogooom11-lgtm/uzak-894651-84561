import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_environment.dart';
import 'config/firebase_options.dart';
import 'repositories/device_repository.dart';
import 'repositories/firebase_device_repository.dart';
import 'repositories/mock_device_repository.dart';
import 'screens/devices_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final DeviceRepository repository;
  if (AppEnvironment.useFirebase) {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (_) {}
    }
    repository = FirebaseDeviceRepository();
  } else {
    repository = MockDeviceRepository();
  }

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
        color: isDark ? Colors.white : const Color(0xFF0F172A),
        fontSize: 21,
        fontWeight: FontWeight.w900,
      ),
    ),
    cardTheme: CardThemeData(
      color: isDark
          ? const Color(0xFF111827).withValues(alpha: .92)
          : Colors.white.withValues(alpha: .96),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shadowColor: Colors.black.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: .08)
              : Colors.black.withValues(alpha: .05),
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: .06)
          : Colors.white.withValues(alpha: .94),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: .08)
              : Colors.black.withValues(alpha: .06),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        side: BorderSide(color: scheme.primary.withValues(alpha: .24)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
      contentTextStyle: TextStyle(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}
