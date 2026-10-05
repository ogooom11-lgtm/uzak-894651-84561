enum CommandType {
  checkConnection,
  closeApplication,
  closeApplicationAfterDelay,
  blockApplication,
  allowApplication,
  blockWebsite,
  allowWebsite,
  showPairingQr,
  showPermissionCenter,
  configureTelegramChat,
  requestScreenshot,
  emergencyMode,
  applyPresetMode,
  systemHealth,
  privacyMode,
  undoLastCommand,
  wifiOn,
  wifiOff,
  internetOffPermanent,
  internetOn,
  bluetoothOn,
  bluetoothOff,
  listBluetoothDevices,
  openBluetoothReceive,
  sendBluetoothFile,
  showMessage,
  volumeUp,
  volumeDown,
  setVolume,
  muteVolume,
  unmuteVolume,
  shutdownPc,
  restartPc,
  lockScreen,
  lockForDuration,
  lockAfterDelay,
  clearTimedLock,
  cancelScheduledLock,
  logoutUser,
  shutdownAfterDelay,
  restartAfterDelay,
  cancelScheduledPowerCommand,
  addPathRule,
  removePathRule,
  updatePathRule,
  approvePermission,
  rejectPermission,
  approveInstall,
  rejectInstall,
  requestLogs,
  deleteCloudLogs,
  browsePath,
  searchFiles,
  openPath,
  renamePath,
  copyPath,
  movePath,
  deletePath,
  hidePath,
  unhidePath,
}

extension CommandTypeX on CommandType {
  String get wireName {
    switch (this) {
      case CommandType.checkConnection:
        return 'check_connection';
      case CommandType.closeApplication:
        return 'close_application';
      case CommandType.closeApplicationAfterDelay:
        return 'close_application_after_delay';
      case CommandType.blockApplication:
        return 'block_application';
      case CommandType.allowApplication:
        return 'allow_application';
      case CommandType.blockWebsite:
        return 'block_website';
      case CommandType.allowWebsite:
        return 'allow_website';
      case CommandType.showPairingQr:
        return 'show_pairing_qr';
      case CommandType.showPermissionCenter:
        return 'show_permission_center';
      case CommandType.configureTelegramChat:
        return 'configure_telegram_chat';
      case CommandType.requestScreenshot:
        return 'request_screenshot';
      case CommandType.emergencyMode:
        return 'emergency_mode';
      case CommandType.applyPresetMode:
        return 'apply_preset_mode';
      case CommandType.systemHealth:
        return 'system_health';
      case CommandType.privacyMode:
        return 'privacy_mode';
      case CommandType.undoLastCommand:
        return 'undo_last_command';
      case CommandType.wifiOn:
        return 'wifi_on';
      case CommandType.wifiOff:
        return 'wifi_off';
      case CommandType.internetOffPermanent:
        return 'internet_off_permanent';
      case CommandType.internetOn:
        return 'internet_on';
      case CommandType.bluetoothOn:
        return 'bluetooth_on';
      case CommandType.bluetoothOff:
        return 'bluetooth_off';
      case CommandType.listBluetoothDevices:
        return 'list_bluetooth_devices';
      case CommandType.openBluetoothReceive:
        return 'open_bluetooth_receive';
      case CommandType.sendBluetoothFile:
        return 'send_bluetooth_file';
      case CommandType.showMessage:
        return 'show_message';
      case CommandType.volumeUp:
        return 'volume_up';
      case CommandType.volumeDown:
        return 'volume_down';
      case CommandType.setVolume:
        return 'set_volume';
      case CommandType.muteVolume:
        return 'mute_volume';
      case CommandType.unmuteVolume:
        return 'unmute_volume';
      case CommandType.shutdownPc:
        return 'shutdown_pc';
      case CommandType.restartPc:
        return 'restart_pc';
      case CommandType.lockScreen:
        return 'lock_screen';
      case CommandType.lockForDuration:
        return 'lock_for_duration';
      case CommandType.lockAfterDelay:
        return 'lock_after_delay';
      case CommandType.clearTimedLock:
        return 'clear_timed_lock';
      case CommandType.cancelScheduledLock:
        return 'cancel_scheduled_lock';
      case CommandType.logoutUser:
        return 'logout_user';
      case CommandType.shutdownAfterDelay:
        return 'shutdown_after_delay';
      case CommandType.restartAfterDelay:
        return 'restart_after_delay';
      case CommandType.cancelScheduledPowerCommand:
        return 'cancel_scheduled_power_command';
      case CommandType.addPathRule:
        return 'add_path_rule';
      case CommandType.removePathRule:
        return 'remove_path_rule';
      case CommandType.updatePathRule:
        return 'update_path_rule';
      case CommandType.approvePermission:
        return 'approve_permission';
      case CommandType.rejectPermission:
        return 'reject_permission';
      case CommandType.approveInstall:
        return 'approve_install';
      case CommandType.rejectInstall:
        return 'reject_install';
      case CommandType.requestLogs:
        return 'request_logs';
      case CommandType.deleteCloudLogs:
        return 'delete_cloud_logs';
      case CommandType.browsePath:
        return 'browse_path';
      case CommandType.searchFiles:
        return 'search_files';
      case CommandType.openPath:
        return 'open_path';
      case CommandType.renamePath:
        return 'rename_path';
      case CommandType.copyPath:
        return 'copy_path';
      case CommandType.movePath:
        return 'move_path';
      case CommandType.deletePath:
        return 'delete_path';
      case CommandType.hidePath:
        return 'hide_path';
      case CommandType.unhidePath:
        return 'unhide_path';
    }
  }

