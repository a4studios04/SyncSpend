package com.studioa4.syncspend

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.studioa4.syncspend/intent"
    private var intentAction: String? = null

    override fun getBackgroundMode(): BackgroundMode {
        return BackgroundMode.transparent
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Capture the action when the app is first created
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Capture the action if the app was already open in the background
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        intentAction = intent.action
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // This is the bridge that answers Flutter's "getIntentAction" call
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getIntentAction") {
                result.success(intentAction)
                // Clear it after sending so it doesn't fire again on hot restart
                intentAction = null
            } else {
                result.notImplemented()
            }
        }
    }
}