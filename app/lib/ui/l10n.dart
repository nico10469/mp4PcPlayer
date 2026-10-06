import 'dart:ui';

import '../services/settings.dart';

/// Le lingue dell'interfaccia.
enum AppLanguage { italian, english }

/// La lingua in uso. La imposta l'app dalle Impostazioni; nei test resta l'italiano.
AppLanguage appLanguage = AppLanguage.italian;

/// La lingua da usare per una scelta delle Impostazioni: con "come il sistema" è l'italiano
/// se il dispositivo è in italiano, altrimenti l'inglese.
AppLanguage resolveLanguage(LanguageChoice choice, [Locale? system]) => switch (choice) {
  LanguageChoice.italian => AppLanguage.italian,
  LanguageChoice.english => AppLanguage.english,
  LanguageChoice.system =>
    (system ?? PlatformDispatcher.instance.locale).languageCode == 'it' ? AppLanguage.italian : AppLanguage.english,
};

/// Il testo [it] nella lingua dell'app. I segnaposto `{nome}` si riempiono con [args]:
/// `tr('{n} brani', {'n': 3})` → "3 brani" o "3 songs".
String tr(String it, [Map<String, Object?> args = const {}]) {
  var text = appLanguage == AppLanguage.english ? (english[it] ?? it) : it;
  args.forEach((key, value) => text = text.replaceAll('{$key}', '$value'));
  return text;
}

/// "1 brano" / "{n} brani", nella lingua dell'app.
String plural(int n, String one, String many) => n == 1 ? tr(one) : tr(many, {'n': n});

