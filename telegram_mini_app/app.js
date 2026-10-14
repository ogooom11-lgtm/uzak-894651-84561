/**
 * KIOM - Telegram Mini App Controller
<<<<<<< HEAD
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
=======
 * Automatic Chat Binding & Multi-Device Selection System
 */

const tg = window.Telegram ? window.Telegram.WebApp : null;

// App State
let state = {
  chatId: '',
  botToken: '',
  activeDeviceId: '',
  activeDeviceName: 'كمبيوتر KIOM',
  devices: []
};

document.addEventListener('DOMContentLoaded', () => {
  initApp();
  setupEventListeners();
});

/**
 * Initialize Telegram App & Auto-Binding
 */
function initApp() {
  // 1. Initialize Telegram WebApp SDK
  if (tg) {
    tg.ready();
    tg.expand();
    if (typeof tg.enableClosingConfirmation === 'function') {
      tg.enableClosingConfirmation();
    }
>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
    if (tg.themeParams) {
      applyTelegramTheme(tg.themeParams);
    }
  }
<<<<<<< HEAD
}

/**
 * Apply Telegram Theme parameters to CSS Variables
=======

  // 2. Load stored state from localStorage
  loadLocalStorage();

  // 3. Extract Auto-Binding parameters from URL query string
  const urlParams = new URLSearchParams(window.location.search);
  const qChatId = urlParams.get('chat_id');
  const qBotToken = urlParams.get('bot_token');
  const qDeviceId = urlParams.get('device_id');
  const qDeviceName = urlParams.get('device_name');

  // If passed from Bot URL, auto-bind immediately without asking user!
  if (qChatId) state.chatId = qChatId;
  if (qBotToken) state.botToken = qBotToken;

  // Telegram native initData fallback
  if (!state.chatId && tg && tg.initDataUnsafe) {
    if (tg.initDataUnsafe.chat && tg.initDataUnsafe.chat.id) {
      state.chatId = tg.initDataUnsafe.chat.id.toString();
    } else if (tg.initDataUnsafe.user && tg.initDataUnsafe.user.id) {
      state.chatId = tg.initDataUnsafe.user.id.toString();
    }
  }

  // Handle Device Registration from URL or start_param
  let initialDeviceId = qDeviceId;
  let initialDeviceName = qDeviceName;

  if (!initialDeviceId && tg && tg.initDataUnsafe && tg.initDataUnsafe.start_param) {
    const sp = tg.initDataUnsafe.start_param;
    if (sp.startsWith('dev_')) {
      initialDeviceId = sp.substring(4);
    } else {
      initialDeviceId = sp;
    }
  }

  if (initialDeviceId) {
    registerDevice({
      id: initialDeviceId,
      name: initialDeviceName || `كمبيوتر (${initialDeviceId.substring(0, 6)})`,
      lastSeen: new Date().toISOString()
    }, true);
  } else if (state.devices.length === 0) {
    // Default fallback device if none exist
    registerDevice({
      id: 'default_pc',
      name: 'كمبيوتر KIOM الأساسي',
      lastSeen: new Date().toISOString()
    }, true);
  }

  saveLocalStorage();
  updateUI();
}

/**
 * Apply Telegram Theme
>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
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
<<<<<<< HEAD
 * Tab Switching
 */
function switchTab(tabId) {
  triggerHaptic('light');

  // Deactivate all tabs
  document.querySelectorAll('.tab-pane').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));

  // Activate selected tab
=======
 * Storage Helpers
 */
function loadLocalStorage() {
  state.chatId = localStorage.getItem('kiom_chat_id') || '';
  state.botToken = localStorage.getItem('kiom_bot_token') || '';
  state.activeDeviceId = localStorage.getItem('kiom_active_device_id') || '';
  state.activeDeviceName = localStorage.getItem('kiom_active_device_name') || 'كمبيوتر KIOM';

  try {
    const rawDevices = localStorage.getItem('kiom_devices');
    if (rawDevices) {
      state.devices = JSON.parse(rawDevices);
    }
  } catch (e) {
    state.devices = [];
  }
}

function saveLocalStorage() {
  if (state.chatId) localStorage.setItem('kiom_chat_id', state.chatId);
  if (state.botToken) localStorage.setItem('kiom_bot_token', state.botToken);
  if (state.activeDeviceId) localStorage.setItem('kiom_active_device_id', state.activeDeviceId);
  if (state.activeDeviceName) localStorage.setItem('kiom_active_device_name', state.activeDeviceName);
  localStorage.setItem('kiom_devices', JSON.stringify(state.devices));
}

/**
 * Device Registration & Selection
 */
function registerDevice(device, setActive = false) {
  const index = state.devices.findIndex(d => d.id === device.id);
  if (index >= 0) {
    state.devices[index] = { ...state.devices[index], ...device };
  } else {
    state.devices.push(device);
  }

  if (setActive || !state.activeDeviceId) {
    state.activeDeviceId = device.id;
    state.activeDeviceName = device.name;
  }
}

