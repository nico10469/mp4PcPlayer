import 'dart:io';

import 'package:flutter/services.dart';

import '../models/track.dart';
import 'direct_audio.dart';
import 'music_catalog.dart';

/// yt-dlp vero dentro l'app Android (vedi YtDlpChannel.kt). Lo stesso programma del server,
/// che si aggiorna dalle Impostazioni quando YouTube cambia qualcosa.
class YtDlp {
  YtDlp({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('carrots/ytdlp') {
    _channel.setMethodCallHandler(_onCall);
  }

  static YtDlp? _instance;
  static YtDlp get instance => _instance ??= YtDlp();

  /// Solo su Android: su iPhone non si possono avviare programmi come Python.
  static bool? debugAvailable;
  static bool get available => debugAvailable ?? Platform.isAndroid;

  final MethodChannel _channel;
  final _progress = <String, void Function(double)>{};
  var _next = 0;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'progress') {
      final args = Map<String, Object?>.from(call.arguments as Map);
      _progress[args['id']]?.call(((args['progress'] as num?) ?? 0).toDouble().clamp(0, 1).toDouble());
    }
    return null;
  }

  /// La versione di yt-dlp nell'app, per esempio "yt-dlp 2025.11.12".
  Future<String?> version() => _call<String>('version');

  /// Scarica l'ultima versione di yt-dlp. Restituisce se è cambiata e la versione attuale.
  Future<({bool updated, String? version})> update() async {
    final r = Map<String, Object?>.from((await _call<Map>('update'))!);
    return (updated: r['updated'] == true, version: r['version'] as String?);
  }

  /// Scarica l'audio di [url] in [dir] e restituisce il percorso del file scritto.
  Future<String> download(String url, Directory dir, {void Function(double)? onProgress}) async {
    final id = 'dl${DateTime.now().microsecondsSinceEpoch}-${_next++}';
    if (onProgress != null) _progress[id] = onProgress;
    try {
      return (await _call<String>('download', {'url': url, 'dir': dir.path, 'id': id}))!;
    } finally {
      _progress.remove(id);
    }
  }

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw YtDlpException(e.message ?? e.code, engineBroken: e.code == 'init');
    } on MissingPluginException {
      throw YtDlpException('yt-dlp non è disponibile su questo dispositivo', engineBroken: true);
    }
  }
}

class YtDlpException extends CatalogException {
  YtDlpException(super.message, {this.engineBroken = false});

  /// yt-dlp non è partito proprio (non è un errore di YouTube).
  final bool engineBroken;
}

/// Su Android scarica con yt-dlp. Se yt-dlp non riesce nemmeno ad avviarsi si usa il metodo
/// di prima ([fallback]); se invece è YouTube a dire di no, non si insiste con altre richieste.
class YtDlpAudioFetcher implements AudioFetcher {
  YtDlpAudioFetcher({this._ytDlp, this._fallback, this._tempRoot});

  YtDlp? _ytDlp;
  AudioFetcher? _fallback;
  final Directory? _tempRoot;

  YtDlp get ytDlp => _ytDlp ??= YtDlp.instance;
  AudioFetcher get fallback => _fallback ??= YoutubeAudioFetcher();

  @override
  Future<File> fetch(String videoId, File Function(String ext) target, {void Function(double)? onProgress}) async {
    final tmp = await (_tempRoot ?? Directory.systemTemp).createTemp('ytdlp');
    try {
      final String path;
      try {
        path = await ytDlp.download('https://www.youtube.com/watch?v=$videoId', tmp, onProgress: onProgress);
      } on YtDlpException catch (e) {
        if (e.engineBroken) return await fallback.fetch(videoId, target, onProgress: onProgress);
        throw CatalogException(ytDlpFailure(e.message));
      }
      final source = File(path);
      final dot = source.path.lastIndexOf('.');
      final ext = dot < 0 ? 'm4a' : source.path.substring(dot + 1).toLowerCase();
      final file = target(ext);
      if (await file.exists()) await file.delete();
      // La cartella della musica può stare su un'altra memoria: si copia invece di spostare.
      try {
        return await source.rename(file.path);
      } on FileSystemException {
        final copy = await source.copy(file.path);
        await source.delete();
        return copy;
      }
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  @override
  Future<SearchResult?> describe(String videoId) => fallback.describe(videoId);
}

/// Il messaggio per l'utente quando yt-dlp non riesce a scaricare.
String ytDlpFailure(String error) {
  final e = error.toLowerCase();
  final String hint;
  if (e.contains('not a bot') || e.contains('sign in to confirm') || e.contains('429') || e.contains('rate')) {
    hint =
        'YouTube ha bloccato per un po\' i download da questa connessione. Aspetta qualche minuto, o prova '
        'con un\'altra rete (per esempio i dati invece del Wi-Fi)';
  } else if (e.contains('403') || e.contains('forbidden')) {
    hint = 'YouTube ha rifiutato il download. Prova "Aggiorna motore download" nelle Impostazioni';
  } else if (e.contains('unable to download') || e.contains('getaddrinfo') || e.contains('network')) {
    hint = 'Non riesco a raggiungere YouTube: controlla la connessione';
  } else {
    hint = 'yt-dlp non è riuscito a scaricare il brano. Prova "Aggiorna motore download" nelle Impostazioni';
  }
  return '$hint ($error)';
}
