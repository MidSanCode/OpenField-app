package com.midsancode.openfield

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the `openfield/call` channel that lets the Dart call layer keep an
 * in-progress call alive while the app is backgrounded.
 *
 * Only two operations are exposed — start and stop the foreground service —
 * because everything else about a call is already handled in Dart and the
 * platform side has no opinion about call state.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForeground" -> {
                        startCallService(call.argument<String>("title").orEmpty())
                        result.success(true)
                    }
                    "stopForeground" -> {
                        stopService(Intent(this, CallForegroundService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startCallService(title: String) {
        val intent = Intent(this, CallForegroundService::class.java)
            .putExtra(CallForegroundService.EXTRA_TITLE, title)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    companion object {
        private const val CHANNEL = "openfield/call"
    }
}
