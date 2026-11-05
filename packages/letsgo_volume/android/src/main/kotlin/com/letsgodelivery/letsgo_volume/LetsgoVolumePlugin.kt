package com.letsgodelivery.letsgo_volume

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Volume do alerta de pedido (2026-11-04). Antes o canal 'letsgo/volume' era
// registrado só na MainActivity: com o app fechado/em segundo plano o push é
// tratado numa engine sem Activity (_firebaseBackgroundHandler) e a chamada
// falhava em silêncio — o volume não subia. Como plugin, o Flutter registra
// este canal em TODAS as engines, inclusive a de background.
class LetsgoVolumePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "letsgo/volume")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Mídia E Alarme no máximo, sem mostrar a barra de volume (flags=0).
            // Mesma regra de antes (decisão de produto, igual iFood); precisa de
            // MODIFY_AUDIO_SETTINGS no manifest do app (já existe).
            "forcarVolumeMidiaMaximo" -> try {
                val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                for (stream in intArrayOf(AudioManager.STREAM_MUSIC, AudioManager.STREAM_ALARM)) {
                    val max = am.getStreamMaxVolume(stream)
                    if (am.getStreamVolume(stream) < max) am.setStreamVolume(stream, max, 0)
                }
                result.success(true)
            } catch (e: Exception) {
                result.error("volume_error", e.message, null)
            }
            // Canal de pedido novo silenciado pelo usuário (notificações do app
            // desligadas, canal desligado, importância abaixo de alta ou sem som).
            "canalSilenciado" -> try {
                val id = call.argument<String>("canal") ?: ""
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                var silenciado = !nm.areNotificationsEnabled()
                if (!silenciado && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val ch = nm.getNotificationChannel(id)
                    silenciado = ch != null && (ch.importance < NotificationManager.IMPORTANCE_HIGH || ch.sound == null)
                }
                result.success(silenciado)
            } catch (e: Exception) {
                result.success(false)   // na dúvida, não incomoda o entregador
            }
            "abrirConfigCanal" -> try {
                val id = call.argument<String>("canal") ?: ""
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        .putExtra(Settings.EXTRA_CHANNEL_ID, id)
                else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                result.success(true)
            } catch (e: Exception) {
                result.success(false)
            }
            else -> result.notImplemented()
        }
    }
}
