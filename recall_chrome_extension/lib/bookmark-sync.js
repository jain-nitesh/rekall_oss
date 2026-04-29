/**
 * Core bookmark sync logic.
 *
 * Handles:
 * - Reading Chrome bookmark tree
 * - Flattening to a list with folder paths
 * - Initial full sync
 * - Incremental sync for individual bookmarks
 */

// Chrome's built-in root container IDs (fixed across all locales)
// "0" = root, "1" = Bookmarks Bar, "2" = Other Bookmarks, "3" = Mobile Bookmarks
const CHROME_ROOT_IDS = new Set(['0', '1', '2', '3']);
const OTHER_BOOKMARKS_ID = '2';
const MOBILE_BOOKMARKS_ID = '3';

/**
 * Flatten the Chrome bookmark tree into a list of bookmarks with folder paths.
 * @param {object[]} tree - From chrome.bookmarks.getTree()
 * @param {object} settings - User settings (syncOtherBookmarks, nestedFolderStyle)
 * @returns {Array<{id: string, url: string, title: string, folderPath: string|null}>}
 */
function flattenBookmarkTree(tree, settings = {}) {
  const bookmarks = [];

  function walk(nodes, pathParts) {
    if (!nodes || !Array.isArray(nodes)) return;

    for (const node of nodes) {
      if (node.url) {
        // Leaf node — it's a bookmark
        if (node.url.startsWith('http://') || node.url.startsWith('https://')) {
          const folderPath = pathParts.length > 0
            ? pathParts.join(' / ')
            : null;

          bookmarks.push({
            id: node.id,
            url: node.url,
            title: node.title || '',
            folderPath,
          });
        }
      } else if (node.children) {
        // Folder node
        const isRoot = CHROME_ROOT_IDS.has(node.id);

        // Skip "Mobile Bookmarks" (id=3) or "Other Bookmarks" (id=2) based on settings
        if (node.id === MOBILE_BOOKMARKS_ID && !settings.syncMobileBookmarks) {
          console.log(`[ReCall] Skipping Mobile Bookmarks (id=${node.id})`);
          continue;
        }
        if (node.id === OTHER_BOOKMARKS_ID && !settings.syncOtherBookmarks) {
          console.log(`[ReCall] Skipping Other Bookmarks (id=${node.id})`);
          continue;
        }

        // Root containers are transparent — don't become Spaces
        const title = (node.title || '').trim();
        const newPath = isRoot || !title
          ? pathParts
          : [...pathParts, title];

        console.log(`[ReCall] Walking folder: "${title}" (id=${node.id}, isRoot=${isRoot}, children=${node.children.length})`);
        walk(node.children, newPath);
      }
    }
  }

  console.log('[ReCall] flattenBookmarkTree called, tree nodes:', tree?.length);
  walk(tree, []);
  console.log(`[ReCall] Found ${bookmarks.length} bookmarks`);
  return bookmarks;
}

/**
 * Get the folder path for a bookmark by its parent chain.
 * @param {string} bookmarkId
 * @returns {Promise<string|null>}
 */
async function getFolderPathForBookmark(bookmarkId) {
  const [bookmark] = await chrome.bookmarks.get(bookmarkId);
  if (!bookmark || !bookmark.parentId) return null;

  const pathParts = [];
  let currentId = bookmark.parentId;

  while (currentId && !CHROME_ROOT_IDS.has(currentId)) {
    const [node] = await chrome.bookmarks.get(currentId);
    if (!node) break;

    if (node.title) {
      pathParts.unshift(node.title);
    }
    currentId = node.parentId;
  }

  return pathParts.length > 0 ? pathParts.join(' / ') : null;
}

/**
 * Chunk an array into smaller batches.
 * @param {Array} array
 * @param {number} size
 * @returns {Array<Array>}
 */
function chunk(array, size) {
  const chunks = [];
  for (let i = 0; i < array.length; i += size) {
    chunks.push(array.slice(i, i + size));
  }
  return chunks;
}

