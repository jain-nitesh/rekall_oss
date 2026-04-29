package com.rekallhq.rekall

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class ContentSyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "ContentSyncWorker"
        private const val SHARED_PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_PENDING_SHARES = "flutter.pending_shares"
        private const val KEY_UPLOADED_URLS = "flutter.uploaded_urls"  // Flutter adds prefix automatically
    }

    override suspend fun doWork(): Result {
        Log.d(TAG, "═══════════════════════════════════════════════════")
        Log.d(TAG, "Background Sync Worker Started")
        Log.d(TAG, "Worker ID: ${id}")
        Log.d(TAG, "═══════════════════════════════════════════════════")

        // 1. Check authentication
        val token = SecureTokenManager.getJwtToken(applicationContext)
        if (token == null) {
            Log.d(TAG, "No valid token - user not logged in. Keeping shares for app-open sync.")
            return Result.success() // Don't retry, wait for user login (Tier 3)
        }

        // 2. Read pending shares
        val prefs = applicationContext.getSharedPreferences(SHARED_PREFS_NAME, Context.MODE_PRIVATE)
        val pendingJson = prefs.getString(KEY_PENDING_SHARES, null)

        if (pendingJson.isNullOrEmpty()) {
            Log.d(TAG, "No pending shares to sync")
            return Result.success()
        }

        val sharesArray = try {
            JSONArray(pendingJson)
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing pending shares: ${e.message}")
            return Result.failure()
        }

        if (sharesArray.length() == 0) {
            Log.d(TAG, "Pending shares array is empty")
            return Result.success()
        }

        Log.d(TAG, "Found ${sharesArray.length()} pending share(s)")

        // 3. Load uploaded URLs to prevent duplicates
        val uploadedUrlsJson = prefs.getString(KEY_UPLOADED_URLS, null)
        val uploadedUrls = if (!uploadedUrlsJson.isNullOrEmpty()) {
            try {
                val array = JSONArray(uploadedUrlsJson)
                (0 until array.length()).map { array.getString(it) }.toMutableSet()
            } catch (e: Exception) {
                mutableSetOf()
            }
        } else {
            mutableSetOf()
        }

        // 4. Process each share
        val apiBaseUrl = SecureTokenManager.getApiBaseUrl(applicationContext)
        Log.d(TAG, "API Base URL: $apiBaseUrl")
        val client = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .build()

        val successfulShares = mutableListOf<Int>()
        val failedCount = mutableListOf<Int>()

        for (i in 0 until sharesArray.length()) {
            val shareObj = sharesArray.getJSONObject(i)
            val content = shareObj.getString("content")
            val packageName = shareObj.optString("package_name", null)
            val appName = shareObj.optString("app_name", null)

            // Extract URL from content
            val url = extractUrl(content)
            if (url == null) {
                Log.w(TAG, "Share $i: No URL found in content, skipping")
                successfulShares.add(i) // Remove from queue (invalid)
                continue
            }

            // Check if already uploaded
            if (uploadedUrls.contains(url)) {
                Log.d(TAG, "Share $i: URL already uploaded, skipping: $url")
                successfulShares.add(i)
                continue
            }

            // Upload to backend
            try {
                val uploaded = uploadToBackend(client, apiBaseUrl, token, url, content, packageName, appName)
                if (uploaded) {
                    Log.d(TAG, "Share $i: ✓ Successfully uploaded: $url")
                    successfulShares.add(i)
                    uploadedUrls.add(url)
                } else {
                    Log.w(TAG, "Share $i: ✗ Failed to upload: $url")
                    failedCount.add(i)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Share $i: Exception during upload: ${e.message}")
                failedCount.add(i)
            }
        }

        // 5. Update SharedPreferences
        // Remove successful shares, keep failed ones for retry
        if (successfulShares.isNotEmpty()) {
            val remainingShares = JSONArray()
            for (i in 0 until sharesArray.length()) {
                if (!successfulShares.contains(i)) {
                    remainingShares.put(sharesArray.getJSONObject(i))
                }
            }

            val editor = prefs.edit()
            if (remainingShares.length() > 0) {
                editor.putString(KEY_PENDING_SHARES, remainingShares.toString())
            } else {
                editor.remove(KEY_PENDING_SHARES)
            }

            // Save uploaded URLs
            val uploadedUrlsArray = JSONArray(uploadedUrls.toList())
            editor.putString(KEY_UPLOADED_URLS, uploadedUrlsArray.toString())

            editor.commit()
        }

        // 6. Return result
        Log.d(TAG, "Sync complete: ${successfulShares.size} success, ${failedCount.size} failed")
        Log.d(TAG, "═══════════════════════════════════════════════════")

        return when {
            failedCount.isEmpty() -> Result.success()
            successfulShares.isNotEmpty() -> Result.success() // Partial success
            runAttemptCount < 3 -> Result.retry() // Retry with backoff
            else -> Result.failure() // Give up, will sync via Tier 3
        }
    }

    private fun extractUrl(content: String): String? {
        // Extract URL from shared text
        val urlPattern = Regex("https?://[^\\s]+")
        val match = urlPattern.find(content)
        return match?.value
    }

    private fun uploadToBackend(
        client: OkHttpClient,
        baseUrl: String,
        token: String,
        url: String,
        sharedText: String,
        packageName: String?,
        appName: String?
    ): Boolean {
        val requestBody = JSONObject().apply {
            put("url", url)
            put("shared_text", sharedText)
            if (!packageName.isNullOrEmpty()) put("source_app_package", packageName)
            if (!appName.isNullOrEmpty()) put("source_app_name", appName)
        }

        val fullUrl = "$baseUrl/content/ingest"
        Log.d(TAG, "Uploading to: $fullUrl")

        val request = Request.Builder()
            .url(fullUrl)
            .addHeader("Authorization", "Bearer $token")
            .addHeader("Content-Type", "application/json")
            .post(requestBody.toString().toRequestBody("application/json".toMediaType()))
            .build()

        return try {
            val response = client.newCall(request).execute()
            val success = response.isSuccessful

            if (!success) {
                Log.w(TAG, "Upload failed: HTTP ${response.code}")
                Log.w(TAG, "Response: ${response.body?.string()}")
            }

            response.close()
            success
        } catch (e: Exception) {
            Log.e(TAG, "Network error during upload: ${e.message}")
            false
        }
    }
}
