package com.apex.agent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ReplyApprovalReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_APPROVE = "com.apex.agent.action.APPROVE_REPLY"
        const val ACTION_DISMISS = "com.apex.agent.action.DISMISS_REPLY"
        const val EXTRA_APPROVAL_ID = "approval_id"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        intent ?: return
        val approvalId = intent.getIntExtra(EXTRA_APPROVAL_ID, -1)
        if (approvalId == -1) return

        when (intent.action) {
            ACTION_APPROVE -> {
                val pendingResult = goAsync()
                Thread {
                    try {
                        ApexNotificationListener.approvePending(context.applicationContext, approvalId)
                    } finally {
                        pendingResult.finish()
                    }
                }.start()
            }
            ACTION_DISMISS -> {
                ApexNotificationListener.dismissPending(context.applicationContext, approvalId)
            }
        }
    }
}
