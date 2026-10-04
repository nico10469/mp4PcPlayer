# yt-dlp nell'app (youtubedl-android) legge le risposte con Jackson: le sue classi non vanno toccate.
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**
-dontwarn java.beans.**
-dontwarn org.w3c.dom.bootstrap.**
