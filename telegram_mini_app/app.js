/**
 * KIOM - Telegram Mini App Controller
 * Full integration with Telegram WebApp SDK & Telegram Bot API
 */

// Initialize Telegram WebApp
const tg = window.Telegram ? window.Telegram.WebApp : null;

// State
let appConfig = {
  botToken: localStorage.getItem('kiom_bot_token') || '',
  chatId: localStorage.getItem('kiom_chat_id') || '',
  deviceName: localStorage.getItem('kiom_device_name') || 'كمبيوتر KIOM'
};

document.addEventListener('DOMContentLoaded', () => {
  initTelegramApp();
  loadSavedSettings();
  setupEventListeners();
  updateHeaderInfo();
});

/**
 * Initialize Telegram WebApp SDK properties
 */
function initTelegramApp() {
  if (tg) {
    tg.ready();
    tg.expand();
    
    // Enable closing confirmation to prevent accidental swipes
    if (typeof tg.enableClosingConfirmation === 'function') {
      tg.enableClosingConfirmation();
    }

    // Auto-fill chat ID or user ID if available from Telegram
    if (tg.initDataUnsafe && tg.initDataUnsafe.user) {
      const user = tg.initDataUnsafe.user;
      if (!appConfig.chatId) {
        appConfig.chatId = user.id.toString();
        localStorage.setItem('kiom_chat_id', appConfig.chatId);
      }
    }

    // Adapt to Telegram theme
    if (tg.themeParams) {
      applyTelegramTheme(tg.themeParams);
    }
  }
}

/**
 * Apply Telegram Theme parameters to CSS Variables
 */
function applyTelegramTheme(theme) {
  const root = document.documentElement;
  if (theme.bg_color) root.style.setProperty('--bg-color', theme.bg_color);
  if (theme.secondary_bg_color) root.style.setProperty('--secondary-bg-color', theme.secondary_bg_color);
  if (theme.text_color) root.style.setProperty('--text-color', theme.text_color);
  if (theme.hint_color) root.style.setProperty('--hint-color', theme.hint_color);
  if (theme.button_color) root.style.setProperty('--button-color', theme.button_color);
  if (theme.button_text_color) root.style.setProperty('--button-text-color', theme.button_text_color);
}

/**
 * Tab Switching
 */
function switchTab(tabId) {
  triggerHaptic('light');

  // Deactivate all tabs
  document.querySelectorAll('.tab-pane').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));

  // Activate selected tab
  const targetTab = document.getElementById(tabId);
  const targetNav = document.querySelector(`.nav-item[data-tab="${tabId}"]`);

  if (targetTab) targetTab.classList.add('active');
  if (targetNav) targetNav.classList.add('active');

  // Scroll to top
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

/**
 * Send Command directly to the PC via Telegram
 */
async function sendPcCommand(commandText) {
  triggerHaptic('medium');
  showToast(`⚡ جاري إرسال الأمر: ${commandText}...`);

  // Method 1: If Telegram WebApp sendData is supported and in keyboard mode
  // Method 2: Call Telegram Bot API sendMessage directly if token and chat ID are configured
  if (appConfig.botToken && appConfig.chatId) {
    try {
      const url = `https://api.telegram.org/bot${appConfig.botToken}/sendMessage`;
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: appConfig.chatId,
          text: commandText
        })
      });

      const resData = await response.json();
      if (resData.ok) {
        showToast(`✅ تم إرسال الأمر بنجاح إلى الكمبيوتر!`);
        triggerHaptic('success');
      } else {
        showToast(`⚠️ خطأ في الإرسال: ${resData.description || 'فشل الاتصال'}`);
      }
    } catch (err) {
      console.error('Error sending command via Bot API:', err);
      showToast(`❌ تعذر الاتصال بـ Telegram API`);
    }
  } else if (tg && typeof tg.sendData === 'function') {
    // WebApp inline sendData
    try {
      tg.sendData(commandText);
      showToast(`✅ تم إرسال الأمر إلى البوت`);
    } catch (e) {
      promptSettingsAlert();
    }
  } else {
    promptSettingsAlert();
  }
}

function promptSettingsAlert() {
  showToast('⚙️ يرجى إدخال Bot Token و Chat ID في قسم الإعدادات أولاً');
  setTimeout(() => switchTab('tab-settings'), 800);
}

/**
 * Handlers for UI Actions
 */
function handleSpeak() {
  const text = document.getElementById('inputSayText').value.trim();
  if (!text) {
    showToast('⚠️ يرجى كتابة نص ليتم نطقه');
    return;
  }
  sendPcCommand(`/say ${text}`);
  document.getElementById('inputSayText').value = '';
}

function handleVolumeChange(val) {
  document.getElementById('valVolumePercent').innerText = `${val}%`;
  sendPcCommand(`/vol ${val}`);
}

function handleSendToast() {
  const title = document.getElementById('toastTitle').value.trim() || 'تنبيه';
  const msg = document.getElementById('toastMsg').value.trim();
  if (!msg) {
    showToast('⚠️ يرجى كتابة نص الرسالة');
    return;
  }
  sendPcCommand(`/toast ${title} | ${msg}`);
  document.getElementById('toastMsg').value = '';
}

function handleSetClipboard() {
  const text = prompt('أدخل النص الذي تريد نسخه إلى حافظة الكمبيوتر:');
  if (text) {
    sendPcCommand(`/clip ${text}`);
  }
}

function handleOpenRemoteUrl() {
  const url = document.getElementById('inputOpenUrl').value.trim();
  if (!url) {
    showToast('⚠️ يرجى إدخال الرابط');
    return;
  }
  sendPcCommand(`/open ${url}`);
  document.getElementById('inputOpenUrl').value = '';
}

