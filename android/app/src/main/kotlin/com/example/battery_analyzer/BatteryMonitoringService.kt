package com.example.battery_analyzer

import android.app.Service
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.Context
import android.content.IntentFilter
import android.content.BroadcastReceiver
import android.os.Build
import android.os.BatteryManager
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import android.util.Log

class BatteryMonitoringService : Service() {
    private val CHANNEL_ID = "battery_monitoring_channel"
    private val NOTIFICATION_ID = 1
    private val TAG = "BatteryMonitoringService"
    
    private var batteryReceiver: BroadcastReceiver? = null
    private var lastBatteryLevel = 0
    private var lastTemperature = 0
    private var lastVoltage = 0
    private var lastHealth = "Unknown"
    private var lastDesignCapacity = 4000
    
    companion object {
        private var isRunning = false
        
        fun isMonitoring(): Boolean = isRunning
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service started")
        
        try {
            // Start foreground with initial notification
            val notification = createNotification("Battery Analyzer", "Initializing...", 0, 0)
            startForeground(NOTIFICATION_ID, notification)
            
            // Register battery receiver
            registerBatteryReceiver()
            
            isRunning = true
            
            // Update notification immediately
            updateBatteryInfo()
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground service", e)
            // Continue anyway, just log the error
        }
        
        return START_STICKY
    }
    
    override fun onDestroy() {
        Log.d(TAG, "Service destroyed")
        if (batteryReceiver != null) {
            try {
                unregisterReceiver(batteryReceiver)
            } catch (e: Exception) {
                Log.e(TAG, "Error unregistering receiver", e)
            }
        }
        isRunning = false
        super.onDestroy()
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Battery Monitoring"
            val descriptionText = "Real-time battery monitoring"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                enableVibration(false)
                enableLights(false)
                setShowBadge(false)
            }
            
            val notificationManager: NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(
        title: String,
        text: String,
        batteryLevel: Int,
        temperature: Int
    ): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent: PendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val largeText = if (batteryLevel > 0) {
            "Level: $batteryLevel% | Temp: ${temperature / 10}°C | Health: $lastHealth"
        } else {
            text
        }
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(largeText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(largeText))
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setShowWhen(true)
            .setColor(ContextCompat.getColor(this, android.R.color.holo_green_dark))
            .build()
    }
    
    private fun registerBatteryReceiver() {
        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == Intent.ACTION_BATTERY_CHANGED) {
                    updateBatteryInfo()
                }
            }
        }
        
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        registerReceiver(batteryReceiver, filter, Context.RECEIVER_EXPORTED)
        Log.d(TAG, "Battery receiver registered")
    }
    
    private fun updateBatteryInfo() {
        try {
            val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus: Intent? = registerReceiver(null, ifilter)
            
            if (batteryStatus != null) {
                lastBatteryLevel = batteryStatus.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = batteryStatus.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                lastTemperature = batteryStatus.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0)
                lastVoltage = batteryStatus.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0)
                lastHealth = getHealthStatus(batteryStatus.getIntExtra(BatteryManager.EXTRA_HEALTH, -1))
                
                // Get design capacity from BatteryManager
                val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val chargeCounter = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
                    if (chargeCounter > 1000000) {
                        lastDesignCapacity = chargeCounter / 1000
                    }
                }
                
                val statusInt = batteryStatus.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                val isCharging = statusInt == BatteryManager.BATTERY_STATUS_CHARGING || 
                                statusInt == BatteryManager.BATTERY_STATUS_FULL
                
                // Update notification with current battery info
                val statusText = if (isCharging) "🔌 Charging" else "⚡ Discharging"
                val title = "🔋 Battery: $lastBatteryLevel%"
                val text = "$statusText | Temp: ${lastTemperature / 10}°C | Health: $lastHealth | Cap: ${lastDesignCapacity}mAh"
                
                val notification = createNotification(title, text, lastBatteryLevel, lastTemperature)
                val notificationManager: NotificationManager =
                    getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(NOTIFICATION_ID, notification)
                
                Log.d(TAG, "Notification updated: Level=$lastBatteryLevel%, Temp=${lastTemperature / 10}°C, Capacity=$lastDesignCapacity mAh")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error updating battery info", e)
        }
    }
    
    private fun getHealthStatus(health: Int): String {
        return when (health) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "Good ✅"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Overheat 🔥"
            BatteryManager.BATTERY_HEALTH_DEAD -> "Dead ❌"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Over Voltage ⚡"
            BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "Failure ❌"
            BatteryManager.BATTERY_HEALTH_COLD -> "Cold ❄️"
            else -> "Unknown"
        }
    }
}
