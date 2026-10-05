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
    'connection':
        'يسمح للتطبيق بالرد على أمر check_connection وإظهار Online في الهاتف.',
    'closeApplication': 'يسمح بإغلاق تطبيق مفتوح باستخدام PID أو اسم العملية.',
    'pathGuard':
        'يحمي فتح المجلدات عبر File Explorer ويعرض رسالة أو كلمة مرور حسب القاعدة.',
    'logs': 'يسمح بإرسال آخر السجلات المحفوظة محلياً عند طلبها من الهاتف.',
    'lockScreen': 'ينفذ قفل شاشة Windows فقط، ولا يغلق الجهاز.',
    'powerCommands':
        'أمر حساس. يسمح بإيقاف أو إعادة تشغيل الجهاز أو تسجيل الخروج.',
    'startupRegistration':
        'يثبت Scheduled Task بصلاحية عالية ليعمل مع بداية Windows.',
    'wifiBluetooth':
        'يستخدم أوامر Windows المباشرة. يحتاج أن يكون KIOM PC Agent شغالاً كمسؤول.',
    'volumeControl':
        'يتحكم بالصوت عبر أوامر Windows المباشرة بدون أي Helper خارجي.',
    'screenshots':
        'يلتقط الشاشة عبر screen_capturer مع fallback محلي عبر Windows GDI ويرسلها إلى Telegram عند ضبط البوت.',
    'installProtection':
        'يراقب تغييرات التثبيت ويستخدم منع التطبيقات للمثبتات المعروفة. المنع العميق قبل بدء التثبيت يحتاج سياسة Windows.',
    'deepPathProtection':
        'حماية فتح المسارات تعمل عبر Path Guard. منع النسخ/الحذف العميق على مستوى النظام يحتاج File System Filter أو سياسة Windows.',
    'fileManager':
        'يسمح بعرض الملفات وتنفيذ أوامر فتح/نسخ/نقل/إعادة تسمية/إخفاء/حذف عند طلبها من الهاتف.',
    'installedApps':
        'يعرض التطبيقات المثبتة ويرسل تغييرات التثبيت أو الإزالة عند حدوثها.',
  };

  static const Set<String> _availableNow = {
    'connection',
    'closeApplication',
    'pathGuard',
    'logs',
    'lockScreen',
    'powerCommands',
    'startupRegistration',
    'wifiBluetooth',
    'fileManager',
    'installedApps',
    'screenshots',
    'volumeControl',
    'installProtection',
  };

  static const Set<String> _allowedByDefault = {
    'connection',
    'closeApplication',
    'pathGuard',
    'logs',
    'lockScreen',
    'powerCommands',
    'startupRegistration',
    'wifiBluetooth',
    'fileManager',
    'installedApps',
    'screenshots',
    'volumeControl',
  };

  Future<void> ensureInitialized() async {
    final existing = store.get<Map<String, dynamic>>('permissions');
    if (existing == null || existing.isEmpty) {
      await store.set('permissions', _buildDefaultMap());
      return;
    }

    // دمج أي أذونات جديدة تمت إضافتها لاحقاً بدون حذف اختيارات المستخدم القديمة.
    await store.set('permissions', _raw());
  }

  Future<void> refreshDirectWindowsAvailability() async {
    final raw = _raw();

    if (raw.containsKey('wifiBluetooth')) {
      final item = (raw['wifiBluetooth'] as Map).cast<String, dynamic>();
      item['available'] = true;
      item['allowed'] = true;
      item['reason'] =
          'متاح عبر أوامر Windows المباشرة عندما يعمل التطبيق كمسؤول';
      item['lastChangedAt'] = DateTime.now().toIso8601String();
      raw['wifiBluetooth'] = item;
    }

    if (raw.containsKey('powerCommands')) {
      final item = (raw['powerCommands'] as Map).cast<String, dynamic>();
      item['available'] = true;
      item['allowed'] = true;
      item['reason'] = 'متاح عبر أوامر Windows المباشرة بدون أي Helper خارجي.';
      item['lastChangedAt'] = DateTime.now().toIso8601String();
      raw['powerCommands'] = item;
    }

    if (raw.containsKey('screenshots')) {
      final item = (raw['screenshots'] as Map).cast<String, dynamic>();
      item['available'] = true;
      item['reason'] =
          'متاح عبر screen_capturer مع fallback Windows GDI، بدون أي Helper خارجي.';
      item['lastChangedAt'] = DateTime.now().toIso8601String();
      raw['screenshots'] = item;
    }

    if (raw.containsKey('volumeControl')) {
      final item = (raw['volumeControl'] as Map).cast<String, dynamic>();
      item['available'] = true;
      item['reason'] =
          'متاح عبر Windows Audio API / media keys بدون Helper خارجي.';
      item['lastChangedAt'] = DateTime.now().toIso8601String();
      raw['volumeControl'] = item;
    }

    if (raw.containsKey('installProtection')) {
      final item = (raw['installProtection'] as Map).cast<String, dynamic>();
      item['available'] = true;
      item['reason'] =
          'متاح عبر مراقبة المثبتات وإرسال طلب موافقة للهاتف قبل السماح بإعادة تشغيل المثبت.';
      item['lastChangedAt'] = DateTime.now().toIso8601String();
      raw['installProtection'] = item;
    }

    await store.set('permissions', raw);
  }

  Map<String, dynamic> _buildDefaultMap() {
    final map = <String, dynamic>{};
    for (final id in _names.keys) {
      final available = _availableNow.contains(id);
      map[id] = {
        'id': id,
        'name': _names[id],
        'description': _descriptions[id],
        'available': available,
        'allowed': available && _allowedByDefault.contains(id),
        'reason': available
            ? 'متاح في النسخة الحالية'
            : 'غير متاح حالياً: يحتاج تشغيل التطبيق كمسؤول أو دعم Windows API مباشر',
        'lastChangedAt': DateTime.now().toIso8601String(),
      };
    }
    return map;
  }

  Map<String, dynamic> _raw() {
    final existing = store.get<Map<String, dynamic>>('permissions');
    if (existing == null || existing.isEmpty) return _buildDefaultMap();

    final merged = _buildDefaultMap();
    for (final entry in existing.entries) {
      if (entry.value is! Map || !merged.containsKey(entry.key)) continue;
      final canonical = (merged[entry.key] as Map).cast<String, dynamic>();
      final stored = (entry.value as Map).cast<String, dynamic>();

      // Keep the user's allow/deny choice, but always refresh canonical
      // capability text from code so removed helpers never linger in storage.
      merged[entry.key] = {
        ...canonical,
        'allowed':
            canonical['available'] == true ? stored['allowed'] == true : false,
        'lastChangedAt': stored['lastChangedAt'] ?? canonical['lastChangedAt'],
      };
    }
    return merged;
  }

  List<Map<String, dynamic>> list() {
    final raw = _raw();
    return _names.keys
        .map((id) => (raw[id] as Map).cast<String, dynamic>())
        .toList();
  }

  Map<String, dynamic> getPermission(String id) {
    final raw = _raw();
    return ((raw[id] ?? _buildDefaultMap()[id]) as Map).cast<String, dynamic>();
  }

  bool isAvailable(String id) => getPermission(id)['available'] == true;

  bool isAllowed(String id) {
    final item = getPermission(id);
    return item['available'] == true && item['allowed'] == true;
  }

  String nameOf(String id) => (getPermission(id)['name'] ?? id).toString();

  String unavailableOrDeniedMessage(String id) {
    final item = getPermission(id);
    final name = (item['name'] ?? id).toString();
    if (item['available'] != true) {
      return 'تم استلام الأمر، لكن إذن "$name" غير متاح الآن. السبب: ${item['reason']}';
    }
    return 'تم استلام الأمر، لكن إذن "$name" غير مسموح حالياً. افتح شاشة الأذونات أو فعّله من إعدادات الكمبيوتر.';
  }

  Future<void> setAllowed(String id, bool allowed) async {
    final raw = _raw();
    if (!raw.containsKey(id)) return;
    final item = (raw[id] as Map).cast<String, dynamic>();
    item['allowed'] = item['available'] == true ? allowed : false;
    item['lastChangedAt'] = DateTime.now().toIso8601String();
    raw[id] = item;
    await store.set('permissions', raw);
  }

  Future<void> allowAllAvailable() async {
    final raw = _raw();
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final item = (entry.value as Map).cast<String, dynamic>();
      item['allowed'] = item['available'] == true;
      item['lastChangedAt'] = DateTime.now().toIso8601String();
      raw[entry.key] = item;
    }
    await store.set('permissions', raw);
  }

  Future<void> denyAll() async {
    final raw = _raw();
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final item = (entry.value as Map).cast<String, dynamic>();
      item['allowed'] = false;
      item['lastChangedAt'] = DateTime.now().toIso8601String();
      raw[entry.key] = item;
    }
    await store.set('permissions', raw);
  }

  Future<void> applyAllowMap(Map<String, bool> values) async {
    final raw = _raw();
    for (final entry in values.entries) {
      if (!raw.containsKey(entry.key)) continue;
      final item = (raw[entry.key] as Map).cast<String, dynamic>();
      item['allowed'] = item['available'] == true ? entry.value : false;
      item['lastChangedAt'] = DateTime.now().toIso8601String();
      raw[entry.key] = item;
    }
    await store.set('permissions', raw);
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'updatedAt': DateTime.now().toIso8601String(),
      'items': list(),
    };
  }
}
