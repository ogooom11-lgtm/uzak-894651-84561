/**
 * KIOM - Telegram Mini App Controller
 * Automatic Chat Binding, Live Cloud Device Discovery & Command Dispatcher
 */

// Default credentials embedded for seamless standalone & WebApp operation
const DEFAULT_USER_BOT_TOKEN = '8465366644:AAEMXtYGEl5Qo5BwNwiUdqmWml_vO-meliM';
const DEFAULT_CLOUD_DB_BOT_TOKEN = '8919370396:AAHQrNYtJzy7yVPGIWQSsQjbcaAJ1Q8cWGw';
const DEFAULT_CLOUD_DB_CHAT_ID = '-1004449817252';
const DEFAULT_CHAT_ID = '8597783492';

const tg = window.Telegram ? window.Telegram.WebApp : null;

// Application State
let state = {
  chatId: DEFAULT_CHAT_ID,
  botToken: DEFAULT_USER_BOT_TOKEN,
  cloudDbBotToken: DEFAULT_CLOUD_DB_BOT_TOKEN,
  cloudDbChatId: DEFAULT_CLOUD_DB_CHAT_ID,
  activeDeviceId: '',
  activeDeviceName: 'كمبيوتر KIOM',
  devices: []
};

document.addEventListener('DOMContentLoaded', () => {
  initApp();
  setupEventListeners();
  fetchLiveDevicesFromCloud();
  // Poll cloud devices every 8 seconds
  setInterval(fetchLiveDevicesFromCloud, 8000);
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
    if (tg.themeParams) {
      applyTelegramTheme(tg.themeParams);
    }
  }

  // 2. Load stored state from localStorage
  loadLocalStorage();

  // 3. Extract Auto-Binding parameters from URL query string
  const urlParams = new URLSearchParams(window.location.search);
  const qChatId = urlParams.get('chat_id');
  const qBotToken = urlParams.get('bot_token');
  const qDeviceId = urlParams.get('device_id');
  const qDeviceName = urlParams.get('device_name');

  if (qChatId) state.chatId = qChatId;
  if (qBotToken) state.botToken = qBotToken;

  // Fallback to Telegram native initData
  if (tg && tg.initDataUnsafe) {
    if (tg.initDataUnsafe.chat && tg.initDataUnsafe.chat.id) {
      state.chatId = tg.initDataUnsafe.chat.id.toString();
    } else if (tg.initDataUnsafe.user && tg.initDataUnsafe.user.id) {
      state.chatId = tg.initDataUnsafe.user.id.toString();
    }
  }

  // Handle Initial Device
  let initialDeviceId = qDeviceId;
  let initialDeviceName = qDeviceName;

  if (!initialDeviceId && tg && tg.initDataUnsafe && tg.initDataUnsafe.start_param) {
    const sp = tg.initDataUnsafe.start_param;
    if (sp.startsWith('dev_')) {
      initialDeviceId = sp.substring(4);
    }
  }

  if (initialDeviceId) {
    registerOrUpdateDevice(initialDeviceId, initialDeviceName || 'كمبيوتر متصل');
    selectDevice(initialDeviceId);
  } else if (!state.activeDeviceId && state.devices.length > 0) {
    selectDevice(state.devices[0].id);
  }

  saveLocalStorage();
  updateUI();
  showToast('✅ لوحة التحكم جاهزة ومربوطة بسحابة Telegram!');
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
  if (theme.link_color) root.style.setProperty('--link-color', theme.link_color);
  if (theme.button_color) root.style.setProperty('--button-color', theme.button_color);
  if (theme.button_text_color) root.style.setProperty('--button-text-color', theme.button_text_color);
}

/**
 * Load state from localStorage
 */
function loadLocalStorage() {
  try {
    const storedChatId = localStorage.getItem('kiom_chat_id');
    const storedToken = localStorage.getItem('kiom_bot_token');
    const storedActiveId = localStorage.getItem('kiom_active_device_id');
    const storedDevices = localStorage.getItem('kiom_devices_list');

    if (storedChatId) state.chatId = storedChatId;
    if (storedToken) state.botToken = storedToken;
    if (storedActiveId) state.activeDeviceId = storedActiveId;
    if (storedDevices) {
      state.devices = JSON.parse(storedDevices);
    }
  } catch (e) {
    console.warn('Failed to load localStorage:', e);
  }
}

