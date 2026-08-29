package com.letsgodelivery.entregador

import android.app.NotificationManager
import android.content.ComponentName
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
    private val miuiAutostartChannel = "letsgo/miui_autostart"

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

        // Autoiniciar da MIUI: sem API pública do Android pra isso (é um
        // recurso próprio da Xiaomi, por fora do sistema padrão de bateria/
        // notificação) — sem essa permissão, o processo do app é morto
        // agressivamente pelo gerenciador de bateria da MIUI assim que sai
        // de primeiro plano, e nenhuma notificação FCM (nem data-only, nem
        // com bloco `notification`) consegue tocar som depois disso.
        // Componente descoberto por engenharia reversa da comunidade —
        // muda entre versões da MIUI, por isso a lista de candidatos +
        // fallback pra tela de detalhes do app se nenhum abrir.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, miuiAutostartChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getManufacturer" -> result.success(Build.MANUFACTURER ?: "")
                "getBrand" -> result.success(Build.BRAND ?: "")
                "openAutostartSettings" -> {
                    val candidatos = listOf(
                        ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
                        ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity_")
                    )
                    var aberto = false
                    for (componente in candidatos) {
                        try {
                            val intent = Intent().apply {
                                component = componente
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            aberto = true
                            break
                        } catch (e: Exception) {
                            // Esse componente não existe nesta versão da MIUI — tenta o próximo.
                        }
                    }
                    if (!aberto) {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        } catch (e: Exception) {
                            // Nada mais a tentar.
                        }
                    }
                    result.success(aberto)
                }
                else -> result.notImplemented()
            }
        }
    }
}
