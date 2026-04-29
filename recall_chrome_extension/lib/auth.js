/**
 * Google OAuth authentication via Chrome Identity API.
 *
 * Flow:
 * 1. chrome.identity.launchWebAuthFlow -> Google ID token
 * 2. Send ID token to POST /api/auth/google-auth -> JWT
 * 3. Store JWT in chrome.storage.local
 */

// Read client ID from manifest
function getClientId() {
  const manifest = chrome.runtime.getManifest();
  return manifest.oauth2?.client_id;
}

/**
 * Generate a random nonce for OAuth security.
 * @returns {string}
 */
function generateNonce() {
  const array = new Uint8Array(16);
  crypto.getRandomValues(array);
  return Array.from(array, b => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Launch Google OAuth flow and return an ID token.
 * @returns {Promise<string>} Google ID token
 */
async function getGoogleIdToken() {
  const clientId = getClientId();
  const redirectUri = chrome.identity.getRedirectURL();
  const nonce = generateNonce();

  const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  authUrl.searchParams.set('client_id', clientId);
  authUrl.searchParams.set('response_type', 'id_token');
  authUrl.searchParams.set('redirect_uri', redirectUri);
  authUrl.searchParams.set('scope', 'openid email profile');
  authUrl.searchParams.set('nonce', nonce);
  authUrl.searchParams.set('prompt', 'select_account');

  const responseUrl = await chrome.identity.launchWebAuthFlow({
    url: authUrl.toString(),
    interactive: true,
  });

  // Extract id_token from the redirect URL fragment
  const url = new URL(responseUrl);
  const fragment = new URLSearchParams(url.hash.slice(1));
  const idToken = fragment.get('id_token');

  if (!idToken) {
    throw new Error('No ID token received from Google');
  }

  return idToken;
}

/**
 * Authenticate with the ReCall backend using a Google ID token.
 * @param {string} idToken
 * @returns {Promise<{access_token: string, user: object}>}
 */
async function authenticateWithBackend(idToken) {
  const response = await apiRequest('/auth/google-auth', {
    method: 'POST',
    body: JSON.stringify({ id_token: idToken }),
    skipAuth: true,
  });

  return response;
}

/**
 * Full login flow: Google OAuth -> backend auth -> store token.
 * @returns {Promise<object>} User object
 */
async function login() {
  const idToken = await getGoogleIdToken();
  const authResponse = await authenticateWithBackend(idToken);

  await setAuthToken(authResponse.access_token);
  await setUser(authResponse.user);

  return authResponse.user;
}

/**
 * Log out: clear stored auth data.
 */
async function logout() {
  await clearAuth();
}

/**
 * Ensure we have a valid token. Re-authenticates if expired.
 * @returns {Promise<boolean>} true if authenticated
 */
async function ensureAuth() {
  if (await isTokenExpired()) {
    try {
      await login();
      return true;
    } catch {
      return false;
    }
  }
  return true;
}

// Export
if (typeof globalThis !== 'undefined') {
  globalThis.login = login;
  globalThis.logout = logout;
  globalThis.ensureAuth = ensureAuth;
}
