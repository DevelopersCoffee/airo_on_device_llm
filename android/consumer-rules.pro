# LiteRT-LM loads Kotlin classes from JNI; keep them through R8 in apps that
# minify their release build.
-keep class com.google.ai.edge.litertlm.** { *; }
-dontwarn com.google.ai.edge.litertlm.**
