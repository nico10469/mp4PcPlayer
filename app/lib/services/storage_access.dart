import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Chiede al telefono il permesso di leggere e modificare le cartelle, per salvare
/// i brani nella cartella scelta dall'utente. Su computer e iPhone non serve.
///
/// - Android 11 e successivi: "Accesso a tutti i file" (si apre la pagina delle impostazioni).
/// - Android 10 e precedenti: il classico permesso "Archiviazione".
Future<bool> requestStorageAccess() async {
  if (!Platform.isAndroid) return true;
  final manage = await Permission.manageExternalStorage.status;
  if (manage.isGranted) return true;
  if (manage.isRestricted) {
    // Prima di Android 11 "Accesso a tutti i file" non esiste.
    return (await Permission.storage.request()).isGranted;
  }
  return (await Permission.manageExternalStorage.request()).isGranted;
}

/// Apre le impostazioni dell'app, per quando il permesso è stato negato per sempre.
Future<void> openStorageSettings() => openAppSettings();