/**
 * Run a full bookmark sync.
 * @param {function} onProgress - Callback(stage, current, total)
 * @returns {Promise<{created: number, skipped: number, spacesCreated: number, errors: number}>}
 */
async function fullSync(onProgress = () => {}) {
  const settings = await getSettings();
  console.log('[ReCall] fullSync settings:', JSON.stringify(settings));
  const syncedBookmarks = await getSyncedBookmarks();

  // Step 1: Read bookmark tree
  onProgress('reading', 0, 0);
  const tree = await chrome.bookmarks.getTree();
  console.log('[ReCall] chrome.bookmarks.getTree() returned', tree?.length, 'root nodes');
  const bookmarks = flattenBookmarkTree(tree, settings);
  console.log(`[ReCall] fullSync: ${bookmarks.length} bookmarks to process`);
  onProgress('reading', bookmarks.length, bookmarks.length);

  if (bookmarks.length === 0) {
    return { created: 0, skipped: 0, spacesCreated: 0, errors: 0 };
  }

  // Step 2: Check which URLs already exist (batch 500)
  onProgress('checking', 0, bookmarks.length);
  const allUrls = bookmarks.map(b => b.url);
  const urlBatches = chunk(allUrls, 500);
  const existingUrlMap = {}; // url -> content_id

  for (let i = 0; i < urlBatches.length; i++) {
    const result = await checkUrls(urlBatches[i]);
    Object.assign(existingUrlMap, result.existing_urls);
    onProgress('checking', Math.min((i + 1) * 500, allUrls.length), allUrls.length);
  }

  // Separate new vs existing bookmarks
  const newBookmarks = [];
  const existingBookmarks = [];

  for (const bm of bookmarks) {
    const normalized = normalizeUrl(bm.url);
    if (existingUrlMap[bm.url]) {
      existingBookmarks.push({ ...bm, contentId: existingUrlMap[bm.url] });
    } else {
      newBookmarks.push(bm);
    }
  }

  // Step 3: Bulk ingest new bookmarks (batch 100)
  let totalCreated = 0;
  let totalErrors = 0;
  const ingestBatches = chunk(newBookmarks, 100);
  const newContentMap = {}; // chrome_bookmark_id -> content_id

  onProgress('ingesting', 0, newBookmarks.length);
  for (let i = 0; i < ingestBatches.length; i++) {
    const batch = ingestBatches[i].map(bm => ({
      url: bm.url,
      title: bm.title || undefined,
      chrome_bookmark_id: bm.id,
      folder_path: bm.folderPath,
    }));

    const result = await bulkIngest(batch);
    totalCreated += result.created;
    totalErrors += result.errors;

    for (const item of result.results) {
      if (item.content_id) {
        newContentMap[item.chrome_bookmark_id] = item.content_id;
      }
    }

    onProgress('ingesting', Math.min((i + 1) * 100, newBookmarks.length), newBookmarks.length);
  }

  // Step 4: Map to spaces (batch 200)
  const spaceMappings = [];

  // New bookmarks with folders
  for (const bm of newBookmarks) {
    if (bm.folderPath && newContentMap[bm.id]) {
      spaceMappings.push({
        content_id: newContentMap[bm.id],
        space_name: bm.folderPath,
      });
    }
  }

  // Existing bookmarks with folders (may not be in the right space yet)
  for (const bm of existingBookmarks) {
    if (bm.folderPath && bm.contentId) {
      spaceMappings.push({
        content_id: bm.contentId,
        space_name: bm.folderPath,
      });
    }
  }

  let spacesCreated = 0;
  if (spaceMappings.length > 0) {
    onProgress('mapping', 0, spaceMappings.length);
    const mapBatches = chunk(spaceMappings, 200);

    for (let i = 0; i < mapBatches.length; i++) {
      const result = await mapToSpaces(mapBatches[i]);
      spacesCreated += result.spaces_created;
      onProgress('mapping', Math.min((i + 1) * 200, spaceMappings.length), spaceMappings.length);
    }
  }

  // Step 5: Update local sync state
  const updatedSynced = { ...syncedBookmarks };
  for (const bm of newBookmarks) {
    if (newContentMap[bm.id]) {
      updatedSynced[bm.id] = {
        content_id: newContentMap[bm.id],
        url: bm.url,
        synced_at: new Date().toISOString(),
      };
    }
  }
  for (const bm of existingBookmarks) {
    updatedSynced[bm.id] = {
      content_id: bm.contentId,
      url: bm.url,
      synced_at: new Date().toISOString(),
    };
  }

  await setSyncedBookmarks(updatedSynced);
  await setLastFullSync(new Date().toISOString());

  // Update synced folders
  const folderMap = {};
  for (const bm of bookmarks) {
    if (bm.folderPath) {
      folderMap[bm.folderPath] = true;
    }
  }
  await setSyncedFolders(folderMap);

  onProgress('done', 0, 0);

  return {
    created: totalCreated,
    skipped: existingBookmarks.length,
    spacesCreated,
    errors: totalErrors,
  };
}

