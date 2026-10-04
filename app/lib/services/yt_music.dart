import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'music_catalog.dart';

/// Client di YouTube Music che gira direttamente nell'app, senza server: parla con le stesse
/// API interne del sito (InnerTube), come fa ytmusicapi sul server. Serve per cercare brani,
/// album, playlist e per leggere la discografia di un artista.
class YtMusicClient implements MusicCatalog {
  YtMusicClient({http.Client? client, this.baseUrl = 'https://music.youtube.com/youtubei/v1/', this.sendOrigin = true})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// Il sito vuole Origin e Referer di music.youtube.com (i test usano un altro host e li tolgono).
  final bool sendOrigin;
  String? _visitorId;

  static const _key = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';

  Map<String, dynamic> get _context {
    final now = DateTime.now().toUtc();
    final day = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return {
      'client': {'clientName': 'WEB_REMIX', 'clientVersion': '1.$day.01.00', 'hl': 'en'},
      'user': <String, dynamic>{},
    };
  }

  Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$endpoint?alt=json&key=$_key');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': '*/*',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0',
      if (sendOrigin) ...{'Origin': 'https://music.youtube.com', 'Referer': 'https://music.youtube.com/'},
      'X-Goog-Visitor-Id': ?_visitorId,
    };
    final http.Response res;
    try {
      res = await _client
          .post(uri, headers: headers, body: jsonEncode({...body, 'context': _context}))
          .timeout(const Duration(seconds: 30));
    } on Exception catch (e) {
      throw CatalogException('YouTube Music non raggiungibile ($e)');
    }
    if (res.statusCode >= 400) {
      throw CatalogException('YouTube Music ha risposto con l\'errore ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    _visitorId ??= _nav(data, ['responseContext', 'visitorData']) as String?;
    return data;
  }

  // ---------------------------------------------------------------- ricerca

  static const _searchParams = {
    ResultKind.song: 'EgWKAQIIAWoMEA4QChADEAQQCRAF',
    ResultKind.album: 'EgWKAQIYAWoMEA4QChADEAQQCRAF',
    ResultKind.playlist: 'Eg-KAQwIABAAGAAgACgBMABqChAEEAMQCRAFEAo%3D',
  };

  @override
  Future<List<SearchResult>> search(String query, {ResultKind kind = ResultKind.song}) async {
    final data = await _post('search', {'query': query, 'params': _searchParams[kind]});
    return [
      for (final item in _shelfItems(data))
        ?switch (kind) {
          ResultKind.song => parseSong(item),
          ResultKind.album => parseAlbum(item),
          ResultKind.playlist => parsePlaylist(item),
        },
    ];
  }

  /// Gli elementi dei risultati di una ricerca (le righe della lista, senza il "risultato migliore").
  static List<Map<String, dynamic>> _shelfItems(Map<String, dynamic> data) {
    final tabs = _nav(data, ['contents', 'tabbedSearchResultsRenderer', 'tabs']) as List?;
    final root = tabs == null ? data['contents'] : _nav(tabs.first, ['tabRenderer', 'content']);
    final sections = _nav(root, ['sectionListRenderer', 'contents']) as List? ?? const [];
    return [
      for (final s in sections)
        for (final c in (_nav(s, ['musicShelfRenderer', 'contents']) as List? ?? const []))
          if (c is Map && c['musicResponsiveListItemRenderer'] is Map)
            c['musicResponsiveListItemRenderer'] as Map<String, dynamic>,
    ];
  }

  /// Un brano dei risultati della ricerca: "Titolo" e sotto "Artista, Ospite • Album • 3:21".
  static SearchResult? parseSong(Map<String, dynamic> item) {
    final videoId =
        _nav(item, ['overlay', ..._playButton, 'playNavigationEndpoint', 'watchEndpoint', 'videoId']) ??
        _nav(_flexRuns(item, 0)?.firstOrNull, ['navigationEndpoint', 'watchEndpoint', 'videoId']) ??
        _nav(item, ['playlistItemData', 'videoId']);
    if (videoId is! String || !_available(item)) return null;
    final runs = [...?_flexRuns(item, 1)];
    final extra = _flexRuns(item, 2);
    // Il primo elemento finto fa da separatore tra le due colonne.
    if (extra != null) {
      runs
        ..add({'text': ''})
        ..addAll(extra);
    }
    final info = parseSongRuns(runs, skipTypeSpec: true);
    return SearchResult(
      id: videoId,
      title: _text(_flexRuns(item, 0)) ?? videoId,
      artists: info.artists,
      album: info.album,
      albumId: info.albumId,
      duration: info.duration,
      year: info.year,
      thumbnail: _cover(item) ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
    );
  }

  static SearchResult? parseAlbum(Map<String, dynamic> item) {
    final id = _nav(item, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
    if (id is! String) return null;
    final runs = _flexRuns(item, 1) ?? const [];
    final info = parseSongRuns(runs, skipTypeSpec: true);
    return SearchResult(
      id: id,
      kind: ResultKind.album,
      title: _text(_flexRuns(item, 0)) ?? '',
      artists: info.artists,
      type: _text(runs),
      year: info.year,
      thumbnail: _cover(item),
    );
  }

  static SearchResult? parsePlaylist(Map<String, dynamic> item) {
    final browseId = _nav(item, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
    if (browseId is! String) return null;
    final runs = _flexRuns(item, 1) ?? const [];
    // "Autore • 248 views" oppure "Autore • 50 songs": l'autore è il primo testo.
    final texts = [for (var i = 0; i < runs.length; i += 2) runs[i]['text'] as String? ?? ''];
    int? count;
    for (final t in texts) {
      final m = RegExp(r'^([\d.,]+) (songs|tracks)$').firstMatch(t);
      if (m != null) count = int.tryParse(m.group(1)!.replaceAll(RegExp(r'[.,]'), ''));
    }
    final named = texts.isNotEmpty && texts.first == 'Playlist' ? texts.sublist(1) : texts;
    final author = named.length > 1 ? named.first : '';
    return SearchResult(
      id: browseId.startsWith('VL') ? browseId.substring(2) : browseId,
      kind: ResultKind.playlist,
      title: _text(_flexRuns(item, 0)) ?? '',
      artists: [if (author.isNotEmpty) author],
      count: count,
      thumbnail: _cover(item),
    );
  }

  // ------------------------------------------------------- album e playlist

  @override
  Future<Collection> collection(String source) async {
    final id = collectionId(source);
    if (id.startsWith('MPREb')) return album(id);
    return playlist(id);
  }

  Future<Collection> album(String browseId) async {
    final data = await _post('browse', {'browseId': browseId});
    return parseAlbumPage(data, browseId);
  }

  static Collection parseAlbumPage(Map<String, dynamic> data, String browseId) {
    final two = _nav(data, ['contents', 'twoColumnBrowseResultsRenderer']);
    final header = _nav(two, [..._tabContent, 'sectionListRenderer', 'contents', 0, 'musicResponsiveHeaderRenderer']);
    if (header == null) throw CatalogException('Album non disponibile');
    final title = _text(_nav(header, ['title', 'runs'])) ?? '';
    final subtitle = (_nav(header, ['subtitle', 'runs']) as List?) ?? const [];
    final info = parseSongRuns(subtitle.length > 2 ? subtitle.sublist(2) : const []);
    final strapline = _nav(header, ['straplineTextOne', 'runs']) as List?;
    final artists = strapline == null ? info.artists : artistsFromRuns(strapline);
    final cover = _bigCover(
      _lastThumb(_nav(header, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'])),
    );
    final shelf = _nav(two, [
      'secondaryContents',
      'sectionListRenderer',
      'contents',
      0,
      'musicShelfRenderer',
      'contents',
    ]);
    final tracks = <SearchResult>[];
    for (final row in (shelf as List? ?? const [])) {
      final item = _nav(row, ['musicResponsiveListItemRenderer']);
      if (item is! Map<String, dynamic>) continue;
      final t = parsePlaylistItem(item, isAlbum: true);
      if (t == null || !t.available) continue;
      tracks.add(
        t.copyWith(
          artists: t.artists.isEmpty ? artists : t.artists,
          album: title,
          albumId: browseId,
          thumbnail: cover,
          year: info.year,
        ),
      );
    }
    return Collection(
      id: browseId,
      kind: ResultKind.album,
      title: title,
      artist: artists.join(', '),
      thumbnail: cover,
      year: info.year,
      tracks: tracks,
    );
  }

  Future<Collection> playlist(String playlistId, {int limit = 500}) async {
    final data = await _post('browse', {'browseId': playlistId.startsWith('VL') ? playlistId : 'VL$playlistId'});
    final page = parsePlaylistPage(data, playlistId);
    final tracks = [...page.tracks];
    var token = page.continuation;
    while (token != null && tracks.length < limit) {
      final more = await _post('browse', {'continuation': token});
      final items = _nav(more, ['onResponseReceivedActions', 0, 'appendContinuationItemsAction', 'continuationItems']);
      if (items is! List || items.isEmpty) break;
      final parsed = _playlistRows(items);
      if (parsed.isEmpty) break;
      tracks.addAll(parsed);
      token = _continuationToken(items);
    }
    final isAlbum = playlistId.startsWith('OLAK5uy_');
    final title = page.title.isNotEmpty ? page.title : (tracks.firstOrNull?.album ?? '');
    return Collection(
      id: playlistId,
      kind: isAlbum ? ResultKind.album : ResultKind.playlist,
      title: title,
      artist: isAlbum && page.author.isEmpty ? (tracks.firstOrNull?.artist ?? '') : page.author,
      thumbnail: page.thumbnail ?? tracks.firstOrNull?.thumbnail,
      year: page.year,
      tracks: tracks.where((t) => t.available).toList(),
    );
  }

  static ({String title, String author, String? thumbnail, int? year, List<SearchResult> tracks, String? continuation})
  parsePlaylistPage(Map<String, dynamic> data, String playlistId) {
    final two = _nav(data, ['contents', 'twoColumnBrowseResultsRenderer']);
    final first = _nav(two, [..._tabContent, 'sectionListRenderer', 'contents', 0]);
    final header =
        _nav(first, ['musicResponsiveHeaderRenderer']) ??
        _nav(first, ['musicEditablePlaylistDetailHeaderRenderer', 'header', 'musicResponsiveHeaderRenderer']);
    final shelf = _nav(two, ['secondaryContents', 'sectionListRenderer', 'contents', 0, 'musicPlaylistShelfRenderer']);
    final rows = (_nav(shelf, ['contents']) as List?) ?? const [];
    String author = '';
    int? year;
    if (header != null) {
      author =
          (_nav(header, ['facepile', 'avatarStackViewModel', 'text', 'content']) as String?) ??
          artistsFromRuns((_nav(header, ['straplineTextOne', 'runs']) as List?) ?? const []).join(', ');
      final subtitle = (_nav(header, ['subtitle', 'runs']) as List?) ?? const [];
      year = parseSongRuns(subtitle.length > 2 ? subtitle.sublist(2) : const []).year;
    }
    return (
      title: header == null ? '' : (_nav(header, ['title', 'runs']) as List? ?? const []).map((r) => r['text']).join(),
      author: author,
      thumbnail: _bigCover(
        _lastThumb(_nav(header, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'])),
      ),
      year: year,
      tracks: _playlistRows(rows),
      continuation: rows.isEmpty ? null : _continuationToken(rows),
    );
  }

  static List<SearchResult> _playlistRows(List rows) => [
    for (final row in rows)
      if (_nav(row, ['musicResponsiveListItemRenderer']) case final Map<String, dynamic> item) ?parsePlaylistItem(item),
  ];

  static String? _continuationToken(List rows) {
    final last = rows.last;
    final token = _nav(last, ['continuationItemRenderer', 'continuationEndpoint', 'continuationCommand', 'token']);
    if (token is String) return token;
    final commands =
        _nav(last, ['continuationItemRenderer', 'continuationEndpoint', 'commandExecutorCommand', 'commands']) as List?;
    for (final c in commands ?? const []) {
      final t = _nav(c, ['continuationCommand', 'token']);
      if (t is String) return t;
    }
    return null;
  }

  /// Una riga di un album o di una playlist. Le colonne si riconoscono dal tipo di link
  /// (brano, artista, album), come in ytmusicapi.
  static SearchResult? parsePlaylistItem(Map<String, dynamic> item, {bool isAlbum = false}) {
    final available = _available(item);
    final preset = !available || isAlbum;
    int? titleIndex = preset ? 0 : null;
    int? artistIndex = preset ? 1 : null;
    int? albumIndex = preset ? 2 : null;
    int? unrecognized;
    final columns = (item['flexColumns'] as List?) ?? const [];
    for (var i = 0; i < columns.length; i++) {
      final run = _flexRuns(item, i)?.firstOrNull;
      final nav = _nav(run, ['navigationEndpoint']);
      if (nav == null) {
        if (run != null && run['text'] is String && !_isDuration(run['text'] as String)) unrecognized ??= i;
        continue;
      }
      if (nav['watchEndpoint'] != null) {
        titleIndex = i;
      } else if (nav['browseEndpoint'] != null) {
        final page = _nav(nav, ['browseEndpoint', ..._pageType]);
        if (page == 'MUSIC_PAGE_TYPE_ARTIST' || page == 'MUSIC_PAGE_TYPE_UNKNOWN') {
          artistIndex = i;
        } else if (page == 'MUSIC_PAGE_TYPE_ALBUM' || page == 'MUSIC_PAGE_TYPE_AUDIOBOOK') {
          albumIndex = i;
        } else if (page == 'MUSIC_PAGE_TYPE_USER_CHANNEL') {
          artistIndex ??= i;
        }
      }
    }
    artistIndex ??= unrecognized;
    final videoId =
        _nav(item, ['overlay', ..._playButton, 'playNavigationEndpoint', 'watchEndpoint', 'videoId']) ??
        _nav(item, ['playlistItemData', 'videoId']);
    final title = titleIndex == null ? null : _text(_flexRuns(item, titleIndex));
    if (videoId is! String || title == null || title == 'Song deleted') return null;
    final albumRuns = albumIndex == null ? null : _flexRuns(item, albumIndex);
    String? durationText = _text(
      _nav(item, ['fixedColumns', 0, 'musicResponsiveListItemFixedColumnRenderer', 'text', 'runs']),
    );
    durationText ??= _nav(item, [
      'fixedColumns',
      0,
      'musicResponsiveListItemFixedColumnRenderer',
      'text',
      'simpleText',
    ]);
    return SearchResult(
      id: videoId,
      title: title,
      artists: artistIndex == null ? const [] : artistsFromRuns(_flexRuns(item, artistIndex) ?? const []),
      album: _text(albumRuns),
      albumId: _nav(albumRuns?.firstOrNull, ['navigationEndpoint', 'browseEndpoint', 'browseId']) as String?,
      duration: parseDuration(durationText),
      thumbnail: _cover(item) ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      available: available,
    );
  }

  // ---------------------------------------------------------------- artisti

  @override
  Future<Discography> discography(String artist) async {
    final data = await _post('search', {'query': artist, 'params': 'EgWKAQIgAWoMEA4QChADEAQQCRAF'});
    final found = <(String, String)>[];
    for (final item in _shelfItems(data)) {
      final id = _nav(item, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
      final name = _text(_flexRuns(item, 0));
      if (id is String && name != null) found.add((id, name));
    }
    if (found.isEmpty) throw CatalogException('Artista non trovato su YouTube Music');
    final wanted = artist.trim().toLowerCase();
    final (id, name) = found.firstWhere((f) => f.$2.toLowerCase() == wanted, orElse: () => found.first);
    return artistPage(id, fallbackName: name);
  }

  Future<Discography> artistPage(String channelId, {String fallbackName = ''}) async {
    final data = await _post('browse', {'browseId': channelId.replaceFirst(RegExp('^MPLA'), '')});
    final page = parseArtistPage(data);
    Future<List<SearchResult>> full(ArtistShelf? shelf) async {
      if (shelf == null) return const [];
      if (shelf.browseId == null || shelf.params == null) return shelf.items;
      try {
        final more = await _post('browse', {'browseId': shelf.browseId, 'params': shelf.params});
        final items = parseArtistAlbums(more);
        return items.isEmpty ? shelf.items : items;
      } on Exception {
        return shelf.items;
      }
    }

    return Discography(
      id: channelId,
      name: page.name.isEmpty ? fallbackName : page.name,
      thumbnail: page.thumbnail,
      albums: await full(page.albums),
      singles: await full(page.singles),
    );
  }

  static ({String name, String? thumbnail, ArtistShelf? albums, ArtistShelf? singles}) parseArtistPage(
    Map<String, dynamic> data,
  ) {
    final sections =
        (_nav(data, [
                  'contents',
                  'singleColumnBrowseResultsRenderer',
                  ..._tabContent,
                  'sectionListRenderer',
                  'contents',
                ]) ??
                _nav(data, [
                  'contents',
                  'twoColumnBrowseResultsRenderer',
                  ..._tabContent,
                  'sectionListRenderer',
                  'contents',
                ]))
            as List? ??
        const [];
    final header =
        _nav(data, ['header', 'musicImmersiveHeaderRenderer']) ?? _nav(data, ['header', 'musicVisualHeaderRenderer']);
    final name = _text(_nav(header, ['title', 'runs'])) ?? '';
    ArtistShelf? albums;
    ArtistShelf? singles;
    for (final s in sections) {
      final carousel = _nav(s, ['musicCarouselShelfRenderer']);
      if (carousel == null) continue;
      final titleRun = _nav(carousel, ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title', 'runs', 0]);
      final title = (_nav(titleRun, ['text']) as String? ?? '').toLowerCase();
      final isAlbums = title == 'albums';
      final isSingles = title == 'singles & eps' || title == 'singles';
      if (!isAlbums && !isSingles) continue;
      final items = <SearchResult>[
        for (final c in (carousel['contents'] as List? ?? const []))
          if (_nav(c, ['musicTwoRowItemRenderer']) case final Map<String, dynamic> two)
            ?parseTwoRowAlbum(two, defaultType: isAlbums ? 'Album' : 'Single'),
      ];
      final shelf = ArtistShelf(
        items: items,
        browseId: _nav(titleRun, ['navigationEndpoint', 'browseEndpoint', 'browseId']) as String?,
        params: _nav(titleRun, ['navigationEndpoint', 'browseEndpoint', 'params']) as String?,
      );
      if (isAlbums) {
        albums = shelf;
      } else {
        singles = shelf;
      }
    }
    return (
      name: name,
      thumbnail: _bigCover(
        _lastThumb(_nav(header, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'])),
      ),
      albums: albums,
      singles: singles,
    );
  }

  /// La pagina "Albums" o "Singles" completa di un artista (una griglia).
  static List<SearchResult> parseArtistAlbums(Map<String, dynamic> data) {
    final first = _nav(data, [
      'contents',
      'singleColumnBrowseResultsRenderer',
      ..._tabContent,
      'sectionListRenderer',
      'contents',
      0,
    ]);
    final items =
        (_nav(first, ['gridRenderer', 'items']) ?? _nav(first, ['musicCarouselShelfRenderer', 'contents'])) as List?;
    return [
      for (final c in items ?? const [])
        if (_nav(c, ['musicTwoRowItemRenderer']) case final Map<String, dynamic> two) ?parseTwoRowAlbum(two),
    ];
  }

  /// Una copertina con due righe: "Titolo" e "Album • 2013" (o solo "2013").
  static SearchResult? parseTwoRowAlbum(Map<String, dynamic> item, {String defaultType = 'Album'}) {
    final titleRun = _nav(item, ['title', 'runs', 0]);
    final id = _nav(titleRun, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
    if (id is! String) return null;
    final subtitle = (_nav(item, ['subtitle', 'runs']) as List?) ?? const [];
    String? type;
    int? year;
    for (var i = 0; i < subtitle.length; i += 2) {
      final text = subtitle[i]['text'] as String? ?? '';
      if (RegExp(r'^\d{4}$').hasMatch(text)) {
        year = int.parse(text);
      } else if (i == 0) {
        type = text;
      }
    }
    return SearchResult(
      id: id,
      kind: ResultKind.album,
      title: _nav(titleRun, ['text']) as String? ?? '',
      artists: const [],
      type: type ?? defaultType,
      year: year,
      thumbnail: _bigCover(
        _lastThumb(_nav(item, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'])),
      ),
    );
  }

  // --------------------------------------------------------------- un brano

  /// Titolo, artisti e album di un brano preso da un link, dalla coda "Prossimi" di YouTube Music.
  @override
  Future<SearchResult?> song(String videoId) async {
    final data = await _post('next', {
      'videoId': videoId,
      'playlistId': 'RDAMVM$videoId',
      'isAudioOnly': true,
      'enablePersistentPlaylistPanel': true,
      'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
      'watchEndpointMusicSupportedConfigs': {
        'watchEndpointMusicConfig': {'hasPersistentPlaylistPanel': true, 'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV'},
      },
    });
    return parseNext(data, videoId);
  }

  static SearchResult? parseNext(Map<String, dynamic> data, String videoId) {
    final panel = _nav(data, [
      'contents',
      'singleColumnMusicWatchNextResultsRenderer',
      'tabbedRenderer',
      'watchNextTabbedResultsRenderer',
      ..._tabContent,
      'musicQueueRenderer',
      'content',
      'playlistPanelRenderer',
      'contents',
    ]);
    for (final row in (panel as List? ?? const [])) {
      final video =
          _nav(row, ['playlistPanelVideoRenderer']) ??
          _nav(row, ['playlistPanelVideoWrapperRenderer', 'primaryRenderer', 'playlistPanelVideoRenderer']);
      if (video == null || video['videoId'] != videoId) continue;
      final info = parseSongRuns((_nav(video, ['longBylineText', 'runs']) as List?) ?? const []);
      return SearchResult(
        id: videoId,
        title: _text(_nav(video, ['title', 'runs'])) ?? videoId,
        artists: info.artists,
        album: info.album,
        albumId: info.albumId,
        year: info.year,
        duration: parseDuration(_text(_nav(video, ['lengthText', 'runs']))),
        thumbnail: _bigCover(_lastThumb(_nav(video, ['thumbnail', 'thumbnails']))),
      );
    }
    return null;
  }

  // ---------------------------------------------------------------- utilità

  static const _tabContent = ['tabs', 0, 'tabRenderer', 'content'];
  static const _playButton = ['musicItemThumbnailOverlayRenderer', 'content', 'musicPlayButtonRenderer'];
  static const _pageType = ['browseEndpointContextSupportedConfigs', 'browseEndpointContextMusicConfig', 'pageType'];

  static dynamic _nav(dynamic root, List<Object> path) {
    var node = root;
    for (final key in path) {
      if (key is int && node is List) {
        if (key >= node.length) return null;
        node = node[key];
      } else if (key is String && node is Map) {
        node = node[key];
      } else {
        return null;
      }
      if (node == null) return null;
    }
    return node;
  }

  static List<Map<String, dynamic>>? _flexRuns(Map<String, dynamic> item, int index) {
    final runs = _nav(item, ['flexColumns', index, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs']);
    return runs is List ? runs.whereType<Map<String, dynamic>>().toList() : null;
  }

  static String? _text(dynamic runs) => runs is List && runs.isNotEmpty ? runs.first['text'] as String? : null;

  static bool _available(Map<String, dynamic> item) =>
      item['musicItemRendererDisplayPolicy'] != 'MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT';

  static String? _lastThumb(dynamic thumbs) =>
      thumbs is List && thumbs.isNotEmpty ? thumbs.last['url'] as String? : null;

  static String? _cover(Map<String, dynamic> item) =>
      _bigCover(_lastThumb(_nav(item, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'])));

  /// Le miniature finiscono con =w120-h120-...: si chiede la versione grande, come sul server.
  static String? _bigCover(String? url) => url?.replaceFirst(RegExp(r'=w\d+-h\d+[^/]*$'), '=w544-h544-l90-rj');

  static bool _isDuration(String s) => RegExp(r'^(\d+:)*\d+:\d+$').hasMatch(s);

  static Duration? parseDuration(String? text) {
    if (text == null || !_isDuration(text.trim())) return null;
    var seconds = 0;
    for (final part in text.trim().split(':')) {
      seconds = seconds * 60 + int.parse(part);
    }
    return Duration(seconds: seconds);
  }

  /// Gli artisti in una riga "A, B & C": i testi in posizione pari (gli altri sono separatori).
  static List<String> artistsFromRuns(List runs) => [
    for (var i = 0; i < runs.length; i += 2)
      if ((runs[i]['text'] as String? ?? '').trim().isNotEmpty) (runs[i]['text'] as String).trim(),
  ];

  /// Legge una riga del tipo "Song • Artista & Ospite • Album • 3:21" come fa ytmusicapi:
  /// i testi con link a un album sono l'album, quelli a un artista (o senza link) gli artisti,
  /// e poi durata, anno e visualizzazioni.
  static ({List<String> artists, String? album, String? albumId, Duration? duration, int? year}) parseSongRuns(
    List runs, {
    bool skipTypeSpec = false,
  }) {
    var list = runs.whereType<Map>().toList();
    if (skipTypeSpec &&
        list.length > 2 &&
        list[0]['navigationEndpoint'] == null &&
        _runType(list[0]) == 'artist' &&
        list[1]['text'] == ' • ') {
      list = list.sublist(2);
    }
    final artists = <String>[];
    String? album;
    String? albumId;
    Duration? duration;
    int? year;
    for (var i = 0; i < list.length; i += 2) {
      final run = list[i];
      final text = (run['text'] as String? ?? '').trim();
      switch (_runType(run)) {
        case 'album':
          album = text;
          albumId = _nav(run, ['navigationEndpoint', 'browseEndpoint', 'browseId']) as String?;
        case 'artist':
          if (text.isNotEmpty) artists.add(text);
        case 'duration':
          duration = parseDuration(text);
        case 'year':
          year = int.parse(text);
      }
    }
    return (artists: artists, album: album, albumId: albumId, duration: duration, year: year);
  }

  static String _runType(Map run) {
    final text = (run['text'] as String? ?? '').trim();
    if (run['navigationEndpoint'] != null) {
      final id = _nav(run, ['navigationEndpoint', 'browseEndpoint', 'browseId']) as String?;
      return id != null && (id.startsWith('MPRE') || id.contains('release_detail')) ? 'album' : 'artist';
    }
    if (_isDuration(text)) return 'duration';
    if (RegExp(r'^\d{4}$').hasMatch(text)) return 'year';
    // "248 views", "5.4M likes": un testo senza link che comincia con una cifra e ha uno spazio
    // (gli artisti hanno quasi sempre il link; "2Pac" senza spazio resta un artista).
    if (RegExp(r'^\d').hasMatch(text) && (text.contains(' ') || text.contains('\u00a0'))) return 'views';
    return 'artist';
  }
}

/// Da un link (playlist, album, browse) o da un id restituisce l'id di album o playlist.
String collectionId(String source) {
  source = source.trim();
  if (source.startsWith('http')) {
    final uri = Uri.tryParse(source);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null || !(host == 'youtu.be' || host == 'youtube.com' || host.endsWith('.youtube.com'))) {
      throw CatalogException('Serve un link YouTube');
    }
    final list = uri.queryParameters['list'];
    if (list != null && list.isNotEmpty) return list;
    final m = RegExp(r'^/browse/([A-Za-z0-9_-]+)$').firstMatch(uri.path);
    if (m != null) return m.group(1)!;
    throw CatalogException('Il link non contiene né una playlist né un album');
  }
  if (!RegExp(r'^[A-Za-z0-9_-]{10,}$').hasMatch(source)) throw CatalogException('Id di album o playlist non valido');
  return source;
}
