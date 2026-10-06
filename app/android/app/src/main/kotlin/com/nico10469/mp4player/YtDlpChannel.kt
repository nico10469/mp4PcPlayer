package com.nico10469.mp4player

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * yt-dlp vero dentro l'app (canale "carrots/ytdlp", vedi ytdlp_audio.dart), con il Python e il
 * QuickJS di youtubedl-android. Il programma yt-dlp si aggiorna dall'app, senza una nuova versione.
 */
class YtDlpChannel(context: Context, messenger: BinaryMessenger) {
    private val context = context.applicationContext
    private val channel = MethodChannel(messenger, "carrots/ytdlp")
    private val worker = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var ready = false

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "version" -> run(result) { version() }
            "update" -> run(result) {
                val status = YoutubeDL.getInstance().updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)
                mapOf("updated" to (status == YoutubeDL.UpdateStatus.DONE), "version" to version())
            }
            "download" -> {
                val url = call.argument<String>("url")!!
                val dir = call.argument<String>("dir")!!
                val id = call.argument<String>("id")!!
                run(result) { download(url, File(dir), id) }
            }
            "cancel" -> result.success(YoutubeDL.getInstance().destroyProcessById(call.argument<String>("id")!!))
            else -> result.notImplemented()
        }
    }

    /** Lavora fuori dal thread dell'interfaccia e risponde a Flutter su quello principale. */
    private fun run(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                ensureReady()
            } catch (e: Throwable) {
                main.post { result.error("init", shortMessage(e), null) }
                return@execute
            }
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                main.post { result.error("ytdlp", shortMessage(e), null) }
            }
        }
    }

    @Synchronized
    private fun ensureReady() {
        if (ready) return
        // La prima volta estrae Python nella memoria dell'app: ci vuole qualche secondo.
        YoutubeDL.getInstance().init(context)
        ready = true
    }

    private fun version(): String? =
        YoutubeDL.getInstance().versionName(context) ?: YoutubeDL.getInstance().version(context)

    private fun download(url: String, dir: File, id: String): String {
        dir.mkdirs()
        val request = YoutubeDLRequest(url)
            // Solo audio: prima l'AAC (m4a, va anche su iPhone e Windows), poi il migliore che c'è.
            .addOption("-f", "bestaudio[ext=m4a]/bestaudio")
            .addOption("-o", File(dir, "audio.%(ext)s").absolutePath)
            .addOption("--no-playlist")
            .addOption("--no-mtime")
            .addOption("--newline")
            // Le soluzioni delle sfide JavaScript di YouTube si tengono da un download all'altro.
            .addOption("--cache-dir", File(context.cacheDir, "yt-dlp-cache").absolutePath)
            // Se gli script per le sfide non sono già dentro yt-dlp, li prende da GitHub.
            .addOption("--remote-components", "ejs:github")
        // Le nuove versioni di yt-dlp cercano solo deno: senza dirgli dov'è QuickJS (incluso
        // nell'app) non risolvono le sfide di YouTube, e i download finiscono in "403 Forbidden".
        quickJs()?.let { request.addOption("--js-runtimes", "quickjs:${it.absolutePath}") }
        YoutubeDL.getInstance().execute(request, id, false) { progress, _, _ ->
            if (progress >= 0) {
                main.post { channel.invokeMethod("progress", mapOf("id" to id, "progress" to progress / 100.0)) }
            }
        }
        val file = dir.listFiles()
            ?.filter { it.isFile && it.name.startsWith("audio.") && !it.name.endsWith(".part") && !it.name.endsWith(".ytdl") }
            ?.maxByOrNull { it.length() }
            ?: throw IllegalStateException("yt-dlp non ha scritto nessun file")
        return file.absolutePath
    }

    /** Il programma QuickJS di youtubedl-android, estratto con le altre librerie native. */
    private fun quickJs(): File? {
        val dir = File(context.applicationInfo.nativeLibraryDir)
        return listOf("libqjs.so", "libquickjs.so").map { File(dir, it) }.firstOrNull { it.isFile }
    }

    /** Di quello che scrive yt-dlp tiene la riga con l'errore, non tutto il resoconto. */
    private fun shortMessage(e: Throwable): String {
        val text = generateSequence(e) { it.cause }.mapNotNull { it.message }.joinToString("\n")
        val lines = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
        val line = lines.lastOrNull { it.startsWith("ERROR") } ?: lines.lastOrNull() ?: e.javaClass.simpleName
        return line.removePrefix("ERROR:").trim().take(300)
    }
}
