package com.apex.agent

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val ACCESSIBILITY_CHANNEL = "com.apex.agent/accessibility"
        private const val BACKGROUND_CHANNEL = "com.apex.agent/background"
    }

    private val executor = Executors.newCachedThreadPool()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACCESSIBILITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                handleAccessibilityCall(call, result)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL)
            .setMethodCallHandler { call, result ->
                handleBackgroundCall(call, result)
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
                val status = mapOf(
                    "accessibilityEnabled" to ApexAccessibilityService.isEnabled(this),
                    "notificationListenerEnabled" to ApexNotificationListener.isEnabled(this),
                    "backgroundServiceRunning" to ApexBackgroundService.isServiceRunning(this),
                    "ignoringBatteryOptimizations" to isIgnoringBatteryOptimizations(),
                )
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
                            1001
                        )
                    }
                    result.success(granted)
                } else {
                    result.success(true)
                }
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
}
