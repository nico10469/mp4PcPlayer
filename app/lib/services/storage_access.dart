import 'dart:io';

import 'package:flutter/services.dart';

/// Parla con MainActivity.kt: su Android chiede il permesso di leggere e modificare
/// le cartelle del telefono, per salvare i brani nella cartella scelta dall'utente.
const _channel = MethodChannel('carrots/storage');

/// Chiede al telefono l'accesso alle cartelle. Su computer e iPhone non serve.
/// - Android 11 e successivi: "Accesso a tutti i file" (si apre la pagina delle impostazioni).
/// - Android 10 e precedenti: il classico permesso "Archiviazione".
Future<bool> requestStorageAccess() async {
  if (!Platform.isAndroid) return true;
  return await _channel.invokeMethod<bool>('requestAccess') ?? false;
}

/// Apre le impostazioni dell'app, per quando il permesso è stato negato per sempre.
Future<void> openStorageSettings() async {
  if (Platform.isAndroid) await _channel.invokeMethod<void>('openSettings');
}
