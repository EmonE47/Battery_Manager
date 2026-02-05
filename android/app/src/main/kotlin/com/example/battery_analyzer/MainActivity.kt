package com.example.battery_analyzer

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import android.content.BroadcastReceiver
import android.util.Log

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.battery_analyzer/battery"
    private val EVENT_CHANNEL = "com.example.battery_analyzer/battery_events"
    
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var batteryReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Method Channel for getting battery info
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> handleRequestPermissions(result)
                "getBatteryInfo" -> handleGetBatteryInfo(result)
                "startBackgroundService" -> handleStartBackgroundService(result)
                "stopBackgroundService" -> handleStopBackgroundService(result)
                "isBackgroundServiceRunning" -> result.success(BatteryMonitoringService.isMonitoring())
                else -> result.notImplemented()
            }
        }
        
        // Event Channel for battery change events
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerBatteryReceiver()
                }
                
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterBatteryReceiver()
                }
            }
        )
        
        Log.d("BatteryAnalyzer", "Native battery plugin initialized")
    }
    
    private fun handleRequestPermissions(result: Result) {
        // Request notification permission for Android 13+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ requires runtime permission for notifications
            when {
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED -> {
                    // Permission already granted
                    Log.d("BatteryAnalyzer", "Notification permission already granted")
                    result.success(true)
                }
                else -> {
                    // Request permission
                    Log.d("BatteryAnalyzer", "Requesting notification permission")
                    androidx.core.app.ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        REQUEST_NOTIFICATION_PERMISSION
                    )
                    result.success(true) // Return true anyway, permission check will happen later
                }
            }
        } else {
            // No special permission needed for Android 12 and below
            result.success(true)
        }
    }
    
    companion object {
        private const val REQUEST_NOTIFICATION_PERMISSION = 100
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_NOTIFICATION_PERMISSION -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    Log.d("BatteryAnalyzer", "Notification permission granted")
                } else {
                    Log.d("BatteryAnalyzer", "Notification permission denied")
                }
            }
        }
    }
    
    private fun handleGetBatteryInfo(result: Result) {
        try {
            val batteryInfo = getBatteryInfo()
            result.success(batteryInfo)
        } catch (e: Exception) {
            Log.e("BatteryAnalyzer", "Error getting battery info", e)
            result.error("BATTERY_ERROR", e.message, null)
        }
    }
    
    private fun getBatteryInfo(): Map<String, Any> {
        val intent = applicationContext.registerReceiver(
            null, 
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )
        
        if (intent == null) {
            return emptyMap()
        }
        
        val batteryManager = applicationContext.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        
        val data = mutableMapOf<String, Any>()
        
        // Basic battery info (available on all Android versions)
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val temperature = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0)
        val voltage = intent.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0)
        val health = intent.getIntExtra(BatteryManager.EXTRA_HEALTH, BatteryManager.BATTERY_HEALTH_UNKNOWN)
        val technology = intent.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY) ?: "Unknown"
        
        data["level"] = level
        data["scale"] = scale
        data["isPlugged"] = plugged > 0
        data["status"] = status
        data["temperature"] = temperature
        data["voltage"] = voltage
        data["health"] = health
        data["technology"] = technology
        
        // Current in microamperes (available on API 21+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val currentMicroA = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
                data["current"] = currentMicroA
                
                // Charge counter in nAh (available on API 21+)
                val chargeCounter = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
                if (chargeCounter != BatteryManager.BATTERY_PROPERTY_CURRENT_NOW) {
                    data["chargeCounter"] = chargeCounter
                }
                
                // Capacity in percentage (available on API 21+)
                val capacity = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                if (capacity != BatteryManager.BATTERY_PROPERTY_CURRENT_NOW) {
                    data["capacity"] = capacity
                }
                
                // Energy counter in nWh (available on API 28+)
                var energyCounter = 0L
                var capacityFound = false
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    energyCounter = batteryManager.getLongProperty(BatteryManager.BATTERY_PROPERTY_ENERGY_COUNTER)
                    Log.d("BatteryAnalyzer", "Energy counter value: $energyCounter")
                    if (energyCounter != -1L && energyCounter > 0) {
                        data["energyCounter"] = energyCounter
                        
                        // Calculate actual design capacity from energy and voltage
                        // Energy is in nWh, voltage is in mV
                        if (voltage > 0) {
                            // Design capacity (mAh) = Energy (nWh) * 1000 / Voltage (mV)
                            val designCapacityMah = (energyCounter * 1000) / voltage
                            if (designCapacityMah in 1000..30000) {
                                data["designCapacity"] = designCapacityMah
                                Log.d("BatteryAnalyzer", "✅ Design capacity from energy: ${designCapacityMah}mAh (energy=${energyCounter}nWh, voltage=${voltage}mV)")
                                capacityFound = true
                            }
                        }
                    } else {
                        Log.d("BatteryAnalyzer", "Energy counter not available: $energyCounter")
                    }
                }
                
                // Fallback: Try charge counter (available on API 21+)
                if (!capacityFound && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    try {
                        val chargeCounter = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
                        Log.d("BatteryAnalyzer", "Charge counter value: $chargeCounter")
                        if (chargeCounter > 1000000) { // Must be reasonable
                            val designCapacityMah = chargeCounter / 1000 // nAh to mAh
                            if (designCapacityMah in 1000..30000) {
                                data["designCapacity"] = designCapacityMah
                                Log.d("BatteryAnalyzer", "✅ Design capacity from charge counter: ${designCapacityMah}mAh")
                                capacityFound = true
                            }
                        }
                    } catch (e: Exception) {
                        Log.d("BatteryAnalyzer", "Could not get charge counter: ${e.message}")
                    }
                }
                
                // Also get capacity percentage if available
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    try {
                        val capacityPercent = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                        if (capacityPercent in 1..100) {
                            data["capacityPercent"] = capacityPercent
                            Log.d("BatteryAnalyzer", "Capacity percentage: ${capacityPercent}%")
                        }
                    } catch (e: Exception) {
                        Log.d("BatteryAnalyzer", "Could not get capacity percent: ${e.message}")
                    }
                }
                
                // Final fallback: Try reading from system files if all else fails
                if (!capacityFound) {
                    val systemCapacity = getCapacityFromSystemFiles()
                    if (systemCapacity > 0) {
                        data["designCapacity"] = systemCapacity
                        Log.d("BatteryAnalyzer", "✅ Design capacity from system files: ${systemCapacity}mAh")
                    }
                }
                
            } catch (e: Exception) {
                Log.e("BatteryAnalyzer", "Error getting advanced battery properties", e)
            }
        }
        
        // Additional info for API 28+ - REMOVED PROBLEMATIC LINE
        // The BATTERY_STATUS_PRESENT constant might not exist in older APIs
        // We'll skip this check for compatibility
        
        Log.d("BatteryAnalyzer", "Battery info: $data")
        return data
    }
    
    // Fallback method to read battery capacity from system files
    private fun getCapacityFromSystemFiles(): Int {
        return try {
            // Try reading from power supply files
            val capacityFile = "/sys/class/power_supply/battery/charge_full_design"
            val capacityFile2 = "/sys/class/power_supply/battery/energy_full_design"
            val capacityFile3 = "/sys/class/power_supply/battery/charge_full"
            
            for (file in listOf(capacityFile, capacityFile2, capacityFile3)) {
                try {
                    val content = java.io.File(file).readText().trim()
                    val capacity = content.toLongOrNull()
                    if (capacity != null && capacity > 1000000) {
                        val capacityMah = (capacity / 1000).toInt() // nAh or nWh to mAh
                        if (capacityMah in 1000..30000) {
                            Log.d("BatteryAnalyzer", "✅ Capacity from system file ($file): ${capacityMah}mAh")
                            return capacityMah
                        }
                    }
                } catch (e: Exception) {
                    // Continue to next file
                }
            }
            
            // Try alternative paths
            val batteryFile = java.io.File("/sys/class/power_supply").listFiles()?.firstOrNull { 
                it.name.contains("battery", ignoreCase = true) 
            }
            if (batteryFile != null) {
                val designFile = java.io.File(batteryFile, "charge_full_design")
                if (designFile.exists()) {
                    val capacity = designFile.readText().trim().toLongOrNull()
                    if (capacity != null && capacity > 1000000) {
                        val capacityMah = (capacity / 1000).toInt()
                        if (capacityMah in 1000..30000) {
                            Log.d("BatteryAnalyzer", "✅ Capacity from battery file: ${capacityMah}mAh")
                            return capacityMah
                        }
                    }
                }
            }
            
            0
        } catch (e: Exception) {
            Log.d("BatteryAnalyzer", "Could not read capacity from system files: ${e.message}")
            0
        }
    }
    
    private fun registerBatteryReceiver() {
        if (batteryReceiver != null) return
        
        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == Intent.ACTION_BATTERY_CHANGED) {
                    val batteryInfo = getBatteryInfo()
                    eventSink?.success(batteryInfo)
                }
            }
        }
        
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_BATTERY_CHANGED)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(Intent.ACTION_BATTERY_LOW)
            addAction(Intent.ACTION_BATTERY_OKAY)
        }
        
        registerReceiver(batteryReceiver, filter)
    }
    
    private fun unregisterBatteryReceiver() {
        batteryReceiver?.let {
            unregisterReceiver(it)
            batteryReceiver = null
        }
    }
    
    override fun onDestroy() {
        unregisterBatteryReceiver()
        super.onDestroy()
    }
    
    private fun handleStartBackgroundService(result: MethodChannel.Result) {
        try {
            val intent = Intent(this, BatteryMonitoringService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.d("BatteryAnalyzer", "Background service started")
            result.success(true)
        } catch (e: Exception) {
            Log.e("BatteryAnalyzer", "Error starting background service", e)
            result.error("SERVICE_ERROR", e.message, null)
        }
    }
    
    private fun handleStopBackgroundService(result: MethodChannel.Result) {
        try {
            val intent = Intent(this, BatteryMonitoringService::class.java)
            stopService(intent)
            Log.d("BatteryAnalyzer", "Background service stopped")
            result.success(true)
        } catch (e: Exception) {
            Log.e("BatteryAnalyzer", "Error stopping background service", e)
            result.error("SERVICE_ERROR", e.message, null)
        }
    }
}