package wtf.openstrap.openstrap_edge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The live workout's notification: Android's stand-in for a Live Activity.
 *
 * Two looks. Below Android 16, or when the owner turns the status bar chip
 * off, it is the card measured off the reference lock screen (heart rate,
 * timer, zone track, two figures either side of the wordmark), coloured
 * dark. On Android 16 and up it is a promoted Live Update instead: the
 * system's own layout with the zones as a segmented progress bar, which buys
 * the chip in the status bar (and Samsung's Now Bar), the nearest thing
 * Android has to the Dynamic Island. Promotion forbids a custom layout, so
 * one notification cannot be both.
 *
 * While the band's tracking service runs, the card takes over that
 * service's foreground notification: only a foreground service's
 * notification may be colourised, and the workout is the thing worth
 * showing while it runs. When the session ends the service's own
 * notification comes back.
 */
object LiveActivityNotifier {
    private const val METHOD_CHANNEL = "openstrap/live_activity"
    private const val CHANNEL_ID = "live_workout"
    private const val OWN_ID = 4310
    private const val TAG = "LiveActivity"

    /** The page under the card, and the grey of zone 0 and the labels. */
    private const val CARD = 0xFF121619.toInt()
    private const val IDLE = 0xFF8E9499.toInt()
    private const val TRACK = 0xFF4A4F53.toInt()
    private const val BLUE = 0xFF0093E7.toInt()

    /** Zone 0 (below zone 1) to zone 5, the app's zone colours. */
    private val ZONES = intArrayOf(
        IDLE,
        0xFFAEC2CD.toInt(),
        0xFF479AC2.toInt(),
        0xFF59B896.toInt(),
        0xFFFBAC5D.toInt(),
        0xFFFF6422.toInt(),
    )

    private data class Session(
        val startedAtMs: Long,
        val name: String,
        val promote: Boolean,
        val imperial: Boolean,
    )

    private data class Frame(
        val hr: Int? = null,
        val zone: Int = 0,
        /** 0..6: zone n's segment spans [n, n + 1]. */
        val zonePos: Double = 0.0,
        val strain: Double? = null,
        val calories: Int? = null,
        val distanceKm: Double? = null,
        val paceSecPerKm: Double? = null,
        /** The app's own clock, pauses taken out; null falls back to wall time. */
        val elapsedSec: Long? = null,
        val paused: Boolean = false,
    )

    @Volatile private var session: Session? = null
    @Volatile private var frame = Frame()
    private var wordmark: Bitmap? = null

    fun register(engine: FlutterEngine, app: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        session = Session(
                            startedAtMs = (call.argument<Number>("startedAtMs")
                                ?: System.currentTimeMillis()).toLong(),
                            name = call.argument<String>("name") ?: "Live session",
                            promote = call.argument<Boolean>("promote") ?: true,
                            imperial = call.argument<Boolean>("imperial") ?: false,
                        )
                        frame = Frame()
                        post(app)
                        result.success(true)
                    }
                    "update" -> {
                        frame = Frame(
                            hr = call.argument<Number>("hr")?.toInt()?.takeIf { it > 0 },
                            zone = (call.argument<Number>("zone")?.toInt() ?: 0).coerceIn(0, 5),
                            zonePos = (call.argument<Number>("zonePos")?.toDouble() ?: 0.0)
                                .coerceIn(0.0, 6.0),
                            strain = call.argument<Number>("strain")?.toDouble(),
                            calories = call.argument<Number>("calories")?.toInt(),
                            distanceKm = call.argument<Number>("distanceKm")?.toDouble(),
                            paceSecPerKm = call.argument<Number>("paceSecPerKm")?.toDouble(),
                            elapsedSec = call.argument<Number>("elapsedSec")?.toLong(),
                            paused = call.argument<Boolean>("paused") ?: false,
                        )
                        post(app)
                        result.success(true)
                    }
                    "end" -> {
                        session = null
                        frame = Frame()
                        restore(app)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** The workout's notification while one is live, for the tracking
     *  service to show instead of its own when it (re)starts mid-session. */
    fun current(ctx: Context): Notification? = session?.let { build(ctx, it, frame) }

    private fun post(ctx: Context) {
        val n = current(ctx) ?: return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try {
            if (EdgeTrackingService.running) {
                nm.notify(EdgeTrackingService.NOTIF_ID, n)
            } else {
                nm.notify(OWN_ID, n)
            }
        } catch (e: SecurityException) {
            // Notifications not granted: the workout still runs in the app.
            Log.w(TAG, "notify refused: $e")
        }
    }

    private fun restore(ctx: Context) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(OWN_ID)
        if (EdgeTrackingService.running) {
            try {
                nm.notify(EdgeTrackingService.NOTIF_ID, EdgeTrackingService.baseNotification(ctx))
            } catch (e: SecurityException) {
                Log.w(TAG, "restore refused: $e")
            }
        }
    }

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        // Default importance so the card shows on the lock screen and can be
        // promoted; silent, because it is updated every few seconds.
        val ch = NotificationChannel(
            CHANNEL_ID, "Live workout", NotificationManager.IMPORTANCE_DEFAULT,
        )
        ch.description = "Your heart rate, zone and time while a workout runs"
        ch.setSound(null, null)
        ch.enableVibration(false)
        ch.setShowBadge(false)
        ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        nm.createNotificationChannel(ch)
    }

    private fun openApp(ctx: Context): PendingIntent {
        val i = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?: Intent(ctx, MainActivity::class.java)
        i.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        // The live session screen (kRouteWorkoutIdle in Dart).
        i.putExtra(MainActivity.EXTRA_ROUTE, "/workouts/idle")
        return PendingIntent.getActivity(
            ctx, 0, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun build(ctx: Context, s: Session, f: Frame): Notification {
        ensureChannel(ctx)
        return if (s.promote && Build.VERSION.SDK_INT >= 36) liveUpdate(ctx, s, f) else card(ctx, s, f)
    }

    // ── the two figures under the track ──────────────────────────────────

    /** Left and right: distance and pace on a route, strain and calories
     *  otherwise. Absent stays "–", never 0. */
    private fun figures(s: Session, f: Frame): List<Pair<CharSequence, String>> {
        val dash = "–"
        if (f.distanceKm != null) {
            val unit = if (s.imperial) "mi" else "km"
            val d = if (s.imperial) f.distanceKm / 1.609344 else f.distanceKm
            val pace = f.paceSecPerKm?.let { if (s.imperial) it * 1.609344 else it }
                ?.takeIf { it.isFinite() && it in 60.0..3600.0 }
            return listOf(
                withUnit(String.format(Locale.US, "%.2f", d), unit) to "DISTANCE",
                (pace?.let { withUnit(clock(it.roundToInt()), "/ $unit") } ?: dash) to "PACE",
            )
        }
        return listOf(
            (f.strain?.let { String.format(Locale.US, "%.1f", it) } ?: dash) to "STRAIN",
            (f.calories?.let { withUnit("$it", "kcal") } ?: dash) to "CALORIES",
        )
    }

    private fun withUnit(value: String, unit: String): CharSequence {
        val b = SpannableStringBuilder(value).append(' ')
        val at = b.length
        b.append(unit)
        b.setSpan(RelativeSizeSpan(.62f), at, b.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        b.setSpan(ForegroundColorSpan(0xCCFFFFFF.toInt()), at, b.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return b
    }

    /** How long the session has run, in ms: the app's clock when it sent one. */
    private fun elapsedMs(s: Session, f: Frame): Long =
        f.elapsedSec?.let { it * 1000 } ?: (System.currentTimeMillis() - s.startedAtMs)

    /** "ZONE n", or nothing while no heart rate is arriving. */
    private fun zoneLabel(f: Frame): String = if (f.hr == null) "" else "ZONE ${f.zone}"

    private fun clock(sec: Int) = "${sec / 60}:${(sec % 60).toString().padStart(2, '0')}"

    // ── the card ─────────────────────────────────────────────────────────

    private fun card(ctx: Context, s: Session, f: Frame): Notification {
        val tint = ZONES[f.zone]
        val base = SystemClock.elapsedRealtime() - elapsedMs(s, f)
        val hr = f.hr?.toString() ?: "--"

        val big = RemoteViews(ctx.packageName, R.layout.live_card)
        big.setTextViewText(R.id.hr, hr)
        big.setInt(R.id.heart, "setColorFilter", tint)
        big.setInt(R.id.timer_icon, "setColorFilter", BLUE)
        big.setChronometer(R.id.timer, base, null, !f.paused)
        big.setImageViewBitmap(R.id.track, track(ctx, f))
        big.setImageViewBitmap(R.id.glow, glow(tint))
        wordmark(ctx)?.let { big.setImageViewBitmap(R.id.wordmark, it) }
        val (left, right) = figures(s, f)
        big.setTextViewText(R.id.left_value, left.first)
        big.setTextViewText(R.id.left_label, left.second)
        big.setTextViewText(R.id.right_value, right.first)
        big.setTextViewText(R.id.right_label, right.second)

        val small = RemoteViews(ctx.packageName, R.layout.live_card_small)
        small.setTextViewText(R.id.hr, hr)
        small.setInt(R.id.heart, "setColorFilter", tint)
        small.setInt(R.id.timer_icon, "setColorFilter", BLUE)
        small.setTextViewText(R.id.zone, if (f.paused) "PAUSED" else zoneLabel(f))
        small.setTextColor(R.id.zone, tint)
        small.setChronometer(R.id.timer, base, null, !f.paused)

        return NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_live_heart)
            .setContentTitle(if (f.hr == null) s.name else "$hr bpm · Zone ${f.zone}")
            .setContentText(s.name)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(small)
            .setCustomBigContentView(big)
            .setColor(CARD)
            .setColorized(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(openApp(ctx))
            .build()
    }

    private fun dp(ctx: Context, v: Float) = v * ctx.resources.displayMetrics.density

    /**
     * The zone track: six segments, the live zone's lit, a white marker at
     * the heart rate's place and ZONE n under it in the zone's colour. Drawn
     * at the card's likely width (the screen less the shade's margins), so
     * the fitXY stretch is at most a few percent.
     */
    private fun track(ctx: Context, f: Frame): Bitmap {
        val dm = ctx.resources.displayMetrics
        val w = max(dp(ctx, 200f), dm.widthPixels - dp(ctx, 64f)).roundToInt()
        val h = dp(ctx, 30f).roundToInt()
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val gap = dp(ctx, 3f)
        val y = dp(ctx, 8f)
        val seg = (w - gap * 5) / 6f
        val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            strokeWidth = dp(ctx, 3f)
            strokeCap = Paint.Cap.ROUND
        }
        for (i in 0 until 6) {
            val x0 = i * (seg + gap)
            line.color = if (i == f.zone) ZONES[f.zone] else TRACK
            c.drawLine(x0 + line.strokeWidth / 2, y, x0 + seg - line.strokeWidth / 2, y, line)
        }
        // No heart rate: the bare track, no marker and no label.
        if (f.hr == null) return bmp
        // The marker: the heart rate's place within its zone's segment.
        val zi = min(5, f.zonePos.toInt())
        val within = (f.zonePos - zi).coerceIn(0.0, 1.0)
        val mx = (zi * (seg + gap) + within * seg).toFloat()
            .coerceIn(dp(ctx, 7f), w - dp(ctx, 7f))
        val dot = Paint(Paint.ANTI_ALIAS_FLAG)
        dot.color = CARD
        c.drawCircle(mx, y, dp(ctx, 7.5f), dot)
        dot.color = Color.WHITE
        c.drawCircle(mx, y, dp(ctx, 6f), dot)
        // ZONE n under it, kept inside the track.
        val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ZONES[f.zone]
            textSize = dp(ctx, 10f)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            letterSpacing = .12f
        }
        val text = "ZONE ${f.zone}"
        val tw = label.measureText(text)
        val tx = (mx - tw / 2).coerceIn(0f, w - tw)
        c.drawText(text, tx, h - dp(ctx, 3f), label)
        return bmp
    }

    /** The card's glow: the zone's colour lit from the top left, fading
     *  into the dark by the middle. Small; the ImageView stretches it. */
    private fun glow(tint: Int): Bitmap {
        val w = 160
        val h = 70
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val lit = Color.argb(150, Color.red(tint), Color.green(tint), Color.blue(tint))
        p.shader = RadialGradient(
            0f, h * .35f, w * .55f,
            intArrayOf(lit, Color.argb(0, Color.red(tint), Color.green(tint), Color.blue(tint))),
            floatArrayOf(0f, 1f), Shader.TileMode.CLAMP,
        )
        c.drawRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), p)
        return bmp
    }

    /** LOCUS in Super Bubble, read from the app's own font asset; null if
     *  the asset cannot be read, and the card goes without it. */
    private fun wordmark(ctx: Context): Bitmap? {
        wordmark?.let { return it }
        return try {
            val face = Typeface.createFromAsset(
                ctx.assets, "flutter_assets/assets/fonts/SuperBubble/SuperBubble-Regular.ttf",
            )
            val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = face
                textSize = dp(ctx, 15f)
                color = IDLE
                letterSpacing = .08f
            }
            val text = "LOCUS"
            val w = p.measureText(text).roundToInt() + 4
            val h = dp(ctx, 18f).roundToInt()
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            Canvas(bmp).drawText(text, 2f, h * .8f, p)
            wordmark = bmp
            bmp
        } catch (e: Exception) {
            Log.w(TAG, "wordmark: $e")
            null
        }
    }

    // ── the Live Update (Android 16+) ────────────────────────────────────

    private fun liveUpdate(ctx: Context, s: Session, f: Frame): Notification {
        val hr = f.hr?.toString() ?: "--"
        val (left, right) = figures(s, f)
        val line = (if (f.hr == null) "" else "Zone ${f.zone} · ") +
            "${left.first} ${left.second.lowercase()} · " +
            "${right.first} ${right.second.lowercase()}"
        val elapsed = elapsedMs(s, f)
        val style = Notification.ProgressStyle()
            .setStyledByProgress(false)
            .setProgressSegments(
                ZONES.map { Notification.ProgressStyle.Segment(100).setColor(it) },
            )
            .setProgress((f.zonePos * 100).roundToInt().coerceIn(0, 600))
            .setProgressTrackerIcon(
                Icon.createWithResource(ctx, R.drawable.ic_live_heart).setTint(Color.WHITE),
            )
        return Notification.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_live_heart)
            .setContentTitle(if (f.hr == null) s.name else "$hr bpm")
            .setContentText(line)
            .setStyle(style)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setWhen(System.currentTimeMillis() - elapsed)
            .setShowWhen(!f.paused)
            .setUsesChronometer(!f.paused)
            .setShortCriticalText(if (f.paused) "Paused" else if (f.hr == null) "Live" else "$hr bpm")
            // Asks Android 16 to promote it (the chip). The builder method is
            // newer than this SDK's stubs; the extra is what it sets.
            .addExtras(Bundle().apply { putBoolean("android.requestPromotedOngoing", true) })
            .setCategory(Notification.CATEGORY_WORKOUT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(openApp(ctx))
            .build()
    }
}