  String get arabicTitle {
    switch (this) {
      case CommandType.checkConnection:
        return 'تحقق من الاتصال';
      case CommandType.closeApplication:
        return 'إغلاق تطبيق';
      case CommandType.closeApplicationAfterDelay:
        return 'إغلاق تطبيق بعد مدة';
      case CommandType.blockApplication:
        return 'منع تطبيق';
      case CommandType.allowApplication:
        return 'السماح لتطبيق';
      case CommandType.blockWebsite:
        return 'منع موقع';
      case CommandType.allowWebsite:
        return 'السماح لموقع';
      case CommandType.showPairingQr:
        return 'إظهار رمز الربط';
      case CommandType.showPermissionCenter:
        return 'فتح أذونات الكمبيوتر';
      case CommandType.configureTelegramChat:
        return 'ربط Telegram';
      case CommandType.requestScreenshot:
        return 'طلب لقطة شاشة';
      case CommandType.emergencyMode:
        return 'وضع الطوارئ';
      case CommandType.applyPresetMode:
        return 'تفعيل وضع جاهز';
      case CommandType.systemHealth:
        return 'صحة الجهاز';
      case CommandType.privacyMode:
        return 'وضع الخصوصية';
      case CommandType.undoLastCommand:
        return 'التراجع عن آخر أمر';
      case CommandType.wifiOn:
        return 'تشغيل WiFi';
      case CommandType.wifiOff:
        return 'فصل WiFi';
      case CommandType.internetOffPermanent:
        return 'إيقاف الإنترنت نهائياً';
      case CommandType.internetOn:
        return 'تشغيل الإنترنت';
      case CommandType.bluetoothOn:
        return 'تشغيل Bluetooth';
      case CommandType.bluetoothOff:
        return 'إيقاف Bluetooth';
      case CommandType.listBluetoothDevices:
        return 'عرض أجهزة Bluetooth';
      case CommandType.openBluetoothReceive:
        return 'تلقي ملف عبر Bluetooth';
      case CommandType.sendBluetoothFile:
        return 'إرسال ملف عبر Bluetooth';
      case CommandType.showMessage:
        return 'عرض رسالة على الكمبيوتر';
      case CommandType.volumeUp:
        return 'رفع الصوت';
      case CommandType.volumeDown:
        return 'خفض الصوت';
      case CommandType.setVolume:
        return 'تحديد مستوى الصوت';
      case CommandType.muteVolume:
        return 'كتم الصوت';
      case CommandType.unmuteVolume:
        return 'إلغاء الكتم';
      case CommandType.shutdownPc:
        return 'إغلاق الكمبيوتر';
      case CommandType.restartPc:
        return 'إعادة التشغيل';
      case CommandType.lockScreen:
        return 'قفل الشاشة';
      case CommandType.lockForDuration:
        return 'قفل لمدة محددة';
      case CommandType.lockAfterDelay:
        return 'قفل بعد مدة';
      case CommandType.clearTimedLock:
        return 'إيقاف إعادة القفل';
      case CommandType.cancelScheduledLock:
        return 'إلغاء قفل مجدول';
      case CommandType.logoutUser:
        return 'تسجيل الخروج';
      case CommandType.shutdownAfterDelay:
        return 'إغلاق بعد مدة';
      case CommandType.restartAfterDelay:
        return 'إعادة تشغيل بعد مدة';
      case CommandType.cancelScheduledPowerCommand:
        return 'إلغاء أمر طاقة مجدول';
      case CommandType.addPathRule:
        return 'إضافة قاعدة مسار';
      case CommandType.removePathRule:
        return 'حذف قاعدة مسار';
      case CommandType.updatePathRule:
        return 'تعديل قاعدة مسار';
      case CommandType.approvePermission:
        return 'الموافقة على إذن';
      case CommandType.rejectPermission:
        return 'رفض إذن';
      case CommandType.approveInstall:
        return 'الموافقة على تثبيت';
      case CommandType.rejectInstall:
        return 'رفض تثبيت';
      case CommandType.requestLogs:
        return 'طلب السجلات';
      case CommandType.deleteCloudLogs:
        return 'حذف سجلات السحابة';
      case CommandType.browsePath:
        return 'عرض مسار';
      case CommandType.searchFiles:
        return 'بحث عن ملف';
      case CommandType.openPath:
        return 'فتح مسار على الكمبيوتر';
      case CommandType.renamePath:
        return 'إعادة تسمية';
      case CommandType.copyPath:
        return 'نسخ';
      case CommandType.movePath:
        return 'نقل';
      case CommandType.deletePath:
        return 'حذف';
      case CommandType.hidePath:
        return 'إخفاء';
      case CommandType.unhidePath:
        return 'إظهار';
    }
  }

  static CommandType fromWireName(String value) {
    return CommandType.values.firstWhere(
      (type) => type.wireName == value,
      orElse: () => CommandType.checkConnection,
    );
  }
}
