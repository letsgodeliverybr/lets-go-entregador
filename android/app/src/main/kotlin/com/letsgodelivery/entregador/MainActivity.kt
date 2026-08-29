package com.letsgodelivery.entregador

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
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
    private val volumeChannel = "letsgo/volume"

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

        // DECISÃO DE PRODUTO deliberada, não é bug: força o volume de MÍDIA
        // (STREAM_MUSIC) pro máximo quando um pedido/rota novo chega, mesmo
        // com o aparelho no silencioso — mesmo comportamento do app do
        // iFood pra entregadores. Ciente do precedente: esse comportamento
        // já gerou reclamação de usuários do iFood (perda de controle sobre
        // o próprio volume do aparelho) — decisão consciente do negócio
        // mesmo assim, porque um entregador que não ouve o pedido chegando
        // perde a corrida pro próximo da fila. flags=0 (sem
        // FLAG_SHOW_UI/FLAG_PLAY_SOUND) — sobe o volume em silêncio, sem
        // mostrar a barra de volume do sistema na tela.
        //
        // Não restaura o volume depois (igual iFood) — fica no máximo até
        // o próprio usuário abaixar na mão.
        //
        // Chamado de 2 pontos no Dart (som_pedido_service.dart, dentro de
        // tocarLoop() — cobre tanto o loop em foreground/tela Disponíveis
        // quanto uma eventual chamada vinda do handler de notificação em
        // background), centralizado aqui como única implementação nativa.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, volumeChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "forcarVolumeMidiaMaximo" -> {
                    try {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val atual = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                        if (atual < max) {
                            am.setStreamVolume(AudioManager.STREAM_MUSIC, max, 0)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("volume_error", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