/// Le traduzioni inglesi, con il testo italiano come chiave. Un testo che manca resta in
/// italiano (il test in test/l10n_test.dart controlla che non ne manchi nessuno).
const english = <String, String>{
  // Libreria e navigazione
  'Libreria': 'Library',
  'Cerca': 'Search',
  'Playlist': 'Playlists',
  'Artisti': 'Artists',
  'Brani': 'Songs',
  'Album': 'Albums',
  'Download': 'Download',
  'Impostazioni': 'Settings',
  'Preferiti': 'Favorites',
  'Preferito': 'Favorite',
  'La tua libreria è vuota': 'Your library is empty',
  'I brani che scarichi compaiono qui.': 'The songs you download show up here.',
  'Scarica musica': 'Download music',
  'Aggiunti di recente': 'Recently added',
  'Vedi tutti': 'See all',
  'Vedi tutte': 'See all',
  'Nuova playlist': 'New playlist',
  'Crea': 'Create',
  '1 brano': '1 song',
  '{n} brani': '{n} songs',
  '1 minuto': '1 minute',
  '{n} minuti': '{n} minutes',
  '{songs}, {h} {hours} e {m} minuti': '{songs}, {h} {hours} and {m} minutes',
  'ora': 'hour',
  'ore': 'hours',

  // Barra in basso e player
  'Non in riproduzione': 'Not playing',
  'Scegli un brano dalla libreria': 'Pick a song from your library',
  'Precedente': 'Previous',
  'Successivo': 'Next',
  'Pausa': 'Pause',
  'Riproduci': 'Play',
  'Casuale': 'Shuffle',
  'Ripeti': 'Repeat',
  'Chiudi': 'Close',
  'In coda': 'Up next',
  'Info brano': 'Song info',
  'Timer di spegnimento': 'Sleep timer',
  'Timer: {when}': 'Timer: {when}',
  'Mi piace': 'Like',
  'Non mi piace più': 'Unlike',

  // Coda e timer
  'Svuota': 'Clear',
  'IN RIPRODUZIONE': 'NOW PLAYING',
  'NIENTE IN CODA': 'NOTHING UP NEXT',
  'A SEGUIRE (CASUALE)': 'UP NEXT (SHUFFLED)',
  'A SEGUIRE': 'UP NEXT',
  'Alla fine del brano': 'At the end of the song',
  'alla fine del brano': 'at the end of the song',
  'Spegni il timer': 'Turn off the timer',
  'fra {n} min': 'in {n} min',

  // Menu di un brano
  'Altre azioni': 'More actions',
  'Rimuovi dalla playlist': 'Remove from playlist',
  'Elimina dalla libreria': 'Delete from library',
  'Aggiungi a playlist…': 'Add to playlist…',
  'Aggiungi a playlist': 'Add to playlist',
  'Riproduci dopo': 'Play next',
  'Aggiungi in coda': 'Add to queue',
  'Mostra artista': 'Show artist',
  'Eliminare il brano?': 'Delete this song?',
  '"{title}" verrà cancellato da questo dispositivo e da tutte le playlist.':
      '"{title}" will be deleted from this device and from every playlist.',
  'Annulla': 'Cancel',
  'Elimina': 'Delete',
  '"{title}" sarà il prossimo': '"{title}" will play next',
  '"{title}" aggiunto in coda': '"{title}" added to the queue',
  'Nuova playlist…': 'New playlist…',
  'Aggiunto a "{name}"': 'Added to "{name}"',

  // Artisti e album
  'Artista sconosciuto': 'Unknown artist',
  'Album sconosciuto': 'Unknown album',
  'Nessun artista': 'No artists',
  'Gli artisti dei brani che scarichi compaiono qui.': 'The artists of the songs you download show up here.',
  'Titolo': 'Title',
  'Anno di uscita': 'Release year',
  'Ordina': 'Sort',
  'I più ascoltati': 'Most played',
  'Non riesco a leggere la discografia completa adesso: ecco gli album che hai in libreria.':
      'I can\'t load the full discography right now: here are the albums in your library.',
  'Singoli ed EP': 'Singles and EPs',
  'riproduzione': 'play',
  'riproduzioni': 'plays',
  'Nessun album': 'No albums',
  'In libreria': 'In library',

  // Preferiti
  'Ancora nessun preferito': 'No favorites yet',
  'Tocca il cuore mentre ascolti un brano, o scegli "Mi piace" dal menu "…".':
      'Tap the heart while a song plays, or choose "Like" from the "…" menu.',

  // Playlist
  'Modificate di recente': 'Recently edited',
  'Nome': 'Name',
  'Cerchi le tue playlist?': 'Looking for your playlists?',
  'Le playlist che crei compaiono qui.': 'The playlists you create show up here.',
  'Cerca nelle playlist': 'Search playlists',
  'Opzioni playlist': 'Playlist options',
  'Modifica': 'Edit',
  'Elimina playlist': 'Delete playlist',
  'Playlist vuota': 'Empty playlist',
  'Aggiungi brani dalla tua libreria.': 'Add songs from your library.',
  'Aggiungi musica': 'Add music',
  'AGGIORNATA OGGI': 'UPDATED TODAY',
  'AGGIORNATA IERI': 'UPDATED YESTERDAY',
  'AGGIORNATA {n} GIORNI FA': 'UPDATED {n} DAYS AGO',
  'AGGIORNATA IL {date}': 'UPDATED ON {date}',
  'Scegli la copertina': 'Choose the cover',
  'Modifica playlist': 'Edit playlist',
  'Fine': 'Done',
  'Nome playlist': 'Playlist name',
  'Descrizione': 'Description',
  'Cerca nella libreria': 'Search your library',
  'Nessun brano': 'No songs',
  'Scarica qualcosa per aggiungerlo alle playlist.': 'Download something to add it to your playlists.',

  // Ricerca
  'Brani, artisti, album, generi': 'Songs, artists, albums, genres',
  'Scrivi per cercare nella tua libreria. Premi Invio per cercare anche su YouTube e scaricare.':
      'Type to search your library. Press Enter to also search YouTube and download.',
  'Nella tua libreria': 'In your library',
  'Nessun brano trovato.': 'No songs found.',
  'Su YouTube': 'On YouTube',
  'Cerca "{q}" su YouTube': 'Search YouTube for "{q}"',
  'Cerca nei brani': 'Search songs',

  // Download
  '"{title}" aggiunto alla libreria': '"{title}" added to your library',
  'Download fallito: {error}': 'Download failed: {error}',
  'Brani, album, playlist o link YouTube': 'Songs, albums, playlists or a YouTube link',
  'Cerca su YouTube Music: trovi i brani ufficiali (solo audio, con la copertina dell\'album), '
          'gli album e le playlist da scaricare interi. Puoi anche incollare un link.':
      'Search YouTube Music: you get the official tracks (audio only, with the album cover), and '
      'whole albums and playlists to download. You can also paste a link.',
  'Scaricati {done} di {total}…': 'Downloaded {done} of {total}…',
  'Nessun brano disponibile': 'No songs available',
  'Tutti i brani sono in libreria': 'Every song is in your library',
  'Scarica tutto ({n})': 'Download all ({n})',
  'Scarica i {n} mancanti': 'Download the {n} missing',
  'Playlist "{title}" salvata': 'Playlist "{title}" saved',
  '"{title}" scaricato': '"{title}" downloaded',
  '1 brano non disponibile': '1 song unavailable',
  '{n} brani non disponibili': '{n} songs unavailable',
  'In fila': 'Queued',
  'Già scaricato': 'Already downloaded',
  'Riprova': 'Try again',
  'Scarica': 'Download',

  // Impostazioni
  'CARTELLA DELLA MUSICA': 'MUSIC FOLDER',
  'Cartella della musica': 'Music folder',
  'Cartella scelta da te': 'Your folder',
  'Cartella dell\'app': 'The app\'s folder',
  'Cartella aggiornata': 'Folder updated',
  'Senza il permesso di accedere ai file non posso usare le cartelle del telefono.':
      'Without permission to access files I can\'t use the phone\'s folders.',
  'Non riesco a usare questa cartella: {error}': 'I can\'t use this folder: {error}',
  'Nessun brano nuovo nella cartella': 'No new songs in the folder',
  'Sposto i brani…': 'Moving the songs…',
  'Mostra i brani nell\'app File': 'Show the songs in the Files app',
  'Scegli la cartella': 'Choose the folder',
  'Cerca brani nuovi': 'Look for new songs',
  'Usa quella dell\'app': 'Use the app\'s folder',
  'I brani scaricati vengono salvati qui. Scegliendo una cartella nuova ci sposto i brani che hai già, '
          'e aggiungo alla libreria i file audio che ci trovi dentro. Sul telefono ti chiedo prima il permesso '
          'di accedere ai file.':
      'Downloaded songs are saved here. If you choose a new folder I move your songs there, and add to the '
      'library any audio files already in it. On a phone I ask for permission to access files first.',
  '1 brano spostato': '1 song moved',
  '{n} brani spostati': '{n} songs moved',
  '1 brano trovato': '1 song found',
  '{n} brani trovati': '{n} songs found',
  '1 brano aggiunto': '1 song added',
  '{n} brani aggiunti': '{n} songs added',
  'DOWNLOAD': 'DOWNLOAD',
  'Nell\'app': 'In the app',
  'Con il server': 'With the server',
  'Il server scarica con yt-dlp e manda i brani all\'app. Si aggiorna senza cambiare l\'app.':
      'The server downloads with yt-dlp and sends the songs to the app. It updates without changing the app.',
  'La musica si cerca su YouTube Music e si scarica su questo telefono con yt-dlp, lo stesso '
          'programma del server, senza bisogno del server. Se YouTube cambia qualcosa e i download '
          'smettono di funzionare, aggiorna il motore qui sotto.':
      'Music is searched on YouTube Music and downloaded on this phone with yt-dlp, the same program the '
      'server uses, with no server needed. If YouTube changes something and downloads stop working, update '
      'the engine below.',
  'La musica si cerca su YouTube Music e si scarica direttamente su questo dispositivo, '
          'senza bisogno del server. Se un giorno YouTube cambia qualcosa e i download smettono '
          'di funzionare, aggiorna l\'app o usa il server.':
      'Music is searched on YouTube Music and downloaded straight to this device, with no server needed. If '
      'YouTube changes something one day and downloads stop working, update the app or use the server.',
  'Indirizzo': 'Address',
  'http://IP-DEL-PC:8000': 'http://PC-IP:8000',
  'Token (facoltativo)': 'Token (optional)',
  'Verifica in corso…': 'Checking…',
  'Salva e prova la connessione': 'Save and test the connection',
  'Connesso. yt-dlp {version}': 'Connected. yt-dlp {version}',
  'Il server è il programma Python nella cartella "server" del progetto: tienilo acceso su un PC '
          'o un Raspberry Pi. I brani già scaricati si ascoltano anche senza server.':
      'The server is the Python program in the project\'s "server" folder: keep it running on a PC or a '
      'Raspberry Pi. Songs you already downloaded play without the server too.',
  'Motore download': 'Download engine',
  'Aggiorna motore download': 'Update download engine',
  'Aggiornamento in corso…': 'Updating…',
  'Aggiornato a {version}': 'Updated to {version}',
  'una nuova versione': 'a new version',
  'È già l\'ultima versione': 'Already the latest version',
  'Aggiornamento non riuscito: {error}': 'Update failed: {error}',
  'Il motore non si è avviato: {error}': 'The engine didn\'t start: {error}',
  'ASPETTO': 'APPEARANCE',
  'Scuro': 'Dark',
  'Chiaro': 'Light',
  'Sistema': 'System',
  'RIPRODUZIONE': 'PLAYBACK',
  'Dissolvenza tra i brani': 'Fade between songs',
  'No': 'Off',
  'Alla fine di ogni brano il volume scende piano, e il brano dopo entra allo stesso modo.':
      'At the end of each song the volume fades out, and the next song fades in the same way.',
  'Equalizzatore': 'Equalizer',
  'Attivo': 'On',
  'Spento': 'Off',
  'L\'equalizzatore non è disponibile su questo telefono.': 'The equalizer isn\'t available on this phone.',
  'Riporta tutto a zero': 'Reset all to zero',

  // Info brano
  'Cambia copertina': 'Change cover',
  'Artista': 'Artist',
  'Artista dell\'album': 'Album artist',
  'Genere': 'Genre',
  'Anno': 'Year',
  'Testo': 'Lyrics',
  'TESTO': 'LYRICS',
  'Durata': 'Duration',
  'Formato': 'Format',
  'Dimensione': 'Size',
  'Aggiunto il': 'Added on',
  'Fonte': 'Source',
  'Non disponibile': 'Not available',
  'Non riesco a raggiungere LRCLIB: controlla la connessione a internet.':
      'I can\'t reach LRCLIB: check your internet connection.',
  'Cerco il testo…': 'Looking for the lyrics…',
  'Testo non ancora cercato.': 'Lyrics not searched yet.',
  'Testo non trovato (o brano strumentale).': 'Lyrics not found (or an instrumental).',
  'Cerca di nuovo': 'Search again',
  'Testo in lingua originale da LRCLIB o dai tag del file. Puoi correggerlo con Modifica.':
      'Lyrics in the original language, from LRCLIB or the file\'s tags. You can fix them with Edit.',
  'I dati arrivano da YouTube tramite yt-dlp. Se qualcosa manca o è sbagliato, tocca Modifica.':
      'The details come from YouTube through yt-dlp. If something is missing or wrong, tap Edit.',
};
