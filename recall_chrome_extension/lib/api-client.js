/**
 * HTTP client for ReCall backend API.
 * Handles auth headers, retries, and error handling.
 */

// Backend URL — change to production URL when publishing
const API_BASE_URL = 'https://YOUR_BACKEND_DOMAIN/api';

/**
 * Make an authenticated API request.
 * @param {string} path - API path (e.g., '/chrome-sync/check-urls')
 * @param {object} options - Fetch options + { skipAuth: bool }
 * @returns {Promise<any>} Parsed JSON response
 */
async function apiRequest(path, options = {}) {
  const { skipAuth = false, ...fetchOptions } = options;

  const headers = {
    'Content-Type': 'application/json',
    ...fetchOptions.headers,
  };

  if (!skipAuth) {
    const token = await getAuthToken();
    if (!token) {
      throw new Error('Not authenticated');
    }
    headers['Authorization'] = `Bearer ${token}`;
  }

  const url = `${API_BASE_URL}${path}`;
  let lastError;

  // Retry up to 3 times with exponential backoff
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const response = await fetch(url, {
        ...fetchOptions,
        headers,
      });

      // Handle 401 — try re-auth once
      if (response.status === 401 && !skipAuth && attempt === 0) {
        const reauthed = await ensureAuth();
        if (reauthed) {
          const newToken = await getAuthToken();
          headers['Authorization'] = `Bearer ${newToken}`;
          continue;
        }
        throw new Error('Authentication failed');
      }

      // Handle 429 — respect Retry-After
      if (response.status === 429) {
        const retryAfter = parseInt(response.headers.get('Retry-After') || '5', 10);
        await sleep(retryAfter * 1000);
        continue;
      }

      if (!response.ok) {
        const error = await response.json().catch(() => ({ detail: response.statusText }));
        throw new Error(error.detail || `HTTP ${response.status}`);
      }

      return await response.json();
    } catch (err) {
      lastError = err;
      if (err.message === 'Authentication failed' || err.message === 'Not authenticated') {
        throw err;
      }
      // Network error — retry with backoff
      if (attempt < 2) {
        await sleep(Math.pow(2, attempt) * 1000);
      }
    }
  }

  throw lastError;
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// ===== Chrome Sync API methods =====

/**
 * Check which URLs already exist in the user's library.
 * @param {string[]} urls - URLs to check (max 500)
 * @returns {Promise<{existing_urls: Object, missing_urls: string[]}>}
 */
async function checkUrls(urls) {
  return apiRequest('/chrome-sync/check-urls', {
    method: 'POST',
    body: JSON.stringify({ urls }),
  });
}

/**
 * Bulk ingest bookmarks.
 * @param {Array<{url: string, title?: string, chrome_bookmark_id: string, folder_path?: string}>} bookmarks
 * @returns {Promise<{results: Array, created: number, skipped: number, errors: number}>}
 */
async function bulkIngest(bookmarks) {
  return apiRequest('/chrome-sync/bulk-ingest', {
    method: 'POST',
    body: JSON.stringify({ bookmarks }),
  });
}

/**
 * Map content items to spaces by folder name.
 * @param {Array<{content_id: string, space_name: string}>} mappings
 * @returns {Promise<object>}
 */
async function mapToSpaces(mappings) {
  return apiRequest('/chrome-sync/map-to-spaces', {
    method: 'POST',
    body: JSON.stringify({ mappings }),
  });
}

// Export
if (typeof globalThis !== 'undefined') {
  globalThis.API_BASE_URL = API_BASE_URL;
  globalThis.apiRequest = apiRequest;
  globalThis.checkUrls = checkUrls;
  globalThis.bulkIngest = bulkIngest;
  globalThis.mapToSpaces = mapToSpaces;
}
