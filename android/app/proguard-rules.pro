# flutter_foreground_task — impede R8 de renomear o service declarado no AndroidManifest
-keep class com.pravera.flutter_foreground_task.** { *; }

# flutter_local_notifications — mantém receivers e channels intactos
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# geolocator — mantém LocationService intacto
-keep class com.baseflow.geolocator.** { *; }

# google_mlkit_text_recognition — o plugin referencia (em código Java não
# usado no nosso caso) as classes de opção dos OUTROS scripts de
# reconhecimento (chinês/devanagari/japonês/coreano); só dependemos do
# pacote base (script latino, único usado — ver
# ifood_confirmacao_webview_screen.dart, TextRecognitionScript.latin), então
# essas classes nem existem no classpath. Sem isso o R8 falha o build de
# release inteiro ("Missing classes"), mesmo esse código nunca executando de
# verdade. Regras geradas automaticamente pelo próprio R8
# (missing_rules.txt) — só suprime o aviso, não muda comportamento.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
