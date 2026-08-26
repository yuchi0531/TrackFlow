package com.trackflow.trackflow

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/**
 * ホーム画面ウィジェット（追跡一覧スナップショット表示）。
 *
 * Flutter 側（`updateWidgetSnapshot`）が SharedPreferences に JSON スナップショットを
 * 保存し、`WidgetSnapshotChannel`（MethodChannel）経由で再描画を依頼する。ここでは
 * shared_preferences プラグインのデフォルトファイル `FlutterSharedPreferences` から
 * スナップショットを読み、RemoteViews に反映するだけの薄いレンダラー。
 */
class TrackingWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            buildViews(context).let {
                appWidgetManager.updateAppWidget(appWidgetId, it)
            }
        }
    }

    companion object {
        /** shared_preferences プラグインのデフォルトファイル名 */
        const val PREFS_NAME = "FlutterSharedPreferences"

        /** SharedPreferences 上のキー（`flutter.` プレフィックス付き） */
        const val SNAPSHOT_KEY = "flutter.trackflow_widget_snapshot"

        private const val MAX_ROWS = 4

        private val rowRootIds = intArrayOf(
            R.id.row_0,
            R.id.row_1,
            R.id.row_2,
            R.id.row_3,
        )
        private val rowNumberIds = intArrayOf(
            R.id.row_0_number,
            R.id.row_1_number,
            R.id.row_2_number,
            R.id.row_3_number,
        )
        private val rowStatusIds = intArrayOf(
            R.id.row_0_status,
            R.id.row_1_status,
            R.id.row_2_status,
            R.id.row_3_status,
        )
        private val rowCarrierIds = intArrayOf(
            R.id.row_0_carrier,
            R.id.row_1_carrier,
            R.id.row_2_carrier,
            R.id.row_3_carrier,
        )

        /**
         * 登録されている全ウィジェットを更新する。
         * `WidgetSnapshotChannel.updateWidget`（MethodChannel）から呼ばれる。
         */
        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, TrackingWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            val views = buildViews(context)
            for (id in ids) {
                manager.updateAppWidget(id, views)
            }
        }

        private fun buildViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.tracking_widget_layout)
            val openApp = openAppPendingIntent(context)

            // ウィジェット内のどこをタップしてもアプリを開く
            views.setOnClickPendingIntent(R.id.widget_root, openApp)
            for (rootId in rowRootIds) {
                views.setOnClickPendingIntent(rootId, openApp)
            }

            val (items, total) = readSnapshot(context)
            views.setTextViewText(R.id.widget_total, "全 $total 件")

            if (items.isEmpty()) {
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_empty, View.GONE)
            }

            for (i in 0 until MAX_ROWS) {
                if (i < items.size) {
                    val item = items[i]
                    views.setViewVisibility(rowRootIds[i], View.VISIBLE)
                    views.setTextViewText(rowNumberIds[i], item.trackingNumber)
                    views.setTextViewText(rowStatusIds[i], item.currentStatus)
                    views.setTextViewText(rowCarrierIds[i], item.carrier)
                } else {
                    views.setViewVisibility(rowRootIds[i], View.GONE)
                }
            }
            return views
        }

        private data class SnapshotItem(
            val trackingNumber: String,
            val carrier: String,
            val currentStatus: String,
        )

        private fun readSnapshot(context: Context): Pair<List<SnapshotItem>, Int> {
            val raw = context
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(SNAPSHOT_KEY, null)
                ?.takeIf { it.isNotBlank() }

            if (raw == null) return emptyList<SnapshotItem>() to 0

            return try {
                val root = JSONObject(raw)
                val total = root.optInt("total", 0)
                val array: JSONArray = root.optJSONArray("items") ?: JSONArray()
                val items = (0 until array.length()).mapNotNull { i ->
                    val el = array.getJSONObject(i)
                    SnapshotItem(
                        trackingNumber = el.optString("trackingNumber", ""),
                        carrier = el.optString("carrierDisplay", el.optString("carrier", "")),
                        currentStatus = el.optString("currentStatus", ""),
                    )
                }
                items to total
            } catch (e: Exception) {
                emptyList<SnapshotItem>() to 0
            }
        }

        private fun openAppPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            return PendingIntent.getActivity(context, 0, intent, flags)
        }
    }
}