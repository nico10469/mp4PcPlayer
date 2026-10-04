import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide SearchResult;

import '../models/track.dart';
import 'music_catalog.dart';

/// Scarica l'audio di un video YouTube direttamente sul dispositivo, senza server.
abstract class AudioFetcher {
  /// Scrive l'audio in `target(estensione)` e restituisce il file scritto.
  Future<File> fetch(String videoId, File Function(String ext) target, {void Function(double)? onProgress});

  /// Titolo, canale e durata del video, quando YouTube Music non lo conosce.
  Future<SearchResult?> describe(String videoId);
}

/// Un flusso solo audio con il link diretto e lo User-Agent con cui va scaricato.
class AudioStream {
  const AudioStream({
    required this.itag,
    required this.url,
    required this.mimeType,
    required this.bitrate,
    this.size,
    this.userAgent,
  });

  final int itag;
  final String url;
  final String mimeType;
  final int bitrate;
  final int? size;
  final String? userAgent;

  bool get isAac => mimeType.startsWith('audio/mp4');
  String get ext => isAac ? 'm4a' : 'webm';
}

/// Un client dell'app YouTube che riceve link diretti, senza firma da decifrare.
class PlayerClient {
  const PlayerClient(this.name, this.id, this.version, this.userAgent, this.extra);

  final String name;
  final int id;
  final String version;
  final String userAgent;
  final Map<String, Object> extra;

  /// Il client del visore Quest: è quello che yt-dlp usa senza account e senza PO token.
  static const androidVr = PlayerClient(
    'ANDROID_VR',
    28,
    '1.65.10',
    'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    {
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'androidSdkVersion': 32,
      'osName': 'Android',
      'osVersion': '12L',
    },
  );

  /// Una versione più vecchia dello stesso client, se YouTube rifiuta quella nuova.
  static const androidVrOld = PlayerClient(
    'ANDROID_VR',
    28,
    '1.62.27',
    'com.google.android.apps.youtube.vr.oculus/1.62.27 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    {
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'androidSdkVersion': 32,
      'osName': 'Android',
      'osVersion': '12L',
    },
  );

  /// L'app Android normale senza versione dell'SDK: i suoi link a volte passano quando quelli
  /// del visore vengono rifiutati.
  static const android = PlayerClient(
    'ANDROID',
    3,
    '20.10.38',
    'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
    {'osName': 'Android', 'osVersion': '11'},
  );

  /// Pochi tentativi: tante richieste di fila fanno pensare a YouTube di avere davanti un bot.
  static const all = [androidVr, android];

  String get label => '$name $version';
}

/// Scarica l'audio con richieste fatte a mano all'API di YouTube (come fa yt-dlp), e solo se
/// non va usa youtube_explode_dart. Niente Python, quindi funziona anche su iPhone.
class YoutubeAudioFetcher implements AudioFetcher {
  YoutubeAudioFetcher({
    http.Client? client,
    this._yt,
    this.playerUrl = 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
    this.clients = PlayerClient.all,
    this.chunkSize = 10 << 20,
    this.retryDelay = const Duration(seconds: 1),
    bool? iosOnly,
  }) : _http = client ?? http.Client(),
       iosOnly = iosOnly ?? Platform.isIOS;

  final http.Client _http;
  YoutubeExplode? _yt;
  final String playerUrl;
  final List<PlayerClient> clients;

  /// YouTube rallenta o rifiuta chi chiede tutto il file in una volta: si scarica a pezzi.
  final int chunkSize;

  /// Quanto aspettare prima di riprovare un pezzo (raddoppia ogni volta).
  final Duration retryDelay;

  /// Su iPhone si tiene solo l'AAC, perché l'Opus in webm non si riproduce.
  final bool iosOnly;

  YoutubeExplode get yt => _yt ??= YoutubeExplode();

  /// I flussi audio del video, chiedendoli ai client uno dopo l'altro.
  Future<List<AudioStream>> streams(String videoId) async {
    final errors = <String>[];
    for (final c in clients) {
      try {
        final found = await _player(videoId, c);
        if (found.isNotEmpty) return found;
        errors.add('${c.label}: nessun audio');
      } catch (e) {
        errors.add('${c.label}: ${shortError(e)}');
      }
    }
    throw CatalogException(errors.join('; '));
  }

