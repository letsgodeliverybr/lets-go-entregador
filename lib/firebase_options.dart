import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError('Plataforma não suportada.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDJIoDm0VKPCmTqMQkqQwn9_mQCiL6kkEs',
    appId: '1:594239727397:web:880977db0fba79ff101ccc',
    messagingSenderId: '594239727397',
    projectId: 'lets-go-entregador',
    authDomain: 'lets-go-entregador.firebaseapp.com',
    storageBucket: 'lets-go-entregador.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDJIoDm0VKPCmTqMQkqQwn9_mQCiL6kkEs',
    appId: '1:594239727397:android:6b1323d3b172c44f101ccc',
    messagingSenderId: '594239727397',
    projectId: 'lets-go-entregador',
    storageBucket: 'lets-go-entregador.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDJIoDm0VKPCmTqMQkqQwn9_mQCiL6kkEs',
    appId: '1:594239727397:ios:101ccc',
    messagingSenderId: '594239727397',
    projectId: 'lets-go-entregador',
    storageBucket: 'lets-go-entregador.firebasestorage.app',
    iosBundleId: 'com.letsgodelivery.entregador',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDJIoDm0VKPCmTqMQkqQwn9_mQCiL6kkEs',
    appId: '1:594239727397:ios:101ccc',
    messagingSenderId: '594239727397',
    projectId: 'lets-go-entregador',
    storageBucket: 'lets-go-entregador.firebasestorage.app',
    iosBundleId: 'com.letsgodelivery.entregador',
  );
}
