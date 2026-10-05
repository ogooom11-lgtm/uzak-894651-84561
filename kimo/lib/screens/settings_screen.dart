import 'package:flutter/material.dart';

import '../config/app_environment.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('حالة التشغيل',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('Firebase'),
                    subtitle: Text(AppEnvironment.useFirebase
                        ? 'مفعّل'
                        : 'غير مفعّل - يعمل Demo Mode'),
                  ),
                  const Divider(),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.security_outlined),
                    title: Text('تنبيه أمان'),
                    subtitle: Text(
                        'استخدم التطبيق فقط مع الأجهزة التي تملكها أو لديك تصريح واضح لإدارتها.'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'لتفعيل Firebase: شغّل flutterfire configure، ثم استبدل firebase_options.dart، ثم غيّر useFirebase إلى true من ملف lib/config/app_environment.dart.',
            style: TextStyle(height: 1.7),
          ),
        ],
      ),
    );
  }
}
