/**
 * URL normalization for deduplication.
 * Mirrors the backend's url_normalizer.py logic.
 */

const TRACKING_PARAMS = new Set([
  'utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term',
  'fbclid', 'gclid', 'gclsrc', 'dclid', 'msclkid',
  'ref', 'ref_src', 'ref_url',
  '_ga', '_gl', 'mc_cid', 'mc_eid',
  'yclid', 'twclid', 'ttclid',
]);

/**
 * Normalize a URL for deduplication.
 * @param {string} url
 * @returns {string} Normalized URL
 */
function normalizeUrl(url) {
  try {
    const parsed = new URL(url);

    // Lowercase scheme and hostname (URL API does this automatically)
    let hostname = parsed.hostname;

    // Strip www.
    if (hostname.startsWith('www.')) {
      hostname = hostname.slice(4);
    }
    parsed.hostname = hostname;

    // Remove trailing slashes from path (keep "/" for root)
    if (parsed.pathname.length > 1) {
      parsed.pathname = parsed.pathname.replace(/\/+$/, '');
    }

    // Remove tracking params, sort the rest
    const params = new URLSearchParams(parsed.search);
    const filtered = [];
    for (const [key, value] of params) {
      if (!TRACKING_PARAMS.has(key.toLowerCase())) {
        filtered.push([key, value]);
      }
    }
    filtered.sort((a, b) => a[0].localeCompare(b[0]));
    parsed.search = new URLSearchParams(filtered).toString();

    // Remove fragment unless it's a SPA route
    if (parsed.hash && !parsed.hash.startsWith('#/') && !parsed.hash.startsWith('#!')) {
      parsed.hash = '';
    }

    return parsed.toString();
  } catch {
    return url;
  }
}

// Export for use in other modules
if (typeof globalThis !== 'undefined') {
  globalThis.normalizeUrl = normalizeUrl;
}