/**
 * Sync a single new bookmark (for incremental sync).
 * @param {string} bookmarkId
 * @param {object} bookmark - { url, title, parentId }
 * @returns {Promise<{status: string, contentId?: string}>}
 */
async function syncSingleBookmark(bookmarkId, bookmark) {
  if (!bookmark.url || !bookmark.url.startsWith('http')) {
    return { status: 'skipped' };
  }

  // Check if already synced locally
  const synced = await getSyncedBookmarks();
  if (synced[bookmarkId]) {
    return { status: 'already_synced' };
  }

  // Check with backend
  const urlCheck = await checkUrls([bookmark.url]);
  let contentId;

  if (urlCheck.existing_urls[bookmark.url]) {
    contentId = urlCheck.existing_urls[bookmark.url];
  } else {
    // Ingest new bookmark
    const result = await bulkIngest([{
      url: bookmark.url,
      title: bookmark.title || undefined,
      chrome_bookmark_id: bookmarkId,
    }]);

    const item = result.results[0];
    if (item.status === 'error') {
      return { status: 'error', error: item.error };
    }
    contentId = item.content_id;
  }

  // Map to space if in a folder
  const folderPath = await getFolderPathForBookmark(bookmarkId);
  if (folderPath && contentId) {
    await mapToSpaces([{ content_id: contentId, space_name: folderPath }]);
  }

  // Update local state
  const updated = await getSyncedBookmarks();
  updated[bookmarkId] = {
    content_id: contentId,
    url: bookmark.url,
    synced_at: new Date().toISOString(),
  };
  await setSyncedBookmarks(updated);

  return { status: 'synced', contentId };
}

/**
 * Handle a bookmark being moved to a different folder.
 * @param {string} bookmarkId
 * @param {object} moveInfo - { parentId, oldParentId, index, oldIndex }
 */
async function handleBookmarkMoved(bookmarkId, moveInfo) {
  const synced = await getSyncedBookmarks();
  const entry = synced[bookmarkId];
  if (!entry || !entry.content_id) return;

  const newFolderPath = await getFolderPathForBookmark(bookmarkId);

  // Map to new space if there is one
  if (newFolderPath) {
    await mapToSpaces([{
      content_id: entry.content_id,
      space_name: newFolderPath,
    }]);
  }

  // Note: We don't remove from old space because the backend's
  // SpaceContent is additive. The content remains in both spaces,
  // which is acceptable behavior (user can clean up in the app).
}

// Export
if (typeof globalThis !== 'undefined') {
  globalThis.flattenBookmarkTree = flattenBookmarkTree;
  globalThis.getFolderPathForBookmark = getFolderPathForBookmark;
  globalThis.fullSync = fullSync;
  globalThis.syncSingleBookmark = syncSingleBookmark;
  globalThis.handleBookmarkMoved = handleBookmarkMoved;
  globalThis.chunk = chunk;
}
