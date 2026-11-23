package ch.markusbaechler.geburtstage

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import java.io.File
import java.util.Calendar
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Home screen widgets in the design «Nacht, leiser».
 *
 * The app stores all birthdays as JSON ("people", with optional photo
 * paths). The widgets compute the days themselves and draw the whole widget
 * as one image: a poster in the person's colour with a giant age. Android refreshes them every
 * 30 minutes, and on every resize.
 */
data class Entry(
    val name: String,
    val full: String,
    val day: Int,
    val month: Int,
    val year: Int?,
    val color: Int,
    val photo: String?,
)

data class Next(val entry: Entry, val days: Int, val turning: Int?, val weekday: Int, val date: Calendar)

object BirthdayCalc {
    const val ROSE = 0xFFE9A7C0.toInt()
    // The same posters as in the app (lib/ui/poster.dart).
    private val PALETTE = intArrayOf(
        0xFFE4572E.toInt(), 0xFF0E7C7B.toInt(), 0xFF6C4CE0.toInt(), 0xFFD98A0B.toInt(),
        0xFFD0407F.toInt(), 0xFF2D6CDF.toInt(), 0xFF3E9B4F.toInt())
    private val DEEP = intArrayOf(
        0xFFAE3513.toInt(), 0xFF075453.toInt(), 0xFF462BB0.toInt(), 0xFFA05F00.toInt(),
        0xFF9A2157.toInt(), 0xFF1848A8.toInt(), 0xFF226B34.toInt())

    fun deep(n: Next): Int = DEEP[Math.floorMod(n.entry.color, DEEP.size)]
    private val WEEKDAYS = arrayOf("", "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag")
    private val WEEKDAYS_SHORT = arrayOf("", "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa")

    fun parse(json: String?): List<Entry> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Entry(
                    name = o.optString("n"),
                    full = o.optString("f", o.optString("n")),
                    day = o.getInt("d"),
                    month = o.getInt("m"),
                    year = if (o.isNull("y")) null else o.getInt("y"),
                    color = o.optInt("c", 0),
                    photo = if (o.isNull("p")) null else o.optString("p"),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun isLeap(y: Int) = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0

    private fun occurrence(year: Int, month: Int, day: Int): Calendar {
        val d = if (month == 2 && day == 29 && !isLeap(year)) 28 else day
        return Calendar.getInstance().apply {
            clear()
            set(year, month - 1, d, 12, 0, 0)
        }
    }

    fun upcoming(entries: List<Entry>): List<Next> {
        val now = Calendar.getInstance()
        val today = Calendar.getInstance().apply {
            clear()
            set(now.get(Calendar.YEAR), now.get(Calendar.MONTH), now.get(Calendar.DAY_OF_MONTH), 12, 0, 0)
        }
        return entries.map { e ->
            var date = occurrence(today.get(Calendar.YEAR), e.month, e.day)
            if (date.before(today)) date = occurrence(today.get(Calendar.YEAR) + 1, e.month, e.day)
            val days = Math.round((date.timeInMillis - today.timeInMillis) / 86_400_000.0).toInt()
            val turning = e.year?.let { date.get(Calendar.YEAR) - it }
            Next(e, days, turning, date.get(Calendar.DAY_OF_WEEK), date)
        }.sortedBy { it.days }
    }

    fun color(n: Next): Int = PALETTE[Math.floorMod(n.entry.color, PALETTE.size)]

    /** Big element: the first name. */
    fun big(n: Next): String = n.entry.name

    fun whenText(n: Next): String = when (n.days) {
        0 -> "HEUTE"
        1 -> "MORGEN"
        else -> "IN ${n.days} TAGEN"
    }

    fun below(n: Next): String {
        val day = "${WEEKDAYS[n.weekday]}, ${n.date.get(Calendar.DAY_OF_MONTH)}.${n.date.get(Calendar.MONTH) + 1}."
        return if (n.turning != null) "wird ${n.turning} · $day" else day
    }

    fun dateShort(n: Next): String =
        "${WEEKDAYS_SHORT[n.weekday]} ${n.date.get(Calendar.DAY_OF_MONTH)}.${n.date.get(Calendar.MONTH) + 1}."
}

/** Draws the widget into a bitmap. All sizes in px; [d] = px per dp. */
private class WidgetPainter(private val context: Context, private val d: Float) {
    private val bg = 0xFF141119.toInt()
    private val border = 0xFF2A2532.toInt()
    private val ink = 0xFFECE7F2.toInt()
    private val inkSoft = 0xFFCFC8DA.toInt()
    private val muted = 0xFF9C95A8.toInt()
    private val divider = 0xFF231F2A.toInt()