function handleRemoteDownload() {
  const url = document.getElementById('inputDownloadUrl').value.trim();
  if (!url) {
    showToast('⚠️ يرجى إدخال رابط الملف');
    return;
  }
  sendPcCommand(`/download ${url}`);
  document.getElementById('inputDownloadUrl').value = '';
}

function handleBlockSite() {
  const site = document.getElementById('inputBlockSite').value.trim();
  if (!site) return;
  sendPcCommand(`/blocksite ${site}`);
  document.getElementById('inputBlockSite').value = '';
}

function handleQuickBlockSite(site) {
  sendPcCommand(`/blocksite ${site}`);
}

function handleBlockApp() {
  const app = document.getElementById('inputBlockApp').value.trim();
  if (!app) return;
  sendPcCommand(`/blockapp ${app}`);
  document.getElementById('inputBlockApp').value = '';
}

function handleQuickBlockApp(app) {
  sendPcCommand(`/blockapp ${app}`);
}

function handleBrowseCustomPath() {
  const path = document.getElementById('inputBrowsePath').value.trim();
  if (!path) return;
  sendPcCommand(`/browse ${path}`);
}

function handleCloudUploadUrl() {
  const path = document.getElementById('inputCloudLocalPath').value.trim();
  const url = document.getElementById('inputCloudUploadUrl').value.trim();
  if (!path || !url) {
    showToast('⚠️ يرجى إدخال مسار الملف ورابط الرفع');
    return;
  }
  sendPcCommand(`/upload_to ${path} ${url}`);
}

function handleSyncOneDrive() {
  const path = document.getElementById('inputCloudLocalPath').value.trim();
  if (!path) {
    showToast('⚠️ يرجى إدخال مسار الملف');
    return;
  }
  sendPcCommand(`/sync_onedrive ${path}`);
}

function handleSyncGDrive() {
  const path = document.getElementById('inputCloudLocalPath').value.trim();
  if (!path) {
    showToast('⚠️ يرجى إدخال مسار الملف');
    return;
  }
  sendPcCommand(`/sync_gdrive ${path}`);
}

function handleFastCloudUpload() {
  const path = document.getElementById('inputCloudLocalPath').value.trim();
  if (!path) {
    showToast('⚠️ يرجى إدخال مسار الملف');
    return;
  }
  sendPcCommand(`/cloud_upload ${path}`);
}

function handleFetchFile() {
  const path = document.getElementById('inputFetchPath').value.trim();
  if (!path) {
    showToast('⚠️ يرجى إدخال مسار الملف أو المجلد');
    return;
  }
  sendPcCommand(`/get ${path}`);
}

function setTerminalCmd(cmd) {
  document.getElementById('inputTerminalCmd').value = cmd;
}

function handleRunCommand() {
  const cmd = document.getElementById('inputTerminalCmd').value.trim();
  if (!cmd) return;
  
  const type = document.querySelector('input[name="termType"]:checked').value;
  const fullCmd = type === 'cmd' ? `/cmd ${cmd}` : `/ps ${cmd}`;

  const outputEl = document.getElementById('terminalOutput');
  outputEl.innerText = `> ${fullCmd}\n[جاري التنفيذ على جهاز الكمبيوتر... النتيجة الكاملة ستصل إلى محادثة Telegram]`;

  sendPcCommand(fullCmd);
}

/**
 * Settings Management
 */
function loadSavedSettings() {
  if (document.getElementById('cfgBotToken')) {
    document.getElementById('cfgBotToken').value = appConfig.botToken;
    document.getElementById('cfgChatId').value = appConfig.chatId;
    document.getElementById('cfgDeviceName').value = appConfig.deviceName;
  }
}

function saveSettings() {
  const botToken = document.getElementById('cfgBotToken').value.trim();
  const chatId = document.getElementById('cfgChatId').value.trim();
  const devName = document.getElementById('cfgDeviceName').value.trim() || 'كمبيوتر KIOM';

  appConfig.botToken = botToken;
  appConfig.chatId = chatId;
  appConfig.deviceName = devName;

  localStorage.setItem('kiom_bot_token', botToken);
  localStorage.setItem('kiom_chat_id', chatId);
  localStorage.setItem('kiom_device_name', devName);

  updateHeaderInfo();
  triggerHaptic('success');
  showToast('✅ تم حفظ الإعدادات بنجاح!');
}

function updateHeaderInfo() {
  const nameEl = document.getElementById('headerDeviceName');
  if (nameEl) nameEl.innerText = appConfig.deviceName;
  const devIdEl = document.getElementById('valDeviceId');
  if (devIdEl) devIdEl.innerText = appConfig.chatId || 'غير محدد';
}

/**
 * Event Listeners
 */
function setupEventListeners() {
  document.getElementById('btnRefresh').addEventListener('click', () => {
    triggerHaptic('light');
    sendPcCommand('/status');
  });

  document.getElementById('btnSettings').addEventListener('click', () => {
    switchTab('tab-settings');
  });
}

/**
 * Haptic Feedback helper
 */
function triggerHaptic(type) {
  if (tg && tg.HapticFeedback) {
    if (type === 'light' || type === 'medium' || type === 'heavy') {
      tg.HapticFeedback.impactOccurred(type);
    } else if (type === 'success' || type === 'error' || type === 'warning') {
      tg.HapticFeedback.notificationOccurred(type);
    }
  }
}

/**
 * Toast Notification Overlay
 */
function showToast(message) {
  const toast = document.getElementById('appToast');
  if (!toast) return;
  toast.innerText = message;
  toast.classList.add('show');
  
  clearTimeout(window._toastTimeout);
  window._toastTimeout = setTimeout(() => {
    toast.classList.remove('show');
  }, 2800);
}
