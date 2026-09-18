package com.example.test_1

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.PowerManager
import android.provider.Settings
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.flare/ble"
    private val PACKET_EVENT_CHANNEL = "com.example.flare/packet_stream"
    private val STATUS_EVENT_CHANNEL = "com.example.flare/status_stream"

    private val FLARE_MANUFACTURER_ID = 0x5251 // Flare radio frame identifier

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null

    private var packetEventSink: EventChannel.EventSink? = null
    private var statusEventSink: EventChannel.EventSink? = null

    private var currentAdvertisingSet: AdvertisingSet? = null
    private var isAdvertising = false

    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        var activeInstance: MainActivity? = null
        var isAppInForeground: Boolean = false
        var isAdvertisingCurrently: Boolean = false
    }

    private var isReceiverRegistered = false
    private var isBluetoothStateReceiverRegistered = false

    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                if (state == BluetoothAdapter.STATE_ON) {
                    refreshBluetooth()
                    MeshForegroundService.serviceInstance?.ensureScanning()
                } else if (state == BluetoothAdapter.STATE_OFF || state == BluetoothAdapter.STATE_TURNING_OFF) {
                    isAdvertising = false
                }
            }
        }
    }

    private fun registerBluetoothStateReceiver() {
        if (isBluetoothStateReceiverRegistered) return
        try {
            registerReceiver(bluetoothStateReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
            isBluetoothStateReceiverRegistered = true
        } catch (e: Exception) {}
    }

    private fun unregisterBluetoothStateReceiver() {
        if (!isBluetoothStateReceiverRegistered) return
        try {
            unregisterReceiver(bluetoothStateReceiver)
        } catch (e: Exception) {}
        isBluetoothStateReceiverRegistered = false
    }

    private fun refreshBluetooth() {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
    }

    fun onPacketReceived(payload: ByteArray, rssi: Int, deviceAddress: String) {
        val dataMap = HashMap<String, Any>()
        dataMap["payload"] = payload
        dataMap["rssi"] = rssi
        dataMap["deviceAddress"] = deviceAddress
        dataMap["timestamp"] = System.currentTimeMillis()

        mainHandler.post {
            packetEventSink?.success(dataMap)
        }
    }

    private val blePacketReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.test_1.BLE_PACKET_RECEIVED") {
                val payload = intent.getByteArrayExtra("payload")
                val rssi = intent.getIntExtra("rssi", 0)
                val deviceAddress = intent.getStringExtra("deviceAddress") ?: "UNKNOWN"

                if (payload != null) {
                    onPacketReceived(payload, rssi, deviceAddress)
                }
            }
        }
    }

    private fun registerPacketReceiver() {
        if (isReceiverRegistered) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(blePacketReceiver, IntentFilter("com.example.test_1.BLE_PACKET_RECEIVED"), Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(blePacketReceiver, IntentFilter("com.example.test_1.BLE_PACKET_RECEIVED"))
            }
            isReceiverRegistered = true
        } catch (e: Exception) {}
    }

    override fun onResume() {
        super.onResume()
        activeInstance = this
        isAppInForeground = true
        registerBluetoothStateReceiver()
        refreshBluetooth()
        registerPacketReceiver()

        MeshForegroundService.serviceInstance?.wakeUpAndRescan()
        MeshForegroundService.serviceInstance?.startPresenceHeartbeat(forceRefresh = true)
    }

    override fun onPause() {
        super.onPause()
        isAppInForeground = false
        MeshForegroundService.serviceInstance?.updateScanMode(isForeground = false)
    }

    override fun onDestroy() {
        super.onDestroy()
        isAppInForeground = false
        unregisterBluetoothStateReceiver()
        if (activeInstance == this) {
            activeInstance = null
        }
        if (isReceiverRegistered) {
            try {
                unregisterReceiver(blePacketReceiver)
            } catch (e: Exception) {}
            isReceiverRegistered = false
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser

        // Foreground Service Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.test_1/foreground_service").setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    val serviceIntent = android.content.Intent(this, MeshForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success(null)
                }
                "stopForegroundService" -> {
                    val serviceIntent = android.content.Intent(this, MeshForegroundService::class.java)
                    stopService(serviceIntent)
                    result.success(null)
                }
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "Alert"
                    val body = call.argument<String>("body") ?: ""
                    
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val channel = android.app.NotificationChannel("sos_alerts_v2", "Emergency SOS Alerts", android.app.NotificationManager.IMPORTANCE_HIGH)
                        notificationManager.createNotificationChannel(channel)
                    }
                    
                    val notification = androidx.core.app.NotificationCompat.Builder(this, "sos_alerts_v2")
                        .setContentTitle(title)
                        .setContentText(body)
                        .setSmallIcon(R.drawable.ic_notification_flame)
                        .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                        .setAutoCancel(true)
                        .build()
                        
                    notificationManager.notify(System.currentTimeMillis().toInt(), notification)
                    result.success(null)
                }
                "isBatteryOptimizationIgnored" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    val isIgnored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        powerManager?.isIgnoringBatteryOptimizations(packageName) == true
                    } else {
                        true
                    }
                    result.success(isIgnored)
                }
                "requestIgnoreBatteryOptimization" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.success(false)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkHardwareSupport" -> {
                    refreshBluetooth()
                    val capabilities = HashMap<String, Any>()
                    val adapter = bluetoothAdapter
                    if (adapter != null) {
                        capabilities["isBluetoothEnabled"] = adapter.isEnabled
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            capabilities["isLeCodedPhySupported"] = adapter.isLeCodedPhySupported
                            capabilities["isLe2MPhySupported"] = adapter.isLe2MPhySupported
                            capabilities["isExtendedAdvertisingSupported"] = adapter.isLeExtendedAdvertisingSupported
                            capabilities["isPeriodicAdvertisingSupported"] = adapter.isLePeriodicAdvertisingSupported
                            capabilities["maxAdvDataLength"] = adapter.leMaximumAdvertisingDataLength
                        } else {
                            capabilities["isLeCodedPhySupported"] = false
                            capabilities["isLe2MPhySupported"] = false
                            capabilities["isExtendedAdvertisingSupported"] = false
                            capabilities["isPeriodicAdvertisingSupported"] = false
                            capabilities["maxAdvDataLength"] = 31
                        }
                        capabilities["isMultipleAdvertisementSupported"] = adapter.isMultipleAdvertisementSupported
                    } else {
                        capabilities["isBluetoothEnabled"] = false
                    }
                    result.success(capabilities)
                }

                "startAdvertising" -> {
                    val payload = call.argument<ByteArray>("payload") ?: ByteArray(0)
                    val phyMode = call.argument<String>("phyMode") ?: "leCodedS8"
                    startHardwareAdvertising(payload, phyMode, result)
                }

                "stopAdvertising" -> {
                    stopHardwareAdvertising()
                    result.success(true)
                }

                "startScanning" -> {
                    MeshForegroundService.serviceInstance?.ensureScanning()
                    result.success(true)
                }

                "wakeUpMesh" -> {
                    MeshForegroundService.serviceInstance?.wakeUpAndRescan()
                    MeshForegroundService.serviceInstance?.startPresenceHeartbeat(forceRefresh = true)
                    result.success(true)
                }

                "startPresenceHeartbeat" -> {
                    MeshForegroundService.serviceInstance?.startPresenceHeartbeat(forceRefresh = true)
                    result.success(true)
                }

                "stopScanning" -> {
                    // MeshForegroundService scans 24/7 autonomously in background
                    result.success(true)
                }

                "deletePeer" -> {
                    val senderHash = call.argument<Int>("senderHash") ?: 0
                    if (senderHash != 0) {
                        MeshForegroundService.serviceInstance?.removePeer(senderHash)
                    }
                    result.success(true)
                }

                "clearUnknownPeers" -> {
                    MeshForegroundService.serviceInstance?.clearUnknownPeers()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // Event Channels
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PACKET_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    packetEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    packetEventSink = null
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STATUS_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    statusEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    statusEventSink = null
                }
            }
        )
    }

    private fun startHardwareAdvertising(payload: ByteArray, phyMode: String, result: MethodChannel.Result) {
        refreshBluetooth()
        val advertiser = bluetoothLeAdvertiser ?: bluetoothAdapter?.bluetoothLeAdvertiser
        if (advertiser == null || bluetoothAdapter?.isEnabled != true) {
            result.error("NO_ADVERTISER", "Bluetooth LE Advertiser not available or Bluetooth is disabled", null)
            return
        }

        // Cleanly stop any existing advertising and heartbeats
        MeshForegroundService.serviceInstance?.stopBackgroundHeartbeat()
        MeshForegroundService.serviceInstance?.stopPresenceHeartbeatAdvertiser()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && currentAdvertisingSet != null) {
                advertiser.stopAdvertisingSet(advertisingSetCallback)
                currentAdvertisingSet = null
            }
            advertiser.stopAdvertising(legacyAdvertiseCallback)
        } catch (e: Exception) {}
        isAdvertising = false
        isAdvertisingCurrently = false

        fun executeStart() {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    try {
                        val isLeCodedSupported = bluetoothAdapter?.isLeCodedPhySupported == true
                        val useCoded = phyMode == "leCodedS8" && isLeCodedSupported

                        if (useCoded || payload.size > 48) {
                            val parameters = AdvertisingSetParameters.Builder()
                                .setLegacyMode(false)
                                .setInterval(AdvertisingSetParameters.INTERVAL_MIN)
                                .setTxPowerLevel(AdvertisingSetParameters.TX_POWER_MAX)
                                .setPrimaryPhy(BluetoothDevice.PHY_LE_1M)
                                .setSecondaryPhy(if (useCoded) BluetoothDevice.PHY_LE_CODED else BluetoothDevice.PHY_LE_1M)
                                .build()

                            val advertiseData = AdvertiseData.Builder()
                                .setIncludeDeviceName(false)
                                .setIncludeTxPowerLevel(false)
                                .addManufacturerData(FLARE_MANUFACTURER_ID, payload)
                                .build()

                            advertiser.startAdvertisingSet(parameters, advertiseData, null, null, null, advertisingSetCallback)
                            isAdvertising = true
                            isAdvertisingCurrently = true
                            result.success(true)
                            return
                        }
                    } catch (e: Exception) {
                        // Fall back to legacy
                    }
                }
                
                val legacySettings = AdvertiseSettings.Builder()
                    .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                    .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                    .setConnectable(false)
                    .setTimeout(0)
                    .build()

                val chunk1 = if (payload.size > 24) payload.copyOfRange(0, 24) else payload
                val legacyData = AdvertiseData.Builder()
                    .setIncludeDeviceName(false)
                    .setIncludeTxPowerLevel(false)
                    .addManufacturerData(FLARE_MANUFACTURER_ID, chunk1)
                    .build()

                val scanResponse = if (payload.size > 24) {
                    val chunk2 = payload.copyOfRange(24, payload.size.coerceAtMost(51))
                    AdvertiseData.Builder()
                        .setIncludeDeviceName(false)
                        .setIncludeTxPowerLevel(false)
                        .addManufacturerData(FLARE_MANUFACTURER_ID + 1, chunk2)
                        .build()
                } else null

                advertiser.startAdvertising(legacySettings, legacyData, scanResponse, legacyAdvertiseCallback)
                isAdvertising = true
                isAdvertisingCurrently = true
                result.success(true)
            } catch (e: Exception) {
                isAdvertisingCurrently = false
                result.error("ADV_EXCEPTION", e.message, null)
            }
        }

        // Wait 50ms to ensure the Android Bluetooth daemon frees any previous hardware advertising slot
        mainHandler.postDelayed({
            executeStart()
        }, 50L)
    }

    private val advertisingSetCallback = object : AdvertisingSetCallback() {
        override fun onAdvertisingSetStarted(advertisingSet: AdvertisingSet?, txPower: Int, status: Int) {
            mainHandler.post {
                if (status == AdvertisingSetCallback.ADVERTISE_SUCCESS) {
                    currentAdvertisingSet = advertisingSet
                    isAdvertising = true
                    isAdvertisingCurrently = true
                    notifyStatus("ADVERTISING_STARTED", mapOf("phy" to "leCodedS8"))
                } else {
                    isAdvertisingCurrently = false
                    notifyStatus("ADVERTISING_FAILED", mapOf("errorCode" to status))
                }
            }
        }

        override fun onAdvertisingSetStopped(advertisingSet: AdvertisingSet?) {
            mainHandler.post {
                currentAdvertisingSet = null
                isAdvertising = false
                isAdvertisingCurrently = false
                notifyStatus("ADVERTISING_STOPPED", null)
            }
        }
    }

    private val legacyAdvertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            mainHandler.post {
                isAdvertising = true
                isAdvertisingCurrently = true
                notifyStatus("ADVERTISING_STARTED", mapOf("phy" to "legacy1M"))
            }
        }

        override fun onStartFailure(errorCode: Int) {
            mainHandler.post {
                if (errorCode == AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED || errorCode == AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS || errorCode == AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR) {
                    try {
                        val adv = bluetoothLeAdvertiser ?: bluetoothAdapter?.bluetoothLeAdvertiser
                        adv?.stopAdvertising(this)
                    } catch (e: Exception) {}
                }
                isAdvertising = false
                isAdvertisingCurrently = false
                notifyStatus("ADVERTISING_FAILED", mapOf("errorCode" to errorCode))
            }
        }
    }

    private fun stopHardwareAdvertising() {
        refreshBluetooth()
        val adv = bluetoothLeAdvertiser ?: bluetoothAdapter?.bluetoothLeAdvertiser
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && currentAdvertisingSet != null) {
                adv?.stopAdvertisingSet(advertisingSetCallback)
                currentAdvertisingSet = null
            }
            adv?.stopAdvertising(legacyAdvertiseCallback)
        } catch (e: Exception) {}
        isAdvertising = false
        isAdvertisingCurrently = false
        MeshForegroundService.serviceInstance?.ensureScanning()
        // Immediately resume continuous hardware presence heartbeat beacon in silicon
        mainHandler.postDelayed({
            MeshForegroundService.serviceInstance?.startPresenceHeartbeat(forceRefresh = true)
        }, 60L)
    }

    private fun notifyStatus(status: String, extras: Map<String, Any>?) {
        val data = HashMap<String, Any>()
        data["status"] = status
        extras?.let { data.putAll(it) }
        statusEventSink?.success(data)
    }
}