function selectActiveDevice(deviceId) {
  const target = state.devices.find(d => d.id === deviceId);
  if (!target) return;

  state.activeDeviceId = target.id;
  state.activeDeviceName = target.name;
  saveLocalStorage();
  updateUI();
  closeDeviceSelectorModal();

  triggerHaptic('success');
  showToast(`✅ تم اختيار: ${target.name}`);

  // Send /use command to bot to switch targeted PC agent
  sendRawTelegramText(`/use ${target.id}`);
}

/**
 * UI Updates
 */
function updateUI() {
  // Header
  const titleEl = document.getElementById('headerDeviceName');
  if (titleEl) titleEl.innerText = state.activeDeviceName;

  // Info rows
  const devEl = document.getElementById('valCurrentDevice');
  if (devEl) devEl.innerText = `${state.activeDeviceName} (${state.activeDeviceId})`;

  const chatEl = document.getElementById('valCurrentChat');
  if (chatEl) chatEl.innerText = state.chatId || 'المحادثة الحالية';

  // Settings tab fields
  if (document.getElementById('cfgChatId')) document.getElementById('cfgChatId').value = state.chatId;
  if (document.getElementById('cfgDeviceId')) document.getElementById('cfgDeviceId').value = state.activeDeviceId;
  if (document.getElementById('cfgDeviceName')) document.getElementById('cfgDeviceName').value = state.activeDeviceName;

  renderDevicesList();
}

function renderDevicesList() {
  const container = document.getElementById('devicesListContainer');
  if (!container) return;

  if (state.devices.length === 0) {
    container.innerHTML = `<p class="text-muted text-center py-3">لا توجد أجهزة مضافة حالياً.</p>`;
    return;
  }

  container.innerHTML = state.devices.map(d => {
    const isActive = d.id === state.activeDeviceId;
    return `
      <div class="device-item-card ${isActive ? 'active' : ''}" onclick="selectActiveDevice('${d.id}')">
        <div class="device-item-info">
          <span style="font-size:20px;">💻</span>
          <div>
            <div class="device-item-title">${d.name}</div>
            <div class="device-item-id">ID: ${d.id}</div>
          </div>
        </div>
        <div>
          ${isActive 
            ? `<span class="badge badge-success">✓ النشط حالياً</span>` 
            : `<span class="badge" style="background:rgba(255,255,255,0.08);">اختر</span>`}
        </div>
      </div>
    `;
  }).join('');
}

/**
 * Modals
 */
function openDeviceSelectorModal() {
  triggerHaptic('light');
  renderDevicesList();
  const modal = document.getElementById('deviceSelectorModal');
  if (modal) modal.classList.add('show');
}

function closeDeviceSelectorModal() {
  const modal = document.getElementById('deviceSelectorModal');
  if (modal) modal.classList.remove('show');
}

function handlePromptAddDevice() {
  const id = prompt('أدخل معرّف الجهاز (Device ID):');
  if (!id || !id.trim()) return;

  const name = prompt('أدخل اسم الجهاز (اختياري):', `كمبيوتر ${id.trim().substring(0, 4)}`);
  registerDevice({
    id: id.trim(),
    name: name && name.trim() ? name.trim() : `كمبيوتر ${id.trim()}`,
    lastSeen: new Date().toISOString()
  }, true);

  saveLocalStorage();
  updateUI();
  triggerHaptic('success');
  showToast('✅ تم إضافة الجهاز بنجاح!');
}

/**
 * Command Dispatching
 */
async function sendPcCommand(commandText) {
  triggerHaptic('medium');
  showToast(`⚡ جاري إرسال: ${commandText}...`);
  await sendRawTelegramText(commandText);
}

async function sendRawTelegramText(text) {
  // Method 1: If botToken and chatId are known (auto-bound from bot URL)
  if (state.botToken && state.chatId) {
    try {
      const url = `https://api.telegram.org/bot${state.botToken}/sendMessage`;
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: state.chatId,
          text: text
        })
      });

      const resData = await response.json();
      if (resData.ok) {
        showToast(`✅ تم تنفيذ الأمر بنجاح!`);
        triggerHaptic('success');
        return;
      }
    } catch (e) {
      console.error('API Send error:', e);
    }
  }

  // Method 2: Telegram WebApp sendData (if opened inside Telegram Keyboard mode)
  if (tg && typeof tg.sendData === 'function') {
    try {
      tg.sendData(text);
      showToast(`✅ تم إرسال الأمر للبوت`);
      return;
    } catch (e) {}
  }

  // Fallback toast
  showToast(`⚡ تم توجيه الأمر: ${text}`);
}

/**
 * UI Action Handlers
 */
function switchTab(tabId) {
  triggerHaptic('light');
  document.querySelectorAll('.tab-pane').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));

