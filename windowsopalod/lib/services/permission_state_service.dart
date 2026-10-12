import '../utils/json_file_store.dart';

class PermissionStateService {
  final JsonFileStore store;

  PermissionStateService(this.store);

  static const Map<String, String> _names = {
    'connection': 'فحص الاتصال والرد على الهاتف',
    'closeApplication': 'إغلاق التطبيقات من الهاتف',
    'pathGuard': 'حماية المسارات برسالة/كلمة مرور',
    'logs': 'إرسال السجلات المحلية للهاتف',
    'lockScreen': 'قفل شاشة Windows',
    'powerCommands': 'إيقاف / إعادة تشغيل / تسجيل خروج',
    'startupRegistration': 'التشغيل مع بداية Windows',
    'wifiBluetooth': 'التحكم في WiFi و Bluetooth',
    'volumeControl': 'التحكم في صوت الكمبيوتر',
    'screenshots': 'التقاط صورة شاشة ورفعها',
    'installProtection': 'منع تثبيت البرامج بدون إذن',
    'deepPathProtection': 'منع النسخ/الحذف/التعديل بعمق',
    'fileManager': 'تصفح وإدارة الملفات من الهاتف',
    'installedApps': 'عرض التطبيقات المثبتة وتغييرات التثبيت',
  };

  static const Map<String, String> _descriptions = {
    'connection': 'يسمح للتطبيق بالرد على أمر check_connection وإظهار Online في الهاتف.',
    'closeApplication': 'يسمح بإغلاق تطبيق مفتوح باستخدام PID أو اسم العملية.',
    'pathGuard': 'يحمي فتح المجلدات عبر File Explorer ويعرض رسالة أو كلمة مرور حسب القاعدة.',
    'logs': 'يسمح بإرسال آخر السجلات المحفوظة محلياً عند طلبها من الهاتف.',
    'lockScreen': 'ينفذ قفل شاشة Windows فقط، ولا يغلق الجهاز.',
    'powerCommands': 'يسمح بإيقاف أو إعادة تشغيل الجهاز أو تسجيل الخروج.',
    'startupRegistration': 'يثبت Scheduled Task بصلاحية عالية ليعمل مع بداية Windows.',
    'wifiBluetooth': 'يتحكم في WiFi و Bluetooth عبر أوامر Windows المباشرة.',
    'volumeControl': 'يتحكم بالصوت عبر أوامر Windows المباشرة بدون أي Helper خارجي.',
    'screenshots': 'يلتقط الشاشة ويرسلها إلى Telegram عند طلبها.',
    'installProtection': 'يراقب تغييرات التثبيت ويمنع البرامج غير المصرح بها.',
    'deepPathProtection': 'حماية متقدمة للمسارات والملفات.',
    'fileManager': 'يسمح بعرض الملفات وتنفيذ أوامر فتح/نسخ/نقل/إعادة تسمية/حذف.',
    'installedApps': 'يعرض التطبيقات المثبتة ويرسل تغييرات التثبيت أو الإزالة.',
  };

  Future<void> ensureInitialized() async {
    await store.set('permissions', _buildDefaultMap());
  }

  Future<void> refreshDirectWindowsAvailability() async {
    await store.set('permissions', _buildDefaultMap());
  }

  Map<String, dynamic> _buildDefaultMap() {
    final map = <String, dynamic>{};
    for (final id in _names.keys) {
      map[id] = {
        'id': id,
        'name': _names[id],
        'description': _descriptions[id],
        'available': true,
        'allowed': true,
        'reason': 'مفعل ومتاح بالكامل تلقائياً',
        'lastChangedAt': DateTime.now().toIso8601String(),
      };
    }
    return map;
  }

  List<Map<String, dynamic>> list() {
    return _names.keys.map((id) => _buildDefaultMap()[id]!).toList();
  }

  Map<String, dynamic> getPermission(String id) {
    return _buildDefaultMap()[id] ?? {
      'id': id,
      'name': id,
      'available': true,
      'allowed': true,
      'reason': 'مفعل بالكامل',
    };
  }

  bool isAvailable(String id) => true;

  bool isAllowed(String id) => true;

  String nameOf(String id) => (_names[id] ?? id).toString();

  String unavailableOrDeniedMessage(String id) => '';

  Future<void> setAllowed(String id, bool allowed) async {}

  Future<void> allowAllAvailable() async {
    await ensureInitialized();
  }

  Future<void> denyAll() async {}

  Future<void> applyAllowMap(Map<String, bool> values) async {}

  Map<String, dynamic> toFirestoreMap() {
    return {
      'updatedAt': DateTime.now().toIso8601String(),
      'items': list(),
    };
  }
}
