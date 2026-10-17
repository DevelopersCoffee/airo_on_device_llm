package com.developerscoffee.airo_on_device_llm

import android.content.Context
import android.os.Build
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Text-only LiteRT-LM bridge. Loads one local `.litertlm` model at a time and
 * runs each prompt in a fresh conversation. Nothing here touches the network.
 *
 * Carved out of the airo app's LiteRtLmPlugin (LiteRT-LM 0.18.0 API).
 */
class AiroOnDeviceLlmPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "AiroOnDeviceLlm"
        private const val CHANNEL = "airo_on_device_llm"
        private const val STREAM_CHANNEL = "airo_on_device_llm/stream"
        private const val MIN_SDK = 26
    }

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var streamChannel: EventChannel
    private val streamHandler = TextStreamHandler()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val engineLock = Mutex()
    private var engine: Engine? = null
    private var loadedPath: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        streamChannel = EventChannel(binding.binaryMessenger, STREAM_CHANNEL)
        streamChannel.setStreamHandler(streamHandler)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        streamChannel.setStreamHandler(null)
        scope.cancel()
        engine?.close()
        engine = null
        loadedPath = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "load" -> load(call, result)
            "validate" -> validate(call, result)
            "generate" -> generate(call, result)
            "generateStream" -> generateStream(call, result)
            "unload" -> unload(result)
            else -> result.notImplemented()
        }
    }

    private fun isSupported(): Boolean =
        Build.VERSION.SDK_INT >= MIN_SDK && Build.SUPPORTED_64_BIT_ABIS.contains("arm64-v8a")

    private fun backendFromName(name: String?): Backend = when (name?.lowercase()) {
        "gpu" -> Backend.GPU()
        else -> Backend.CPU()
    }

    private fun openEngine(path: String, backendName: String?): Engine {
        val file = File(path)
        require(file.isFile) { "Model file not found" }
        val created = Engine(
            EngineConfig(
                modelPath = path,
                backend = backendFromName(backendName),
                cacheDir = context.cacheDir.path,
            ),
        )
        created.initialize()
        return created
    }

    private fun load(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val backend = call.argument<String>("backend")
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "path is required", null)
            return
        }
        if (!isSupported()) {
            result.error("UNSUPPORTED_DEVICE", "This device cannot run LiteRT-LM", null)
            return
        }
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    engineLock.withLock {
                        if (loadedPath != path || engine == null) {
                            engine?.close()
                            engine = null
                            loadedPath = null
                            engine = openEngine(path, backend)
                            loadedPath = path
                        }
                    }
                }
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "load failed: ${e.message}", e)
                result.error("LOAD_FAILED", e.message, null)
            }
        }
    }

    /** Opens and closes a model without keeping it, to check a person's own file. */
    private fun validate(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "path is required", null)
            return
        }
        if (!isSupported()) {
            result.error("UNSUPPORTED_DEVICE", "This device cannot run LiteRT-LM", null)
            return
        }
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    engineLock.withLock { openEngine(path, "cpu").close() }
                }
                result.success(true)
            } catch (e: Exception) {
                Log.w(TAG, "validate failed: ${e.message}")
                result.error("INVALID_MODEL", e.message, null)
            }
        }
    }

    private fun conversation(active: Engine, maxTokens: Int?): Conversation =
        if (maxTokens != null && maxTokens > 0) {
            active.createConversation(ConversationConfig(maxOutputToken = maxTokens))
        } else {
            active.createConversation()
        }

    private fun generate(call: MethodCall, result: MethodChannel.Result) {
        val prompt = call.argument<String>("prompt")
        val maxTokens = call.argument<Int>("maxTokens")
        if (prompt == null) {
            result.error("INVALID_ARGUMENT", "prompt is required", null)
            return
        }
        scope.launch {
            try {
                val text = withContext(Dispatchers.IO) {
                    engineLock.withLock {
                        val active = engine ?: throw IllegalStateException("No model loaded")
                        val turn = conversation(active, maxTokens)
                        try {
                            val message = turn.sendMessage(Contents.of(prompt))
                            turn.renderMessageIntoString(message)
                        } finally {
                            turn.close()
                        }
                    }
                }
                result.success(text)
            } catch (e: Exception) {
                Log.e(TAG, "generate failed: ${e.message}", e)
                result.error("GENERATION_FAILED", e.message, null)
            }
        }
    }

    private fun generateStream(call: MethodCall, result: MethodChannel.Result) {
        val prompt = call.argument<String>("prompt")
        val maxTokens = call.argument<Int>("maxTokens")
        if (prompt == null) {
            result.error("INVALID_ARGUMENT", "prompt is required", null)
            return
        }
        result.success(true)
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    engineLock.withLock {
                        val active = engine ?: throw IllegalStateException("No model loaded")
                        val turn = conversation(active, maxTokens)
                        try {
                            var snapshot = ""
                            turn.sendMessageAsync(Contents.of(prompt)).collect { message ->
                                val rendered = turn.renderMessageIntoString(message)
                                snapshot = merge(snapshot, rendered)
                                val chunk = snapshot
                                withContext(Dispatchers.Main) { streamHandler.send(chunk) }
                            }
                        } finally {
                            turn.close()
                        }
                    }
                }
                streamHandler.end()
            } catch (e: Exception) {
                Log.e(TAG, "stream failed: ${e.message}", e)
                streamHandler.fail(e.message ?: "Generation failed")
            }
        }
    }

    private fun unload(result: MethodChannel.Result) {
        scope.launch {
            withContext(Dispatchers.IO) {
                engineLock.withLock {
                    engine?.close()
                    engine = null
                    loadedPath = null
                }
            }
            result.success(true)
        }
    }

    /** LiteRT-LM may emit either deltas or the text so far; keep the text so far. */
    private fun merge(previous: String, rendered: String): String = when {
        rendered.isEmpty() -> previous
        previous.isEmpty() -> rendered
        rendered.startsWith(previous) -> rendered
        previous.endsWith(rendered) -> previous
        else -> previous + rendered
    }
}

/** Sends the generated text so far; the Dart side turns it into a stream. */
private class TextStreamHandler : EventChannel.StreamHandler {
    private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun send(text: String) {
        sink?.success(mapOf("type" to "text", "text" to text))
    }

    fun end() {
        sink?.success(mapOf("type" to "done"))
    }

    fun fail(message: String) {
        sink?.success(mapOf("type" to "error", "message" to message))
    }
}
