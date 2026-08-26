package com.trackflow.trackflow

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ホーム画面ウィジェット更新用 MethodChannel を登録する
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WidgetSnapshotChannel.CHANNEL_NAME,
        ).setMethodCallHandler(WidgetSnapshotChannel(applicationContext))
    }
}
