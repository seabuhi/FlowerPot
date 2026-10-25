package az.agillidibcek.agilli_dibcek

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Klassik Bluetooth (SPP / RFCOMM) körpüsü — HC-05, HC-06, ESP32 BluetoothSerial üçün.
 * BLE hissəsi Dart tərəfində flutter_blue_plus ilə işləyir.
 */
class MainActivity : FlutterActivity() {
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var socket: BluetoothSocket? = null
    private var readerThread: Thread? = null
    private var events: EventChannel.EventSink? = null

    private val adapter: BluetoothAdapter?
        get() = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "agilli_dibcek/classic_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { events = sink }
                override fun onCancel(args: Any?) { events = null }
            })

        MethodChannel(messenger, "agilli_dibcek/classic").setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(adapter?.isEnabled == true)
                "bondedDevices" -> bondedDevices(result)
                "connect" -> connect(call.argument<String>("address")!!, result)
                "write" -> write(call.argument<ByteArray>("data")!!, result)
                "disconnect" -> { close(); result.success(null) }
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun bondedDevices(result: MethodChannel.Result) {
        try {
            val list = adapter?.bondedDevices?.map {
                mapOf("name" to (it.name ?: ""), "address" to it.address, "type" to it.type)
            } ?: emptyList()
            result.success(list)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "Bluetooth icazəsi yoxdur", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun connect(address: String, result: MethodChannel.Result) {
        close()
        io.execute {
            try {
                val bt = adapter ?: throw IOException("Bluetooth adapteri tapılmadı")
                bt.cancelDiscovery()
                val device = bt.getRemoteDevice(address)
                var s: BluetoothSocket = device.createRfcommSocketToServiceRecord(sppUuid)
                try {
                    s.connect()
                } catch (first: IOException) {
                    // Bəzi HC-05/HC-06 modulları üçün ehtiyat yol (kanal 1)
                    try { s.close() } catch (_: IOException) {}
                    val m = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                    s = m.invoke(device, 1) as BluetoothSocket
                    s.connect()
                }
                socket = s
                startReader(s)
                main.post { result.success(true) }
            } catch (e: Exception) {
                close()
                main.post { result.error("CONNECT", e.message ?: "Qoşulmaq alınmadı", null) }
            }
        }
    }

    private fun startReader(s: BluetoothSocket) {
        readerThread = Thread {
            val buf = ByteArray(1024)
            try {
                val input = s.inputStream
                while (!Thread.currentThread().isInterrupted) {
                    val n = input.read(buf)
                    if (n < 0) break
                    if (n > 0) {
                        val chunk = buf.copyOf(n)
                        main.post { events?.success(mapOf("type" to "data", "data" to chunk)) }
                    }
                }
            } catch (_: IOException) {
            }
            if (socket === s) {
                close()
                main.post { events?.success(mapOf("type" to "disconnected")) }
            }
        }.apply { isDaemon = true; start() }
    }

    private fun write(data: ByteArray, result: MethodChannel.Result) {
        val s = socket ?: return result.error("NOT_CONNECTED", "Qoşulu deyil", null)
        io.execute {
            try {
                s.outputStream.write(data)
                s.outputStream.flush()
                main.post { result.success(null) }
            } catch (e: IOException) {
                main.post { result.error("WRITE", e.message, null) }
            }
        }
    }

    private fun close() {
        val s = socket
        socket = null
        readerThread?.interrupt()
        readerThread = null
        try { s?.close() } catch (_: IOException) {}
    }

    override fun onDestroy() {
        close()
        super.onDestroy()
    }
}
