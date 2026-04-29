/**
 * Popup UI controller.
 * Manages view switching, user interactions, and communication with the service worker.
 */

// ===== DOM References =====

const views = {
  login: document.getElementById('view-login'),
  main: document.getElementById('view-main'),
  progress: document.getElementById('view-progress'),
  complete: document.getElementById('view-complete'),
  settings: document.getElementById('view-settings'),
};

const els = {
  btnLogin: document.getElementById('btn-login'),
  btnLogout: document.getElementById('btn-logout'),
  btnSync: document.getElementById('btn-sync'),
  btnSyncNew: document.getElementById('btn-sync-new'),
  btnDone: document.getElementById('btn-done'),
  btnOpenSettings: document.getElementById('btn-open-settings'),
  btnSettingsBack: document.getElementById('btn-settings-back'),
  loginError: document.getElementById('login-error'),
  syncError: document.getElementById('sync-error'),
  userAvatar: document.getElementById('user-avatar'),
  userName: document.getElementById('user-name'),
  userEmail: document.getElementById('user-email'),
  statTotal: document.getElementById('stat-total'),
  statSynced: document.getElementById('stat-synced'),
  lastSync: document.getElementById('last-sync'),
  lastSyncTime: document.getElementById('last-sync-time'),
  footerSettings: document.getElementById('footer-settings'),
  progressStage: document.getElementById('progress-stage'),
  progressFill: document.getElementById('progress-fill'),
  progressDetail: document.getElementById('progress-detail'),
  resultCreated: document.getElementById('result-created'),
  resultSkipped: document.getElementById('result-skipped'),
  resultSpaces: document.getElementById('result-spaces'),
  settingAutoSync: document.getElementById('setting-auto-sync'),
  settingOtherBookmarks: document.getElementById('setting-other-bookmarks'),
  settingMobileBookmarks: document.getElementById('setting-mobile-bookmarks'),
};

// ===== View Management =====

function showView(viewName) {
  Object.values(views).forEach(v => v.classList.add('hidden'));
  views[viewName].classList.remove('hidden');

  // Show footer settings only on main view
  els.footerSettings.classList.toggle('hidden', viewName !== 'main');
}

function showError(element, message) {
  element.textContent = message;
  element.classList.remove('hidden');
}

function hideError(element) {
  element.classList.add('hidden');
}

// ===== Initialize =====

document.addEventListener('DOMContentLoaded', async () => {
  const status = await chrome.runtime.sendMessage({ type: 'GET_STATUS' });
  if (status.isAuthenticated) {
    showMainView(status);
  } else {
    showView('login');
  }
});

// ===== Main View =====

function showMainView(status) {
  showView('main');

  // User info
  if (status.user) {
    const initials = (status.user.name || status.user.email || '?')
      .split(' ')
      .map(w => w[0])
      .join('')
      .toUpperCase()
      .slice(0, 2);
    els.userAvatar.textContent = initials;
    els.userName.textContent = status.user.name || 'ReCall User';
    els.userEmail.textContent = status.user.email || '';
  }

  // Stats
  els.statTotal.textContent = status.totalBookmarks >= 0 ? status.totalBookmarks : '?';
  els.statSynced.textContent = status.syncedCount;

  // Last sync
  if (status.lastSync) {
    els.lastSync.classList.remove('hidden');
    els.lastSyncTime.textContent = formatRelativeTime(status.lastSync);

    // Show "Sync New" button if previously synced
    els.btnSyncNew.classList.remove('hidden');
    els.btnSync.textContent = 'Full Re-sync';
  }

  // Load settings
  if (status.settings) {
    els.settingAutoSync.checked = status.settings.autoSync;
    els.settingOtherBookmarks.checked = status.settings.syncOtherBookmarks;
    els.settingMobileBookmarks.checked = status.settings.syncMobileBookmarks;
  }
}

// ===== Event Handlers =====

els.btnLogin.addEventListener('click', async () => {
  els.btnLogin.disabled = true;
  hideError(els.loginError);

  const result = await chrome.runtime.sendMessage({ type: 'LOGIN' });

  if (result.success) {
    const status = await chrome.runtime.sendMessage({ type: 'GET_STATUS' });
    showMainView(status);
  } else {
    showError(els.loginError, result.error || 'Login failed. Please try again.');
    els.btnLogin.disabled = false;
  }
});

els.btnLogout.addEventListener('click', async () => {
  await chrome.runtime.sendMessage({ type: 'LOGOUT' });
  showView('login');
  els.btnLogin.disabled = false;
  hideError(els.loginError);
});

els.btnSync.addEventListener('click', () => startSync());
els.btnSyncNew.addEventListener('click', () => startSync());

async function startSync() {
  showView('progress');
  hideError(els.syncError);

  const result = await chrome.runtime.sendMessage({ type: 'FULL_SYNC' });

  if (result.success) {
    els.resultCreated.textContent = result.created;
    els.resultSkipped.textContent = result.skipped;
    els.resultSpaces.textContent = result.spacesCreated;
    showView('complete');
  } else {
    showView('main');
    showError(els.syncError, result.error || 'Sync failed. Please try again.');
  }
}

els.btnDone.addEventListener('click', async () => {
  const status = await chrome.runtime.sendMessage({ type: 'GET_STATUS' });
  showMainView(status);
});

els.btnOpenSettings.addEventListener('click', () => showView('settings'));

els.btnSettingsBack.addEventListener('click', async () => {
  // Save settings
  await updateSettings({
    autoSync: els.settingAutoSync.checked,
    syncOtherBookmarks: els.settingOtherBookmarks.checked,
    syncMobileBookmarks: els.settingMobileBookmarks.checked,
  });

  const status = await chrome.runtime.sendMessage({ type: 'GET_STATUS' });
  showMainView(status);
});

// ===== Listen for progress updates from service worker =====

chrome.runtime.onMessage.addListener((message) => {
  if (message.type === 'SYNC_PROGRESS') {
    updateProgress(message.stage, message.current, message.total);
  }
});

function updateProgress(stage, current, total) {
  const stageLabels = {
    reading: 'Reading bookmarks...',
    checking: 'Checking for duplicates...',
    ingesting: 'Syncing bookmarks...',
    mapping: 'Organizing into spaces...',
    done: 'Finishing up...',
  };

  els.progressStage.textContent = stageLabels[stage] || stage;

  if (total > 0) {
    const pct = Math.round((current / total) * 100);
    els.progressFill.style.width = `${pct}%`;
    els.progressDetail.textContent = `${current} / ${total}`;
  } else {
    els.progressFill.style.width = '100%';
    els.progressDetail.textContent = '';
  }
}

// ===== Helpers =====

function formatRelativeTime(isoString) {
  const date = new Date(isoString);
  const now = new Date();
  const diffMs = now - date;
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString();
}
