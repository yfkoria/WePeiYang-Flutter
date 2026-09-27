package com.twt.service.schedule

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import com.twt.service.MainActivity
import com.twt.service.R
import org.json.JSONObject
import java.util.Calendar

/** Keeps the next two days of class alarms in the OS, independently of Flutter. */
object ClassReminder {
    private const val TAG = "ClassReminder"
    private const val PREFS = "class_reminder"
    private const val CHANNEL = "class_reminder"
    private const val ACTION_EVENT = "com.twt.service.schedule.EVENT"
    private const val ACTION_REFRESH = "com.twt.service.schedule.REFRESH"
    private const val FIRST_ID = 71000
    private const val REFRESH_ID = 71999
    private val starts = listOf("08:30", "09:20", "10:25", "11:15", "13:30", "14:20", "15:25", "16:15", "18:30", "19:20", "20:10", "21:00")
    private val ends = listOf("09:15", "10:05", "11:10", "12:00", "14:15", "15:05", "16:10", "17:00", "19:15", "20:05", "20:55", "21:45")

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun flutterPrefs(context: Context) = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    private fun alarms(context: Context) = context.getSystemService(AlarmManager::class.java)
    private fun notifications(context: Context) = context.getSystemService(NotificationManager::class.java)

    fun status(context: Context): Map<String, Any> {
        val p = prefs(context)
        val exact = Build.VERSION.SDK_INT < 31 || alarms(context).canScheduleExactAlarms()
        return mapOf(
            "enabled" to p.getBoolean("enabled", false),
            "silent" to p.getBoolean("silent", false),
            "minute20" to p.getBoolean("minute20", true),
            "minute10" to p.getBoolean("minute10", true),
            "minute5" to p.getBoolean("minute5", true),
            "exact" to exact,
            "policy" to notifications(context).isNotificationPolicyAccessGranted,
            "notifications" to notifications(context).areNotificationsEnabled(),
            "focus" to hasFocusPermission(context),
            "protocol" to Settings.System.getInt(context.contentResolver, "notification_focus_protocol", 0)
        )
    }

    fun setOption(context: Context, key: String, value: Boolean) {
        require(key in setOf("enabled", "silent", "minute20", "minute10", "minute5"))
        prefs(context).edit().putBoolean(key, value).commit()
        if (key == "enabled" && !value || key == "silent" && !value) restoreSilence(context)
        reschedule(context)
    }

