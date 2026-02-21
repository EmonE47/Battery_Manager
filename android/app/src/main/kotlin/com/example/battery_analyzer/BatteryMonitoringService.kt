package com.example.battery_analyzer

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import kotlin.math.abs

class BatteryMonitoringService : Service() {
    private val channelId = "battery_monitoring_channel"
    private val notificationId = 1401
    private val updateIntervalMs = 2000L

    private val mainHandler = Handler(Looper.getMainLooper())
    private var batteryReceiver: BroadcastReceiver? = null
    private lateinit var notificationManager: NotificationManager
    private lateinit var batteryManager: BatteryManager
    private var explicitlyStopped = false

    private val updater = object : Runnable {
        override fun run() {
            updateNotification()
            mainHandler.postDelayed(this, updateIntervalMs)
        }
    }

    companion object {
        private var isRunning = false
        private const val actionStop = "com.example.battery_analyzer.STOP_MONITORING"
        private const val prefsName = "battery_monitoring_prefs"
        private const val keyMonitoringEnabled = "monitoring_enabled"

        fun isMonitoring(): Boolean = isRunning

        fun setMonitoringEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(keyMonitoringEnabled, enabled)
                .apply()
        }

        fun shouldStartOnBoot(context: Context): Boolean {
            return context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .getBoolean(keyMonitoringEnabled, false)
        }
    }

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == actionStop) {
            explicitlyStopped = true
            setMonitoringEnabled(this, false)
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        explicitlyStopped = false

        val initialNotification = createNotification(
            batteryPercent = 0,
            statusLabel = "Starting monitor",
            tempC = 0.0,
            currentMa = 0,
            powerMw = 0.0
        )
        startForeground(notificationId, initialNotification)

        registerBatteryReceiver()
        mainHandler.removeCallbacks(updater)
        mainHandler.post(updater)

        setMonitoringEnabled(this, true)
        isRunning = true
        return START_STICKY
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(updater)
        unregisterBatteryReceiver()
        isRunning = false
        if (!explicitlyStopped && shouldStartOnBoot(this)) {
            scheduleRestart()
        }
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (shouldStartOnBoot(this)) {
            scheduleRestart()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val channel = NotificationChannel(
            channelId,
            "Battery monitoring",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Persistent live battery monitoring"
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun registerBatteryReceiver() {
        if (batteryReceiver != null) {
            return
        }

        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_BATTERY_CHANGED) {
                    updateNotification()
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

    private fun updateNotification() {
        val statusIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?: return

        val level = statusIntent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = statusIntent.getIntExtra(BatteryManager.EXTRA_SCALE, 100).coerceAtLeast(1)
        val status = statusIntent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val tempRaw = statusIntent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0)
        val voltageMv = statusIntent.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0)

        val currentMicroA = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
        } else {
            0
        }
        val currentMa = if (currentMicroA == Int.MIN_VALUE) 0 else currentMicroA / 1000
        val batteryPercent = ((level * 100f) / scale).toInt().coerceIn(0, 100)
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL

        val statusLabel = if (isCharging) "Charging" else "Discharging"
        val tempC = tempRaw / 10.0
        val powerMw = abs(currentMa) * (voltageMv / 1000.0)

        val notification = createNotification(
            batteryPercent = batteryPercent,
            statusLabel = statusLabel,
            tempC = tempC,
            currentMa = currentMa,
            powerMw = powerMw
        )
        notificationManager.notify(notificationId, notification)
    }

    private fun createNotification(
        batteryPercent: Int,
        statusLabel: String,
        tempC: Double,
        currentMa: Int,
        powerMw: Double
    ): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            1,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, BatteryMonitoringService::class.java).apply {
            action = actionStop
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            2,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val direction = when {
            currentMa > 0 -> "+$currentMa mA"
            currentMa < 0 -> "$currentMa mA"
            else -> "0 mA"
        }
        val text = "$statusLabel | $direction | ${powerMw.toInt()} mW | ${"%.1f".format(tempC)} C"

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Battery $batteryPercent%")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setSmallIcon(
                if (statusLabel == "Charging") {
                    android.R.drawable.stat_sys_upload_done
                } else {
                    android.R.drawable.stat_notify_sync_noanim
                }
            )
            .setContentIntent(openPendingIntent)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopPendingIntent
            )
            .build()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun scheduleRestart() {
        val restartIntent = Intent(applicationContext, BatteryMonitoringService::class.java)
        val restartPendingIntent = PendingIntent.getService(
            applicationContext,
            1403,
            restartIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAtMs = System.currentTimeMillis() + 1500L
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMs,
                restartPendingIntent
            )
        } else {
            alarmManager.set(
                AlarmManager.RTC_WAKEUP,
                triggerAtMs,
                restartPendingIntent
            )
        }
    }
}
