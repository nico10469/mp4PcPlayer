import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mp4player/models/track.dart';
import 'package:mp4player/services/direct_audio.dart';
import 'package:mp4player/services/download_manager.dart';
import 'package:mp4player/services/library_store.dart';
import 'package:mp4player/services/music_catalog.dart';
import 'package:mp4player/services/server_api.dart';
import 'package:mp4player/services/settings.dart';
import 'package:mp4player/services/yt_music.dart';

// Risposte di YouTube Music ridotte all'osso, con la stessa forma di quelle vere (le stesse che legge ytmusicapi).

Map<String, dynamic> run(String text, {String? browseId, String? pageType, String? videoId}) => {
  'text': text,
  if (browseId != null)
    'navigationEndpoint': {
      'browseEndpoint': {
        'browseId': browseId,
        'browseEndpointContextSupportedConfigs': {
          'browseEndpointContextMusicConfig': {'pageType': pageType ?? 'MUSIC_PAGE_TYPE_ARTIST'},
        },
      },
    },
  if (videoId != null)
    'navigationEndpoint': {
      'watchEndpoint': {'videoId': videoId},
    },
};

Map<String, dynamic> flex(List<Map<String, dynamic>> runs) => {
  'musicResponsiveListItemFlexColumnRenderer': {
    'text': {'runs': runs},
  },
};

Map<String, dynamic> thumbs(String url) => {
  'musicThumbnailRenderer': {
    'thumbnail': {
      'thumbnails': [
        {'url': '$url=w60-h60-l90-rj'},
        {'url': '$url=w120-h120-l90-rj'},
      ],
    },
  },
};

Map<String, dynamic> playButton(String videoId) => {
  'musicItemThumbnailOverlayRenderer': {
    'content': {
      'musicPlayButtonRenderer': {
        'playNavigationEndpoint': {
          'watchEndpoint': {'videoId': videoId},
        },
      },
    },
  },
};

Map<String, dynamic> searchResponse(List<Map<String, dynamic>> items) => {
  'responseContext': {'visitorData': 'VISITOR'},
  'contents': {
    'tabbedSearchResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'content': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'musicShelfRenderer': {
                      'contents': [
                        for (final i in items) {'musicResponsiveListItemRenderer': i},
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
      ],
    },
  },
};

final getLucky = {
  'flexColumns': [
    flex([run('Get Lucky', videoId: '5NV6Rdv1a3I')]),
    flex([
      run('Song'),
      run(' • '),
      run('Daft Punk', browseId: 'UCdp'),
      run(', '),
      run('Pharrell Williams', browseId: 'UCpw'),
      run(' & '),
      run('Nile Rodgers', browseId: 'UCnr'),
      run(' • '),
      run('Random Access Memories', browseId: 'MPREb_ram', pageType: 'MUSIC_PAGE_TYPE_ALBUM'),
      run(' • '),
      run('6:09'),
    ]),
  ],
  'overlay': playButton('5NV6Rdv1a3I'),
  'thumbnail': thumbs('https://lh3.googleusercontent.com/ram'),
};

Map<String, dynamic> twoRow(String title, String id, List<String> subtitle) => {
  'musicTwoRowItemRenderer': {
    'title': {
      'runs': [run(title, browseId: id, pageType: 'MUSIC_PAGE_TYPE_ALBUM')],
    },
    'subtitle': {
      'runs': [for (final s in subtitle) run(s)],
    },
    'thumbnailRenderer': thumbs('https://lh3.googleusercontent.com/$id'),
  },
};

Map<String, dynamic> carousel(String title, List<Map<String, dynamic>> items, {String? browseId, String? params}) => {
  'musicCarouselShelfRenderer': {
    'header': {
      'musicCarouselShelfBasicHeaderRenderer': {
        'title': {
          'runs': [
            {
              'text': title,
              if (browseId != null)
                'navigationEndpoint': {
                  'browseEndpoint': {'browseId': browseId, 'params': params},
                },
            },
          ],
        },
      },
    },
    'contents': items,
  },
};

