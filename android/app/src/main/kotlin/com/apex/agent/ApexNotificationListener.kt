package com.apex.agent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class ApexNotificationListener : NotificationListenerService() {

    data class NotificationRecord(
        val key: String,
        val packageName: String,
        val appName: String,
        val senderName: String,
        val messageText: String,
        val isGroup: Boolean,
        val timestamp: Long,
        val hasReplyAction: Boolean,
    )

    data class PendingApproval(
        val id: Int,
        val notificationKey: String,
        val packageName: String,
        val senderName: String,
        val replyText: String,
    )

    companion object {
        private const val AUTO_REPLY_CHANNEL_ID = "apex_auto_reply"
        private const val APPROVAL_GROUP = "apex_auto_reply_approval"
        private const val MAX_RECENT_NOTIFICATIONS = 50
        private const val MAX_HISTORY = 100
        private const val MAX_CONSECUTIVE_AUTO_REPLIES = 3
        private const val DUPLICATE_TTL_MS = 10 * 60 * 1000L

        @Volatile
        var instance: ApexNotificationListener? = null
            private set

        private val recentNotifications = CopyOnWriteArrayList<NotificationRecord>()
        private val recentKeys = ConcurrentHashMap<String, Long>()
        private val senderLastReplyAt = ConcurrentHashMap<String, Long>()
        private val senderConsecutiveReplies = ConcurrentHashMap<String, AtomicInteger>()
        private val pendingApprovals = ConcurrentHashMap<Int, PendingApproval>()
        private val executor = Executors.newSingleThreadExecutor()
        private val httpClient: OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .build()

        fun isEnabled(context: Context): Boolean {
            val cn = ComponentName(context, ApexNotificationListener::class.java)
            val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
                ?: return false
            return flat.split(':').any { it.equals(cn.flattenToString(), ignoreCase = true) }
        }

        fun openSettings(context: Context) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }

        fun getRecentNotificationsJson(limit: Int = 20): String {
            val arr = JSONArray()
            val max = limit.coerceIn(1, MAX_RECENT_NOTIFICATIONS)
            val snapshot = recentNotifications.takeLast(max).reversed()
            for (n in snapshot) {
                arr.put(JSONObject().apply {
                    put("key", n.key)
                    put("packageName", n.packageName)
                    put("appName", n.appName)
                    put("senderName", n.senderName)
                    put("messageText", n.messageText)
                    put("isGroup", n.isGroup)
                    put("timestamp", n.timestamp)
                    put("hasReplyAction", n.hasReplyAction)
                })
            }
            return arr.toString()
        }

        fun replyToNotification(context: Context, notificationKey: String, message: String): Boolean {
            val svc = instance ?: return false
            return svc.replyInternal(notificationKey, message)
        }

        fun approvePending(context: Context, approvalId: Int): Boolean {
            val pending = pendingApprovals.remove(approvalId) ?: return false
            val ok = replyToNotification(context, pending.notificationKey, pending.replyText)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(approvalId)
            if (ok) {
                appendHistory(
                    context,
                    mapOf(
                        "type" to "approved_sent",
                        "packageName" to pending.packageName,
                        "senderName" to pending.senderName,
                        "reply" to pending.replyText,
                        "timestamp" to System.currentTimeMillis().toString(),
                    )
                )
            }
            return ok
        }

        fun dismissPending(context: Context, approvalId: Int) {
            val pending = pendingApprovals.remove(approvalId)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(approvalId)
            if (pending != null) {
                appendHistory(
                    context,
                    mapOf(
                        "type" to "dismissed",
                        "packageName" to pending.packageName,
                        "senderName" to pending.senderName,
                        "reply" to pending.replyText,
                        "timestamp" to System.currentTimeMillis().toString(),
                    )
                )
            }
        }

        fun getHistoryJson(context: Context): String {
            return Prefs.getJsonArray(context, Prefs.AUTO_REPLY_HISTORY_JSON).toString()
        }

        fun clearHistory(context: Context) {
            Prefs.putJsonArray(context, Prefs.AUTO_REPLY_HISTORY_JSON, JSONArray())
        }

        private fun appendHistory(context: Context, entry: Map<String, String>) {
            synchronized(ApexNotificationListener::class.java) {
                val arr = Prefs.getJsonArray(context, Prefs.AUTO_REPLY_HISTORY_JSON)
                val obj = JSONObject()
                for ((k, v) in entry) obj.put(k, v)
                arr.put(obj)
                // Trim to MAX_HISTORY
                val trimmed = JSONArray()
                val start = (arr.length() - MAX_HISTORY).coerceAtLeast(0)
                for (i in start until arr.length()) {
                    trimmed.put(arr.opt(i))
                }
                Prefs.putJsonArray(context, Prefs.AUTO_REPLY_HISTORY_JSON, trimmed)
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        createAutoReplyChannel()
    }

    override fun onListenerDisconnected() {
        instance = null
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        sbn ?: return
        try {
            handlePosted(sbn)
        } catch (_: Throwable) {
            // Never crash the listener.
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
    }

    private fun handlePosted(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return
        val notification = sbn.notification ?: return
        val extras = notification.extras ?: Bundle()

        val appName = resolveAppName(sbn.packageName)
        val senderName = extractSenderName(extras, sbn)
        val messageText = extractMessageText(notification, extras)
        val isGroup = extractIsGroup(notification, extras)
        val hasReplyAction = findReplyAction(notification) != null

        if (messageText.isBlank()) return

        val record = NotificationRecord(
            key = sbn.key ?: "${sbn.packageName}:${sbn.id}",
            packageName = sbn.packageName,
            appName = appName,
            senderName = senderName,
            messageText = messageText,
            isGroup = isGroup,
            timestamp = sbn.postTime,
            hasReplyAction = hasReplyAction,
        )
        addRecent(record)

        val masterEnabled = Prefs.getBool(this, Prefs.MASTER_AUTO_REPLY_ENABLED, false)
        if (!masterEnabled) return

        if (!hasReplyAction) return

        // Anti-duplicate
        val dedupeKey = "${record.packageName}|${record.senderName}|${record.messageText}".lowercase()
        val now = System.currentTimeMillis()
        pruneDedupe(now)
        val lastSeen = recentKeys.putIfAbsent(dedupeKey, now)
        if (lastSeen != null) return
        recentKeys[dedupeKey] = now

        // Group chat handling
        val ignoreGroups = Prefs.getBool(this, Prefs.IGNORE_GROUP_CHATS, true)
        if (ignoreGroups && record.isGroup) return

        // App mode
        val appModes = Prefs.getJsonObject(this, Prefs.APP_MODES_JSON)
        val appMode = appModes.optString(record.packageName, "off")
        if (appMode == "off") return
        if (appMode == "alert_only") {
            appendHistory(
                this,
                mapOf(
                    "type" to "alert_only",
                    "packageName" to record.packageName,
                    "appName" to record.appName,
                    "senderName" to record.senderName,
                    "message" to record.messageText,
                    "timestamp" to now.toString(),
                )
            )
            return
        }
        if (appMode != "auto_reply") return

        // Contact allow/block/off
        if (!isContactAllowed(record.senderName, record.packageName)) {
            appendHistory(
                this,
                mapOf(
                    "type" to "blocked_contact",
                    "packageName" to record.packageName,
                    "appName" to record.appName,
                    "senderName" to record.senderName,
                    "message" to record.messageText,
                    "timestamp" to now.toString(),
                )
            )
            return
        }

        // Cooldown per sender
        val cooldownSec = Prefs.getInt(this, Prefs.COOLDOWN_SECONDS, 60).coerceAtLeast(0)
        val senderKey = senderKey(record.packageName, record.senderName)
        val lastReplyAt = senderLastReplyAt[senderKey] ?: 0L
        if (cooldownSec > 0 && now - lastReplyAt < cooldownSec * 1000L) {
            appendHistory(
                this,
                mapOf(
                    "type" to "cooldown",
                    "packageName" to record.packageName,
                    "appName" to record.appName,
                    "senderName" to record.senderName,
                    "message" to record.messageText,
                    "timestamp" to now.toString(),
                )
            )
            return
        }

        // Anti-loop: max consecutive auto-replies per sender without a human gap indicator.
        val consecutive = senderConsecutiveReplies.getOrPut(senderKey) { AtomicInteger(0) }
        val lastReply = senderLastReplyAt[senderKey] ?: 0L
        if (lastReply > 0L && now - lastReply > 30 * 60 * 1000L) {
            consecutive.set(0)
        }
        if (consecutive.get() >= MAX_CONSECUTIVE_AUTO_REPLIES) {
            appendHistory(
                this,
                mapOf(
                    "type" to "anti_loop",
                    "packageName" to record.packageName,
                    "appName" to record.appName,
                    "senderName" to record.senderName,
                    "message" to record.messageText,
                    "timestamp" to now.toString(),
                )
            )
            return
        }

        // Fetch auto-reply from worker
        executor.execute {
            try {
                generateAndHandleReply(record)
            } catch (_: Throwable) {
            }
        }
    }

    private fun addRecent(record: NotificationRecord) {
        recentNotifications.add(record)
        while (recentNotifications.size > MAX_RECENT_NOTIFICATIONS) {
            recentNotifications.removeAt(0)
        }
    }

    private fun pruneDedupe(now: Long) {
        val cutoff = now - DUPLICATE_TTL_MS
        val it = recentKeys.entries.iterator()
        while (it.hasNext()) {
            val e = it.next()
            if (e.value < cutoff) it.remove()
        }
    }

    private fun senderKey(packageName: String, senderName: String): String {
        return "${packageName.lowercase()}|${senderName.lowercase()}"
    }

    private fun isContactAllowed(senderName: String, packageName: String): Boolean {
        val senderLower = senderName.trim().lowercase()
        val senderKeyFull = "${packageName.lowercase()}|$senderLower"

        val contactModes = Prefs.getJsonObject(this, Prefs.CONTACT_MODES_JSON)
        val contactMode = when {
            contactModes.has(senderKeyFull) -> contactModes.optString(senderKeyFull, "")
            contactModes.has(senderLower) -> contactModes.optString(senderLower, "")
            else -> ""
        }
        if (contactMode.equals("off", ignoreCase = true) || contactMode.equals("block", ignoreCase = true)) {
            return false
        }
        if (contactMode.equals("allow", ignoreCase = true)) return true

        val allowlist = Prefs.getStringList(this, Prefs.ALLOWLIST_JSON).map { it.lowercase() }
        val blocklist = Prefs.getStringList(this, Prefs.BLOCKLIST_JSON).map { it.lowercase() }

        if (senderLower in blocklist || senderKeyFull in blocklist) return false
        if (allowlist.isNotEmpty()) {
            return senderLower in allowlist || senderKeyFull in allowlist
        }
        return true
    }

    private fun resolveAppName(packageName: String): String {
        return try {
            val pm = applicationContext.packageManager
            val ai = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(ai)?.toString() ?: packageName
        } catch (_: Throwable) {
            packageName
        }
    }

    private fun extractSenderName(extras: Bundle, sbn: StatusBarNotification): String {
        // MessagingStyle: prefer the latest message sender.
        try {
            val messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
            if (messages != null && messages.isNotEmpty()) {
                val last = messages.last()
                val bundle = last as? Bundle
                if (bundle != null) {
                    val sender = bundle.getCharSequence("sender")?.toString()
                    if (!sender.isNullOrBlank()) return sender
                }
            }
        } catch (_: Throwable) {
        }

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val convTitle = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()?.trim().orEmpty()
        if (title.isNotEmpty()) return title
        if (convTitle.isNotEmpty()) return convTitle
        return sbn.packageName
    }

    private fun extractMessageText(notification: Notification, extras: Bundle): String {
        // MessagingStyle latest message.
        try {
            val messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
            if (messages != null && messages.isNotEmpty()) {
                val last = messages.last() as? Bundle
                val text = last?.getCharSequence("text")?.toString()?.trim()
                if (!text.isNullOrEmpty()) return text
            }
        } catch (_: Throwable) {
        }

        // MessagingStyle via Notification.MessagingStyle API (best effort).
        try {
            val style = notification.extras.getCharSequence(Notification.EXTRA_TEMPLATE)?.toString()
            if (style?.contains("MessagingStyle") == true) {
                val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                if (!text.isNullOrBlank()) return text.trim()
            }
        } catch (_: Throwable) {
        }

        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        if (bigText.isNotEmpty()) return bigText
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        if (text.isNotEmpty()) return text
        val summary = extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()?.trim().orEmpty()
        return summary
    }

    private fun extractIsGroup(notification: Notification, extras: Bundle): Boolean {
        try {
            if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return true
        } catch (_: Throwable) {
        }
        try {
            if (extras.getBoolean(Notification.EXTRA_IS_GROUP_CONVERSATION, false)) return true
        } catch (_: Throwable) {
        }
        val convTitle = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()?.trim().orEmpty()
        if (convTitle.isNotEmpty()) return true
        return false
    }

    private fun findReplyAction(notification: Notification): Notification.Action? {
        val actions = notification.actions ?: return null
        for (action in actions) {
            val remoteInputs = action.remoteInputs ?: continue
            if (remoteInputs.isNotEmpty()) return action
        }
        return null
    }

    private fun replyInternal(notificationKey: String, message: String): Boolean {
        val sbn = try {
            activeNotifications?.firstOrNull { it.key == notificationKey }
        } catch (_: Throwable) {
            null
        } ?: return false

        val notification = sbn.notification ?: return false
        val action = findReplyAction(notification) ?: return false
        val remoteInputs = action.remoteInputs ?: return false
        if (remoteInputs.isEmpty()) return false

        return try {
            val intent = Intent()
            val bundle = Bundle()
            for (ri in remoteInputs) {
                bundle.putCharSequence(ri.resultKey, message)
            }
            RemoteInput.addResultsToIntent(remoteInputs, intent, bundle)
            action.actionIntent.send(this, 0, intent)
            val senderKey = senderKey(sbn.packageName, extractSenderName(notification.extras ?: Bundle(), sbn))
            senderLastReplyAt[senderKey] = System.currentTimeMillis()
            senderConsecutiveReplies.getOrPut(senderKey) { AtomicInteger(0) }.incrementAndGet()
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun generateAndHandleReply(record: NotificationRecord) {
        val workerUrl = Prefs.getString(this, Prefs.WORKER_URL, "").trim()
        val authToken = Prefs.getString(this, Prefs.AUTH_TOKEN, "").trim()
        val model = Prefs.getString(this, Prefs.MODEL_ID, "").trim()

        if (workerUrl.isEmpty() || authToken.isEmpty()) {
            appendHistory(
                this,
                mapOf(
                    "type" to "config_missing",
                    "packageName" to record.packageName,
                    "appName" to record.appName,
                    "senderName" to record.senderName,
                    "message" to record.messageText,
                    "timestamp" to System.currentTimeMillis().toString(),
                )
            )
            return
        }

        val globalRule = Prefs.getString(this, Prefs.GLOBAL_RULE, "").trim()
        val appRules = Prefs.getJsonObject(this, Prefs.APP_RULES_JSON)
        val contactRules = Prefs.getJsonObject(this, Prefs.CONTACT_RULES_JSON)
        val senderLower = record.senderName.trim().lowercase()
        val senderKeyFull = "${record.packageName.lowercase()}|$senderLower"
        val appRule = appRules.optString(record.packageName, "")
        val contactRule = when {
            contactRules.has(senderKeyFull) -> contactRules.optString(senderKeyFull, "")
            contactRules.has(senderLower) -> contactRules.optString(senderLower, "")
            else -> ""
        }
        val customRule = listOf(appRule, contactRule).filter { it.isNotBlank() }.joinToString("\n")

        val payload = JSONObject().apply {
            put("appName", record.appName)
            put("senderName", record.senderName)
            put("messageText", record.messageText)
            put("isGroup", record.isGroup)
            put("globalRule", globalRule)
            put("customRule", customRule)
            if (model.isNotEmpty()) put("model", model)
        }

        val endpoint = buildAutoReplyEndpoint(workerUrl)
        val req = Request.Builder()
            .url(endpoint)
            .addHeader("Authorization", "Bearer $authToken")
            .addHeader("Content-Type", "application/json")
            .post(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
            .build()

        httpClient.newCall(req).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                appendHistory(
                    this@ApexNotificationListener,
                    mapOf(
                        "type" to "worker_error",
                        "packageName" to record.packageName,
                        "appName" to record.appName,
                        "senderName" to record.senderName,
                        "message" to record.messageText,
                        "error" to (e.message ?: "network error"),
                        "timestamp" to System.currentTimeMillis().toString(),
                    )
                )
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    val body = it.body?.string().orEmpty()
                    if (!it.isSuccessful) {
                        appendHistory(
                            this@ApexNotificationListener,
                            mapOf(
                                "type" to "worker_error",
                                "packageName" to record.packageName,
                                "appName" to record.appName,
                                "senderName" to record.senderName,
                                "message" to record.messageText,
                                "error" to "HTTP ${it.code}",
                                "timestamp" to System.currentTimeMillis().toString(),
                            )
                        )
                        return
                    }
                    try {
                        val obj = JSONObject(body)
                        val skip = obj.optBoolean("skip", false)
                        val reply = obj.optString("reply", "").trim()
                        if (skip || reply.isEmpty()) {
                            appendHistory(
                                this@ApexNotificationListener,
                                mapOf(
                                    "type" to "skipped",
                                    "packageName" to record.packageName,
                                    "appName" to record.appName,
                                    "senderName" to record.senderName,
                                    "message" to record.messageText,
                                    "timestamp" to System.currentTimeMillis().toString(),
                                )
                            )
                            return
                        }

                        val requireConfirmation = Prefs.getBool(
                            this@ApexNotificationListener,
                            Prefs.REQUIRE_CONFIRMATION,
                            true
                        )
                        if (requireConfirmation) {
                            showApprovalNotification(record, reply)
                            appendHistory(
                                this@ApexNotificationListener,
                                mapOf(
                                    "type" to "pending_approval",
                                    "packageName" to record.packageName,
                                    "appName" to record.appName,
                                    "senderName" to record.senderName,
                                    "message" to record.messageText,
                                    "reply" to reply,
                                    "timestamp" to System.currentTimeMillis().toString(),
                                )
                            )
                        } else {
                            val sent = replyInternal(record.key, reply)
                            appendHistory(
                                this@ApexNotificationListener,
                                mapOf(
                                    "type" to if (sent) "sent" else "send_failed",
                                    "packageName" to record.packageName,
                                    "appName" to record.appName,
                                    "senderName" to record.senderName,
                                    "message" to record.messageText,
                                    "reply" to reply,
                                    "timestamp" to System.currentTimeMillis().toString(),
                                )
                            )
                        }
                    } catch (e: Throwable) {
                        appendHistory(
                            this@ApexNotificationListener,
                            mapOf(
                                "type" to "parse_error",
                                "packageName" to record.packageName,
                                "appName" to record.appName,
                                "senderName" to record.senderName,
                                "message" to record.messageText,
                                "error" to (e.message ?: "parse error"),
                                "timestamp" to System.currentTimeMillis().toString(),
                            )
                        )
                    }
                }
            }
        })
    }

    private fun buildAutoReplyEndpoint(workerUrl: String): String {
        val trimmed = workerUrl.trim().removeSuffix("/")
        return if (trimmed.endsWith("/auto-reply")) trimmed else "$trimmed/auto-reply"
    }

    private fun createAutoReplyChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                AUTO_REPLY_CHANNEL_ID,
                getString(R.string.auto_reply_channel_name),
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = getString(R.string.auto_reply_channel_description)
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun showApprovalNotification(record: NotificationRecord, reply: String) {
        createAutoReplyChannel()
        val approvalId = (System.currentTimeMillis() % Int.MAX_VALUE).toInt() + (record.key.hashCode() and 0x7fffffff)
        val pending = PendingApproval(
            id = approvalId,
            notificationKey = record.key,
            packageName = record.packageName,
            senderName = record.senderName,
            replyText = reply,
        )
        pendingApprovals[approvalId] = pending

        val approveIntent = Intent(this, ReplyApprovalReceiver::class.java).apply {
            action = ReplyApprovalReceiver.ACTION_APPROVE
            putExtra(ReplyApprovalReceiver.EXTRA_APPROVAL_ID, approvalId)
        }
        val dismissIntent = Intent(this, ReplyApprovalReceiver::class.java).apply {
            action = ReplyApprovalReceiver.ACTION_DISMISS
            putExtra(ReplyApprovalReceiver.EXTRA_APPROVAL_ID, approvalId)
        }

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

        val approvePi = PendingIntent.getBroadcast(this, approvalId, approveIntent, flags)
        val dismissPi = PendingIntent.getBroadcast(this, approvalId + 1, dismissIntent, flags)

        val content = "${record.appName} • ${record.senderName}\nIncoming: ${record.messageText}\nReply: $reply"
        val notification = NotificationCompat.Builder(this, AUTO_REPLY_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_apex)
            .setContentTitle("Auto-reply approval needed")
            .setContentText(reply)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setGroup(APPROVAL_GROUP)
            .addAction(0, "Approve & Send", approvePi)
            .addAction(0, "Dismiss", dismissPi)
            .build()

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(approvalId, notification)
    }
}