    fun openSetting(context: Context, kind: String) {
        val intent = when (kind) {
            "exact" -> Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            "policy" -> Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            "notifications" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            else -> return
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    @Synchronized
    fun reschedule(context: Context) {
        val app = context.applicationContext
        val p = prefs(app)
        val alarm = alarms(app)
        for (id in FIRST_ID until FIRST_ID + p.getInt("count", 0)) {
            alarm.cancel(pending(app, id, ACTION_EVENT))
        }
        alarm.cancel(pending(app, REFRESH_ID, ACTION_REFRESH))
        p.edit().putInt("count", 0).commit()
        if (!p.getBoolean("enabled", false)) return

        val now = System.currentTimeMillis()
        val day = Calendar.getInstance().apply { set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
        val events = mutableListOf<Event>()
        val quiet = mutableListOf<Pair<Long, Long>>()
        val courseJson = flutterPrefs(app).getString("flutter.courseData", "") ?: ""
        val termStart = flutterPrefs(app).getLong("flutter.termStart", 1676822400L) * 1000L
        try {
            val table = JSONObject(courseJson)
            val term = Calendar.getInstance().apply {
                timeInMillis = termStart
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            for (offset in 0..2) {
                val date = (day.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, offset) }
                val days = (date.timeInMillis - term.timeInMillis) / 86400000L
                val week = (days / 7L + 1L).toInt()
                if (days < 0 || week > 24) continue
                val weekday = (date.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
                for (kind in listOf("schoolCourses", "customCourses")) {
                    val courses = table.optJSONArray(kind) ?: continue
                    for (i in 0 until courses.length()) {
                        val course = courses.optJSONObject(i) ?: continue
                        val arrangements = course.optJSONArray("arrangeList") ?: continue
                        for (j in 0 until arrangements.length()) {
                            val arrangement = arrangements.optJSONObject(j) ?: continue
                            if (arrangement.optInt("weekday") != weekday) continue
                            val weeks = arrangement.optJSONArray("weekList") ?: continue
                            if (!(0 until weeks.length()).any { weeks.optInt(it) == week }) continue
                            val units = arrangement.optJSONArray("unitList") ?: continue
                            val first = units.optInt(0) - 1
                            val last = units.optInt(units.length() - 1) - 1
                            if (first !in starts.indices || last !in ends.indices || last < first) continue
                            val start = at(date, starts[first])
                            val end = at(date, ends[last])
                            val name = course.optString("name", "课程")
                            val location = arrangement.optString("location", "")
                            val notificationId = ("$kind:$i:$j:${date.timeInMillis}").hashCode()
                            for (minutes in listOf(20, 10, 5)) {
                                if (p.getBoolean("minute$minutes", true) && start - minutes * 60000L > now) {
                                    events.add(Event(start - minutes * 60000L, "remind", name, location, minutes, notificationId, start))
                                }
                            }
                            if (start > now) events.add(Event(start, "dismiss", "", "", 0, notificationId, start))
                            if (p.getBoolean("silent", false) && end + 300000L > now) {
                                quiet.add(Pair(start - 300000L, end + 300000L))
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Cannot read course table", e)
        }

        quiet.sortBy { it.first }
        var mergedStart = 0L
        var mergedEnd = 0L
        for ((start, end) in quiet) {
            if (mergedEnd != 0L && start <= mergedEnd) {
                mergedEnd = maxOf(mergedEnd, end)
            } else {
                if (mergedEnd != 0L) addQuietWindow(events, mergedStart, mergedEnd, now)
                mergedStart = start
                mergedEnd = end
            }
        }
        if (mergedEnd != 0L) addQuietWindow(events, mergedStart, mergedEnd, now)
        if (quiet.none { it.first <= now && now < it.second }) restoreSilence(app)

        events.sortBy { it.at }
        events.forEachIndexed { index, event ->
            val id = FIRST_ID + index
            val intent = Intent(app, ClassReminderReceiver::class.java).apply {
                action = ACTION_EVENT
                putExtra("kind", event.kind)
                putExtra("name", event.name)
                putExtra("location", event.location)
                putExtra("minutes", event.minutes)
                putExtra("notificationId", event.notificationId)
                putExtra("classStart", event.classStart)
            }
            schedule(app, event.at, id, intent)
        }
        p.edit().putInt("count", events.size).commit()
        val nextDay = (day.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1); set(Calendar.MINUTE, 5) }
        val refresh = Intent(app, ClassReminderReceiver::class.java).apply { action = ACTION_REFRESH }
        schedule(app, nextDay.timeInMillis, REFRESH_ID, refresh)
    }

    private fun addQuietWindow(events: MutableList<Event>, start: Long, end: Long, now: Long) {
        if (start <= now && now < end) events.add(Event(now + 1000L, "silenceStart"))
        else if (start > now) events.add(Event(start, "silenceStart"))
        if (end > now) events.add(Event(end, "silenceEnd"))
    }

    private fun at(day: Calendar, hhmm: String): Long = (day.clone() as Calendar).apply {
        set(Calendar.HOUR_OF_DAY, hhmm.substring(0, 2).toInt())
        set(Calendar.MINUTE, hhmm.substring(3).toInt())
    }.timeInMillis

    private fun pending(context: Context, id: Int, action: String): PendingIntent {
        val intent = Intent(context, ClassReminderReceiver::class.java).apply { this.action = action }
        return PendingIntent.getBroadcast(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun schedule(context: Context, at: Long, id: Int, intent: Intent) {
        val alarm = alarms(context)
        val pi = PendingIntent.getBroadcast(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        if (Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()) {
            try {
                alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } catch (_: SecurityException) {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } else {
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    fun handle(context: Context, intent: Intent) {
        if (intent.action != ACTION_EVENT) {
            reschedule(context)
            return
        }
        when (intent.getStringExtra("kind")) {
            "remind" -> if (prefs(context).getBoolean("enabled", false)) post(context, intent.getStringExtra("name") ?: "课程", intent.getStringExtra("location") ?: "", intent.getIntExtra("minutes", 5), intent.getIntExtra("notificationId", 0), intent.getLongExtra("classStart", 0L))
            "dismiss" -> notifications(context).cancel(intent.getIntExtra("notificationId", 0))
            "silenceStart" -> silence(context)
            "silenceEnd" -> restoreSilence(context)
        }
    }

    private fun silence(context: Context) {
        if (!prefs(context).getBoolean("enabled", false) || !prefs(context).getBoolean("silent", false)) return
        val audio = context.getSystemService(AudioManager::class.java)
        val p = prefs(context)
        if (p.getBoolean("active", false)) return
        val original = audio.ringerMode
        if (original == AudioManager.RINGER_MODE_SILENT) return
        try {
            audio.ringerMode = AudioManager.RINGER_MODE_SILENT
            p.edit().putInt("original", original).putBoolean("active", true).commit()
        } catch (e: SecurityException) {
            Log.w(TAG, "Notification policy access is required for silent mode", e)
        }
    }

    private fun restoreSilence(context: Context) {
        val p = prefs(context)
        if (!p.getBoolean("active", false)) return
        val audio = context.getSystemService(AudioManager::class.java)
        try {
            if (audio.ringerMode == AudioManager.RINGER_MODE_SILENT) {
                audio.ringerMode = p.getInt("original", AudioManager.RINGER_MODE_NORMAL)
            }
            p.edit().putBoolean("active", false).commit()
        } catch (e: SecurityException) {
            Log.w(TAG, "Could not restore ringer mode", e)
        }
    }

    fun test(context: Context) = post(context, "测试课程", "测试教室", 5, 71998, System.currentTimeMillis() + 300000L)

    private fun post(context: Context, name: String, location: String, minutes: Int, id: Int, classStart: Long) {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = notifications(context)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "上课提醒", NotificationManager.IMPORTANCE_HIGH))
        }
        val content = if (location.isBlank()) "$minutes 分钟后上课" else "$minutes 分钟后上课 · $location"
        val click = PendingIntent.getActivity(context, id, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context)
        }
        builder.setSmallIcon(R.drawable.push_small)
            .setContentTitle(name)
            .setContentText(content)
            .setContentIntent(click)
            .setAutoCancel(true)
        if (Build.VERSION.SDK_INT >= 26) {
            builder.setTimeoutAfter((classStart - System.currentTimeMillis()).coerceAtLeast(10000L))
        }
        val notification = builder.build()
        // The OS ignores these extras on unsupported versions. OS4 may report a new protocol value.
        if (Settings.System.getInt(context.contentResolver, "notification_focus_protocol", 0) >= 3 ||
            Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true)) {
            val params = JSONObject().put("param_v2", JSONObject()
                .put("protocol", 1)
                .put("business", "class_reminder")
                .put("islandFirstFloat", true)
                .put("enableFloat", true)
                .put("updatable", true)
                .put("timeout", minutes + 1)
                .put("aodTitle", "$minutes 分钟后上课")
                .put("param_island", JSONObject()
                    .put("islandProperty", 1)
                    .put("islandTimeout", (minutes + 1) * 60)
                    .put("bigIslandArea", JSONObject().put("imageTextInfoLeft", JSONObject()
                        .put("type", 1)
                        .put("picInfo", JSONObject().put("type", 1).put("pic", "miui.focus.pic_course"))
                        .put("textInfo", JSONObject()
                            .put("title", name.take(4))
                            .put("content", "${minutes}分钟"))))
                    .put("smallIslandArea", JSONObject().put("picInfo", JSONObject()
                        .put("type", 1)
                        .put("pic", "miui.focus.pic_course"))))
                .put("baseInfo", JSONObject().put("title", name).put("content", content).put("type", 2)))
            val pics = android.os.Bundle().apply {
                putParcelable("miui.focus.pic_course", android.graphics.drawable.Icon.createWithResource(context, R.drawable.push_small))
            }
            notification.extras.putBundle("miui.focus.pics", pics)
            notification.extras.putString("miui.focus.param", params.toString())
        }
        manager.notify(id, notification)
    }

    private fun hasFocusPermission(context: Context): Boolean = try {
        val extras = android.os.Bundle().apply { putString("package", context.packageName) }
        context.contentResolver.call(android.net.Uri.parse("content://miui.statusbar.notification.public"), "canShowFocus", null, extras)
            ?.getBoolean("canShowFocus", false) ?: false
    } catch (_: Exception) { false }

    private data class Event(
        val at: Long,
        val kind: String,
        val name: String = "",
        val location: String = "",
        val minutes: Int = 0,
        val notificationId: Int = 0,
        val classStart: Long = 0L
    )
}

class ClassReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ClassReminder.handle(context, intent)
    }
}
