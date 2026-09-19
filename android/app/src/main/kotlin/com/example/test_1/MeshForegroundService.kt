package com.example.test_1

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
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
import android.os.IBinder
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import android.widget.Toast
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import android.app.PendingIntent
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.content.pm.ServiceInfo
import android.os.SystemClock
import java.util.UUID
import kotlin.collections.LinkedHashSet

class MeshForegroundService : Service() {

    companion object {
        var isServiceRunning = false
        var serviceInstance: MeshForegroundService? = null
    }

    private val CHANNEL_ID = "flare_mesh_service_channel"
    private val FLARE_MANUFACTURER_ID = 0x5251
    
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var isScanning = false
    private var isBluetoothReceiverRegistered = false
    private var isScreenReceiverRegistered = false
    private var isNativeBroadcasting = false
    private var lastNativeBroadcastStartTime = 0L
    private var nativeBroadcastTimeoutMs = 5000L
    private val lastAckTimeMap = HashMap<Int, Long>()
    private var isHeartbeatActive = false
    private var heartbeatSeq = 1
    private val random = java.util.Random()

    // Real-time nearby peers cache
    private val nearbyPeersMap = HashMap<Int, JSONObject>()
    private var lastPeerSaveTime = 0L
    
    // Dual-Tier WakeLock Architecture:
    // 1. serviceWakeLock: Held indefinitely while service is running (never with a timeout!).
    // 2. transientWakeLock: Separate reference-counted lock for temporary async operations.
    private var serviceWakeLock: PowerManager.WakeLock? = null
    private var transientWakeLock: PowerManager.WakeLock? = null

    // LRU cache for seen packet IDs (prevent infinite relay loops)
    private val seenPacketIds = LinkedHashSet<Int>()
    private val MAX_CACHE_SIZE = 1000
    private val lastSosNotificationTime = HashMap<Int, Long>()

    private val mainHandler = Handler(Looper.getMainLooper())

    private var lastHeartbeatStartTime = 0L
    private var lastScanCycleTime = System.currentTimeMillis()
    private var lastPacketReceivedTime = System.currentTimeMillis()

    fun ensureWakeLock() {
        try {
            if (serviceWakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                serviceWakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Flare:MeshServiceWakeLock")
                serviceWakeLock?.setReferenceCounted(false)
            }
            if (serviceWakeLock?.isHeld != true) {
                serviceWakeLock?.acquire()
            }
        } catch (e: Exception) {
            Log.e("MeshForegroundService", "ensureWakeLock error: ${e.message}")
        }
    }

    fun acquireTransientWakeLock(timeoutMs: Long) {
        try {
            if (transientWakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                transientWakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Flare:TransientWakeLock")
                transientWakeLock?.setReferenceCounted(true)
            }
            transientWakeLock?.acquire(timeoutMs)
        } catch (e: Exception) {}
    }

