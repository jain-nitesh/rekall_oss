/**
 * Chrome storage abstraction layer.
 * Manages auth tokens, sync state, and settings.
 */

const STORAGE_KEYS = {
  AUTH_TOKEN: 'recall_auth_token',
  USER: 'recall_user',
  SYNCED_BOOKMARKS: 'recall_synced_bookmarks',
  SYNCED_FOLDERS: 'recall_synced_folders',
  LAST_FULL_SYNC: 'recall_last_full_sync',
  SETTINGS: 'recall_settings',
  SYNC_QUEUE: 'recall_sync_queue',
};

const DEFAULT_SETTINGS = {
  autoSync: true,
  syncOtherBookmarks: true,
  syncMobileBookmarks: false,
  nestedFolderStyle: 'path', // 'path' = "Parent / Child", 'flat' = only leaf name
};

/**
 * Get a value from chrome.storage.local.
 * @param {string} key
 * @returns {Promise<any>}
 */
async function storageGet(key) {
  const result = await chrome.storage.local.get(key);
  return result[key] ?? null;
}

/**
 * Set a value in chrome.storage.local.
 * @param {string} key
 * @param {any} value
 */
async function storageSet(key, value) {
  await chrome.storage.local.set({ [key]: value });
}

/**
 * Remove a key from chrome.storage.local.
 * @param {string} key
 */
async function storageRemove(key) {
  await chrome.storage.local.remove(key);
}

// ===== Auth helpers =====

async function getAuthToken() {
  return storageGet(STORAGE_KEYS.AUTH_TOKEN);
}

async function setAuthToken(token) {
  await storageSet(STORAGE_KEYS.AUTH_TOKEN, token);
}

async function getUser() {
  return storageGet(STORAGE_KEYS.USER);
}

async function setUser(user) {
  await storageSet(STORAGE_KEYS.USER, user);
}

async function clearAuth() {
  await chrome.storage.local.remove([
    STORAGE_KEYS.AUTH_TOKEN,
    STORAGE_KEYS.USER,
  ]);
}

/**
 * Check if stored JWT is expired.
 * @returns {Promise<boolean>} true if token is missing or expired
 */
async function isTokenExpired() {
  const token = await getAuthToken();
  if (!token) return true;

  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    const expMs = payload.exp * 1000;
    // Consider expired if within 1 hour of expiry
    return Date.now() > expMs - (60 * 60 * 1000);
  } catch {
    return true;
  }
}

// ===== Sync state helpers =====

async function getSyncedBookmarks() {
  return (await storageGet(STORAGE_KEYS.SYNCED_BOOKMARKS)) || {};
}

async function setSyncedBookmarks(bookmarks) {
  await storageSet(STORAGE_KEYS.SYNCED_BOOKMARKS, bookmarks);
}

async function getSyncedFolders() {
  return (await storageGet(STORAGE_KEYS.SYNCED_FOLDERS)) || {};
}

async function setSyncedFolders(folders) {
  await storageSet(STORAGE_KEYS.SYNCED_FOLDERS, folders);
}

async function getLastFullSync() {
  return storageGet(STORAGE_KEYS.LAST_FULL_SYNC);
}

async function setLastFullSync(timestamp) {
  await storageSet(STORAGE_KEYS.LAST_FULL_SYNC, timestamp);
}

// ===== Settings helpers =====

async function getSettings() {
  const settings = await storageGet(STORAGE_KEYS.SETTINGS);
  return { ...DEFAULT_SETTINGS, ...settings };
}

async function updateSettings(updates) {
  const current = await getSettings();
  await storageSet(STORAGE_KEYS.SETTINGS, { ...current, ...updates });
}

// ===== Sync queue (for offline support) =====

async function getSyncQueue() {
  return (await storageGet(STORAGE_KEYS.SYNC_QUEUE)) || [];
}

async function addToSyncQueue(item) {
  const queue = await getSyncQueue();
  queue.push({ ...item, queuedAt: new Date().toISOString() });
  await storageSet(STORAGE_KEYS.SYNC_QUEUE, queue);
}

async function clearSyncQueue() {
  await storageSet(STORAGE_KEYS.SYNC_QUEUE, []);
}

// Export for service worker
if (typeof globalThis !== 'undefined') {
  globalThis.STORAGE_KEYS = STORAGE_KEYS;
  globalThis.storageGet = storageGet;
  globalThis.storageSet = storageSet;
  globalThis.storageRemove = storageRemove;
  globalThis.getAuthToken = getAuthToken;
  globalThis.setAuthToken = setAuthToken;
  globalThis.getUser = getUser;
  globalThis.setUser = setUser;
  globalThis.clearAuth = clearAuth;
  globalThis.isTokenExpired = isTokenExpired;
  globalThis.getSyncedBookmarks = getSyncedBookmarks;
  globalThis.setSyncedBookmarks = setSyncedBookmarks;
  globalThis.getSyncedFolders = getSyncedFolders;
  globalThis.setSyncedFolders = setSyncedFolders;
  globalThis.getLastFullSync = getLastFullSync;
  globalThis.setLastFullSync = setLastFullSync;
  globalThis.getSettings = getSettings;
  globalThis.updateSettings = updateSettings;
  globalThis.getSyncQueue = getSyncQueue;
  globalThis.addToSyncQueue = addToSyncQueue;
  globalThis.clearSyncQueue = clearSyncQueue;
}