    private val sans = Typeface.create("sans-serif", Typeface.NORMAL)
    private val sansMedium = Typeface.create("sans-serif-medium", Typeface.NORMAL)

    private fun flex(weight: Int): Typeface {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                return Typeface.Builder(context.assets, "flutter_assets/assets/fonts/RobotoFlex.ttf")
                    .setFontVariationSettings("'wght' $weight, 'opsz' 144")
                    .build() ?: fallback(weight)
            } catch (e: Exception) {
                // fall through
            }
        }
        return fallback(weight)
    }

    private fun fallback(weight: Int): Typeface =
        if (weight >= 600) Typeface.create("sans-serif", Typeface.BOLD)
        else Typeface.create("sans-serif-thin", Typeface.NORMAL)

    private val thin by lazy { flex(180) }
    private val bold by lazy { flex(720) }
    private val heavy by lazy { flex(800) }
    private val light by lazy { flex(320) }

    private fun dp(v: Float) = v * d

    fun render(w: Int, h: Int, list: List<Next>, large: Boolean): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val radius = dp(28f)
        val card = RectF(0f, 0f, w.toFloat(), h.toFloat())
        val clip = Path().apply { addRoundRect(card, radius, radius, Path.Direction.CW) }
        c.save()
        c.clipPath(clip)
        c.drawColor(bg)

        val first = list.firstOrNull()
        if (first == null) {
            drawEmpty(c, w, h)
        } else {
            val color = BirthdayCalc.color(first)
            val heroW = if (large) w * 0.56f else w.toFloat()
            drawHero(c, first, color, heroW, h.toFloat(), large)
            if (large) drawList(c, list.drop(1).take(3), heroW, w.toFloat(), h.toFloat())
        }
        c.restore()
        return bmp
    }

    private fun blend(a: Int, b: Int, t: Float): Int = Color.rgb(
        (Color.red(a) + (Color.red(b) - Color.red(a)) * t).roundToInt(),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * t).roundToInt(),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).roundToInt())

    private fun drawGlow(c: Canvas, cx: Float, cy: Float, r: Float, color: Int, alpha: Float) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.shader = RadialGradient(cx, cy, r, withAlpha(color, alpha), withAlpha(color, 0f), Shader.TileMode.CLAMP)
        c.drawCircle(cx, cy, r, p)
    }

    private fun drawRings(c: Canvas, cx: Float, cy: Float, base: Float, color: Int) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dp(1f)
        }
        for (i in 0 until 5) {
            p.color = withAlpha(color, max(0.06f, 0.34f - i * 0.06f))
            c.drawCircle(cx, cy, base * (0.28f + i * 0.17f), p)
        }
    }

    private fun drawSparks(c: Canvas, w: Float, h: Float, color: Int) {
        val r = java.util.Random(7)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        repeat(26) {
            val x = r.nextFloat() * w
            val y = r.nextFloat() * h
            p.color = withAlpha(color, 0.25f + r.nextFloat() * 0.5f * (y / h))
            c.drawCircle(x, y, dp(0.8f + r.nextFloat() * 1.6f), p)
        }
    }

    /** A poster in the person's colour: giant age, bold first name. */
    private fun drawHero(c: Canvas, n: Next, color: Int, w: Float, h: Float, large: Boolean) {
        val deep = BirthdayCalc.deep(n)
        val pad = dp(18f)
        c.save()
        c.clipRect(0f, 0f, w, h)

        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        bgPaint.shader = LinearGradient(0f, 0f, w, h, color, blend(color, deep, 0.75f), Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, w, h, bgPaint)
        drawGlow(c, 0f, 0f, max(w, h) * 0.8f, Color.WHITE, 0.2f)

        // Giant figure: the age, or the first letter.
        val figure = n.turning?.toString() ?: n.entry.name.take(1).uppercase()
        val fig = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = heavy
            this.color = withAlpha(deep, 0.62f)
            textSize = h * (if (figure.length > 2) 0.7f else 0.95f)
            letterSpacing = -0.06f
            textAlign = Paint.Align.RIGHT
        }
        c.drawText(figure, w + dp(6f), h * 0.62f, fig)
        if (n.days == 0) drawSparks(c, w, h, Color.WHITE)

        if (n.entry.photo != null) {
            val avatar = dp(if (large) 40f else 36f)
            drawAvatar(c, n, pad, pad, avatar, color)
        }

        // Bottom line: age and weekday.
        val below = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = sans
            textSize = dp(13f)
            this.color = withAlpha(Color.WHITE, 0.9f)
        }
        val belowBaseline = h - pad
        c.drawText(ellipsize(BirthdayCalc.below(n), below, w - 2 * pad), pad, belowBaseline, below)

        // First name: bold, as wide as fits.
        val name = BirthdayCalc.big(n)
        val namePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = bold
            this.color = Color.WHITE
            letterSpacing = -0.03f
        }
        var size = min(h * 0.27f, dp(46f))
        namePaint.textSize = size
        val maxW = w - 2 * pad
        val measured = namePaint.measureText(name)
        if (measured > maxW) {
            size *= maxW / measured
            namePaint.textSize = size
        }
        val nameBaseline = belowBaseline - dp(21f)
        c.drawText(name, pad - dp(1f), nameBaseline, namePaint)

        // When: small caps above the name.
        val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = sansMedium
            textSize = dp(11f)
            letterSpacing = 0.14f
            this.color = withAlpha(Color.WHITE, 0.92f)
        }
        c.drawText(BirthdayCalc.whenText(n), pad, nameBaseline - size * 0.82f - dp(5f), label)
        c.restore()
    }

    private fun drawList(c: Canvas, rows: List<Next>, x0: Float, x1: Float, h: Float) {
        if (rows.isEmpty()) return
        val pad = dp(16f)
        val right = x1 - pad
        val divPaint = Paint().apply { color = divider; strokeWidth = dp(1f) }
        c.drawLine(x0, pad, x0, h - pad, divPaint)

        val rowH = (h - 2 * pad) / 3f
        val avatar = min(dp(28f), rowH * 0.62f)
        val name = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = sans; textSize = dp(13f); color = ink }
        val date = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = light; textSize = dp(12.5f); color = muted }
        rows.forEachIndexed { i, n ->
            val cy = pad + rowH * i + rowH / 2
            val ax = x0 + dp(14f)
            drawAvatar(c, n, ax, cy - avatar / 2, avatar, BirthdayCalc.color(n))
            val textX = ax + avatar + dp(10f)
            val dateText = if (n.days == 0) "heute" else BirthdayCalc.dateShort(n)
            val dateW = date.measureText(dateText)
            c.drawText(dateText, right - dateW, cy + dp(4.5f), date)
            c.drawText(ellipsize(n.entry.name, name, right - dateW - dp(8f) - textX), textX, cy + dp(4.5f), name)
        }
    }

    private fun drawAvatar(c: Canvas, n: Next, x: Float, y: Float, size: Float, color: Int) {
        val cx = x + size / 2
        val cy = y + size / 2
        val inner = size / 2 - dp(3f)
        val photo = n.entry.photo?.let { loadPhoto(it, (inner * 2).roundToInt()) }
        if (photo != null) {
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            val shader = BitmapShader(photo, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            val scale = (inner * 2) / min(photo.width, photo.height)
            val m = Matrix()
            m.setScale(scale, scale)
            m.postTranslate(cx - photo.width * scale / 2, cy - photo.height * scale / 2)
            shader.setLocalMatrix(m)
            p.shader = shader
            c.drawCircle(cx, cy, inner, p)
        } else {
            val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
            c.drawCircle(cx, cy, size / 2, fill)
            val initials = n.entry.full.split(" ")
                .mapNotNull { w -> w.firstOrNull { it.isLetter() } }.take(2)
                .joinToString("") { it.uppercase() }
            val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = bold
                textSize = size * 0.36f
                this.color = Color.WHITE
                textAlign = Paint.Align.CENTER
            }
            val fm = t.fontMetrics
            c.drawText(initials, cx, cy - (fm.ascent + fm.descent) / 2, t)
        }
        if (photo != null) {
            val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp(1.2f)
                this.color = withAlpha(Color.WHITE, 0.7f)
            }
            c.drawCircle(cx, cy, size / 2 - dp(0.6f), ring)
        }
    }

    private fun drawEmpty(c: Canvas, w: Int, h: Int) {
        drawRings(c, w * 0.9f, h * 0.15f, min(w, h).toFloat(), muted)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = sans; textSize = dp(13f); color = inkSoft }
        c.drawText("Noch niemand erfasst", dp(18f), h - dp(18f), p)
    }

    private val photoCache = HashMap<String, Bitmap?>()

    private fun loadPhoto(path: String, target: Int): Bitmap? = photoCache.getOrPut(path) {
        try {
            if (!File(path).exists()) {
                null
            } else {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                var sample = 1
                while (target > 0 && min(bounds.outWidth, bounds.outHeight) / (sample * 2) >= target) sample *= 2
                BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun ellipsize(text: String, p: Paint, maxW: Float): String {
        if (maxW <= 0) return ""
        if (p.measureText(text) <= maxW) return text
        var t = text
        while (t.isNotEmpty() && p.measureText("$t…") > maxW) t = t.dropLast(1)
        return "$t…"
    }

    private fun withAlpha(color: Int, a: Float): Int =
        Color.argb((a.coerceIn(0f, 1f) * 255).roundToInt(), Color.red(color), Color.green(color), Color.blue(color))
}

private fun renderInto(
    context: Context,
    appWidgetManager: AppWidgetManager,
    id: Int,
    data: SharedPreferences,
    large: Boolean,
) {
    val list = BirthdayCalc.upcoming(BirthdayCalc.parse(data.getString("people", null)))
    val density = context.resources.displayMetrics.density
    val opts: Bundle = appWidgetManager.getAppWidgetOptions(id)
    var wDp = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
    var hDp = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
    if (wDp <= 0) wDp = if (large) 320 else 160
    if (hDp <= 0) hDp = 160
    // Keep the bitmap within the RemoteViews memory budget.
    val scale = min(density, 1100f / max(wDp, hDp))
    val w = (wDp * scale).roundToInt().coerceAtLeast(100)
    val h = (hDp * scale).roundToInt().coerceAtLeast(100)

    val bmp = WidgetPainter(context, scale).render(w, h, list, large)
    val views = RemoteViews(context.packageName, R.layout.widget_image)
    views.setImageViewBitmap(R.id.w_image, bmp)
    val first = list.firstOrNull()
    views.setContentDescription(
        R.id.w_image,
        if (first == null) "Geburtstage: noch niemand erfasst"
        else "Nächster Geburtstag: ${first.entry.full}, ${BirthdayCalc.whenText(first).lowercase()}" +
            (first.turning?.let { ", wird $it" } ?: ""),
    )
    views.setOnClickPendingIntent(
        R.id.widget_root,
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
    )
    appWidgetManager.updateAppWidget(id, views)
}

class LargeBirthdayWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) renderInto(context, appWidgetManager, id, widgetData, large = true)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        renderInto(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context), large = true)
    }
}

class SmallBirthdayWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) renderInto(context, appWidgetManager, id, widgetData, large = false)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        renderInto(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context), large = false)
    }
}
