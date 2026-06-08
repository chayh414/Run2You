package com.example.running_app  // 네 프로젝트 패키지 그대로!

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "r2u/location_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "startService" -> {
                    val intent = Intent(this, LocationService::class.java)
                    startForegroundService(intent)   // 🔥 핵심
                    result.success("started")
                }

                "stopService" -> {
                    val intent = Intent(this, LocationService::class.java)
                    stopService(intent)
                    result.success("stopped")
                }

                else -> result.notImplemented()
            }
        }
    }
}