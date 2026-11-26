package com.apex.agent

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {

    companion object {
        private const val ACCESSIBILITY_CHANNEL = "com.apex.agent/accessibility"
        private const val BACKGROUND_CHANNEL = "com.apex.agent/background"
        private const val REQ_POST_NOTIFICATIONS = 1001
        private const val REQ_PHONE_SMS = 1002
    }

    private val executor = Executors.newCachedThreadPool()
    private var tts: TextToSpeech? = null
    private var ttsReady: Boolean = false
    private var pendingSpeakText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (tts == null) {
            tts = TextToSpeech(applicationContext, this)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACCESSIBILITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                handleAccessibilityCall(call, result)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL)
            .setMethodCallHandler { call, result ->
                handleBackgroundCall(call, result)
            }
    }

    override fun onDestroy() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Throwable) {
        }
        tts = null
        ttsReady = false
        super.onDestroy()
    }

    override fun onInit(status: Int) {
        ttsReady = status == TextToSpeech.SUCCESS
        if (ttsReady) {
            try {
                tts?.language = Locale.US
            } catch (_: Throwable) {
            }
            val pending = pendingSpeakText
            if (!pending.isNullOrBlank()) {
                pendingSpeakText = null
                speakInternal(pending)
            }
        }
    }

    private fun handleAccessibilityCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isEnabled" -> {
                result.success(ApexAccessibilityService.isEnabled(this))
            }
            "openSettings" -> {
                try {
                    ApexAccessibilityService.openSettings(this)
                    result.success(true)
                } catch (e: Throwable) {
                    result.error("OPEN_SETTINGS_FAILED", e.message, null)
                }
            }
            "getScreenStateJson" -> {
                executor.execute {
                    try {
                        val json = ApexAccessibilityService.getScreenStateJson()
                        runOnUiThread { result.success(json) }
                    } catch (e: Throwable) {
                        runOnUiThread { result.error("SCREEN_STATE_FAILED", e.message, null) }
                    }
                }
            }
            "openApp" -> {
                val packageOrName = call.argument<String>("packageOrName")
                    ?: call.argument<String>("package")
                    ?: call.argument<String>("name")
                    ?: ""
                executor.execute {
                    val ok = ApexAccessibilityService.openApp(this, packageOrName)
                    runOnUiThread { result.success(ok) }
                }
            }
            "clickText" -> {
                val target = call.argument<String>("target") ?: ""
                executor.execute {
                    val ok = ApexAccessibilityService.clickText(target)
                    runOnUiThread { result.success(ok) }
                }
            }
            "typeText" -> {
                val targetOrFocused = call.argument<String>("targetOrFocused")
                    ?: call.argument<String>("target")
                val text = call.argument<String>("text") ?: ""
                executor.execute {
                    val ok = ApexAccessibilityService.typeText(targetOrFocused, text)
                    runOnUiThread { result.success(ok) }
                }
            }
            "scrollScreen" -> {
                val direction = call.argument<String>("direction") ?: "down"
                executor.execute {
                    val ok = ApexAccessibilityService.scrollScreen(direction)
                    runOnUiThread { result.success(ok) }
                }
            }
            "pressGlobal" -> {
                val action = call.argument<String>("action") ?: ""
                executor.execute {
                    val ok = ApexAccessibilityService.pressGlobal(action)
                    runOnUiThread { result.success(ok) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun handleBackgroundCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isNotificationListenerEnabled" -> {
                result.success(ApexNotificationListener.isEnabled(this))
            }
            "openNotificationListenerSettings" -> {
                try {
                    ApexNotificationListener.openSettings(this)
                    result.success(true)
                } catch (e: Throwable) {
                    result.error("OPEN_SETTINGS_FAILED", e.message, null)
                }
            }
            "isBackgroundServiceRunning" -> {
                result.success(ApexBackgroundService.isServiceRunning(this))
            }
            "startBackgroundService" -> {
                try {
                    ApexBackgroundService.start(this)
                    result.success(true)
                } catch (e: Throwable) {
                    result.error("START_SERVICE_FAILED", e.message, null)
                }
            }
            "stopBackgroundService" -> {
                try {
                    ApexBackgroundService.stop(this)
                    result.success(true)
                } catch (e: Throwable) {
                    result.error("STOP_SERVICE_FAILED", e.message, null)
                }
            }
            "isIgnoringBatteryOptimizations" -> {
                result.success(isIgnoringBatteryOptimizations())
            }
            "requestIgnoreBatteryOptimizations" -> {
                try {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                } catch (e: Throwable) {
                    result.error("BATTERY_OPT_FAILED", e.message, null)
                }
            }
            "getInstalledApps" -> {
                executor.execute {
                    try {
                        val apps = getInstalledApps()
                        runOnUiThread { result.success(apps) }
                    } catch (e: Throwable) {
                        runOnUiThread { result.error("GET_APPS_FAILED", e.message, null) }
                    }
                }
            }
            "getRecentNotifications" -> {
                val limit = call.argument<Int>("limit") ?: 20
                val json = ApexNotificationListener.getRecentNotificationsJson(limit)
                result.success(json)
            }
            "replyToNotification" -> {
                val notificationKey = call.argument<String>("notificationKey") ?: ""
                val message = call.argument<String>("message") ?: ""
                executor.execute {
                    val ok = ApexNotificationListener.replyToNotification(this, notificationKey, message)
                    runOnUiThread { result.success(ok) }
                }
            }
            "setAlarm" -> {
                val hour = call.argument<Int>("hour") ?: 0
                val minute = call.argument<Int>("minute") ?: 0
                val message = call.argument<String>("message")
                val ok = ApexBackgroundService.setAlarm(this, hour, minute, message)
                result.success(ok)
            }
            "saveNote" -> {
                val title = call.argument<String>("title") ?: ""
                val content = call.argument<String>("content") ?: ""
                val ok = ApexBackgroundService.saveNote(this, title, content)
                result.success(ok)
            }
            "getNotes" -> {
                result.success(ApexBackgroundService.getNotes(this))
            }
            "getAutoReplyHistory" -> {
                result.success(ApexNotificationListener.getHistoryJson(this))
            }
            "clearAutoReplyHistory" -> {
                ApexNotificationListener.clearHistory(this)
                result.success(true)
            }
            "getDeviceStatus" -> {
                val status = HashMap<String, Any>()
                status["accessibilityEnabled"] = ApexAccessibilityService.isEnabled(this)
                status["notificationListenerEnabled"] = ApexNotificationListener.isEnabled(this)
                status["backgroundServiceRunning"] = ApexBackgroundService.isServiceRunning(this)
                status["ignoringBatteryOptimizations"] = isIgnoringBatteryOptimizations()
                status["phoneSmsPermissionsGranted"] = arePhoneSmsPermissionsGranted()
                result.success(status)
            }
            "requestPostNotifications" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.POST_NOTIFICATIONS
                    ) == PackageManager.PERMISSION_GRANTED
                    if (!granted) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQ_POST_NOTIFICATIONS
                        )
                    }
                    result.success(granted)
                } else {
                    result.success(true)
                }
            }
            "getPhoneSmsPermissionStatus" -> {
                result.success(getPhoneSmsPermissionStatus())
            }
            "requestPhoneSmsPermissions" -> {
                requestPhoneSmsPermissions()
                result.success(getPhoneSmsPermissionStatus())
            }
            "makeCall" -> {
                val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                executor.execute {
                    val ok = ApexBackgroundService.makeCall(this, phoneNumber)
                    runOnUiThread { result.success(ok) }
                }
            }
            "sendSms" -> {
                val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                val message = call.argument<String>("message") ?: ""
                executor.execute {
                    val ok = ApexBackgroundService.sendSms(this, phoneNumber, message)
                    runOnUiThread { result.success(ok) }
                }
            }
            "openWhatsAppChat" -> {
                val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                val message = call.argument<String>("message") ?: ""
                executor.execute {
                    val ok = ApexBackgroundService.openWhatsAppChat(this, phoneNumber, message)
                    runOnUiThread { result.success(ok) }
                }
            }
            "speakText" -> {
                val text = call.argument<String>("text") ?: ""
                val ok = speakText(text)
                result.success(ok)
            }
            "stopSpeaking" -> {
                try {
                    tts?.stop()
                    result.success(true)
                } catch (_: Throwable) {
                    result.success(false)
                }
            }
            "isMicrophonePermissionGranted" -> {
                val granted = ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED
                result.success(granted)
            }
            "requestMicrophonePermission" -> {
                val granted = ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED
                if (!granted) {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.RECORD_AUDIO),
                        REQ_PHONE_SMS + 1
                    )
                }
                result.success(granted)
            }
            "listenForSpeech" -> {
                listenForSpeech(result)
            }
            else -> result.notImplemented()
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } catch (_: Throwable) {
            false
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (isIgnoringBatteryOptimizations()) return
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolved = pm.queryIntentActivities(intent, 0)
        val apps = resolved.mapNotNull { ri ->
            val pkg = ri.activityInfo?.packageName ?: return@mapNotNull null
            val label = ri.loadLabel(pm)?.toString()?.trim().orEmpty()
            if (label.isEmpty()) return@mapNotNull null
            mapOf(
                "packageName" to pkg,
                "appName" to label,
            )
        }.distinctBy { it["packageName"] }
            .sortedBy { it["appName"]?.lowercase() ?: "" }
        return apps
    }

    private fun requiredPhoneSmsPermissions(): Array<String> {
        return arrayOf(
            Manifest.permission.CALL_PHONE,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.SEND_SMS,
            Manifest.permission.READ_CONTACTS,
        )
    }

    private fun arePhoneSmsPermissionsGranted(): Boolean {
        return requiredPhoneSmsPermissions().all { perm ->
            ContextCompat.checkSelfPermission(this, perm) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun getPhoneSmsPermissionStatus(): Map<String, Boolean> {
        val status = HashMap<String, Boolean>()
        for (perm in requiredPhoneSmsPermissions()) {
            val short = perm.substringAfterLast('.')
            status[short] = ContextCompat.checkSelfPermission(this, perm) == PackageManager.PERMISSION_GRANTED
        }
        status["allGranted"] = status.values.all { it }
        return status
    }

    private fun requestPhoneSmsPermissions() {
        val missing = requiredPhoneSmsPermissions().filter { perm ->
            ContextCompat.checkSelfPermission(this, perm) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQ_PHONE_SMS)
        }
    }

    private fun speakText(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return false
        if (!ttsReady) {
            pendingSpeakText = trimmed
            if (tts == null) {
                tts = TextToSpeech(applicationContext, this)
            }
            return true
        }
        return speakInternal(trimmed)
    }

    private fun speakInternal(text: String): Boolean {
        return try {
            val engine = tts ?: return false
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "apex_tts_${System.currentTimeMillis()}")
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun listenForSpeech(result: MethodChannel.Result) {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            result.error("MIC_PERMISSION", "RECORD_AUDIO permission not granted", null)
            return
        }

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error("SPEECH_UNAVAILABLE", "Speech recognition not available on this device", null)
            return
        }

        runOnUiThread {
            try {
                val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                    putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak your command")
                }

                var delivered = false
                recognizer.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {}
                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {}
                    override fun onPartialResults(partialResults: Bundle?) {}
                    override fun onEvent(eventType: Int, params: Bundle?) {}

                    override fun onError(error: Int) {
                        if (delivered) return
                        delivered = true
                        try { recognizer.destroy() } catch (_: Throwable) {}
                        result.error("SPEECH_ERROR", "Speech recognition error: $error", null)
                    }

                    override fun onResults(results: Bundle?) {
                        if (delivered) return
                        delivered = true
                        try { recognizer.destroy() } catch (_: Throwable) {}
                        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull()?.trim().orEmpty()
                        result.success(text)
                    }
                })

                recognizer.startListening(intent)
            } catch (e: Throwable) {
                result.error("SPEECH_ERROR", e.message, null)
            }
        }
    }
}