    fun ensureScanning() {
        ensureWakeLock()
        refreshBluetooth()
        if (bluetoothAdapter?.isEnabled == true && !isScanning) {
            startHardwareScanning()
        }
        if (!MainActivity.isAppInForeground) {
            startBackgroundHeartbeat(forceRefresh = false)
        }
    }

    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                if (state == BluetoothAdapter.STATE_ON) {
                    mainHandler.postDelayed({
                        refreshBluetooth()
                        startHardwareScanning()
                        startBackgroundHeartbeat(forceRefresh = true)
                    }, 1000L)
                } else if (state == BluetoothAdapter.STATE_OFF || state == BluetoothAdapter.STATE_TURNING_OFF) {
                    isScanning = false
                    isHeartbeatAdvertising = false
                    stopHardwareScanning()
                    stopPresenceHeartbeatAdvertiser()
                    stopRelayAdvertiser()
                }
            }
        }
    }

    private var alarmManager: AlarmManager? = null
    private var scanCyclePendingIntent: PendingIntent? = null
    private val SCAN_CYCLE_ACTION = "com.example.test_1.ACTION_SCAN_CYCLE"
    private var isScanCycleReceiverRegistered = false

    private val scanCycleReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == SCAN_CYCLE_ACTION) {
                ensureWakeLock()
                acquireTransientWakeLock(6000L)
                refreshBluetooth()
                
                // 90-second watchdog alarm: ensures service is alive, scanner is verified active,
                // and background heartbeat is fresh.
                val now = System.currentTimeMillis()
                if (bluetoothAdapter?.isEnabled == true) {
                    if (!isScanning) {
                        startHardwareScanning()
                    }
                }
                if (!MainActivity.isAppInForeground && !isNativeBroadcasting && !MainActivity.isAdvertisingCurrently) {
                    if (!isHeartbeatAdvertising) {
                        startBackgroundHeartbeat(forceRefresh = false)
                    }
                }
                scheduleNextRtcScanCycle()
            }
        }
    }

    private fun registerScanCycleReceiver() {
        if (isScanCycleReceiverRegistered) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(scanCycleReceiver, IntentFilter(SCAN_CYCLE_ACTION), Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(scanCycleReceiver, IntentFilter(SCAN_CYCLE_ACTION))
            }
            isScanCycleReceiverRegistered = true
        } catch (e: Exception) {}
    }

    private fun unregisterScanCycleReceiver() {
        if (!isScanCycleReceiverRegistered) return
        try {
            unregisterReceiver(scanCycleReceiver)
        } catch (e: Exception) {}
        isScanCycleReceiverRegistered = false
    }

    private fun scheduleNextRtcScanCycle() {
        try {
            if (alarmManager == null) {
                alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            }
            val intent = Intent(SCAN_CYCLE_ACTION).apply {
                setPackage(packageName)
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            scanCyclePendingIntent = PendingIntent.getBroadcast(this, 101, intent, flags)
            
            // 90-second watchdog alarm: ensures service is alive, scanner is verified active,
            // and background heartbeat is fresh.
            val triggerAt = android.os.SystemClock.elapsedRealtime() + (90 * 1000L)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager?.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAt,
                    scanCyclePendingIntent!!
                )
            } else {
                alarmManager?.setExact(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAt,
                    scanCyclePendingIntent!!
                )
            }
        } catch (e: Exception) {
            Log.e("MeshForegroundService", "Error scheduling RTC alarm: ${e.message}")
        }
    }

    private fun cancelRtcScanCycle() {
        try {
            scanCyclePendingIntent?.let { alarmManager?.cancel(it) }
        } catch (e: Exception) {}
    }

    private val screenStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            when (action) {
                Intent.ACTION_SCREEN_ON,
                Intent.ACTION_USER_PRESENT -> {
                    wakeUpAndRescan()
                }
                Intent.ACTION_SCREEN_OFF -> {
                    startBackgroundHeartbeat(forceRefresh = false)
                }
            }
        }
    }

    private fun registerScreenReceiver() {
        if (isScreenReceiverRegistered) return
        try {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_PRESENT)
            }
            registerReceiver(screenStateReceiver, filter)
            isScreenReceiverRegistered = true
        } catch (e: Exception) {}
    }

    private fun unregisterScreenReceiver() {
        if (!isScreenReceiverRegistered) return
        try {
            unregisterReceiver(screenStateReceiver)
        } catch (e: Exception) {}
        isScreenReceiverRegistered = false
    }

    private fun registerBluetoothReceiver() {
        if (isBluetoothReceiverRegistered) return
        try {
            registerReceiver(bluetoothStateReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
            isBluetoothReceiverRegistered = true
        } catch (e: Exception) {}
    }

    private fun unregisterBluetoothReceiver() {
        if (!isBluetoothReceiverRegistered) return
        try {
            unregisterReceiver(bluetoothStateReceiver)
        } catch (e: Exception) {}
        isBluetoothReceiverRegistered = false
    }

    private fun refreshBluetooth() {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner
        bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
    }

    // 24/7 Native Background Presence Heartbeat & Scan Cycling Watchdog
    private val backgroundHeartbeatRunnable = object : Runnable {
        override fun run() {
            try {
                ensureWakeLock()
                val now = System.currentTimeMillis()

                // 1. Ensure scanner is active 24/7
                if (bluetoothAdapter?.isEnabled == true && !isScanning && !isStartingScan) {
                    startHardwareScanning()
                } else if (MainActivity.isAppInForeground && (now - lastPacketReceivedTime > 15000L) && (now - lastScanStartTime > 15000L)) {
                    // Periodic scan cycle if in foreground to clear controller duplicate filter table
                    cycleHardwareScan()
                }

                // 1b. Safety Watchdog for native broadcasting (guarantees radio is freed even during deep sleep)
                if (isNativeBroadcasting && (now - lastNativeBroadcastStartTime > nativeBroadcastTimeoutMs)) {
                    stopRelayAdvertiser()
                    isNativeBroadcasting = false
                }

                // 2. Ensure presence beacon is active continuously in hardware (rolling seq every 15s to bypass duplicate filters)
                if (!isNativeBroadcasting && !MainActivity.isAdvertisingCurrently) {
                    if (!isHeartbeatAdvertising || (now - lastHeartbeatStartTime > 15000L)) {
                        startPresenceHeartbeat(forceRefresh = true)
                    }
                }
            } catch (e: Exception) {}
            mainHandler.postDelayed(this, 2500L)
        }
    }

    fun safeRestartScan(delayMs: Long = 150L) {
        ensureWakeLock()
        acquireTransientWakeLock(delayMs + 4000L)
        refreshBluetooth()
        if (bluetoothAdapter?.isEnabled != true || bluetoothLeScanner == null) return

        try {
            if (isScanning) {
                bluetoothLeScanner?.stopScan(scanCallback)
            }
        } catch (e: Exception) {}
        isScanning = false
        isStartingScan = false

        mainHandler.postDelayed({
            ensureWakeLock()
            if (bluetoothAdapter?.isEnabled == true && !isScanning) {
                lastScanStartTime = 0L // Reset rate-limiting guard so scan start succeeds immediately
                startHardwareScanning()
            }
        }, delayMs)
    }

    fun cycleHardwareScan() {
        safeRestartScan(150L)
    }

    private var lastRescanTime = 0L

    fun wakeUpAndRescan() {
        mainHandler.post {
            val now = System.currentTimeMillis()
            if (now - lastRescanTime < 3000L && isScanning) {
                // Prevent AOSP error 6 (SCAN_FAILED_SCANNING_TOO_FREQUENTLY)
                ensureScanning()
                return@post
            }
            lastRescanTime = now
            safeRestartScan(300L)

            if (!isNativeBroadcasting && !MainActivity.isAdvertisingCurrently) {
                stopPresenceHeartbeatAdvertiser()
                startPresenceHeartbeat(forceRefresh = true)
            }
        }
    }

    private var isHeartbeatAdvertising = false
    private val heartbeatCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            isHeartbeatAdvertising = true
            lastHeartbeatStartTime = System.currentTimeMillis()
        }
        override fun onStartFailure(errorCode: Int) {
            if (errorCode == AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED) {
                isHeartbeatAdvertising = true
                lastHeartbeatStartTime = System.currentTimeMillis()
                return
            }
            isHeartbeatAdvertising = false
            if (errorCode == AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS || errorCode == AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR) {
                try {
                    bluetoothLeAdvertiser?.stopAdvertising(this)
                } catch (e: Exception) {}
                mainHandler.postDelayed({
                    if (!isHeartbeatAdvertising && !isNativeBroadcasting && !MainActivity.isAdvertisingCurrently) {
                        startPresenceHeartbeat(forceRefresh = true)
                    }
                }, 300L)
            }
        }
    }

    fun stopPresenceHeartbeatAdvertiser() {
        try {
            bluetoothLeAdvertiser?.stopAdvertising(heartbeatCallback)
        } catch (e: Exception) {}
        isHeartbeatAdvertising = false
    }

    fun startPresenceHeartbeat(forceRefresh: Boolean = false) {
        if (!forceRefresh && isHeartbeatAdvertising) return
        if (isNativeBroadcasting || MainActivity.isAdvertisingCurrently) return
        refreshBluetooth()
        if (bluetoothAdapter?.isEnabled != true) return
        val advertiser = bluetoothLeAdvertiser ?: return

        val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val myPubKey = prefs.getString("flutter.flare_my_pub_key", null)
            ?: prefs.getString("flutter.resqmesh_my_pub_key", null) ?: return
        val myHash = consistentHash(myPubKey) and 0xFFFF
        if (myHash == 0) return

        val hbPacket = ByteArray(8)
        hbPacket[0] = 0x52.toByte() // Magic byte 1 (0x52)
        hbPacket[1] = 0x51.toByte() // Magic byte 2 (0x51)
        hbPacket[2] = 0x48.toByte() // 'H' = Presence Heartbeat
        hbPacket[3] = 1.toByte()    // TTL = 1
        hbPacket[4] = (myHash shr 8).toByte()
        hbPacket[5] = (myHash and 0xFF).toByte()
        hbPacket[6] = (heartbeatSeq shr 8).toByte()
        hbPacket[7] = (heartbeatSeq and 0xFF).toByte()
        heartbeatSeq = (heartbeatSeq + 1) and 0xFFFF
        if (heartbeatSeq == 0) heartbeatSeq = 1

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED) // ~250ms interval in silicon
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .setTimeout(0) // 0 = continuous indefinite hardware beaconing
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addManufacturerData(FLARE_MANUFACTURER_ID, hbPacket)
            .build()

        try {
            stopPresenceHeartbeatAdvertiser()
            mainHandler.postDelayed({
                if (isNativeBroadcasting || MainActivity.isAdvertisingCurrently) return@postDelayed
                try {
                    advertiser.startAdvertising(settings, data, heartbeatCallback)
                    lastHeartbeatStartTime = System.currentTimeMillis()
                } catch (e: Exception) {
                    isHeartbeatAdvertising = false
                }
            }, 60L)
        } catch (e: Exception) {
            isHeartbeatAdvertising = false
        }
    }

    fun startBackgroundHeartbeat(forceRefresh: Boolean = false) {
        startPresenceHeartbeat(forceRefresh)
    }

    fun stopBackgroundHeartbeat() {
        stopPresenceHeartbeatAdvertiser()
    }

    fun triggerImmediateScanBurst() {
        refreshBluetooth()
        if (bluetoothAdapter?.isEnabled != true) return
        if (!isScanning) {
            startHardwareScanning()
        } else {
            updateScanMode(isForeground = true)
        }
    }

    private var currentScanMode = ScanSettings.SCAN_MODE_LOW_LATENCY
    private var lastScanModeChangeTime = 0L

    fun updateScanMode(isForeground: Boolean) {
        val desiredMode = ScanSettings.SCAN_MODE_LOW_LATENCY
        if (desiredMode == currentScanMode && isScanning) return
        
        val now = System.currentTimeMillis()
        if (now - lastScanModeChangeTime < 3000L) return
        lastScanModeChangeTime = now
        currentScanMode = desiredMode

        safeRestartScan(300L)
    }

    private fun getMyHash(): Int {
        val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val myPubKey = prefs.getString("flutter.flare_my_pub_key", null)
            ?: prefs.getString("flutter.resqmesh_my_pub_key", null) ?: return 0
        return consistentHash(myPubKey) and 0xFFFF
    }

    private fun updateNearbyPeerSignal(senderHash: Int, rssi: Int, deviceAddress: String) {
        if (senderHash == 0) return
        val myHash = getMyHash()
        if (myHash != 0 && senderHash == myHash) return

        val now = System.currentTimeMillis()
        val peerObj = nearbyPeersMap[senderHash] ?: JSONObject().apply {
            put("senderHash", senderHash)
            put("packetCount", 0)
        }
        peerObj.put("lastRssi", rssi)
        peerObj.put("lastSeen", now)
        peerObj.put("deviceAddress", deviceAddress)
        peerObj.put("packetCount", peerObj.optInt("packetCount", 0) + 1)
        nearbyPeersMap[senderHash] = peerObj

        // Persist to SharedPreferences periodically so Flutter cold-start immediately has peers
        if (now - lastPeerSaveTime > 2000L) {
            lastPeerSaveTime = now
            try {
                val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val jsonArr = JSONArray()
                for (obj in nearbyPeersMap.values) {
                    jsonArr.put(obj)
                }
                val jsonStr = jsonArr.toString()
                prefs.edit()
                    .putString("flutter.flare_nearby_peers_cache", jsonStr)
                    .putString("flutter.resqmesh_nearby_peers_cache", jsonStr)
                    .apply()
            } catch (e: Exception) {}
        }
    }

    fun removePeer(senderHash: Int) {
        if (senderHash == 0) return
        nearbyPeersMap.remove(senderHash)
        try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val jsonArr = JSONArray()
            for (obj in nearbyPeersMap.values) {
                jsonArr.put(obj)
            }
            val jsonStr = jsonArr.toString()
            prefs.edit()
                .putString("flutter.flare_nearby_peers_cache", jsonStr)
                .putString("flutter.resqmesh_nearby_peers_cache", jsonStr)
                .apply()
        } catch (e: Exception) {}
    }

    fun clearUnknownPeers() {
        try {
            val myHash = getMyHash()
            if (myHash != 0) {
                nearbyPeersMap.remove(myHash)
            }
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val contactsJson = prefs.getString("flutter.flare_saved_contacts", null)
                ?: prefs.getString("flutter.resqmesh_saved_contacts", null)
            val knownHashes = HashSet<Int>()
            val knownKeys = ArrayList<String>()
            if (contactsJson != null) {
                val array = JSONArray(contactsJson)
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    val pubKey = obj.optString("publicKey", "")
                    if (pubKey.isNotEmpty()) {
                        knownKeys.add(pubKey)
                        val hash = consistentHash(pubKey) and 0xFFFF
                        if (hash != 0) knownHashes.add(hash)
                        val clean = pubKey.replace("PUB_KEY_", "").replace("HASH_", "").uppercase()
                        if (clean.length == 16 && clean.startsWith("0000")) {
                            val suffix = clean.substring(12)
                            val parsed = suffix.toIntOrNull(16)
                            if (parsed != null && parsed != 0) {
                                knownHashes.add(parsed and 0xFFFF)
                            }
                        }
                    }
                }
            }
            val toRemove = nearbyPeersMap.keys.filter { hash ->
                (myHash != 0 && hash == myHash) || (!knownHashes.contains(hash) && !knownKeys.any { contactMatchesSender(it, hash) })
            }
            for (key in toRemove) {
                nearbyPeersMap.remove(key)
            }
            val jsonArr = JSONArray()
            for (obj in nearbyPeersMap.values) {
                jsonArr.put(obj)
            }
            val jsonStr = jsonArr.toString()
            prefs.edit()
                .putString("flutter.flare_nearby_peers_cache", jsonStr)
                .putString("flutter.resqmesh_nearby_peers_cache", jsonStr)
                .apply()
        } catch (e: Exception) {}
    }

    override fun onCreate() {
        super.onCreate()
        serviceInstance = this
        createNotificationChannel()

        val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isMuleEnabled = prefs.getBoolean("flutter.is_mule_enabled", true)
        if (!isMuleEnabled) {
            return
        }

        registerBluetoothReceiver()
        registerScreenReceiver()
        registerScanCycleReceiver()
        refreshBluetooth()
        
        ensureWakeLock()

        startBackgroundHeartbeat(forceRefresh = true)
        scheduleNextRtcScanCycle()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isMuleEnabled = prefs.getBoolean("flutter.is_mule_enabled", true)
        if (!isMuleEnabled) {
            isServiceRunning = false
            if (serviceInstance == this) {
                serviceInstance = null
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.cancel(1)
            stopSelf()
            return START_NOT_STICKY
        }

        isServiceRunning = true
        ensureWakeLock()
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Flare")
            .setContentText("In a mesh network")
            .setSmallIcon(R.drawable.ic_notification_flame)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(1, notification)
        }

        // Start scanning autonomously
        refreshBluetooth()
        startHardwareScanning()
        startBackgroundHeartbeat(forceRefresh = true)
        scheduleNextRtcScanCycle()

        // Schedule periodic presence watchdog
        mainHandler.removeCallbacks(backgroundHeartbeatRunnable)
        mainHandler.postDelayed(backgroundHeartbeatRunnable, 2500L)

        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isMuleEnabled = prefs.getBoolean("flutter.is_mule_enabled", true)
        if (!isMuleEnabled) {
            return
        }

        ensureWakeLock()
        wakeUpAndRescan()

        // Schedule auto-resurrect alarm if process gets killed by OS upon swipe
        try {
            val restartIntent = Intent(applicationContext, MeshForegroundService::class.java)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_ONE_SHOT
            }
            val restartPendingIntent = PendingIntent.getService(applicationContext, 999, restartIntent, flags)
            val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am?.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 500L,
                    restartPendingIntent
                )
            } else {
                am?.setExact(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 500L,
                    restartPendingIntent
                )
            }
        } catch (e: Exception) {
            Log.e("MeshForegroundService", "Error scheduling resurrection alarm: ${e.message}")
        }
    }

    override fun onDestroy() {
        isServiceRunning = false
        if (serviceInstance == this) {
            serviceInstance = null
        }
        super.onDestroy()
        cancelRtcScanCycle()
        unregisterScanCycleReceiver()
        unregisterScreenReceiver()
        unregisterBluetoothReceiver()
        stopBackgroundHeartbeat()
        stopPresenceHeartbeatAdvertiser()
        stopRelayAdvertiser()
        mainHandler.removeCallbacks(backgroundHeartbeatRunnable)
        stopHardwareScanning()

        // If service was killed unexpectedly while mule/mesh is enabled, schedule resurrection alarm
        try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isMuleEnabled = prefs.getBoolean("flutter.is_mule_enabled", true)
            val restartIntent = Intent(applicationContext, MeshForegroundService::class.java)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_ONE_SHOT
            }
            val restartPendingIntent = PendingIntent.getService(applicationContext, 999, restartIntent, flags)
            val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            if (isMuleEnabled) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am?.setExactAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        SystemClock.elapsedRealtime() + 1000L,
                        restartPendingIntent
                    )
                } else {
                    am?.setExact(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        SystemClock.elapsedRealtime() + 1000L,
                        restartPendingIntent
                    )
                }
            } else {
                am?.cancel(restartPendingIntent)
            }
        } catch (e: Exception) {}

        try {
            if (serviceWakeLock?.isHeld == true) {
                serviceWakeLock?.release()
            }
            if (transientWakeLock?.isHeld == true) {
                transientWakeLock?.release()
            }
        } catch (e: Exception) {}

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        notificationManager?.cancel(1)
    }

    private fun wakeScreenForEmergency() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            @Suppress("DEPRECATION")
            val screenLock = powerManager?.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "Flare:EmergencyScreenWake"
            )
            screenLock?.acquire(8000L) // Turn on screen for 8 seconds on emergency SOS!
        } catch (e: Exception) {}
    }

    private fun wakeScreenBriefly() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            @Suppress("DEPRECATION")
            val screenLock = powerManager?.newWakeLock(
                PowerManager.SCREEN_DIM_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "Flare:MessageScreenWake"
            )
            screenLock?.acquire(3000L) // Wake screen for 3 seconds on incoming message!
        } catch (e: Exception) {}
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Flare Mesh Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the mesh network relay active in the background"
            }

            val msgChannel = NotificationChannel(
                "mesh_messages_v2",
                "Mesh Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Offline peer messages"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 250, 250, 250)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val sosChannel = NotificationChannel(
                "sos_alerts_v2",
                "Emergency SOS Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "High priority emergency alerts"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
            manager.createNotificationChannel(msgChannel)
            manager.createNotificationChannel(sosChannel)
        }
    }

    private var isStartingScan = false
    private var lastScanStartTime = 0L

    private fun startHardwareScanning() {
        ensureWakeLock()
        refreshBluetooth()

        if (isScanning || isStartingScan || bluetoothAdapter?.isEnabled != true || bluetoothLeScanner == null) return

        val now = System.currentTimeMillis()
        if (now - lastScanStartTime < 2000L && lastScanStartTime != 0L) return
        lastScanStartTime = now
        isStartingScan = true

        try {
            val targetMode = ScanSettings.SCAN_MODE_LOW_LATENCY
            currentScanMode = targetMode

            val settingsBuilder = ScanSettings.Builder()
                .setScanMode(targetMode)
                .setReportDelay(0)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                settingsBuilder.setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                settingsBuilder.setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                settingsBuilder.setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                settingsBuilder.setLegacy(true)
            }

            val settings = settingsBuilder.build()

            val filters = listOf(
                ScanFilter.Builder()
                    .setManufacturerData(FLARE_MANUFACTURER_ID, byteArrayOf(0x52, 0x51), byteArrayOf(0xFF.toByte(), 0xFF.toByte()))
                    .build(),
                ScanFilter.Builder()
                    .setManufacturerData(FLARE_MANUFACTURER_ID, byteArrayOf(0x53, 0x7C), byteArrayOf(0xFF.toByte(), 0xFF.toByte()))
                    .build(),
                ScanFilter.Builder()
                    .setManufacturerData(FLARE_MANUFACTURER_ID + 1, byteArrayOf(0), byteArrayOf(0))
                    .build()
            )

            try {
                bluetoothLeScanner?.startScan(filters, settings, scanCallback)
                isScanning = true
            } catch (e: Exception) {
                // Fallback to basic standard ScanSettings for older Android 8 chipsets
                try {
                    val fallbackSettings = ScanSettings.Builder()
                        .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                        .setReportDelay(0)
                        .build()
                    bluetoothLeScanner?.startScan(filters, fallbackSettings, scanCallback)
                    isScanning = true
                } catch (e2: Exception) {
                    Log.e("MeshForegroundService", "startHardwareScanning exception: ${e2.message}")
                    isScanning = false
                }
            }
        } catch (e: Exception) {
            Log.e("MeshForegroundService", "startHardwareScanning exception: ${e.message}")
            isScanning = false
        } finally {
            isStartingScan = false
        }
    }

    private fun stopHardwareScanning() {
        if (!isScanning) return
        try {
            bluetoothLeScanner?.stopScan(scanCallback)
        } catch (e: Exception) {}
        isScanning = false
    }

    private val pendingChunks = HashMap<String, ByteArray>()

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            ensureWakeLock()
            lastPacketReceivedTime = System.currentTimeMillis()
            result ?: return
            val scanRecord = result.scanRecord ?: return
            val deviceAddress = result.device?.address ?: "UNKNOWN"

            val chunk1 = scanRecord.getManufacturerSpecificData(FLARE_MANUFACTURER_ID)
            val chunk2 = scanRecord.getManufacturerSpecificData(FLARE_MANUFACTURER_ID + 1)

            var packetBytes: ByteArray? = null

            if (chunk1 != null && chunk2 != null) {
                packetBytes = chunk1 + chunk2
                pendingChunks.remove(deviceAddress)
            } else if (chunk1 != null) {
                packetBytes = chunk1
                if (chunk1.size >= 24) {
                    pendingChunks[deviceAddress] = chunk1
                }
            } else if (chunk2 != null) {
                val prev = pendingChunks.remove(deviceAddress)
                if (prev != null) {
                    packetBytes = prev + chunk2
                }
            }

            if (packetBytes == null || packetBytes.isEmpty()) return

            val finalBytes = packetBytes

            // 1. Direct in-memory dispatch to MainActivity if alive (avoids duplicate broadcast)
            if (MainActivity.activeInstance != null) {
                MainActivity.activeInstance?.onPacketReceived(finalBytes, result.rssi, deviceAddress)
            } else {
                // 2. Explicit broadcast targeting our own package
                val intent = Intent("com.example.test_1.BLE_PACKET_RECEIVED")
                intent.setPackage(packageName)
                intent.putExtra("payload", finalBytes)
                intent.putExtra("rssi", result.rssi)
                intent.putExtra("deviceAddress", deviceAddress)
                sendBroadcast(intent)
            }

            // 2b. Track nearby peer signal in real-time across all packet formats
            val myHash = getMyHash()
            if (finalBytes.size >= 8 && finalBytes[0] == 0x52.toByte() && finalBytes[1] == 0x51.toByte()) {
                val fByte = finalBytes[2].toInt() and 0xFF
                var peerHash = 0
                when (fByte) {
                    0x48 -> { // Presence Heartbeat
                        peerHash = ((finalBytes[4].toInt() and 0xFF) shl 8) or (finalBytes[5].toInt() and 0xFF)
                    }
                    0x4D -> { // Single-Frame Mesh Chat
                        if (finalBytes.size >= 12) {
                            peerHash = ((finalBytes[7].toInt() and 0xFF) shl 8) or (finalBytes[8].toInt() and 0xFF)
                        }
                    }
                    0xFE -> { // Fragmented Mesh Chat
                        if (finalBytes.size >= 12) {
                            peerHash = ((finalBytes[8].toInt() and 0xFF) shl 8) or (finalBytes[9].toInt() and 0xFF)
                        }
                    }
                    0x41 -> { // Dedicated Delivery ACK
                        if (finalBytes.size >= 10) {
                            peerHash = ((finalBytes[6].toInt() and 0xFF) shl 8) or (finalBytes[7].toInt() and 0xFF)
                        }
                    }
                    0x53 -> { // Emergency SOS
                        if (finalBytes.size >= 20) {
                            peerHash = ((finalBytes[7].toInt() and 0xFF) shl 8) or (finalBytes[8].toInt() and 0xFF)
                        }
                    }
                    0, 1, 2, 3 -> {
                        val isCompact = finalBytes.size >= 14 && (finalBytes[13].toInt() and 0xFF) == (finalBytes.size - 14)
                        if (isCompact) {
                            val b7 = finalBytes[7].toInt() and 0xFF
                            val b8 = finalBytes[8].toInt() and 0xFF
                            peerHash = (b7 shl 8) or b8
                        } else if (finalBytes.size >= 24) {
                            val b17 = finalBytes[17].toInt() and 0xFF
                            val b18 = finalBytes[18].toInt() and 0xFF
                            peerHash = (b17 shl 8) or b18
                        }
                    }
                }
                if (peerHash != 0 && (myHash == 0 || peerHash != myHash)) {
                    updateNearbyPeerSignal(peerHash, result.rssi, deviceAddress)
                }
            }

            // 2c. Track compact auto-sync packets 'S' (0x53) '|' (0x7C)
            if (finalBytes.size >= 11 && finalBytes[0] == 0x53.toByte() && finalBytes[1] == 0x7C.toByte()) {
                var secondSep = -1
                for (i in 2 until finalBytes.size) {
                    if (finalBytes[i] == 0x7C.toByte()) {
                        secondSep = i
                        break
                    }
                }
                if (secondSep != -1 && finalBytes.size >= secondSep + 1 + 8) {
                    val keyBytes = finalBytes.copyOfRange(secondSep + 1, secondSep + 1 + 8)
                    val hexChars = StringBuilder()
                    for (b in keyBytes) {
                        hexChars.append(String.format("%02X", b))
                    }
                    val fullPubKey = "PUB_KEY_$hexChars"
                    val peerHash = consistentHash(fullPubKey) and 0xFFFF
                    if (peerHash != 0 && (myHash == 0 || peerHash != myHash)) {
                        updateNearbyPeerSignal(peerHash, result.rssi, deviceAddress)
                    }

                    if (!MainActivity.isAppInForeground && (myHash == 0 || peerHash != myHash)) {
                        val packetIdHash = (0x53 shl 24) or (peerHash and 0xFFFF)
                        val isNew: Boolean
                        synchronized(seenPacketIds) {
                            isNew = seenPacketIds.add(packetIdHash)
                        }
                        if (isNew) {
                            savePendingBackgroundPacket(finalBytes, result.rssi, deviceAddress)
                            val nameBytes = finalBytes.copyOfRange(2, secondSep)
                            val peerName = String(nameBytes, Charsets.UTF_8).trim().ifEmpty { "Nearby Peer" }
                            showIncomingAlertNotification(
                                "Contact Sync from $peerName",
                                "Tap to open Flare and sync contacts",
                                false,
                                30000 + (peerHash and 0x7FFF)
                            )
                        }
                    }
                }
            }

            // 3. Background Message Processing & Blind Mule Relay
            if (!MainActivity.isAppInForeground && finalBytes.size >= 8 && finalBytes[0] == 0x52.toByte() && finalBytes[1] == 0x51.toByte()) {
                val formatByte = finalBytes[2].toInt() and 0xFF
                var msgId = 0
                var senderHash = 0
                var ttl = 0
                var ttlIndex = -1

                when (formatByte) {
                    0x4D -> { // Single-Frame Mesh Chat (size: 12..48 bytes)
                        if (finalBytes.size >= 12) {
                            msgId = ((finalBytes[4].toInt() and 0xFF) shl 8) or (finalBytes[5].toInt() and 0xFF)
                            ttl = finalBytes[6].toInt() and 0xFF
                            ttlIndex = 6
                            senderHash = ((finalBytes[7].toInt() and 0xFF) shl 8) or (finalBytes[8].toInt() and 0xFF)
                        }
                    }
                    0xFE -> { // Fragmented Mesh Chat (size: 12..48 bytes)
                        if (finalBytes.size >= 12) {
                            val baseMsgId = ((finalBytes[4].toInt() and 0xFF) shl 8) or (finalBytes[5].toInt() and 0xFF)
                            val chunkIndex = finalBytes[7].toInt() and 0xFF
                            senderHash = ((finalBytes[8].toInt() and 0xFF) shl 8) or (finalBytes[9].toInt() and 0xFF)
                            msgId = (baseMsgId shl 8) or chunkIndex
                            ttl = 3
                        }
                    }
                    0x41 -> { // Dedicated Delivery ACK (size: 10 bytes)
                        if (finalBytes.size >= 10) {
                            ttl = finalBytes[3].toInt() and 0xFF
                            ttlIndex = 3
                            msgId = ((finalBytes[4].toInt() and 0xFF) shl 8) or (finalBytes[5].toInt() and 0xFF)
                            senderHash = ((finalBytes[6].toInt() and 0xFF) shl 8) or (finalBytes[7].toInt() and 0xFF)
                        }
                    }
                    0x53 -> { // Emergency SOS Frame (size: 20..48 bytes)
                        if (finalBytes.size >= 20) {
                            ttl = finalBytes[4].toInt() and 0xFF
                            ttlIndex = 4
                            msgId = ((finalBytes[5].toInt() and 0xFF) shl 8) or (finalBytes[6].toInt() and 0xFF)
                            senderHash = ((finalBytes[7].toInt() and 0xFF) shl 8) or (finalBytes[8].toInt() and 0xFF)
                        }
                    }
                    0, 1, 2, 3 -> { // Emergency SOS or Full/Compact Packet
                        val isCompact = finalBytes.size >= 14 && (finalBytes[13].toInt() and 0xFF) == (finalBytes.size - 14)
                        if (isCompact) {
                            ttl = finalBytes[4].toInt() and 0xFF
                            ttlIndex = 4
                            val b5 = finalBytes[5].toInt() and 0xFF
                            val b6 = finalBytes[6].toInt() and 0xFF
                            val b7 = finalBytes[7].toInt() and 0xFF
                            val b8 = finalBytes[8].toInt() and 0xFF
                            msgId = (b5 shl 8) or b6
                            senderHash = (b7 shl 8) or b8
                        } else if (finalBytes.size >= 24) {
                            ttl = finalBytes[14].toInt() and 0xFF
                            ttlIndex = 14
                            val b15 = finalBytes[15].toInt() and 0xFF
                            val b16 = finalBytes[16].toInt() and 0xFF
                            val b17 = finalBytes[17].toInt() and 0xFF
                            val b18 = finalBytes[18].toInt() and 0xFF
                            msgId = (b15 shl 8) or b16
                            senderHash = (b17 shl 8) or b18
                        }
                    }
                }

                if (myHash != 0 && senderHash == myHash) return

                val packetIdHash = (formatByte shl 24) or (msgId shl 8) or (senderHash and 0xFF)
                val isNewPacket: Boolean
                synchronized(seenPacketIds) {
                    isNewPacket = seenPacketIds.add(packetIdHash)
                    if (isNewPacket && seenPacketIds.size > MAX_CACHE_SIZE) {
                        val first = seenPacketIds.iterator().next()
                        seenPacketIds.remove(first)
                    }
                }

                // If already seen, re-send Delivery ACK to confirm receipt to sender, but DO NOT re-save or alert!
                if (!isNewPacket) {
                    if (formatByte == 0x4D || formatByte == 0xFE || formatByte == 0x53) {
                        val actualMsgId = if (formatByte == 0xFE) (msgId shr 8) else msgId
                        sendNativeDeliveryAck(actualMsgId, senderHash)
                    }
                    return
                }

                // Process New Packet
                when (formatByte) {
                    0x4D, 0xFE -> {
                        val actualMsgId = if (formatByte == 0xFE) (msgId shr 8) else msgId
                        savePendingBackgroundPacket(finalBytes, result.rssi, deviceAddress)
                        sendNativeDeliveryAck(actualMsgId, senderHash)
                        wakeScreenBriefly()
                        val contactName = resolveContactName(senderHash)
                        val isBroadcast = finalBytes.size > 3 && (finalBytes[3].toInt() and 0xFF) == 0
                        val preview = if (formatByte == 0x4D && isBroadcast && finalBytes.size > 12) {
                            val len = (finalBytes[11].toInt() and 0xFF).coerceAtMost(finalBytes.size - 12)
                            try {
                                String(finalBytes, 12, len, Charsets.UTF_8).trim()
                            } catch (e: Exception) { "" }
                        } else ""
                        val bodyText = if (preview.isNotEmpty()) preview else "Tap to open Flare"
                        showIncomingAlertNotification(
                            if (isBroadcast) "Broadcast from $contactName" else "New message from $contactName",
                            bodyText,
                            false,
                            10000 + (senderHash and 0x7FFF)
                        )
                    }
                    0x41 -> {
                        savePendingBackgroundPacket(finalBytes, result.rssi, deviceAddress)
                    }
                    0x53 -> {
                        savePendingBackgroundPacket(finalBytes, result.rssi, deviceAddress)
                        sendNativeDeliveryAck(msgId, senderHash)
                        wakeScreenForEmergency()

                        val now = System.currentTimeMillis()
                        val lastTime = lastSosNotificationTime[senderHash] ?: 0L
                        if (now - lastTime > 15000L) {
                            lastSosNotificationTime[senderHash] = now

                            var noteText = ""
                            if (finalBytes.size > 21) {
                                val noteLen = (finalBytes[20].toInt() and 0xFF).coerceAtMost(finalBytes.size - 21)
                                if (noteLen > 0) {
                                    noteText = String(finalBytes, 21, noteLen, Charsets.UTF_8).trim()
                                }
                            }
                            val lat = java.nio.ByteBuffer.wrap(finalBytes, 11, 4).float
                            val lng = java.nio.ByteBuffer.wrap(finalBytes, 15, 4).float
                            val locStr = String.format(java.util.Locale.US, "%.5f, %.5f", lat, lng)
                            val bodyText = if (noteText.isNotEmpty()) "$noteText ($locStr)" else "Location: $locStr"
                            val contactName = resolveContactName(senderHash)

                            showIncomingAlertNotification(
                                "EMERGENCY SOS from $contactName",
                                bodyText,
                                true,
                                20000 + (senderHash and 0x7FFF)
                            )
                        }
                    }
                    0, 1, 2, 3 -> {
                        savePendingBackgroundPacket(finalBytes, result.rssi, deviceAddress)
                        wakeScreenForEmergency()
                        val contactName = resolveContactName(senderHash)
                        showIncomingAlertNotification(
                            "EMERGENCY ALERT from $contactName",
                            "Emergency beacon received",
                            true,
                            20000 + (senderHash and 0x7FFF)
                        )
                    }
                }

                if (ttl > 1) {
                    val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val isMuleEnabled = prefs.getBoolean("flutter.is_mule_enabled", true)
                    if (isMuleEnabled) {
                        val newBytes = finalBytes.clone()
                        if (ttlIndex >= 0) {
                            newBytes[ttlIndex] = (ttl - 1).toByte()
                        }
                        relayPacket(newBytes)
                    }
                }
            }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e("MeshForegroundService", "BLE onScanFailed: errorCode=$errorCode")
            if (errorCode == ScanCallback.SCAN_FAILED_ALREADY_STARTED) {
                isScanning = true
                return
            }
            isScanning = false

            val retryDelay = if (errorCode == 6) { // SCAN_FAILED_SCANNING_TOO_FREQUENTLY
                Log.w("MeshForegroundService", "Scan rate-limited by OS. Backing off for 31 seconds...")
                31000L
            } else {
                5000L
            }

            acquireTransientWakeLock(retryDelay + 4000L)

            mainHandler.postDelayed({
                if (!isScanning) {
                    refreshBluetooth()
                    startHardwareScanning()
                }
            }, retryDelay)
        }
    }

    private fun resolveContactName(senderHash: Int): String {
        try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val contactsJson = prefs.getString("flutter.flare_saved_contacts", null)
                ?: prefs.getString("flutter.resqmesh_saved_contacts", null)
            if (contactsJson != null) {
                val array = JSONArray(contactsJson)
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    val pubKey = obj.optString("publicKey", "")
                    if (pubKey.isNotEmpty() && contactMatchesSender(pubKey, senderHash)) {
                        val name = obj.optString("name", "")
                        if (name.isNotEmpty()) return name
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("MeshForegroundService", "Error resolving contact name: ${e.message}")
        }
        return "Nearby Device"
    }

    private fun contactMatchesSender(pubKey: String, senderHash: Int): Boolean {
        if (pubKey.isEmpty() || senderHash == 0) return false
        val hash = consistentHash(pubKey) and 0xFFFF
        if (hash == senderHash) return true
        val clean = pubKey.replace("PUB_KEY_", "").replace("HASH_", "").uppercase()
        val hexStr = String.format("%04X", senderHash)
        if (clean == hexStr || clean.endsWith(hexStr) || clean.startsWith(hexStr)) return true
        return false
    }

    private fun showIncomingAlertNotification(title: String, body: String, isSos: Boolean, notificationId: Int) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val channelId = if (isSos) "sos_alerts_v2" else "mesh_messages_v2"
            val soundUri = RingtoneManager.getDefaultUri(if (isSos) RingtoneManager.TYPE_ALARM else RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(if (isSos) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_NOTIFICATION)
                    .build()

                val channel = NotificationChannel(
                    channelId,
                    if (isSos) "Emergency SOS Alerts" else "Mesh Messages",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = if (isSos) "High priority emergency alerts" else "Offline peer messages"
                    enableVibration(true)
                    vibrationPattern = if (isSos) longArrayOf(0, 500, 200, 500, 200, 500) else longArrayOf(0, 250, 250, 250)
                    setSound(soundUri, audioAttributes)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    if (isSos) {
                        setBypassDnd(true)
                    }
                }
                notificationManager.createNotificationChannel(channel)
            }

            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(applicationContext, MainActivity::class.java).apply {
                    action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                }
            launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP

            val pendingIntent = PendingIntent.getActivity(
                applicationContext,
                notificationId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = NotificationCompat.Builder(this, channelId)
                .setContentTitle(title)
                .setSmallIcon(R.drawable.ic_notification_flame)
                .setPriority(if (isSos) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .setVibrate(if (isSos) longArrayOf(0, 500, 200, 500, 200, 500) else longArrayOf(0, 250, 250, 250))
                .setSound(soundUri)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setCategory(if (isSos) NotificationCompat.CATEGORY_ALARM else NotificationCompat.CATEGORY_MESSAGE)

            if (isSos) {
                builder.setFullScreenIntent(pendingIntent, true)
            }

            if (body.isNotEmpty()) {
                builder.setContentText(body)
            }

            val notification = builder.build()
            notificationManager.notify(notificationId, notification)
        } catch (e: Exception) {
            Log.e("MeshForegroundService", "Error showing notification: ${e.message}")
        }
    }

    private fun savePendingBackgroundPacket(payload: ByteArray, rssi: Int, deviceAddress: String) {
        try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val existingJson = prefs.getString("flutter.pending_background_packets", "[]") ?: "[]"
            val array = JSONArray(existingJson)
            val obj = JSONObject()
            obj.put("payload", Base64.encodeToString(payload, Base64.NO_WRAP))
            obj.put("rssi", rssi)
            obj.put("deviceAddress", deviceAddress)
            obj.put("timestamp", System.currentTimeMillis())
            array.put(obj)

            val trimmedArray = JSONArray()
            val startIdx = if (array.length() > 50) array.length() - 50 else 0
            for (i in startIdx until array.length()) {
                trimmedArray.put(array.getJSONObject(i))
            }
            prefs.edit().putString("flutter.pending_background_packets", trimmedArray.toString()).commit()
        } catch (e: Exception) {
            Log.e("MeshForegroundService", "Error saving background packet: ${e.message}")
        }
    }

    private fun consistentHash(str: String): Int {
        val clean = str.trim().replace("PUB_KEY_", "").uppercase()
        var hash = 0
        for (i in 0 until clean.length) {
            hash = 0x1fffffff and (hash + clean[i].code)
            hash = 0x1fffffff and (hash + ((0x0007ffff and hash) shl 10))
            hash = hash xor (hash shr 6)
        }
        hash = 0x1fffffff and (hash + ((0x03ffffff and hash) shl 3))
        hash = hash xor (hash shr 11)
        return 0x1fffffff and (hash + ((0x00003fff and hash) shl 15))
    }

    private fun sendNativeDeliveryAck(msgId: Int, targetRecipientHash: Int) {
        if (targetRecipientHash == 0) return
        val now = System.currentTimeMillis()
        val ackKey = (msgId shl 16) or (targetRecipientHash and 0xFFFF)
        val lastSent = lastAckTimeMap[ackKey] ?: 0L
        // Debounce ACK for 3500ms to avoid restarting advertiser on fast successive chunk arrivals
        if (now - lastSent < 3500L) {
            return
        }
        lastAckTimeMap[ackKey] = now
        if (lastAckTimeMap.size > 200) {
            val oldest = lastAckTimeMap.entries.minByOrNull { it.value }?.key
            if (oldest != null) lastAckTimeMap.remove(oldest)
        }

        try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val myPubKey = prefs.getString("flutter.flare_my_pub_key", null)
                ?: prefs.getString("flutter.resqmesh_my_pub_key", null)
            val myHash = if (myPubKey != null) (consistentHash(myPubKey) and 0xFFFF) else 0
            if (myHash == 0 || targetRecipientHash == myHash) return

            val ackPacket = ByteArray(10)
            ackPacket[0] = 0x52.toByte() // 'R'
            ackPacket[1] = 0x51.toByte() // 'Q'
            ackPacket[2] = 0x41.toByte() // 'A' = Delivery ACK
            ackPacket[3] = 3.toByte()    // TTL = 3
            ackPacket[4] = (msgId shr 8).toByte()
            ackPacket[5] = (msgId and 0xFF).toByte()
            ackPacket[6] = (myHash shr 8).toByte()
            ackPacket[7] = (myHash and 0xFF).toByte()
            ackPacket[8] = (targetRecipientHash shr 8).toByte()
            ackPacket[9] = (targetRecipientHash and 0xFF).toByte()

            relayPacket(ackPacket)
        } catch (e: Exception) {
            Log.e("MeshForegroundService", "Error sending native delivery ACK: ${e.message}")
        }
    }

    private var isRelayAdvertising = false
    private val relayAdvertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            isRelayAdvertising = true
        }
        override fun onStartFailure(errorCode: Int) {
            if (errorCode == AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED) {
                isRelayAdvertising = true
                return
            }
            isRelayAdvertising = false
            isNativeBroadcasting = false
        }
    }

    private fun stopRelayAdvertiser() {
        if (isRelayAdvertising) {
            try {
                bluetoothLeAdvertiser?.stopAdvertising(relayAdvertiseCallback)
            } catch (e: Exception) {}
            isRelayAdvertising = false
        }
        isNativeBroadcasting = false
    }

    private fun relayPacket(payload: ByteArray) {
        val isAck = payload.size >= 3 && payload[2] == 0x41.toByte()
        // 4200ms hold time for Delivery ACKs outlasts sender's 3500ms broadcast, guaranteeing delivery ticks!
        val holdTime = if (isAck) 4200L else 1200L

        acquireTransientWakeLock(holdTime + 2000L)
        refreshBluetooth()
        val advertiser = bluetoothLeAdvertiser ?: return

        // 1. Stop any active advertising cleanly BEFORE declaring native broadcast!
        stopPresenceHeartbeatAdvertiser()
        stopRelayAdvertiser()

        // 2. Now declare active native broadcast so postDelayed will not abort
        isNativeBroadcasting = true
        lastNativeBroadcastStartTime = System.currentTimeMillis()
        nativeBroadcastTimeoutMs = holdTime + 1500L

        mainHandler.postDelayed({
            if (!isNativeBroadcasting) return@postDelayed
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    try {
                        if (payload.size > 48) {
                            val isLeCodedSupported = bluetoothAdapter?.isLeCodedPhySupported == true
                            val parameters = AdvertisingSetParameters.Builder()
                                .setLegacyMode(false)
                                .setInterval(AdvertisingSetParameters.INTERVAL_MIN)
                                .setTxPowerLevel(AdvertisingSetParameters.TX_POWER_MAX)
                                .setPrimaryPhy(BluetoothDevice.PHY_LE_1M)
                                .setSecondaryPhy(if (isLeCodedSupported) BluetoothDevice.PHY_LE_CODED else BluetoothDevice.PHY_LE_1M)
                                .build()

                            val advertiseData = AdvertiseData.Builder()
                                .setIncludeDeviceName(false)
                                .setIncludeTxPowerLevel(false)
                                .addManufacturerData(FLARE_MANUFACTURER_ID, payload)
                                .build()
                            
                            val callback = object : AdvertisingSetCallback() {}
                            advertiser.startAdvertisingSet(parameters, advertiseData, null, null, null, callback)
                            
                            mainHandler.postDelayed({
                                try { advertiser.stopAdvertisingSet(callback) } catch (e: Exception) {}
                                isNativeBroadcasting = false
                                if (!MainActivity.isAppInForeground) {
                                    mainHandler.postDelayed({
                                        if (!MainActivity.isAppInForeground && !isNativeBroadcasting && !MainActivity.isAdvertisingCurrently) {
                                            startBackgroundHeartbeat(forceRefresh = true)
                                        }
                                    }, 60L)
                                }
                            }, holdTime)
                            return@postDelayed
                        }
                    } catch (e: Exception) {
                        // Fallback to legacy below
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

                advertiser.startAdvertising(legacySettings, legacyData, scanResponse, relayAdvertiseCallback)
                
                mainHandler.postDelayed({
                    stopRelayAdvertiser()
                    isNativeBroadcasting = false
                    if (!MainActivity.isAppInForeground) {
                        mainHandler.postDelayed({
                            if (!MainActivity.isAppInForeground && !isNativeBroadcasting && !MainActivity.isAdvertisingCurrently) {
                                startBackgroundHeartbeat(forceRefresh = true)
                            }
                        }, 60L)
                    }
                }, holdTime)
            } catch (e: Exception) {
                isNativeBroadcasting = false
                isRelayAdvertising = false
                if (!MainActivity.isAppInForeground) {
                    mainHandler.postDelayed({
                        if (!MainActivity.isAppInForeground && !isNativeBroadcasting && !MainActivity.isAdvertisingCurrently) {
                            startBackgroundHeartbeat(forceRefresh = true)
                        }
                    }, 60L)
                }
            }
        }, 60L)
    }
}
