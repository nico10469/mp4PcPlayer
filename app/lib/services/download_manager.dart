import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'library_store.dart';
import 'server_api.dart';

enum DownloadPhase { server, transfer, done, error }

class DownloadState {
  const DownloadState(this.phase, this.progress, [this.error]);
  final DownloadPhase phase;

  /// Avanzamento complessivo da 0 a 1: il download sul server pesa l'80%,
  /// il trasferimento sul dispositivo il restante 20%.
  final double progress;
  final String? error;
}

/// Coordina il flusso: il server scarica da YouTube, poi l'app copia il file in locale.
class DownloadManager extends ChangeNotifier {
  DownloadManager({required this.library, required this.api, this.pollInterval = const Duration(milliseconds: 700)});

  final LibraryStore library;
  ServerApi api;
  final Duration pollInterval;
  final Map<String, DownloadState> _states = {};

  DownloadState? stateOf(String id) => _states[id];

  void _set(String id, DownloadState s) {
    _states[id] = s;
    notifyListeners();
  }

  /// [key] identifica la riga nell'interfaccia (l'id del risultato, o il link incollato).
  Future<Track?> download(String key, {String? source}) async {
    final current = _states[key];
    if (current != null && (current.phase == DownloadPhase.server || current.phase == DownloadPhase.transfer)) {
      return null;
    }
    _set(key, const DownloadState(DownloadPhase.server, 0));
    try {
      var job = await api.startDownload(source ?? key);
      while (!job.isDone) {
        if (job.isError) throw ServerException(job.error ?? 'Download fallito');
        await Future<void>.delayed(pollInterval);
        job = await api.job(job.id);
        _set(key, DownloadState(DownloadPhase.server, job.progress * 0.8));
      }

      final trackId = job.trackId!;
      final meta = await api.track(trackId);
      final fileName = '$trackId.${meta['ext'] ?? 'm4a'}';
      await api.fetchFile(
        trackId,
        library.fileFor(fileName),
        onProgress: (p) => _set(key, DownloadState(DownloadPhase.transfer, 0.8 + p * 0.2)),
      );

      String? coverName;
      final thumb = meta['thumbnail'] as String?;
      if (thumb != null && await api.fetchCover(thumb, library.fileFor('$trackId.jpg'))) {
        coverName = '$trackId.jpg';
      }

      final track = Track.fromServer(meta, fileName: fileName, coverFileName: coverName);
      await library.add(track);
      _set(key, const DownloadState(DownloadPhase.done, 1));
      return track;
    } on Exception catch (e) {
      _set(key, DownloadState(DownloadPhase.error, 0, e.toString()));
      return null;
    }
  }
}