/// Finto YouTube Music: risponde in base all'endpoint e al corpo della richiesta.
MockClient fakeYtMusic({List<Map<String, dynamic>>? requests}) => MockClient((req) async {
  final body = jsonDecode(req.body) as Map<String, dynamic>;
  requests?.add({'path': req.url.path, 'visitor': req.headers['X-Goog-Visitor-Id'], ...body});
  final endpoint = req.url.pathSegments.last;
  Object? response;
  if (endpoint == 'search' && body['params'] == 'EgWKAQIIAWoMEA4QChADEAQQCRAF') {
    response = searchResponse([getLucky]);
  } else if (endpoint == 'search' && body['params'] == 'EgWKAQIYAWoMEA4QChADEAQQCRAF') {
    response = searchResponse([
      {
        'flexColumns': [
          flex([run('Random Access Memories')]),
          flex([run('Album'), run(' • '), run('Daft Punk', browseId: 'UCdp'), run(' • '), run('2013')]),
        ],
        'navigationEndpoint': {
          'browseEndpoint': {'browseId': 'MPREb_ram'},
        },
        'thumbnail': thumbs('https://lh3.googleusercontent.com/ram'),
      },
    ]);
  } else if (endpoint == 'search' && body['params'] == 'EgWKAQIgAWoMEA4QChADEAQQCRAF') {
    response = searchResponse([
      {
        'flexColumns': [
          flex([run('Daft Punk Tribute')]),
        ],
        'navigationEndpoint': {
          'browseEndpoint': {'browseId': 'UCtribute'},
        },
      },
      {
        'flexColumns': [
          flex([run('Daft Punk')]),
        ],
        'navigationEndpoint': {
          'browseEndpoint': {'browseId': 'UCdp'},
        },
      },
    ]);
  } else if (endpoint == 'browse' && body['browseId'] == 'MPREb_ram') {
    response = {
      'contents': {
        'twoColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'musicResponsiveHeaderRenderer': {
                          'title': {
                            'runs': [run('Random Access Memories')],
                          },
                          'subtitle': {
                            'runs': [run('Album'), run(' • '), run('2013')],
                          },
                          'straplineTextOne': {
                            'runs': [run('Daft Punk', browseId: 'UCdp')],
                          },
                          'thumbnail': thumbs('https://lh3.googleusercontent.com/ram'),
                        },
                      },
                    ],
                  },
                },
              },
            },
          ],
          'secondaryContents': {
            'sectionListRenderer': {
              'contents': [
                {
                  'musicShelfRenderer': {
                    'contents': [
                      {
                        'musicResponsiveListItemRenderer': {
                          'flexColumns': [
                            flex([run('Give Life Back to Music', videoId: 'aaaaaaaaaaa')]),
                            flex([]),
                            flex([run('39M plays')]),
                          ],
                          'fixedColumns': [
                            {
                              'musicResponsiveListItemFixedColumnRenderer': {
                                'text': {
                                  'runs': [run('4:35')],
                                },
                              },
                            },
                          ],
                          'overlay': playButton('aaaaaaaaaaa'),
                        },
                      },
                      {
                        'musicResponsiveListItemRenderer': {
                          'flexColumns': [
                            flex([run('Get Lucky', videoId: '5NV6Rdv1a3I')]),
                            flex([
                              run('Daft Punk', browseId: 'UCdp'),
                              run(', '),
                              run('Pharrell Williams', browseId: 'UCpw'),
                              run(' & '),
                              run('Nile Rodgers', browseId: 'UCnr'),
                            ]),
                          ],
                          'overlay': playButton('5NV6Rdv1a3I'),
                        },
                      },
                      {
                        'musicResponsiveListItemRenderer': {
                          'flexColumns': [
                            flex([run('Non disponibile')]),
                          ],
                          'musicItemRendererDisplayPolicy': 'MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT',
                          'playlistItemData': {'videoId': 'bbbbbbbbbbb'},
                        },
                      },
                    ],
                  },
                },
              ],
            },
          },
        },
      },
    };
  } else if (endpoint == 'browse' && body['browseId'] == 'UCdp' && body['params'] == null) {
    response = {
      'header': {
        'musicImmersiveHeaderRenderer': {
          'title': {
            'runs': [run('Daft Punk')],
          },
        },
      },
      'contents': {
        'singleColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      carousel(
                        'Albums',
                        [
                          twoRow('Random Access Memories', 'MPREb_ram', ['2013']),
                        ],
                        browseId: 'UCdp_albums',
                        params: 'albums',
                      ),
                      carousel('Singles & EPs', [
                        twoRow('Get Lucky', 'MPREb_gl', ['Single', ' • ', '2013']),
                      ]),
                      carousel('Fans might also like', [twoRow('Justice', 'UCjustice', [])]),
                    ],
                  },
                },
              },
            },
          ],
        },
      },
    };
  } else if (endpoint == 'browse' && body['browseId'] == 'UCdp_albums') {
    expect(body['params'], 'albums');
    response = {
      'contents': {
        'singleColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'gridRenderer': {
                          'items': [
                            twoRow('Random Access Memories', 'MPREb_ram', ['Album', ' • ', '2013']),
                            twoRow('Discovery', 'MPREb_disc', ['Album', ' • ', '2001']),
                            twoRow('Homework', 'MPREb_home', ['Album', ' • ', '1997']),
                          ],
                        },
                      },
                    ],
                  },
                },
              },
            },
          ],
        },
      },
    };
  } else if (endpoint == 'next') {
    response = {
      'contents': {
        'singleColumnMusicWatchNextResultsRenderer': {
          'tabbedRenderer': {
            'watchNextTabbedResultsRenderer': {
              'tabs': [
                {
                  'tabRenderer': {
                    'content': {
                      'musicQueueRenderer': {
                        'content': {
                          'playlistPanelRenderer': {
                            'contents': [
                              {
                                'playlistPanelVideoRenderer': {
                                  'videoId': body['videoId'],
                                  'title': {
                                    'runs': [run('Get Lucky')],
                                  },
                                  'longBylineText': {
                                    'runs': [
                                      run('Daft Punk', browseId: 'UCdp'),
                                      run(' & '),
                                      run('Pharrell Williams', browseId: 'UCpw'),
                                      run(' • '),
                                      run('Random Access Memories', browseId: 'MPREb_ram'),
                                      run(' • '),
                                      run('2013'),
                                    ],
                                  },
                                  'lengthText': {
                                    'runs': [run('6:09')],
                                  },
                                  'thumbnail': {
                                    'thumbnails': [
                                      {'url': 'https://lh3.googleusercontent.com/ram=w60-h60-l90-rj'},
                                    ],
                                  },
                                },
                              },
                            ],
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    };
  }
  if (response == null) return http.Response('{}', 404);
  return http.Response.bytes(utf8.encode(jsonEncode(response)), 200);
});

/// Finto download dell'audio: scrive qualche byte come farebbe YouTube.
class FakeAudio implements AudioFetcher {
  final fetched = <String>[];

  @override
  Future<File> fetch(String videoId, File Function(String ext) target, {void Function(double)? onProgress}) async {
    fetched.add(videoId);
    onProgress?.call(0.5);
    final f = target('m4a');
    await f.writeAsBytes([1, 2, 3]);
    return f;
  }

  @override
  Future<SearchResult?> describe(String videoId) async => null;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('mp4direct'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('songs keep the main and featured artists, not the "Song" label', () async {
    final requests = <Map<String, dynamic>>[];
    final yt = YtMusicClient(client: fakeYtMusic(requests: requests));
    final songs = await yt.search('get lucky');
    expect(songs.single.id, '5NV6Rdv1a3I');
    expect(songs.single.artists, ['Daft Punk', 'Pharrell Williams', 'Nile Rodgers']);
    expect(songs.single.album, 'Random Access Memories');
    expect(songs.single.duration, const Duration(minutes: 6, seconds: 9));
    expect(songs.single.thumbnail, 'https://lh3.googleusercontent.com/ram=w544-h544-l90-rj');

    final albums = await yt.search('ram', kind: ResultKind.album);
    expect(albums.single.id, 'MPREb_ram');
    expect(albums.single.type, 'Album');
    expect(albums.single.year, 2013);
    expect(albums.single.artist, 'Daft Punk');
    // Dalla seconda richiesta si manda il visitor id ricevuto con la prima.
    expect(requests.map((r) => r['visitor']), [null, 'VISITOR']);
    expect(requests.first['context']['client']['clientName'], 'WEB_REMIX');
  });

  test('an album page gives its tracks with the album artist when the row has none', () async {
    final yt = YtMusicClient(client: fakeYtMusic());
    final album = await yt.collection('https://music.youtube.com/browse/MPREb_ram');
    expect(album.kind, ResultKind.album);
    expect(album.title, 'Random Access Memories');
    expect(album.artist, 'Daft Punk');
    expect(album.year, 2013);
    // La riga grigia (non disponibile) non c'è.
    expect(album.tracks.map((t) => t.title), ['Give Life Back to Music', 'Get Lucky']);
    expect(album.tracks.first.artists, ['Daft Punk']);
    expect(album.tracks.first.duration, const Duration(minutes: 4, seconds: 35));
    expect(album.tracks.last.artists, ['Daft Punk', 'Pharrell Williams', 'Nile Rodgers']);
    expect(album.tracks.last.thumbnail, album.thumbnail);
  });

  test('the discography finds the right artist and reads every album', () async {
    final yt = YtMusicClient(client: fakeYtMusic());
    final d = await yt.discography('daft punk');
    expect(d.id, 'UCdp');
    expect(d.name, 'Daft Punk');
    expect(d.albums.map((a) => (a.title, a.year)), [
      ('Random Access Memories', 2013),
      ('Discovery', 2001),
      ('Homework', 1997),
    ]);
    expect(d.singles.single.type, 'Single');
    expect(d.singles.single.year, 2013);
  });

  test('a pasted link gets title and main artists from the up next queue', () async {
    final yt = YtMusicClient(client: fakeYtMusic());
    final s = await yt.song('5NV6Rdv1a3I');
    expect(s!.title, 'Get Lucky');
    expect(s.artists, ['Daft Punk', 'Pharrell Williams']);
    expect(s.album, 'Random Access Memories');
    expect(s.year, 2013);
  });

  test('without YouTube Music data the channel and the featured guests are the artists', () {
    expect(mainArtistsFromVideo('Daft Punk', 'Get Lucky (feat. Pharrell Williams & Nile Rodgers)'), [
      'Daft Punk',
      'Pharrell Williams',
      'Nile Rodgers',
    ]);
    expect(mainArtistsFromVideo('Sia', 'Chandelier (Official Video)'), ['Sia']);
    expect(videoIdOf('https://music.youtube.com/watch?v=5NV6Rdv1a3I&list=RD'), '5NV6Rdv1a3I');
    expect(videoIdOf('https://youtu.be/5NV6Rdv1a3I?si=x'), '5NV6Rdv1a3I');
    expect(videoIdOf('https://www.youtube.com/shorts/5NV6Rdv1a3I'), '5NV6Rdv1a3I');
    expect(videoIdOf('https://evil.example/watch?v=5NV6Rdv1a3I'), isNull);
    expect(splitArtists('Simon & Garfunkel, Paul Simon'), ['Simon & Garfunkel', 'Paul Simon']);
  });

  test('on the device a download needs no server and keeps the main artists', () async {
    final library = LibraryStore(dir);
    await library.load();
    final audio = FakeAudio();
    final noServer = ServerApi(
      baseUrl: 'http://server',
      client: MockClient((req) async {
        // Solo la copertina passa dalla rete; il server non viene mai chiamato.
        expect(req.url.host, 'lh3.googleusercontent.com');
        return http.Response.bytes([9, 9], 200);
      }),
    );
    final yt = YtMusicClient(client: fakeYtMusic());
    final downloads = DownloadManager(
      library: library,
      api: noServer,
      mode: DownloadMode.device,
      music: yt,
      audio: audio,
    );
    expect(downloads.catalog, same(yt));

    final result = (await downloads.catalog.search('get lucky')).single;
    final track = await downloads.download(result.id, result: result);
    expect(downloads.stateOf(result.id)?.phase, DownloadPhase.done);
    expect(track!.id, '5NV6Rdv1a3I');
    expect(track.artist, 'Daft Punk, Pharrell Williams, Nile Rodgers');
    expect(track.artistNames, ['Daft Punk', 'Pharrell Williams', 'Nile Rodgers']);
    expect(track.album, 'Random Access Memories');
    expect(track.fileName, 'Daft Punk, Pharrell Williams, Nile Rodgers - Get Lucky.m4a');
    expect(await library.audioFile(track).readAsBytes(), [1, 2, 3]);
    expect(await library.coverFile(track)!.readAsBytes(), [9, 9]);

    // Un link incollato: i dati arrivano dalla coda di YouTube Music.
    final link = await downloads.download('https://youtu.be/aaaaaaaaaaa', source: 'https://youtu.be/aaaaaaaaaaa');
    expect(link!.id, 'aaaaaaaaaaa');
    expect(link.artists, ['Daft Punk', 'Pharrell Williams']);
    expect(audio.fetched, ['5NV6Rdv1a3I', 'aaaaaaaaaaa']);

    // Dopo un riavvio gli artisti ci sono ancora, uno per uno.
    final reloaded = LibraryStore(dir);
    await reloaded.load();
    expect(reloaded.byId('5NV6Rdv1a3I')!.artists, ['Daft Punk', 'Pharrell Williams', 'Nile Rodgers']);
  });

  test('play counts add up and survive a reload; old songs keep their artist', () async {
    final library = LibraryStore(dir);
    await library.load();
    await library.recordPlay('a');
    await library.recordPlay('a');
    await library.recordPlay('b');
    final reloaded = LibraryStore(dir);
    await reloaded.load();
    expect(reloaded.playCount('a'), 2);
    expect(reloaded.playCount('b'), 1);
    expect(reloaded.playCount('c'), 0);

    // Un brano delle versioni precedenti (senza elenco) resta sotto il suo artista intero.
    final old = Track.fromJson({
      'id': 'x',
      'title': 'T',
      'artist': 'Sia · Greg Kurstin · Jesse Shatkin',
      'fileName': 'x.m4a',
      'addedAt': 0,
    });
    expect(old.artistNames, ['Sia · Greg Kurstin · Jesse Shatkin']);
    // Cambiando l'artista a mano si rilegge l'elenco.
    final edited = old.withMetadata(
      title: 'T',
      artist: 'Sia, Sean Paul',
      album: '',
      albumArtist: '',
      genre: '',
      year: null,
    );
    expect(edited.artistNames, ['Sia', 'Sean Paul']);
  });

  test('the server catalog reads the discography and sends the artists of a search', () async {
    final sent = <Map<String, dynamic>>[];
    final api = ServerApi(
      baseUrl: 'http://server',
      client: MockClient((req) async {
        if (req.url.path == '/artist') {
          expect(req.url.queryParameters['name'], 'Sia');
          return http.Response(
            jsonEncode({
              'id': 'UCsia',
              'name': 'Sia',
              'albums': [
                {'kind': 'album', 'id': 'MPREb_1', 'title': '1000 Forms of Fear', 'artist': 'Sia', 'year': 2014},
              ],
              'singles': [],
            }),
            200,
          );
        }
        sent.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'id': 'j', 'status': 'queued', 'progress': 0}), 202);
      }),
    );
    final d = await api.discography('Sia');
    expect(d.albums.single.title, '1000 Forms of Fear');
    expect(d.albums.single.kind, ResultKind.album);
    await api.startDownload('2vjPBrBU-TM', artists: ['Sia', 'Sean Paul']);
    expect(sent.single['artists'], ['Sia', 'Sean Paul']);
    expect(d, isA<Discography>());
  });

  Map<String, dynamic> format(int itag, String mime, int bitrate, {String? url, Map<String, dynamic>? extra}) => {
    'itag': itag,
    'mimeType': mime,
    'bitrate': bitrate,
    'contentLength': '10',
    if (url != null) 'url': url else 'signatureCipher': 's=abc&url=https://x',
    ...?extra,
  };

  test('player response: AAC first, no dubbed or DRC copies, no ciphered links', () {
    final data = {
      'playabilityStatus': {'status': 'OK'},
      'streamingData': {
        'adaptiveFormats': [
          format(137, 'video/mp4; codecs="avc1.640028"', 4000000, url: 'https://v/137'),
          format(139, 'audio/mp4; codecs="mp4a.40.5"', 50000, url: 'https://a/139'),
          format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000, url: 'https://a/140'),
          format(141, 'audio/mp4; codecs="mp4a.40.2"', 260000),
          format(140, 'audio/mp4; codecs="mp4a.40.2"', 140000, url: 'https://a/140drc', extra: {'isDrc': true}),
          format(
            140,
            'audio/mp4; codecs="mp4a.40.2"',
            150000,
            url: 'https://a/140es',
            extra: {
              'audioTrack': {'displayName': 'Spanish', 'audioIsDefault': false},
            },
          ),
          format(251, 'audio/webm; codecs="opus"', 160000, url: 'https://a/251'),
        ],
      },
    };
    final streams = parsePlayer(data, userAgent: 'vr');
    expect(streams.map((s) => s.url), ['https://a/139', 'https://a/140', 'https://a/251']);
    expect(pickAudio(streams)!.url, 'https://a/140');
    expect(pickAudio(streams)!.ext, 'm4a');
    expect(pickAudio(streams)!.userAgent, 'vr');
    final opus = streams.where((s) => !s.isAac).toList();
    expect(pickAudio(opus)!.ext, 'webm');
    expect(pickAudio(opus, iosOnly: true), isNull);
  });

  test('downloads the audio itself: Quest client, visitor id retry, file in pieces', () async {
    final audio = List<int>.generate(10, (i) => i);
    final players = <Map<String, dynamic>>[];
    final ranges = <String>[];
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/player')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        players.add({...body, 'header': req.headers['X-Goog-Visitor-Id']});
        final client = body['context']['client'] as Map<String, dynamic>;
        expect(req.headers['User-Agent'], contains('vr.oculus'));
        if (client['visitorData'] == null) {
          return http.Response(
            jsonEncode({
              'playabilityStatus': {'status': 'LOGIN_REQUIRED', 'reason': 'Sign in to confirm you are not a bot'},
              'responseContext': {'visitorData': 'CgtWSVNJVE9S'},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'playabilityStatus': {'status': 'OK'},
            'streamingData': {
              'adaptiveFormats': [format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000, url: 'https://gv/140')],
            },
          }),
          200,
        );
      }
      expect(req.url.toString(), 'https://gv/140');
      expect(req.headers['User-Agent'], contains('vr.oculus'));
      final range = req.headers['Range']!;
      ranges.add(range);
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
      final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
      return http.Response.bytes(audio.sublist(a, b + 1), 206);
    });
    final fetcher = YoutubeAudioFetcher(client: client, chunkSize: 4, iosOnly: true);
    final progress = <double>[];
    final file = await fetcher.fetch('dQw4w9WgXcQ', (ext) => File('${dir.path}/song.$ext'), onProgress: progress.add);

    expect(file.path, endsWith('song.m4a'));
    expect(file.readAsBytesSync(), audio);
    expect(File('${file.path}.part').existsSync(), isFalse);
    expect(ranges, ['bytes=0-3', 'bytes=4-7', 'bytes=8-9']);
    expect(progress.last, 1.0);
    expect(players, hasLength(2));
    expect(players.first['context']['client']['clientName'], 'ANDROID_VR');
    expect(players.last['context']['client']['visitorData'], 'CgtWSVNJVE9S');
    expect(players.last['header'], 'CgtWSVNJVE9S');
  });

  test('if YouTube refuses the first client, the next one is tried', () async {
    final versions = <String>[];
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final version = body['context']['client']['clientVersion'] as String;
      versions.add(version);
      if (version == PlayerClient.androidVr.version) return http.Response('{}', 403);
      return http.Response(
        jsonEncode({
          'playabilityStatus': {'status': 'OK'},
          'streamingData': {
            'adaptiveFormats': [format(251, 'audio/webm; codecs="opus"', 160000, url: 'https://gv/251')],
          },
        }),
        200,
      );
    });
    final streams = await YoutubeAudioFetcher(client: client).streams('dQw4w9WgXcQ');
    expect(streams.single.itag, 251);
    expect(versions, [PlayerClient.androidVr.version, PlayerClient.android.version]);
  });

  test('a refused link is retried with range= in the URL, then with the next client', () async {
    final audio = List<int>.generate(10, (i) => i);
    final players = <String>[];
    final gets = <String>[];
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/player')) {
        final c = (jsonDecode(req.body) as Map<String, dynamic>)['context']['client'] as Map<String, dynamic>;
        final name = '${c['clientName']} ${c['clientVersion']}';
        players.add(name);
        final url = c['clientName'] == 'ANDROID' ? 'https://gv/android' : 'https://gv/vr?id=${c['clientVersion']}';
        return http.Response(
          jsonEncode({
            'playabilityStatus': {'status': 'OK'},
            'streamingData': {
              'adaptiveFormats': [format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000, url: url)],
            },
          }),
          200,
        );
      }
      final range = req.headers['Range'] ?? 'query ${req.url.queryParameters['range']}';
      gets.add('${req.url.path} $range');
      // Il visore viene rifiutato in tutti e due i modi; l'app Android passa con &range=.
      if (req.url.path == '/vr' || req.headers['Range'] != null) return http.Response('', 403);
      final m = RegExp(r'(\d+)-(\d+)').firstMatch(req.url.queryParameters['range']!)!;
      return http.Response.bytes(audio.sublist(int.parse(m.group(1)!), int.parse(m.group(2)!) + 1), 206);
    });
    final fetcher = YoutubeAudioFetcher(client: client, chunkSize: 6, iosOnly: true, retryDelay: Duration.zero);
    final file = await fetcher.fetch('dQw4w9WgXcQ', (ext) => File('${dir.path}/song.$ext'));

    expect(file.readAsBytesSync(), audio);
    expect(players, ['ANDROID_VR 1.65.10', 'ANDROID 20.10.38']);
    expect(gets, ['/vr bytes=0-5', '/vr query 0-5', '/android bytes=0-5', '/android query 0-5', '/android query 6-9']);
  });

  test('errors are short and say what to do', () {
    final dns = http.ClientException(
      "SocketException: Failed host lookup: 'rr6---sn-fpoq-4jvz.googlevideo.com' (OS Error: No address associated with hostname, errno = 7)",
      Uri.parse('https://rr6---sn-fpoq-4jvz.googlevideo.com/videoplayback?expire=1&sig=abc'),
    );
    expect(shortError(dns), 'indirizzo non trovato (rr6---sn-fpoq-4jvz.googlevideo.com)');
    final offline = downloadFailure(['ANDROID_VR 1.65.10: ${shortError(dns)}', 'IOS: rete: Connection reset']);
    expect(offline, startsWith('Non riesco a raggiungere YouTube'));
    expect(offline, isNot(contains('videoplayback')));
    final refused = downloadFailure([
      'ANDROID_VR 1.65.10 (itag 140): ${shortError(const AudioHttpException(403))}',
      'ANDROID: ${shortError(dns)}',
    ]);
    expect(refused, startsWith('YouTube ha rifiutato il download'));
    expect(refused, contains('rifiutato (403)'));
  });

  test('when YouTube asks "are you a bot?" no other client is tried', () async {
    final players = <String>[];
    final client = MockClient((req) async {
      final c = (jsonDecode(req.body) as Map<String, dynamic>)['context']['client'] as Map<String, dynamic>;
      players.add('${c['clientName']}');
      return http.Response(
        jsonEncode({
          'playabilityStatus': {'status': 'LOGIN_REQUIRED', 'reason': 'Sign in to confirm you are not a bot'},
        }),
        200,
      );
    });
    final fetcher = YoutubeAudioFetcher(client: client, retryDelay: Duration.zero);
    await expectLater(
      fetcher.fetch('dQw4w9WgXcQ', (ext) => File('${dir.path}/song.$ext')),
      throwsA(isA<CatalogException>().having((e) => e.message, 'message', startsWith('YouTube ha bloccato per un po'))),
    );
    expect(players, ['ANDROID_VR']);
  });
}
