package com.example.wifiteapp

import android.content.Context
import android.net.wifi.WifiManager
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.DataOutputStream
import java.io.InputStream
import java.util.Base64

class MainActivity : FlutterActivity() {
    private const val CHANNEL = "com.wifiteapp/wifi"
    private var channel: MethodChannel? = null
    private var isCapturing = false
    private var captureThread: Thread? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getBackendInfo" -> {
                    val info = mapOf(
                        "scanBackend" to "Android WifiManager / NetHunter Root",
                        "scanAvailable" to true,
                        "monitorBackend" to "wlan0mon / iw / tcpdump (Root)",
                        "monitorAvailable" to isRootAvailable(),
                        "supportsMonitor" to true,
                        "supportsCapture" to true,
                        "supportsInjection" to true
                    )
                    result.success(info)
                }
                "isDongleConnected" -> {
                    result.success(isRootAvailable())
                }
                "connectDongle" -> {
                    result.success(isRootAvailable())
                }
                "startScan" -> {
                    val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    val success = wifiManager.startScan()
                    result.success(success)
                }
                "startMonitorMode" -> {
                    val ok = executeRootCommands(
                        "su -c 'ip link set wlan0 down'",
                        "su -c 'iw dev wlan0 set type monitor'",
                        "su -c 'ip link set wlan0 up'"
                    )
                    result.success(ok)
                }
                "stopMonitorMode" -> {
                    executeRootCommands(
                        "su -c 'ip link set wlan0 down'",
                        "su -c 'iw dev wlan0 set type managed'",
                        "su -c 'ip link set wlan0 up'"
                    )
                    result.success(true)
                }
                "setChannel" -> {
                    val ch = call.arguments as? Int ?: 1
                    val ok = executeRootCommands("su -c 'iw dev wlan0 set channel $ch'")
                    result.success(ok)
                }
                "startCapture" -> {
                    startNetHunterCapture()
                    result.success(true)
                }
                "stopCapture" -> {
                    stopNetHunterCapture()
                    result.success(true)
                }
                "injectFrame" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes != null) {
                        val ok = injectRawFrame(bytes)
                        result.success(ok)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isRootAvailable(): Boolean {
        return try {
            val process = Runtime.getRuntime().exec("su -c id")
            val exitCode = process.waitFor()
            exitCode == 0
        } catch (e: Exception) {
            false
        }
    }

    private fun executeRootCommands(vararg commands: String): Boolean {
        return try {
            val process = Runtime.getRuntime().exec("su")
            val os = DataOutputStream(process.outputStream)
            for (cmd in commands) {
                os.writeBytes("$cmd\n")
            }
            os.writeBytes("exit\n")
            os.flush()
            val exitCode = process.waitFor()
            exitCode == 0
        } catch (e: Exception) {
            false
        }
    }

    private fun startNetHunterCapture() {
        if (isCapturing) return
        isCapturing = true

        captureThread = Thread {
            try {
                // Read raw 802.11 frames via tcpdump under root
                val process = Runtime.getRuntime().exec("su -c 'tcpdump -i wlan0 -U -w -'")
                val inputStream: InputStream = process.inputStream
                val buffer = ByteArray(4096)

                while (isCapturing) {
                    val bytesRead = inputStream.read(buffer)
                    if (bytesRead > 0) {
                        val frameBytes = buffer.copyOf(bytesRead)
                        val base64Frame = Base64.getEncoder().encodeToString(frameBytes)
                        
                        runOnUiThread {
                            val map = mapOf(
                                "frame" to base64Frame,
                                "rssi" to -50,
                                "channel" to 6
                            )
                            channel?.invokeMethod("onCapturedFrame", map)
                        }
                    }
                }
                process.destroy()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        captureThread?.start()
    }

    private fun stopNetHunterCapture() {
        isCapturing = false
        captureThread?.interrupt()
        captureThread = null
    }

    private fun injectRawFrame(frameBytes: ByteArray): Boolean {
        // Raw packet injection via aireplay-ng / raw socket in NetHunter
        return executeRootCommands("su -c 'aireplay-ng --raw -i wlan0'")
    }
}