/**
 * Save state to localStorage
 */
function saveLocalStorage() {
  try {
    if (state.chatId) localStorage.setItem('kiom_chat_id', state.chatId);
    if (state.botToken) localStorage.setItem('kiom_bot_token', state.botToken);
    if (state.activeDeviceId) localStorage.setItem('kiom_active_device_id', state.activeDeviceId);
    localStorage.setItem('kiom_devices_list', JSON.stringify(state.devices));
  } catch (e) {
    console.warn('Failed to save localStorage:', e);
  }
}

/**
 * Register or update device in registry
 */
function registerOrUpdateDevice(id, name, extra = {}) {
  if (!id) return;
  const existing = state.devices.find(d => d.id === id);
  if (existing) {
    if (name && name !== 'كمبيوتر متصل') existing.name = name;
    existing.lastSeen = new Date().toISOString();
    Object.assign(existing, extra);
  } else {
    state.devices.push({
      id: id,
      name: name || `كمبيوتر (${id.substring(0, 6)})`,
      registeredAt: new Date().toISOString(),
      lastSeen: new Date().toISOString(),
      ...extra
    });
  }
  saveLocalStorage();
}

/**
 * Select active device
 */
function selectDevice(id) {
  const dev = state.devices.find(d => d.id === id);
  if (dev) {
    state.activeDeviceId = dev.id;
    state.activeDeviceName = dev.name;
  } else if (id) {
    state.activeDeviceId = id;
    state.activeDeviceName = id;
    registerOrUpdateDevice(id, id);
  }
  saveLocalStorage();
  updateUI();
  if (state.activeDeviceId) {
    sendPcCommandSilent(`/use ${state.activeDeviceId}`);
  }
}

/**
 * Fetch Live Connected Devices from Telegram Cloud Database (#KIOM_STATE)
 */
async function fetchLiveDevicesFromCloud() {
  try {
    const url = `https://api.telegram.org/bot${state.cloudDbBotToken}/getUpdates?limit=30&offset=-30`;
    const resp = await fetch(url);
    const data = await resp.json();
    if (!data || !data.ok || !data.result) return;

    data.result.forEach(update => {
      const msg = update.message || update.channel_post;
      if (!msg || !msg.text) return;
      const text = msg.text.trim();
      if (text.startsWith('#KIOM_STATE')) {
        const jsonPart = text.substring('#KIOM_STATE'.length).trim();
        try {
          const payload = JSON.parse(jsonPart);
          if (payload && payload.deviceId) {
            registerOrUpdateDevice(payload.deviceId, payload.name || payload.deviceName, {
              cpu: payload.cpu || payload.cpuPercent,
              ram: payload.ram || payload.ramPercent,
              activeWindow: payload.activeWindow || payload.windowTitle,
              online: true,
              lastStateUpdate: new Date().toISOString()
            });

            if (!state.activeDeviceId || state.activeDeviceId === payload.deviceId) {
              state.activeDeviceId = payload.deviceId;
              state.activeDeviceName = payload.name || payload.deviceName || state.activeDeviceName;
              updateBadges(payload);
            }
          }
        } catch (_) {}
      }
    });

    updateUI();
  } catch (e) {
    console.debug('Cloud DB polling notice:', e);
  }
}

/**
 * Update Status Badges (CPU, RAM, Active Window)
 */
function updateBadges(payload) {
  const badgeCpu = document.getElementById('badgeCpu');
  const badgeRam = document.getElementById('badgeRam');
  const valActiveWindow = document.getElementById('valActiveWindow');

  if (badgeCpu && payload.cpu) {
    badgeCpu.textContent = `⚡ CPU: ${payload.cpu}`;
  }
  if (badgeRam && payload.ram) {
    badgeRam.textContent = `🧠 RAM: ${payload.ram}`;
  }
  if (valActiveWindow && payload.activeWindow) {
    valActiveWindow.textContent = payload.activeWindow;
  }
}

/**
 * Update UI Elements with current state
 */
