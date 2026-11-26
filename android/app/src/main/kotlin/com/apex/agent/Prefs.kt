package com.apex.agent

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

object Prefs {
    private const val FILE_NAME = "FlutterSharedPreferences"
    private const val PREFIX = "flutter."

    private fun sp(context: Context): SharedPreferences =
        context.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)

    private fun key(name: String): String = PREFIX + name

    fun getString(context: Context, name: String, default: String = ""): String {
        val prefs = sp(context)
        val k = key(name)
        return when {
            prefs.contains(k) -> {
                try {
                    prefs.getString(k, default) ?: default
                } catch (_: Throwable) {
                    // Flutter may store some values in unexpected types; be defensive.
                    try { prefs.all[k]?.toString() ?: default } catch (_: Throwable) { default }
                }
            }
            else -> default
        }
    }

    fun putString(context: Context, name: String, value: String) {
        sp(context).edit().putString(key(name), value).apply()
    }

    fun getBool(context: Context, name: String, default: Boolean = false): Boolean {
        val prefs = sp(context)
        val k = key(name)
        if (!prefs.contains(k)) return default
        return try {
            prefs.getBoolean(k, default)
        } catch (_: Throwable) {
            val raw = prefs.all[k]
            when (raw) {
                is Boolean -> raw
                is String -> raw.equals("true", ignoreCase = true)
                is Long -> raw != 0L
                is Int -> raw != 0
                else -> default
            }
        }
    }

    fun putBool(context: Context, name: String, value: Boolean) {
        sp(context).edit().putBoolean(key(name), value).apply()
    }

    fun getInt(context: Context, name: String, default: Int = 0): Int {
        val prefs = sp(context)
        val k = key(name)
        if (!prefs.contains(k)) return default
        return try {
            // Flutter shared_preferences stores ints as Long on Android.
            prefs.getLong(k, default.toLong()).toInt()
        } catch (_: Throwable) {
            try {
                prefs.getInt(k, default)
            } catch (_: Throwable) {
                val raw = prefs.all[k]
                when (raw) {
                    is Long -> raw.toInt()
                    is Int -> raw
                    is String -> raw.toIntOrNull() ?: default
                    else -> default
                }
            }
        }
    }

    fun putInt(context: Context, name: String, value: Int) {
        sp(context).edit().putLong(key(name), value.toLong()).apply()
    }

    fun getStringList(context: Context, name: String): List<String> {
        // Prefer JSON string storage for cross-platform/native consistency.
        val json = getString(context, name, "")
        if (json.isNotBlank()) {
            try {
                val arr = JSONArray(json)
                val out = mutableListOf<String>()
                for (i in 0 until arr.length()) {
                    out.add(arr.optString(i, ""))
                }
                return out.filter { it.isNotEmpty() }
            } catch (_: Throwable) {
                // fall through
            }
        }
        // Fallback: try native StringSet (legacy/shared_preferences behavior).
        val prefs = sp(context)
        val k = key(name)
        return try {
            @Suppress("UNCHECKED_CAST")
            val set = prefs.getStringSet(k, emptySet()) ?: emptySet()
            set.toList()
        } catch (_: Throwable) {
            emptyList()
        }
    }

    fun putStringList(context: Context, name: String, values: List<String>) {
        val arr = JSONArray()
        values.forEach { arr.put(it) }
        putString(context, name, arr.toString())
    }

    fun getJsonObject(context: Context, name: String): JSONObject {
        val raw = getString(context, name, "")
        if (raw.isBlank()) return JSONObject()
        return try { JSONObject(raw) } catch (_: Throwable) { JSONObject() }
    }

    fun putJsonObject(context: Context, name: String, obj: JSONObject) {
        putString(context, name, obj.toString())
    }

    fun getJsonArray(context: Context, name: String): JSONArray {
        val raw = getString(context, name, "")
        if (raw.isBlank()) return JSONArray()
        return try { JSONArray(raw) } catch (_: Throwable) { JSONArray() }
    }

    fun putJsonArray(context: Context, name: String, arr: JSONArray) {
        putString(context, name, arr.toString())
    }

    // Well-known keys
    const val WORKER_URL = "worker_url"
    const val AUTH_TOKEN = "auth_token"
    const val MODEL_ID = "model_id"

    const val MASTER_AUTO_REPLY_ENABLED = "master_auto_reply_enabled"
    const val REQUIRE_CONFIRMATION = "require_confirmation"
    const val IGNORE_GROUP_CHATS = "ignore_group_chats"
    const val COOLDOWN_SECONDS = "cooldown_seconds"
    const val GLOBAL_RULE = "global_rule"

    const val APP_MODES_JSON = "app_modes_json"
    const val APP_RULES_JSON = "app_rules_json"
    const val CONTACT_RULES_JSON = "contact_rules_json"
    const val CONTACT_MODES_JSON = "contact_modes_json"
    const val ALLOWLIST_JSON = "allowlist_json"
    const val BLOCKLIST_JSON = "blocklist_json"
    const val AUTO_REPLY_HISTORY_JSON = "auto_reply_history_json"
    const val NOTES_JSON = "notes_json"
}
