package com.rekallhq.rekall

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.BackoffPolicy
import androidx.work.WorkRequest
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Process share intent in background
        handleShareIntent(intent)

        // Finish immediately - no UI shown
        finish()
    }

    private fun handleShareIntent(intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_SEND -> {
                if (intent.type == "text/plain") {
                    val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                    if (sharedText != null) {
                        val packageName = intent.`package` ?: intent.getStringExtra(Intent.EXTRA_PACKAGE_NAME)
                        val appName = packageName?.let { resolveAppName(it) }

                        // Save shared content to SharedPreferences for later processing
                        saveSharedContent(sharedText, packageName, appName)

                        // Show quick toast notification
                        Toast.makeText(
                            this,
                            "✓ Saved to ReKall!",
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                // Handle multiple items if needed
                Toast.makeText(
                    this,
                    "✓ Saved to ReKall!",
                    Toast.LENGTH_SHORT
                ).show()
            }
        }
    }

    private fun resolveAppName(pkg: String): String? {
        return try {
            val applicationInfo = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(applicationInfo).toString()
        } catch (e: Exception) {
            null
        }
    }

    private fun saveSharedContent(content: String, packageName: String?, appName: String?) {
        android.util.Log.d("ShareActivity", "═══════════════════════════════════════════════════")
        android.util.Log.d("ShareActivity", "SAVING SHARED CONTENT TO SHAREDPREFERENCES")
        android.util.Log.d("ShareActivity", "═══════════════════════════════════════════════════")

        // Save to SharedPreferences for processing when app opens
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        android.util.Log.d("ShareActivity", "✓ Obtained SharedPreferences: FlutterSharedPreferences")

        try {
            // Get existing pending shares as JSON array
            val existingJsonStr = prefs.getString("flutter.pending_shares", null)
            val sharesArray = if (existingJsonStr != null && existingJsonStr.isNotEmpty()) {
                try {
                    JSONArray(existingJsonStr)
                } catch (e: Exception) {
                    android.util.Log.w("ShareActivity", "⚠️ Existing data not valid JSON, migrating from old format")
                    // Migrate old format to new format
                    migrateOldFormat(existingJsonStr)
                }
            } else {
                JSONArray()
            }

            android.util.Log.d("ShareActivity", "Existing shares: ${sharesArray.length()} item(s)")

            // Create new share object
            val timestamp = System.currentTimeMillis()
            val shareObject = JSONObject().apply {
                put("timestamp", timestamp)
                put("content", content) // Store raw content as-is, no cleaning needed!
                if (!packageName.isNullOrEmpty()) put("package_name", packageName)
                if (!appName.isNullOrEmpty()) put("app_name", appName)
            }

            // Add to array
            sharesArray.put(shareObject)

            // Save back to SharedPreferences
            val updatedJsonStr = sharesArray.toString()
            android.util.Log.d("ShareActivity", "New share added:")
            android.util.Log.d("ShareActivity", "  Timestamp: $timestamp")
            android.util.Log.d("ShareActivity", "  Content preview: ${if (content.length > 100) content.substring(0, 100) + "..." else content}")
            android.util.Log.d("ShareActivity", "Total shares now: ${sharesArray.length()}")

            // Save back (using Flutter's SharedPreferences format)
            val editor = prefs.edit()
            editor.putString("flutter.pending_shares", updatedJsonStr)

            // CRITICAL: Use commit() instead of apply() to ensure synchronous write
            // apply() is async and data might not be written before Flutter reads it
            val success = editor.commit()

            android.util.Log.d("ShareActivity", "SharedPreferences.commit() result: $success")

            // Verify the data was actually written
            val verifyRead = prefs.getString("flutter.pending_shares", null)
            if (verifyRead == updatedJsonStr) {
                android.util.Log.d("ShareActivity", "✓ VERIFIED: Data successfully written to SharedPreferences")
                android.util.Log.d("ShareActivity", "Key: flutter.pending_shares")
                android.util.Log.d("ShareActivity", "Value length: ${verifyRead?.length ?: 0} chars")
            } else {
                android.util.Log.e("ShareActivity", "❌ ERROR: Data verification failed!")
                android.util.Log.e("ShareActivity", "Expected length: ${updatedJsonStr.length}")
                android.util.Log.e("ShareActivity", "Got length: ${verifyRead?.length ?: 0}")
            }
        } catch (e: Exception) {
            android.util.Log.e("ShareActivity", "❌ ERROR saving share: ${e.message}")
            e.printStackTrace()
        }

        android.util.Log.d("ShareActivity", "═══════════════════════════════════════════════════")

        // NEW: Schedule immediate background sync
        scheduleBackgroundSync()
    }

    /**
     * Migrate old pipe-separated format to JSON format.
     *
     * Old format: "timestamp1|content1\ntimestamp2|content2"
     * New format: [{"timestamp": 123, "content": "..."}]
     */
    private fun migrateOldFormat(oldData: String): JSONArray {
        android.util.Log.d("ShareActivity", "Migrating old format to JSON...")
        val array = JSONArray()

        try {
            val lines = oldData.split("\n").filter { it.isNotEmpty() }
            for (line in lines) {
                val parts = line.split("|", limit = 2)
                if (parts.size >= 2) {
                    val timestamp = parts[0].toLongOrNull() ?: System.currentTimeMillis()
                    val content = parts[1]
                    array.put(JSONObject().apply {
                        put("timestamp", timestamp)
                        put("content", content)
                    })
                } else if (line.startsWith("http://") || line.startsWith("https://")) {
                    // Orphaned URL without timestamp
                    array.put(JSONObject().apply {
                        put("timestamp", System.currentTimeMillis())
                        put("content", line)
                    })
                }
            }
            android.util.Log.d("ShareActivity", "✓ Migrated ${array.length()} items from old format")
        } catch (e: Exception) {
            android.util.Log.e("ShareActivity", "Error migrating old format: ${e.message}")
        }

        return array
    }

    private fun scheduleBackgroundSync() {
        android.util.Log.d("ShareActivity", "Scheduling background sync...")

        try {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(true)  // Don't drain battery
                .build()

            val syncRequest = OneTimeWorkRequestBuilder<ContentSyncWorker>()
                .setConstraints(constraints)
                .setInitialDelay(2, TimeUnit.SECONDS)  // Brief delay for UX
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    WorkRequest.MIN_BACKOFF_MILLIS,  // 10 seconds
                    TimeUnit.MILLISECONDS
                )
                .build()

            WorkManager.getInstance(applicationContext).enqueue(syncRequest)
            android.util.Log.d("ShareActivity", "✓ Background sync scheduled: ${syncRequest.id}")
        } catch (e: Exception) {
            android.util.Log.e("ShareActivity", "Failed to schedule background sync: ${e.message}")
        }
    }
}