function updateUI() {
  const headerDevice = document.getElementById('headerDeviceName');
  const headerStatus = document.getElementById('headerStatusText');
  const valCurrentDevice = document.getElementById('valCurrentDevice');
  const valCurrentChat = document.getElementById('valCurrentChat');
  const settingsChat = document.getElementById('settingsChatId');
  const settingsToken = document.getElementById('settingsBotToken');
  const settingsActive = document.getElementById('settingsActiveDevice');

  if (headerDevice) headerDevice.textContent = state.activeDeviceName || 'كمبيوتر KIOM';
  if (headerStatus) {
    headerStatus.textContent = state.activeDeviceId 
      ? `🟢 متصل: ${state.activeDeviceId.substring(0, 8)}... (${state.devices.length} جهاز مسجل)` 
      : '🟢 مربوط تلقائياً بسحابة Telegram';
  }

  if (valCurrentDevice) valCurrentDevice.textContent = state.activeDeviceId || 'الافتراضي (تلقائي)';
  if (valCurrentChat) valCurrentChat.textContent = state.chatId || DEFAULT_CHAT_ID;

  if (settingsChat) settingsChat.textContent = state.chatId || DEFAULT_CHAT_ID;
  if (settingsToken) settingsToken.textContent = `${state.botToken.substring(0, 10)}... (Control Bot)`;
  if (settingsActive) settingsActive.textContent = `${state.activeDeviceName} (${state.activeDeviceId || 'auto'})`;

  renderDeviceList();
}

/**
 * Render device list inside modal
 */
function renderDeviceList() {
  const container = document.getElementById('deviceListContainer');
  if (!container) return;

  if (state.devices.length === 0) {
    container.innerHTML = `
      <div class="card text-center text-muted text-sm">
        لا توجد أجهزة مسجلة بعد. عند تشغيل PC Agent على أي كمبيوتر سيظهر هنا فوراً.
      </div>
    `;
    return;
  }

  let html = '';
  state.devices.forEach(d => {
    const isSelected = d.id === state.activeDeviceId;
    html += `
      <div class="item-card" style="${isSelected ? 'border: 1px solid var(--accent-color); background: rgba(56, 189, 248, 0.08);' : ''}">
        <div class="item-left">
          <span class="item-icon">${isSelected ? '⭐' : '🖥️'}</span>
          <div class="item-text">
            <div class="item-title">${escapeHtml(d.name)} ${isSelected ? '<span class="badge badge-success text-xs">الجهاز النشط</span>' : ''}</div>
            <div class="item-sub font-mono">ID: ${escapeHtml(d.id)}</div>
          </div>
        </div>
        <div class="item-actions">
          ${isSelected 
            ? '<button class="btn btn-sm btn-outline-success" disabled>محدد ✓</button>' 
            : `<button class="btn btn-sm btn-primary" onclick="selectDevice('${escapeHtml(d.id)}'); closeDeviceSelectorModal(); showToast('تم اختيار الجهاز!');">اختيار ↵</button>`
          }
        </div>
      </div>
    `;
  });

  container.innerHTML = html;
}

/**
 * Send Command to PC (Direct Telegram Bot API Execution)
 */
async function sendPcCommand(command) {
  if (!command) return;
  const cleanCmd = command.trim();
  logTerminal(`> ${cleanCmd}`);

  // Send directly via Telegram Bot HTTP API
  const token = state.botToken || DEFAULT_USER_BOT_TOKEN;
  const chatId = state.chatId || DEFAULT_CHAT_ID;

  try {
    const url = `https://api.telegram.org/bot${token}/sendMessage`;
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        text: cleanCmd
      })
    });

    const resJson = await response.json();
    if (resJson && resJson.ok) {
      logTerminal(`✔ تم إرسال الأمر للكمبيوتر بنجاح (${cleanCmd})`);
      showToast(`⚡ تم إرسال الأمر: ${cleanCmd}`);
    } else {
      logTerminal(`⚠ تنبيه: ${resJson.description || 'فشل الإرسال'}`);
      showToast(`⚠️ ${resJson.description || 'تعذر الإرسال'}`, true);
    }
  } catch (e) {
    logTerminal(`❌ خطأ في الاتصال: ${e.message}`);
    showToast(`❌ خطأ في الاتصال بالسحابة`, true);
  }
}

/**
 * Send command silently without toast
 */
async function sendPcCommandSilent(command) {
  if (!command) return;
  const token = state.botToken || DEFAULT_USER_BOT_TOKEN;
  const chatId = state.chatId || DEFAULT_CHAT_ID;
  try {
    const url = `https://api.telegram.org/bot${token}/sendMessage`;
    await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        text: command.trim()
      })
    });
  } catch (_) {}
}

