package com.apex.agent

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject

class ApexAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var instance: ApexAccessibilityService? = null
            private set

        fun isEnabled(context: Context): Boolean {
            val expected = ComponentName(context, ApexAccessibilityService::class.java).flattenToString()
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            val enabled = Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0
            )
            if (enabled != 1) return false
            return enabledServices.split(':').any { it.equals(expected, ignoreCase = true) }
        }

        fun openSettings(context: Context) {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }

        fun getScreenStateJson(): String {
            return instance?.dumpScreenState() ?: JSONObject().apply {
                put("error", "Accessibility service not connected")
                put("elements", JSONArray())
            }.toString()
        }

        fun openApp(context: Context, packageOrName: String): Boolean {
            val svc = instance
            if (svc != null) {
                val ok = svc.openAppInternal(packageOrName)
                if (ok) return true
            }
            return openAppViaPackageManager(context, packageOrName)
        }

        fun clickText(target: String): Boolean {
            return instance?.clickTextInternal(target) ?: false
        }

        fun typeText(targetOrFocused: String?, text: String): Boolean {
            return instance?.typeTextInternal(targetOrFocused, text) ?: false
        }

        fun scrollScreen(direction: String): Boolean {
            return instance?.scrollScreenInternal(direction) ?: false
        }

        fun pressGlobal(action: String): Boolean {
            return instance?.pressGlobalInternal(action) ?: false
        }

        private fun openAppViaPackageManager(context: Context, packageOrName: String): Boolean {
            val pm = context.packageManager
            val trimmed = packageOrName.trim()
            if (trimmed.isEmpty()) return false

            // Try direct package name launch first.
            val direct = pm.getLaunchIntentForPackage(trimmed)
            if (direct != null) {
                direct.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(direct)
                return true
            }

            // Try case-insensitive package match and label match.
            val intent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val resolved = pm.queryIntentActivities(intent, 0)
            val lower = trimmed.lowercase()
            var bestPackage: String? = null
            for (ri in resolved) {
                val pkg = ri.activityInfo?.packageName ?: continue
                val label = ri.loadLabel(pm)?.toString() ?: ""
                if (pkg.equals(trimmed, ignoreCase = true) || label.equals(trimmed, ignoreCase = true)) {
                    bestPackage = pkg
                    break
                }
                if (label.lowercase().contains(lower) || pkg.lowercase().contains(lower)) {
                    if (bestPackage == null) bestPackage = pkg
                }
            }
            if (bestPackage != null) {
                val launch = pm.getLaunchIntentForPackage(bestPackage)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(launch)
                    return true
                }
            }
            return false
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No-op: screen state is queried on demand.
    }

    override fun onInterrupt() {
        // No-op
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    private fun dumpScreenState(): String {
        val root = rootInActiveWindow
        val result = JSONObject()
        if (root == null) {
            result.put("error", "No active window")
            result.put("elements", JSONArray())
            return result.toString()
        }
        val elements = JSONArray()
        try {
            val queue: ArrayDeque<Pair<AccessibilityNodeInfo, Int>> = ArrayDeque()
            queue.addLast(root to 0)
            var count = 0
            val maxNodes = 250
            while (queue.isNotEmpty() && count < maxNodes) {
                val (node, depth) = queue.removeFirst()
                try {
                    val obj = nodeToJson(node, depth)
                    if (obj != null) {
                        elements.put(obj)
                        count++
                    }
                    for (i in 0 until node.childCount) {
                        val child = node.getChild(i) ?: continue
                        queue.addLast(child to depth + 1)
                    }
                } finally {
                    if (node != root) {
                        try { node.recycle() } catch (_: Throwable) {}
                    }
                }
            }
            // Drain any remaining nodes to recycle them.
            while (queue.isNotEmpty()) {
                val (node, _) = queue.removeFirst()
                if (node != root) {
                    try { node.recycle() } catch (_: Throwable) {}
                }
            }
        } finally {
            try { root.recycle() } catch (_: Throwable) {}
        }
        result.put("packageName", rootInActiveWindow?.packageName?.toString() ?: "")
        try { rootInActiveWindow?.recycle() } catch (_: Throwable) {}
        result.put("elements", elements)
        return result.toString()
    }

    private fun nodeToJson(node: AccessibilityNodeInfo, depth: Int): JSONObject? {
        val text = node.text?.toString()?.trim() ?: ""
        val desc = node.contentDescription?.toString()?.trim() ?: ""
        val className = node.className?.toString() ?: ""
        val viewId = try { node.viewIdResourceName ?: "" } catch (_: Throwable) { "" }

        // Keep nodes that have some useful signal to reduce noise.
        val hasSignal = text.isNotEmpty() || desc.isNotEmpty() || node.isClickable ||
            node.isEditable || node.isScrollable || node.isCheckable
        if (!hasSignal) return null

        val rect = Rect()
        node.getBoundsInScreen(rect)
        val bounds = JSONObject().apply {
            put("left", rect.left)
            put("top", rect.top)
            put("right", rect.right)
            put("bottom", rect.bottom)
        }

        return JSONObject().apply {
            put("text", text)
            put("contentDescription", desc)
            put("className", className)
            if (viewId.isNotEmpty()) put("viewId", viewId)
            put("isClickable", node.isClickable)
            put("isEditable", node.isEditable)
            put("isScrollable", node.isScrollable)
            put("isCheckable", node.isCheckable)
            put("isChecked", node.isChecked)
            put("isEnabled", node.isEnabled)
            put("isFocused", node.isFocused)
            put("bounds", bounds)
            put("depth", depth)
        }
    }

    private fun openAppInternal(packageOrName: String): Boolean {
        return openAppViaPackageManager(this, packageOrName)
    }

    private fun clickTextInternal(target: String): Boolean {
        val root = rootInActiveWindow ?: return false
        try {
            val needle = target.trim().lowercase()
            if (needle.isEmpty()) return false
            val match = findNodeByText(root, needle) ?: return false
            val clickable = findClickableParent(match) ?: match
            val clicked = clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            if (!clicked) {
                // Fallback: click by gesture at center bounds.
                val rect = Rect()
                clickable.getBoundsInScreen(rect)
                if (!rect.isEmpty) {
                    return clickByGesture(rect.centerX().toFloat(), rect.centerY().toFloat())
                }
            }
            return clicked
        } finally {
            try { root.recycle() } catch (_: Throwable) {}
        }
    }

    private fun findNodeByText(root: AccessibilityNodeInfo, needle: String): AccessibilityNodeInfo? {
        val queue: ArrayDeque<AccessibilityNodeInfo> = ArrayDeque()
        queue.addLast(root)
        var best: AccessibilityNodeInfo? = null
        var bestScore = Int.MAX_VALUE
        val visited = HashSet<AccessibilityNodeInfo>()
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (!visited.add(node)) continue
            val text = node.text?.toString()?.trim()?.lowercase() ?: ""
            val desc = node.contentDescription?.toString()?.trim()?.lowercase() ?: ""
            val score = when {
                text == needle || desc == needle -> 0
                text.contains(needle) || desc.contains(needle) -> 1
                else -> -1
            }
            if (score >= 0 && score < bestScore) {
                best = node
                bestScore = score
                if (bestScore == 0) break
            }
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                queue.addLast(child)
            }
        }
        return best
    }

    private fun findClickableParent(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var current: AccessibilityNodeInfo? = node
        var hops = 0
        while (current != null && hops < 8) {
            if (current.isClickable) return current
            current = current.parent
            hops++
        }
        return null
    }

    private fun clickByGesture(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    private fun typeTextInternal(targetOrFocused: String?, text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        try {
            val target = targetOrFocused?.trim().orEmpty()
            val node: AccessibilityNodeInfo? = if (target.isEmpty() || target.equals("focused", ignoreCase = true)) {
                root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                    ?: findFocusedEditable(root)
            } else {
                val match = findNodeByText(root, target.lowercase())
                findEditableNode(match) ?: findFocusedEditable(root)
            }
            val editable = node ?: return false
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            }
            if (!editable.isFocused) {
                editable.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            }
            return editable.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        } finally {
            try { root.recycle() } catch (_: Throwable) {}
        }
    }

    private fun findFocusedEditable(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val queue: ArrayDeque<AccessibilityNodeInfo> = ArrayDeque()
        queue.addLast(root)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (node.isEditable && node.isFocused) return node
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                queue.addLast(child)
            }
        }
        // Fallback: any editable.
        val q2: ArrayDeque<AccessibilityNodeInfo> = ArrayDeque()
        q2.addLast(root)
        while (q2.isNotEmpty()) {
            val node = q2.removeFirst()
            if (node.isEditable) return node
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                q2.addLast(child)
            }
        }
        return null
    }

    private fun findEditableNode(start: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (start == null) return null
        if (start.isEditable) return start
        // Check children
        val queue: ArrayDeque<AccessibilityNodeInfo> = ArrayDeque()
        queue.addLast(start)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (node.isEditable) return node
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                queue.addLast(child)
            }
        }
        // Check parent chain
        var current: AccessibilityNodeInfo? = start.parent
        var hops = 0
        while (current != null && hops < 6) {
            if (current.isEditable) return current
            current = current.parent
            hops++
        }
        return null
    }

    private fun scrollScreenInternal(direction: String): Boolean {
        val root = rootInActiveWindow ?: return false
        try {
            val dir = direction.trim().lowercase()
            val action = when (dir) {
                "down" -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                "up" -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
                "right" -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                "left" -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
                else -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            }

            val scrollable = findScrollableNode(root, dir) ?: root
            val acted = scrollable.performAction(action)
            if (acted) return true

            // Gesture fallback.
            return scrollByGesture(dir)
        } finally {
            try { root.recycle() } catch (_: Throwable) {}
        }
    }

    private fun findScrollableNode(root: AccessibilityNodeInfo, direction: String): AccessibilityNodeInfo? {
        val queue: ArrayDeque<AccessibilityNodeInfo> = ArrayDeque()
        queue.addLast(root)
        var fallback: AccessibilityNodeInfo? = null
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (node.isScrollable) {
                if (fallback == null) fallback = node
                // Prefer large scrollable containers.
                val rect = Rect()
                node.getBoundsInScreen(rect)
                if (rect.height() > 300 || rect.width() > 300) return node
            }
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                queue.addLast(child)
            }
        }
        return fallback
    }

    private fun scrollByGesture(direction: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val dm = resources.displayMetrics
        val width = dm.widthPixels.toFloat()
        val height = dm.heightPixels.toFloat()
        val startX: Float
        val startY: Float
        val endX: Float
        val endY: Float
        when (direction.lowercase()) {
            "up" -> {
                startX = width / 2; startY = height * 0.3f
                endX = width / 2; endY = height * 0.7f
            }
            "down" -> {
                startX = width / 2; startY = height * 0.7f
                endX = width / 2; endY = height * 0.3f
            }
            "left" -> {
                startX = width * 0.2f; startY = height / 2
                endX = width * 0.8f; endY = height / 2
            }
            "right" -> {
                startX = width * 0.8f; startY = height / 2
                endX = width * 0.2f; endY = height / 2
            }
            else -> {
                startX = width / 2; startY = height * 0.7f
                endX = width / 2; endY = height * 0.3f
            }
        }
        val path = Path().apply {
            moveTo(startX, startY)
            lineTo(endX, endY)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 300))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    private fun pressGlobalInternal(action: String): Boolean {
        val globalAction = when (action.trim().uppercase()) {
            "BACK" -> GLOBAL_ACTION_BACK
            "HOME" -> GLOBAL_ACTION_HOME
            "RECENTS" -> GLOBAL_ACTION_RECENTS
            else -> return false
        }
        return performGlobalAction(globalAction)
    }
}
