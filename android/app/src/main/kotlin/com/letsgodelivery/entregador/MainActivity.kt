package com.letsgodelivery.entregador

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val dndChannel = "letsgo/dnd"
    private val fullScreenIntentChannel = "letsgo/fullscreen_intent"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, dndChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGranted" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    result.success(nm.isNotificationPolicyAccessGranted)
                }
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fullScreenIntentChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGranted" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        result.success(nm.canUseFullScreenIntent())
                    } else {
                        // Abaixo do Android 14 não existe esse acesso especial —
                        // a permissão do manifest já basta.
                        result.success(true)
                    }
                }
                "openSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                            .setData(Uri.parse("package:$packageName"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
