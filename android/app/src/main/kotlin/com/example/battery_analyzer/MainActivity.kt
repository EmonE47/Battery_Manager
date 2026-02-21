package com.example.battery_analyzer

import android.Manifest
import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.battery_analyzer/battery"
    private val eventChannelName = "com.example.battery_analyzer/battery_events"
    private val notificationPermissionRequestCode = 1001

    private var eventSink: EventChannel.EventSink? = null
    private var batteryReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "requestPermissions" -> handlePermissionRequest(result)
                    "getBatteryInfo" -> result.success(getBatteryInfo())
                    "startBackgroundService" -> startBackgroundService(result)
                    "stopBackgroundService" -> stopBackgroundService(result)
                    "isBackgroundServiceRunning" -> {
                        result.success(isBackgroundServiceRunning())
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(
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
    }

    private fun handlePermissionRequest(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }

        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) {
            result.success(true)
            return
        }

        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode
        )
        result.success(false)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            Log.d("BatteryAnalyzer", "Notification permission granted=$granted")
        }
    }

    private fun getBatteryInfo(): Map<String, Any> {
        val statusIntent = applicationContext.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        ) ?: return emptyMap()

        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager

        val level = statusIntent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = statusIntent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val status = statusIntent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = statusIntent.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)
        val temperature = statusIntent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0)
        val voltage = statusIntent.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0)
        val health = statusIntent.getIntExtra(
            BatteryManager.EXTRA_HEALTH,
            BatteryManager.BATTERY_HEALTH_UNKNOWN
        )
        val technology = statusIntent.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY) ?: "Unknown"

        val data = mutableMapOf<String, Any>(
            "level" to level,
            "scale" to scale,
            "status" to status,
            "isPlugged" to (plugged > 0),
            "temperature" to temperature,
            "voltage" to voltage,
            "health" to health,
            "technology" to technology,
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "product" to Build.PRODUCT,
            "timestamp" to System.currentTimeMillis()
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val currentNow = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
            if (currentNow != Int.MIN_VALUE) {
                data["current"] = currentNow
            }

            val chargeCounter = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
            if (chargeCounter > 0) {
                data["chargeCounter"] = chargeCounter
            }

            val capacity = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            if (capacity in 0..100) {
                data["capacity"] = capacity
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val energyCounter = batteryManager.getLongProperty(BatteryManager.BATTERY_PROPERTY_ENERGY_COUNTER)
            if (energyCounter > 0 && voltage > 0) {
                data["energyCounter"] = energyCounter
                val remainingCapacityMah = (energyCounter * 1000L / voltage).toInt()
                if (remainingCapacityMah in 1..30000) {
                    data["remainingCapacityFromEnergy"] = remainingCapacityMah
                }
            }
        }

        return data
    }

    private fun registerBatteryReceiver() {
        if (batteryReceiver != null) {
            return
        }

        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_BATTERY_CHANGED) {
                    eventSink?.success(getBatteryInfo())
                }
            }
        }

        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(batteryReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(batteryReceiver, filter)
        }
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

    private fun startBackgroundService(result: MethodChannel.Result) {
        try {
            val serviceIntent = Intent(this, BatteryMonitoringService::class.java)
            BatteryMonitoringService.setMonitoringEnabled(this, true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            result.success(true)
        } catch (error: Exception) {
            result.error("SERVICE_START_ERROR", error.message, null)
        }
    }

    private fun stopBackgroundService(result: MethodChannel.Result) {
        try {
            val serviceIntent = Intent(this, BatteryMonitoringService::class.java)
            BatteryMonitoringService.setMonitoringEnabled(this, false)
            stopService(serviceIntent)
            result.success(true)
        } catch (error: Exception) {
            result.error("SERVICE_STOP_ERROR", error.message, null)
        }
    }

    private fun isBackgroundServiceRunning(): Boolean {
        if (BatteryMonitoringService.isMonitoring()) {
            return true
        }

        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        @Suppress("DEPRECATION")
        val running = activityManager.getRunningServices(Int.MAX_VALUE).any { serviceInfo ->
            serviceInfo.service.className == BatteryMonitoringService::class.java.name
        }

        if (running) {
            return true
        }

        return BatteryMonitoringService.shouldStartOnBoot(this)
    }
}