/**
 * Tab Navigation
 */
function switchTab(tabName) {
  const panes = document.querySelectorAll('.tab-pane');
  const navItems = document.querySelectorAll('.nav-item');

  panes.forEach(pane => pane.classList.remove('active'));
  navItems.forEach(item => item.classList.remove('active'));

  const targetPane = document.getElementById(`tab-${tabName}`);
  if (targetPane) targetPane.classList.add('active');

  const tabIndex = ['dashboard', 'controls', 'apps', 'files', 'insights'].indexOf(tabName);
  if (tabIndex !== -1 && navItems[tabIndex]) {
    navItems[tabIndex].classList.add('active');
  }

  window.scrollTo({ top: 0, behavior: 'smooth' });
}

/**
 * Action Handlers
 */
function handleSpeak() {
  const input = document.getElementById('inputSayText');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/say ${input.value.trim()}`);
  input.value = '';
}

function handleVolumeChange(val) {
  const label = document.getElementById('valVolumePercent');
  if (label) label.textContent = `${val}%`;
  sendPcCommand(`/vol ${val}`);
}

function handleOpenRemoteUrl() {
  const input = document.getElementById('inputOpenUrl');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/open ${input.value.trim()}`);
  input.value = '';
}

function handleSendToast() {
  const input = document.getElementById('inputToastText');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/toast ${input.value.trim()}`);
  input.value = '';
}

function handleBlockSite() {
  const input = document.getElementById('inputBlockSite');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/blocksite ${input.value.trim()}`);
  input.value = '';
}

function handleUnblockSite() {
  const input = document.getElementById('inputBlockSite');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/unblocksite ${input.value.trim()}`);
  input.value = '';
}

function handleBlockApp() {
  const input = document.getElementById('inputBlockApp');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/blockapp ${input.value.trim()}`);
  input.value = '';
}

function handleUnblockApp() {
  const input = document.getElementById('inputBlockApp');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/unblockapp ${input.value.trim()}`);
  input.value = '';
}

function handleLockPath() {
  const input = document.getElementById('inputLockPath');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/lock ${input.value.trim()}`);
  input.value = '';
}

function handleUnlockPath() {
  const input = document.getElementById('inputLockPath');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/unlock ${input.value.trim()}`);
  input.value = '';
}

function handleFastSendText() {
  const input = document.getElementById('inputFastTypeText');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/press ${input.value.trim()}`);
  input.value = '';
}

function handleDownloadFromUrl() {
  const input = document.getElementById('inputDownloadUrl');
  if (!input || !input.value.trim()) {
    showToast('⚠️ يرجى إدخال رابط الملف المراد تنزيله', true);
    return;
  }
  sendPcCommand(`/download ${input.value.trim()}`);
  input.value = '';
}