>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
  const targetTab = document.getElementById(tabId);
  const targetNav = document.querySelector(`.nav-item[data-tab="${tabId}"]`);

  if (targetTab) targetTab.classList.add('active');
  if (targetNav) targetNav.classList.add('active');

<<<<<<< HEAD
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
=======
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function handleSpeak() {
  const text = document.getElementById('inputSayText').value.trim();
  if (!text) return showToast('⚠️ يرجى كتابة نص ليتم نطقه');
>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
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
<<<<<<< HEAD
  if (!msg) {
    showToast('⚠️ يرجى كتابة نص الرسالة');
    return;
  }
=======
  if (!msg) return showToast('⚠️ يرجى كتابة نص الرسالة');
>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
  sendPcCommand(`/toast ${title} | ${msg}`);
  document.getElementById('toastMsg').value = '';
}

function handleSetClipboard() {
  const text = prompt('أدخل النص الذي تريد نسخه إلى حافظة الكمبيوتر:');
<<<<<<< HEAD
  if (text) {
    sendPcCommand(`/clip ${text}`);
  }
=======
  if (text) sendPcCommand(`/clip ${text}`);
>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
}

function handleOpenRemoteUrl() {
  const url = document.getElementById('inputOpenUrl').value.trim();
<<<<<<< HEAD
  if (!url) {
    showToast('⚠️ يرجى إدخال الرابط');
    return;
  }
=======
  if (!url) return showToast('⚠️ يرجى إدخال الرابط');
>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
  sendPcCommand(`/open ${url}`);
  document.getElementById('inputOpenUrl').value = '';
}

function handleRemoteDownload() {
  const url = document.getElementById('inputDownloadUrl').value.trim();
<<<<<<< HEAD
  if (!url) {
    showToast('⚠️ يرجى إدخال رابط الملف');
    return;
  }
=======
  if (!url) return showToast('⚠️ يرجى إدخال رابط الملف');
>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
  sendPcCommand(`/download ${url}`);
  document.getElementById('inputDownloadUrl').value = '';
}

<<<<<<< HEAD
=======
function handleCloudUploadUrl() {
  const path = document.getElementById('inputCloudLocalPath').value.trim();
  const url = document.getElementById('inputCloudUploadUrl').value.trim();
  if (!path || !url) return showToast('⚠️ يرجى إدخال مسار الملف ورابط الرفع');
  sendPcCommand(`/upload_to ${path} ${url}`);
}

function handleSyncOneDrive() {
  const path = document.getElementById('inputCloudLocalPath').value.trim();
  if (!path) return showToast('⚠️ يرجى إدخال مسار الملف');
  sendPcCommand(`/sync_onedrive ${path}`);
}

function handleSyncGDrive() {
  const path = document.getElementById('inputCloudLocalPath').value.trim();
  if (!path) return showToast('⚠️ يرجى إدخال مسار الملف');
  sendPcCommand(`/sync_gdrive ${path}`);
}

function handleFastCloudUpload() {
  const path = document.getElementById('inputCloudLocalPath').value.trim();
  if (!path) return showToast('⚠️ يرجى إدخال مسار الملف');
  sendPcCommand(`/cloud_upload ${path}`);
}

>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
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

<<<<<<< HEAD
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
=======
function handleFetchFile() {
  const path = document.getElementById('inputFetchPath').value.trim();
  if (!path) return showToast('⚠️ يرجى إدخال مسار الملف أو المجلد');
>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
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

<<<<<<< HEAD
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
=======
>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
function setupEventListeners() {
  document.getElementById('btnRefresh').addEventListener('click', () => {
    triggerHaptic('light');
    sendPcCommand('/status');
  });

<<<<<<< HEAD
  document.getElementById('btnSettings').addEventListener('click', () => {
    switchTab('tab-settings');
  });
}

/**
 * Haptic Feedback helper
 */
=======
  const modal = document.getElementById('deviceSelectorModal');
  if (modal) {
    modal.addEventListener('click', (e) => {
      if (e.target === modal) closeDeviceSelectorModal();
    });
  }
}

>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
function triggerHaptic(type) {
  if (tg && tg.HapticFeedback) {
    if (type === 'light' || type === 'medium' || type === 'heavy') {
      tg.HapticFeedback.impactOccurred(type);
    } else if (type === 'success' || type === 'error' || type === 'warning') {
      tg.HapticFeedback.notificationOccurred(type);
    }
  }
}

<<<<<<< HEAD
/**
 * Toast Notification Overlay
 */
=======
>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
function showToast(message) {
  const toast = document.getElementById('appToast');
  if (!toast) return;
  toast.innerText = message;
  toast.classList.add('show');
<<<<<<< HEAD
  
=======
>>>>>>> 251eaa2 (Auto-bind Mini App to conversation and implement multi-device selector)
  clearTimeout(window._toastTimeout);
  window._toastTimeout = setTimeout(() => {
    toast.classList.remove('show');
  }, 2800);
}
