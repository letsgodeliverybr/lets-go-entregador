# flutter_foreground_task — impede R8 de renomear o service declarado no AndroidManifest
-keep class com.pravera.flutter_foreground_task.** { *; }

# flutter_local_notifications — mantém receivers e channels intactos
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# geolocator — mantém LocationService intacto
-keep class com.baseflow.geolocator.** { *; }
