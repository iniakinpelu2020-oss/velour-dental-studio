package com.apex.agent

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.AlarmClock
import android.telephony.SmsManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class ApexBackgroundService : Service() {

    companion object {
        private const val TAG = "ApexBackgroundService"
        const val CHANNEL_ID = "apex_background"
        const val NOTIFICATION_ID = 1001
        const val PREF_BACKGROUND_ENABLED = "background_service_enabled"

        @Volatile
        var isRunning: Boolean = false
            private set

        private val httpClient: OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .build()

        fun start(context: Context) {
            val intent = Intent(context, ApexBackgroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Prefs.putBool(context, PREF_BACKGROUND_ENABLED, true)
        }

        fun stop(context: Context) {
            val intent = Intent(context, ApexBackgroundService::class.java)
            context.stopService(intent)
            Prefs.putBool(context, PREF_BACKGROUND_ENABLED, false)
        }

        fun isServiceRunning(context: Context): Boolean {
            return isRunning
        }

        fun callWorker(
            context: Context,
            endpointPath: String,
            payload: JSONObject,
            callback: (success: Boolean, responseBody: String?, error: String?) -> Unit
        ) {
            val workerUrl = Prefs.getString(context, Prefs.WORKER_URL, "").trim()
            val authToken = Prefs.getString(context, Prefs.AUTH_TOKEN, "").trim()
            if (workerUrl.isEmpty() || authToken.isEmpty()) {
                callback(false, null, "Worker URL or auth token not configured")
                return
            }
            val base = workerUrl.trim().removeSuffix("/")
            val path = if (endpointPath.startsWith("/")) endpointPath else "/$endpointPath"
            val url = base + path

            val model = Prefs.getString(context, Prefs.MODEL_ID, "").trim()
            if (model.isNotEmpty() && !payload.has("model")) {
                payload.put("model", model)
            }

            val req = Request.Builder()
                .url(url)
                .addHeader("Authorization", "Bearer $authToken")
                .addHeader("Content-Type", "application/json")
                .post(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
                .build()

            httpClient.newCall(req).enqueue(object : okhttp3.Callback {
                override fun onFailure(call: okhttp3.Call, e: IOException) {
                    callback(false, null, e.message ?: "Network error")
                }

                override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
                    response.use {
                        val body = it.body?.string().orEmpty()
                        if (it.isSuccessful) {
                            callback(true, body, null)
                        } else {
                            callback(false, body, "HTTP ${it.code}")
                        }
                    }
                }
            })
        }

        fun callWorkerSync(
            context: Context,
            endpointPath: String,
            payload: JSONObject
        ): Pair<Boolean, String> {
            val workerUrl = Prefs.getString(context, Prefs.WORKER_URL, "").trim()
            val authToken = Prefs.getString(context, Prefs.AUTH_TOKEN, "").trim()
            if (workerUrl.isEmpty() || authToken.isEmpty()) {
                return false to "Worker URL or auth token not configured"
            }
            val base = workerUrl.trim().removeSuffix("/")
            val path = if (endpointPath.startsWith("/")) endpointPath else "/$endpointPath"
            val url = base + path

            val model = Prefs.getString(context, Prefs.MODEL_ID, "").trim()
            if (model.isNotEmpty() && !payload.has("model")) {
                payload.put("model", model)
            }

            val req = Request.Builder()
                .url(url)
                .addHeader("Authorization", "Bearer $authToken")
                .addHeader("Content-Type", "application/json")
                .post(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
                .build()

            return try {
                httpClient.newCall(req).execute().use { resp ->
                    val body = resp.body?.string().orEmpty()
                    if (resp.isSuccessful) true to body else false to "HTTP ${resp.code}: $body"
                }
            } catch (e: Throwable) {
                false to (e.message ?: "Network error")
            }
        }

        fun setAlarm(context: Context, hour: Int, minute: Int, message: String?): Boolean {
            return try {
                val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                    putExtra(AlarmClock.EXTRA_HOUR, hour.coerceIn(0, 23))
                    putExtra(AlarmClock.EXTRA_MINUTES, minute.coerceIn(0, 59))
                    putExtra(AlarmClock.EXTRA_MESSAGE, message ?: "Apex Agent Alarm")
                    putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                true
            } catch (e: Throwable) {
                Log.w(TAG, "Failed to set alarm", e)
                false
            }
        }

        fun saveNote(context: Context, title: String, content: String): Boolean {
            return try {
                synchronized(ApexBackgroundService::class.java) {
                    val arr = Prefs.getJsonArray(context, Prefs.NOTES_JSON)
                    val note = JSONObject().apply {
                        put("id", System.currentTimeMillis().toString())
                        put("title", title)
                        put("content", content)
                        put("createdAt", System.currentTimeMillis())
                    }
                    arr.put(note)
                    // Keep last 200 notes
                    val trimmed = JSONArray()
                    val start = (arr.length() - 200).coerceAtLeast(0)
                    for (i in start until arr.length()) trimmed.put(arr.opt(i))
                    Prefs.putJsonArray(context, Prefs.NOTES_JSON, trimmed)
                }
                true
            } catch (e: Throwable) {
                Log.w(TAG, "Failed to save note", e)
                false
            }
        }

        fun getNotes(context: Context): String {
            return Prefs.getJsonArray(context, Prefs.NOTES_JSON).toString()
        }

        fun makeCall(context: Context, phoneNumber: String): Boolean {
            val normalized = normalizePhoneNumber(phoneNumber)
            if (normalized.isEmpty()) return false
            val hasCallPermission = ContextCompat.checkSelfPermission(
                context, Manifest.permission.CALL_PHONE
            ) == PackageManager.PERMISSION_GRANTED

            return try {
                if (hasCallPermission) {
                    val intent = Intent(Intent.ACTION_CALL).apply {
                        data = Uri.parse("tel:$normalized")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    true
                } else {
                    val intent = Intent(Intent.ACTION_DIAL).apply {
                        data = Uri.parse("tel:$normalized")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    true
                }
            } catch (e: Throwable) {
                Log.w(TAG, "Failed to make call, trying dial fallback", e)
                try {
                    val fallback = Intent(Intent.ACTION_DIAL).apply {
                        data = Uri.parse("tel:$normalized")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(fallback)
                    true
                } catch (e2: Throwable) {
                    Log.w(TAG, "Failed to make call", e2)
                    false
                }
            }
        }

        fun sendSms(context: Context, phoneNumber: String, message: String): Boolean {
            val normalized = normalizePhoneNumber(phoneNumber)
            val body = message.trim()
            if (normalized.isEmpty() || body.isEmpty()) return false

            val hasSmsPermission = ContextCompat.checkSelfPermission(
                context, Manifest.permission.SEND_SMS
            ) == PackageManager.PERMISSION_GRANTED

            if (hasSmsPermission) {
                try {
                    val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        context.getSystemService(SmsManager::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getDefault()
                    }
                    val parts = smsManager.divideMessage(body)
                    if (parts.size > 1) {
                        smsManager.sendMultipartTextMessage(normalized, null, parts, null, null)
                    } else {
                        smsManager.sendTextMessage(normalized, null, body, null, null)
                    }
                    return true
                } catch (e: Throwable) {
                    Log.w(TAG, "SmsManager send failed, falling back to composer", e)
                }
            }

            return try {
                val intent = Intent(Intent.ACTION_SENDTO).apply {
                    data = Uri.parse("smsto:$normalized")
                    putExtra("sms_body", body)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                true
            } catch (e: Throwable) {
                Log.w(TAG, "Failed to send SMS", e)
                false
            }
        }

        fun openWhatsAppChat(context: Context, phoneNumber: String, message: String): Boolean {
            val digits = normalizePhoneDigits(phoneNumber)
            if (digits.isEmpty()) return false
            val encodedMessage = try {
                URLEncoder.encode(message.trim(), "UTF-8")
            } catch (_: Throwable) {
                message.trim().replace(" ", "%20")
            }
            val url = if (encodedMessage.isNotEmpty()) {
                "https://wa.me/$digits?text=$encodedMessage"
            } else {
                "https://wa.me/$digits"
            }

            return try {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    data = Uri.parse(url)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    setPackage("com.whatsapp")
                }
                context.startActivity(intent)
                true
            } catch (_: Throwable) {
                try {
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        data = Uri.parse(url)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        setPackage("com.whatsapp.w4b")
                    }
                    context.startActivity(intent)
                    true
                } catch (_: Throwable) {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            data = Uri.parse(url)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        true
                    } catch (e: Throwable) {
                        Log.w(TAG, "Failed to open WhatsApp chat", e)
                        false
                    }
                }
            }
        }

        fun normalizePhoneNumber(phoneNumber: String): String {
            val trimmed = phoneNumber.trim()
            if (trimmed.isEmpty()) return ""
            val hasPlus = trimmed.startsWith("+")
            val digits = trimmed.filter { it.isDigit() }
            if (digits.isEmpty()) return ""
            return if (hasPlus) "+$digits" else digits
        }

        fun normalizePhoneDigits(phoneNumber: String): String {
            val normalized = normalizePhoneNumber(phoneNumber)
            return normalized.removePrefix("+")
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        isRunning = true
        Prefs.putBool(this, PREF_BACKGROUND_ENABLED, true)
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.background_service_channel_name),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = getString(R.string.background_service_channel_description)
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, piFlags)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_apex)
            .setContentTitle(getString(R.string.background_service_notification_title))
            .setContentText(getString(R.string.background_service_notification_text))
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
}
