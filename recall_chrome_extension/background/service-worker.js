/**
 * Background service worker for the ReCall Chrome extension.
 *
 * Handles:
 * - Bookmark event listeners (onCreated, onRemoved, onMoved, onChanged)
 * - Periodic reconciliation via chrome.alarms
 * - Message handling from popup
 */

// Import library modules
importScripts(
  '../lib/url-utils.js',
  '../lib/storage.js',
  '../lib/api-client.js',
  '../lib/auth.js',
  '../lib/bookmark-sync.js'
);

// ===== Bookmark Event Listeners =====

chrome.bookmarks.onCreated.addListener(async (id, bookmark) => {
  const settings = await getSettings();
  if (!settings.autoSync) return;

  const authenticated = await ensureAuth();
  if (!authenticated) return;

  try {
    await syncSingleBookmark(id, bookmark);
    console.log(`[ReCall] Synced new bookmark: ${bookmark.url}`);
  } catch (err) {
    console.error(`[ReCall] Failed to sync bookmark ${id}:`, err);
    // Queue for retry
    await addToSyncQueue({ type: 'created', bookmarkId: id, url: bookmark.url, title: bookmark.title });
  }
});

chrome.bookmarks.onRemoved.addListener(async (id, removeInfo) => {
  // Mark as removed in local state but do NOT delete from ReCall
  const synced = await getSyncedBookmarks();
  if (synced[id]) {
    delete synced[id];
    await setSyncedBookmarks(synced);
    console.log(`[ReCall] Bookmark ${id} removed from Chrome (kept in ReCall)`);
  }
});

chrome.bookmarks.onMoved.addListener(async (id, moveInfo) => {
  const settings = await getSettings();
  if (!settings.autoSync) return;

  const authenticated = await ensureAuth();
  if (!authenticated) return;

  try {
    await handleBookmarkMoved(id, moveInfo);
    console.log(`[ReCall] Updated space mapping for moved bookmark ${id}`);
  } catch (err) {
    console.error(`[ReCall] Failed to handle bookmark move ${id}:`, err);
    await addToSyncQueue({ type: 'moved', bookmarkId: id, moveInfo });
  }
});

chrome.bookmarks.onChanged.addListener(async (id, changeInfo) => {
  // If URL changed, treat as a new bookmark
  if (changeInfo.url) {
    const settings = await getSettings();
    if (!settings.autoSync) return;

    const authenticated = await ensureAuth();
    if (!authenticated) return;

    try {
      // Remove old tracking
      const synced = await getSyncedBookmarks();
      delete synced[id];
      await setSyncedBookmarks(synced);

      // Sync as new
      const [bookmark] = await chrome.bookmarks.get(id);
      await syncSingleBookmark(id, bookmark);
      console.log(`[ReCall] Re-synced changed bookmark ${id}`);
    } catch (err) {
      console.error(`[ReCall] Failed to handle bookmark change ${id}:`, err);
    }
  }
});

// ===== Periodic Reconciliation =====

const RECONCILE_ALARM = 'recall-reconcile';

// Set up periodic alarm (every 6 hours)
chrome.alarms.create(RECONCILE_ALARM, {
  periodInMinutes: 360,
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== RECONCILE_ALARM) return;

  const settings = await getSettings();
  if (!settings.autoSync) return;

  const authenticated = await ensureAuth();
  if (!authenticated) return;

  console.log('[ReCall] Running periodic reconciliation...');

  try {
    // Process any queued items first
    const queue = await getSyncQueue();
    if (queue.length > 0) {
      console.log(`[ReCall] Processing ${queue.length} queued items...`);
      for (const item of queue) {
        try {
          if (item.type === 'created') {
            const [bookmark] = await chrome.bookmarks.get(item.bookmarkId).catch(() => [null]);
            if (bookmark) {
              await syncSingleBookmark(item.bookmarkId, bookmark);
            }
          } else if (item.type === 'moved') {
            await handleBookmarkMoved(item.bookmarkId, item.moveInfo);
          }
        } catch (err) {
          console.error(`[ReCall] Failed to process queued item:`, err);
        }
      }
      await clearSyncQueue();
    }
  } catch (err) {
    console.error('[ReCall] Reconciliation failed:', err);
  }
});

// ===== Message Handling (from popup) =====

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'FULL_SYNC') {
    handleFullSync(message).then(sendResponse);
    return true; // Keep message channel open for async response
  }

  if (message.type === 'GET_STATUS') {
    handleGetStatus().then(sendResponse);
    return true;
  }

  if (message.type === 'LOGIN') {
    handleLogin().then(sendResponse);
    return true;
  }

  if (message.type === 'LOGOUT') {
    handleLogout().then(sendResponse);
    return true;
  }
});

async function handleFullSync(message) {
  try {
    const authenticated = await ensureAuth();
    if (!authenticated) {
      return { success: false, error: 'Not authenticated' };
    }

    const result = await fullSync((stage, current, total) => {
      // Send progress updates to popup
      chrome.runtime.sendMessage({
        type: 'SYNC_PROGRESS',
        stage,
        current,
        total,
      }).catch(() => {}); // Popup may be closed
    });

    return { success: true, ...result };
  } catch (err) {
    console.error('[ReCall] Full sync failed:', err);
    return { success: false, error: err.message };
  }
}

async function handleGetStatus() {
  const token = await getAuthToken();
  const user = await getUser();
  const expired = await isTokenExpired();
  const lastSync = await getLastFullSync();
  const synced = await getSyncedBookmarks();
  const settings = await getSettings();

  // Count Chrome bookmarks
  let totalBookmarks = 0;
  try {
    const tree = await chrome.bookmarks.getTree();
    const flat = flattenBookmarkTree(tree, settings);
    totalBookmarks = flat.length;
  } catch {
    totalBookmarks = -1;
  }

  return {
    isAuthenticated: !!token && !expired,
    user,
    lastSync,
    syncedCount: Object.keys(synced).length,
    totalBookmarks,
    settings,
  };
}

async function handleLogin() {
  try {
    const user = await login();
    return { success: true, user };
  } catch (err) {
    return { success: false, error: err.message };
  }
}

async function handleLogout() {
  await logout();
  return { success: true };
}

// ===== Extension Install =====

chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === 'install') {
    console.log('[ReCall] Extension installed');
  } else if (details.reason === 'update') {
    console.log(`[ReCall] Extension updated to ${chrome.runtime.getManifest().version}`);
  }
});