function handleSearchFiles() {
  const input = document.getElementById('inputSearchFile');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/search ${input.value.trim()}`);
  input.value = '';
}

function handleGetFile() {
  const input = document.getElementById('inputGetFilePath');
  if (!input || !input.value.trim()) return;
  sendPcCommand(`/get ${input.value.trim()}`);
  input.value = '';
}

function handleSyncOneDrive() {
  const input = document.getElementById('inputCloudFilePath');
  if (!input || !input.value.trim()) {
    showToast('⚠️ يرجى كتابة مسار الملف المراد مزامنته', true);
    return;
  }
  sendPcCommand(`/sync_onedrive ${input.value.trim()}`);
}

function handleSyncGDrive() {
  const input = document.getElementById('inputCloudFilePath');
  if (!input || !input.value.trim()) {
    showToast('⚠️ يرجى كتابة مسار الملف المراد مزامنته', true);
    return;
  }
  sendPcCommand(`/sync_gdrive ${input.value.trim()}`);
}

function handleFastCloudUpload() {
  const fileInput = document.getElementById('inputCloudFilePath');
  const urlInput = document.getElementById('inputCloudUploadUrl');
  if (!fileInput || !fileInput.value.trim()) {
    showToast('⚠️ يرجى كتابة مسار الملف بالكمبيوتر', true);
    return;
  }
  if (urlInput && urlInput.value.trim()) {
    sendPcCommand(`/upload_to ${fileInput.value.trim()} ${urlInput.value.trim()}`);
  } else {
    sendPcCommand(`/cloud_upload ${fileInput.value.trim()}`);
  }
}

function handleFilterLogs() {
  const selectType = document.getElementById('selectLogType');
  const selectRange = document.getElementById('selectLogRange');
  const typeVal = selectType ? selectType.value : 'all';
  const rangeVal = selectRange ? selectRange.value : 'today';

  sendPcCommand(`/logs ${typeVal} ${rangeVal}`);
  showToast(`🔍 جاري جلب السجل (${typeVal} - ${rangeVal})...`);
}

function handleTerminalSend() {
  const input = document.getElementById('inputTerminalCmd');
  if (!input || !input.value.trim()) return;
  sendPcCommand(input.value.trim());
  input.value = '';
}

function handleManualDeviceAdd() {
  const idInput = document.getElementById('inputManualDeviceId');
  const nameInput = document.getElementById('inputManualDeviceName');
  if (!idInput || !idInput.value.trim()) {
    showToast('⚠️ يرجى إدخال معرف الجهاز (Device ID)', true);
    return;
  }
  const id = idInput.value.trim();
  const name = nameInput && nameInput.value.trim() ? nameInput.value.trim() : `كمبيوتر (${id.substring(0, 6)})`;
  registerOrUpdateDevice(id, name);
  selectDevice(id);
  idInput.value = '';
  if (nameInput) nameInput.value = '';
  closeDeviceSelectorModal();
  showToast('✅ تم تسجيل واختيار الجهاز بنجاح!');
}

function handleClearData() {
  if (confirm('هل أنت متأكد من مسح البيانات المؤقتة؟')) {
    localStorage.clear();
    state.devices = [];
    state.activeDeviceId = '';
    closeSettingsModal();
    initApp();
    showToast('تم مسح الذاكرة المؤقتة بنجاح.');
  }
}

function refreshDashboard() {
  sendPcCommand('/status');
  fetchLiveDevicesFromCloud();
  showToast('🔄 تم إرسال طلب تحديث الحالة...');
}

/**
 * Modal Dialogs
 */
function openDeviceSelectorModal() {
  renderDeviceList();
  const modal = document.getElementById('modalDeviceSelector');
  if (modal) modal.classList.add('show');
}

function closeDeviceSelectorModal(e) {
  if (e && e.target !== e.currentTarget && e.target.tagName !== 'BUTTON') return;
  const modal = document.getElementById('modalDeviceSelector');
  if (modal) modal.classList.remove('show');
}

function openSettingsModal() {
  updateUI();
  const modal = document.getElementById('modalSettings');
  if (modal) modal.classList.add('show');
}

function closeSettingsModal(e) {
  if (e && e.target !== e.currentTarget && e.target.tagName !== 'BUTTON') return;
  const modal = document.getElementById('modalSettings');
  if (modal) modal.classList.remove('show');
}

/**
 * Toast Notification Helper
 */
let toastTimer = null;
function showToast(message, isError = false) {
  const toast = document.getElementById('appToast');
  if (!toast) return;

  toast.textContent = message;
  toast.style.borderColor = isError ? 'var(--danger-color)' : 'var(--card-border)';
  toast.classList.add('show');

  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.classList.remove('show');
  }, 2500);
}

/**
 * Terminal logger
 */
function logTerminal(msg) {
  const term = document.getElementById('terminalOutput');
  if (!term) return;
  term.textContent += `\n${msg}`;
  term.scrollTop = term.scrollHeight;
}

/**
 * Escape HTML
 */
function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

/**
 * Setup Event Listeners
 */
function setupEventListeners() {
  const enterInputs = [
    { id: 'inputSayText', fn: handleSpeak },
    { id: 'inputOpenUrl', fn: handleOpenRemoteUrl },
    { id: 'inputToastText', fn: handleSendToast },
    { id: 'inputBlockSite', fn: handleBlockSite },
    { id: 'inputBlockApp', fn: handleBlockApp },
    { id: 'inputLockPath', fn: handleLockPath },
    { id: 'inputDownloadUrl', fn: handleDownloadFromUrl },
    { id: 'inputSearchFile', fn: handleSearchFiles },
    { id: 'inputGetFilePath', fn: handleGetFile },
    { id: 'inputTerminalCmd', fn: handleTerminalSend }
  ];

  enterInputs.forEach(item => {
    const el = document.getElementById(item.id);
    if (el) {
      el.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          item.fn();
        }
      });
    }
  });
}
