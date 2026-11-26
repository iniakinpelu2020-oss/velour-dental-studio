package com.apex.agent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "ApexBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (
            action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.QUICKBOOT_POWERON"
        ) {
            val enabled = Prefs.getBool(context, ApexBackgroundService.PREF_BACKGROUND_ENABLED, false)
            if (enabled) {
                try {
                    ApexBackgroundService.start(context.applicationContext)
                } catch (e: Throwable) {
                    Log.w(TAG, "Failed to start background service on boot", e)
                }
            }
        }
    }
}