  Future<List<AudioStream>> _player(String videoId, PlayerClient c) async {
    String? visitor;
    for (var attempt = 0; attempt < 2; attempt++) {
      final res = await _http.post(
        Uri.parse(playerUrl),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': c.userAgent,
          'X-YouTube-Client-Name': '${c.id}',
          'X-YouTube-Client-Version': c.version,
          'Origin': 'https://www.youtube.com',
          'X-Goog-Visitor-Id': ?visitor,
        },
        body: jsonEncode({
          'context': {
            'client': {
              'clientName': c.name,
              'clientVersion': c.version,
              'userAgent': c.userAgent,
              'hl': 'en',
              'gl': 'US',
              'timeZone': 'UTC',
              'utcOffsetMinutes': 0,
              'visitorData': ?visitor,
              ...c.extra,
            },
          },
          'videoId': videoId,
          'contentCheckOk': true,
          'racyCheckOk': true,
        }),
      );
      if (res.statusCode != 200) throw CatalogException('risposta ${res.statusCode}');
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final status = data['playabilityStatus'] as Map<String, dynamic>? ?? {};
      if (status['status'] == 'OK') return parsePlayer(data, userAgent: c.userAgent);
      // "Accedi per confermare che non sei un bot": di solito basta ripetere con il visitor id.
      final next = (data['responseContext'] as Map<String, dynamic>?)?['visitorData'] as String?;
      if (attempt == 0 && visitor == null && next != null) {
        visitor = next;
        continue;
      }
      throw CatalogException('${status['status']}: ${status['reason'] ?? 'non disponibile'}');
    }
    return const [];
  }

  @override
  Future<File> fetch(String videoId, File Function(String ext) target, {void Function(double)? onProgress}) async {
    // Si prova un client alla volta fino in fondo: se YouTube rifiuta il link di uno (403),
    // quello dopo riceve un link diverso.
    final failures = <String>[];
    for (final c in clients) {
      final AudioStream? stream;
      try {
        stream = pickAudio(await _player(videoId, c), iosOnly: iosOnly);
      } catch (e) {
        failures.add('${c.label}: ${shortError(e)}');
        // YouTube pensa che siamo un bot: altre richieste peggiorerebbero il blocco.
        if (isBlocked(e)) throw CatalogException(downloadFailure(failures));
        continue;
      }
      if (stream == null) {
        failures.add('${c.label}: nessun audio adatto');
        continue;
      }
      try {
        return await _save(target(stream.ext), onProgress, (sink, progress) => _download(stream!, sink, progress));
      } catch (e) {
        failures.add('${c.label} (itag ${stream.itag}): ${shortError(e)}');
      }
    }
    // Piano B: youtube_explode_dart, con un client diverso dai nostri.
    for (final client in explodeClients) {
      final name = client.payload['context']['client']['clientName'];
      try {
        final manifest = await yt.videos.streamsClient.getManifest(videoId, ytClients: [client]);
        final stream = pickExplodeAudio(manifest.audioOnly, iosOnly: iosOnly);
        if (stream == null) {
          failures.add('$name: nessun audio adatto');
          continue;
        }
        final ext = stream.container == StreamContainer.mp4 ? 'm4a' : stream.container.name;
        final total = stream.size.totalBytes;
        return await _save(target(ext), onProgress, (sink, progress) async {
          var received = 0;
          await for (final chunk in yt.videos.streamsClient.get(stream)) {
            sink.add(chunk);
            received += chunk.length;
            if (total > 0) progress(received / total);
          }
        });
      } catch (e) {
        failures.add('$name: ${shortError(e)}');
        if (isBlocked(e)) break;
      }
    }
    throw CatalogException(downloadFailure(failures));
  }

  /// I client di youtube_explode_dart da provare se i nostri non bastano.
  static final explodeClients = [YoutubeApiClient.ios];

  Future<File> _save(
    File file,
    void Function(double)? onProgress,
    Future<void> Function(IOSink sink, void Function(double) progress) write,
  ) async {
    final tmp = File('${file.path}.part');
    final sink = tmp.openWrite();
    try {
      await write(sink, (p) => onProgress?.call(p.clamp(0, 1).toDouble()));
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    if (await file.exists()) await file.delete();
    return tmp.rename(file.path);
  }

  Future<void> _download(AudioStream stream, IOSink sink, void Function(double) progress) async {
    final total = stream.size;
    final agent = stream.userAgent ?? YoutubeHttpClient.defaultHeaders['user-agent']!;
    // Senza dimensione nota si chiede tutto il file in una volta.
    if (total == null || total <= 0) {
      await _range(stream.url, agent, null, sink, (_) {}, inQuery: false);
      return;
    }
    // Il pezzo si chiede con l'header Range, come yt-dlp; se YouTube lo rifiuta si riprova con
    // `&range=` nel link, come fa il sito.
    var inQuery = false;
    var start = 0;
    while (start < total) {
      final end = (start + chunkSize < total ? start + chunkSize : total) - 1;
      var tries = 0;
      while (true) {
        try {
          final got = await _range(
            stream.url,
            agent,
            (start, end),
            sink,
            (n) => progress((start + n) / total),
            inQuery: inQuery,
          );
          if (got == 0) throw const AudioHttpException(0);
          start += got;
          break;
        } on AudioHttpException catch (e) {
          if (e.status == 403 && start == 0 && !inQuery) {
            inQuery = true;
            continue;
          }
          rethrow;
        } catch (_) {
          // Rete caduta o indirizzo non trovato: si riprova il pezzo dopo una pausa. I byte già
          // scritti non si perdono, si riparte da dove si era arrivati.
          if (++tries >= 4) rethrow;
          await Future<void>.delayed(retryDelay * tries);
        }
      }
    }
  }

  /// Scarica un pezzo del file e restituisce quanti byte ha scritto.
  Future<int> _range(
    String url,
    String agent,
    (int, int)? range,
    IOSink sink,
    void Function(int) progress, {
    required bool inQuery,
  }) async {
    var uri = Uri.parse(url);
    if (range != null && inQuery) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, 'range': '${range.$1}-${range.$2}'});
    }
    final req = http.Request('GET', uri)..headers['User-Agent'] = agent;
    if (range != null && !inQuery) req.headers['Range'] = 'bytes=${range.$1}-${range.$2}';
    final res = await _http.send(req);
    if (res.statusCode != 200 && res.statusCode != 206) {
      await res.stream.drain<void>();
      throw AudioHttpException(res.statusCode);
    }
    var got = 0;
    try {
      await for (final bytes in res.stream) {
        sink.add(bytes);
        got += bytes.length;
        progress(got);
      }
    } catch (_) {
      if (got == 0) rethrow;
    }
    return got;
  }

  @override
  Future<SearchResult?> describe(String videoId) async {
    try {
      final v = await yt.videos.get(videoId);
      final author = v.author.replaceFirst(RegExp(r' - Topic$'), '');
      return SearchResult(
        id: videoId,
        title: v.title,
        artists: mainArtistsFromVideo(author, v.title),
        duration: v.duration,
        thumbnail: v.thumbnails.highResUrl,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Il server dell'audio ha risposto con un codice d'errore (0 = nessun dato).
class AudioHttpException implements Exception {
  const AudioHttpException(this.status);

  final int status;

  @override
  String toString() => status == 0 ? 'nessun dato' : 'rifiutato ($status)';
}

/// Un errore in poche parole, senza i link lunghissimi di YouTube.
String shortError(Object e) {
  if (e is CatalogException) return e.message;
  if (e is AudioHttpException) return '$e';
  if (e is SocketException) {
    final host = e.address?.host;
    final lookup = e.message.contains('host lookup') || e.osError?.errorCode == 7;
    if (lookup) return 'indirizzo non trovato${host == null ? '' : ' ($host)'}';
    return 'rete: ${e.osError?.message ?? e.message}';
  }
  if (e is http.ClientException) {
    final m = RegExp(r"Failed host lookup: '([^']+)'").firstMatch(e.message);
    if (m != null) return 'indirizzo non trovato (${m.group(1)})';
    return 'rete: ${e.message.replaceAll(RegExp(r'https?://\S+'), '…')}';
  }
  if (e is TimeoutException) return 'tempo scaduto';
  var text = '$e'.replaceAll(RegExp(r'https?://\S+'), '…').replaceAll(RegExp(r'\s+'), ' ');
  if (text.length > 160) text = '${text.substring(0, 160)}…';
  return text;
}

/// YouTube sta bloccando questa connessione ("non sei un bot?", troppe richieste).
bool isBlocked(Object e) {
  if (e is RequestLimitExceededException) return true;
  if (e is AudioHttpException) return e.status == 429;
  final text = '$e'.toLowerCase();
  return text.contains('login_required') || text.contains('not a bot') || text.contains('rate limit');
}

/// Il messaggio per l'utente: prima la causa probabile, poi i dettagli di ogni tentativo.
String downloadFailure(List<String> failures) {
  final details = failures.join('; ');
  final network =
      failures.isNotEmpty &&
      failures.every((f) => f.contains('indirizzo non trovato') || f.contains('rete:') || f.contains('tempo scaduto'));
  if (network) {
    return 'Non riesco a raggiungere YouTube: controlla la connessione, e se usi un DNS privato, '
        'una VPN o un blocco pubblicità prova a spegnerlo ($details)';
  }
  final lower = details.toLowerCase();
  if (lower.contains('login_required') || lower.contains('not a bot') || lower.contains('rate limit')) {
    return 'YouTube ha bloccato per un po\' i download da questa connessione. Aspetta qualche minuto, o '
        'prova con un\'altra rete (per esempio i dati invece del Wi-Fi) ($details)';
  }
  if (failures.any((f) => RegExp(r'\b403\b').hasMatch(f))) {
    return 'YouTube ha rifiutato il download di questo brano. Riprova tra un po\', oppure usa '
        '"Con il server" nelle Impostazioni ($details)';
  }
  return 'YouTube non ha dato l\'audio del brano ($details)';
}

/// I flussi solo audio con link diretto della risposta `player`. Le versioni doppiate in
/// altre lingue e quelle a volume compresso (DRC) si scartano quando c'è l'originale.
List<AudioStream> parsePlayer(Map<String, dynamic> data, {String? userAgent}) {
  final formats = ((data['streamingData'] as Map<String, dynamic>?)?['adaptiveFormats'] as List?) ?? const [];
  final all = <(AudioStream, bool)>[];
  for (final f in formats.whereType<Map<String, dynamic>>()) {
    final mime = f['mimeType'] as String? ?? '';
    final url = f['url'] as String?;
    if (!mime.startsWith('audio/') || url == null) continue;
    final track = f['audioTrack'] as Map<String, dynamic>?;
    final original = track == null || track['audioIsDefault'] == true;
    final plain = f['isDrc'] != true && original;
    all.add((
      AudioStream(
        itag: f['itag'] as int? ?? 0,
        url: url,
        mimeType: mime,
        bitrate: (f['averageBitrate'] ?? f['bitrate'] ?? 0) as int,
        size: int.tryParse('${f['contentLength'] ?? ''}'),
        userAgent: userAgent,
      ),
      plain,
    ));
  }
  final plain = [
    for (final (s, ok) in all)
      if (ok) s,
  ];
  return plain.isNotEmpty ? plain : [for (final (s, _) in all) s];
}

/// L'audio migliore: AAC (m4a) se c'è, altrimenti, tranne su iPhone, anche Opus (webm).
AudioStream? pickAudio(List<AudioStream> streams, {bool iosOnly = false}) {
  final aac = streams.where((s) => s.isAac).toList();
  final pool = aac.isNotEmpty ? aac : (iosOnly ? <AudioStream>[] : streams);
  if (pool.isEmpty) return null;
  return pool.reduce((a, b) => b.bitrate > a.bitrate ? b : a);
}

/// Come [pickAudio], per i flussi di youtube_explode_dart.
AudioOnlyStreamInfo? pickExplodeAudio(List<AudioOnlyStreamInfo> streams, {bool iosOnly = false}) {
  final aac = streams.where((s) => s.container == StreamContainer.mp4).toList();
  if (aac.isNotEmpty) return aac.withHighestBitrate();
  if (iosOnly || streams.isEmpty) return null;
  return streams.withHighestBitrate();
}

/// Per un video che YouTube Music non conosce: il canale è l'artista principale, e gli
/// ospiti si leggono dal titolo ("Brano (feat. A & B)", "Brano ft. A, B").
List<String> mainArtistsFromVideo(String channel, String title) {
  final artists = <String>[if (channel.trim().isNotEmpty) channel.trim()];
  final m = RegExp(r'\b(?:feat\.?|ft\.?|featuring)\s+([^()\[\]]+)', caseSensitive: false).firstMatch(title);
  if (m != null) {
    for (final name in m.group(1)!.split(RegExp(r',|&| and | e | x ', caseSensitive: false))) {
      final n = name.trim();
      if (n.isNotEmpty && !artists.any((a) => a.toLowerCase() == n.toLowerCase())) artists.add(n);
    }
  }
  return artists;
}

/// L'id del video da un id o da un link YouTube / YouTube Music (watch, youtu.be, shorts).
String? videoIdOf(String source) {
  source = source.trim();
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(source)) return source;
  final uri = Uri.tryParse(source);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.firstOrNull;
  } else if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
    id = uri.queryParameters['v'];
    if (id == null && uri.pathSegments.length >= 2 && {'shorts', 'live', 'embed'}.contains(uri.pathSegments[0])) {
      id = uri.pathSegments[1];
    }
  }
  return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
}
