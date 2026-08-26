package com.trackflow.trackflow

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter 側 `WidgetSnapshotChannel` からの呼び出しを処理する。
 * スナップショット保存後に `updateWidget` が呼ばれ、ネイティブ側の
 * `TrackingWidgetProvider` に全ウィジェットの再描画を実行させる。
 */
class WidgetSnapshotChannel(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateWidget" -> {
                try {
                    TrackingWidgetProvider.updateAllWidgets(context)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("WIDGET_UPDATE_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        /** Dart 側 WidgetSnapshotChannel と一致させる */
        const val CHANNEL_NAME = "com.trackflow.trackflow/widget_snapshot"
    }
}