package com.rekallhq.rekall

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONObject
import java.util.Base64

object SecureTokenManager {
    private const val SHARED_PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_API_BASE_URL = "flutter.api_base_url"
    private const val FLUTTER_SECURE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"
    private const val KEY_AUTH_TOKEN = "${FLUTTER_SECURE_PREFIX}_auth_token"

    fun getJwtToken(context: Context): String? {
        return try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            val prefs = EncryptedSharedPreferences.create(
                context,
                "FlutterSecureStorage",
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            val token = prefs.getString(KEY_AUTH_TOKEN, null) ?: return null
            if (isTokenValid(token)) token else null
        } catch (e: Exception) {
            null
        }
    }

    fun isTokenValid(token: String): Boolean {
        return try {
            val parts = token.split(".")
            if (parts.size != 3) return false
            val payload = String(Base64.getUrlDecoder().decode(parts[1]))
            val json = JSONObject(payload)
            if (json.has("exp")) {
                val expiry = json.getLong("exp")
                val now = System.currentTimeMillis() / 1000
                if (now >= expiry) return false
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    fun getApiBaseUrl(context: Context): String {
        val prefs = context.getSharedPreferences(SHARED_PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_API_BASE_URL, "https://YOUR_BACKEND")
            ?: "https://YOUR_BACKEND"
    }
}
