package ch.markusbaechler.geburtstage

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
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
 * as one image: photo, rings, light, thin type. Android refreshes them every
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
    private val PALETTE = intArrayOf(0xFF8FB4E8.toInt(), 0xFF8FD0AA.toInt(), 0xFFE3C27A.toInt())
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

    fun color(n: Next): Int = if (n.days == 0) ROSE else PALETTE[Math.floorMod(n.entry.color, PALETTE.size)]

    /** Big element: the age, or the name when the birth year is unknown. */
    fun big(n: Next): String = n.turning?.toString() ?: n.entry.name

    fun whenText(n: Next): String = when (n.days) {
        0 -> "HEUTE"
        1 -> "MORGEN"
        else -> "IN ${n.days} TAGEN"
    }

    fun below(n: Next): String =
        if (n.turning != null) "${n.entry.name} · ${WEEKDAYS[n.weekday]}" else WEEKDAYS[n.weekday]

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
                    .build() ?: Typeface.create("sans-serif-thin", Typeface.NORMAL)
            } catch (e: Exception) {
                // fall through
            }
        }
        return Typeface.create("sans-serif-thin", Typeface.NORMAL)
    }

    private val thin by lazy { flex(180) }
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
            drawGlow(c, heroW * 0.3f, h * 0.85f, max(heroW, h.toFloat()) * 0.95f, color, 0.26f)
            drawRings(c, heroW * 0.98f, h * 0.12f, min(heroW, h.toFloat()), color)
            if (first.days == 0) drawSparks(c, heroW, h.toFloat(), color)
            drawHero(c, first, color, heroW, h.toFloat(), large)
            if (large) drawList(c, list.drop(1).take(3), heroW, w.toFloat(), h.toFloat())
        }
        c.restore()
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dp(1f)
            this.color = border
        }
        val inset = dp(0.5f)
        c.drawRoundRect(RectF(inset, inset, w - inset, h - inset), radius, radius, stroke)
        return bmp
    }

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

    private fun drawHero(c: Canvas, n: Next, color: Int, w: Float, h: Float, large: Boolean) {
        val pad = dp(18f)
        val avatar = dp(if (large) 40f else 36f)
        drawAvatar(c, n, w - pad - avatar, pad, avatar, color)

        // When: small caps, top left.
        val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = sansMedium
            textSize = dp(11f)
            letterSpacing = 0.14f
            this.color = if (n.days == 0) BirthdayCalc.ROSE else muted
        }
        c.drawText(BirthdayCalc.whenText(n), pad, pad + dp(12f), label)

        // Bottom line: who and weekday.
        val below = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = sans
            textSize = dp(13f)
            this.color = inkSoft
        }
        val belowBaseline = h - pad
        c.drawText(ellipsize(BirthdayCalc.below(n), below, w - 2 * pad), pad, belowBaseline, below)

        // Big age or name: thin, as large as fits between label and bottom line.
        val big = BirthdayCalc.big(n)
        val bigPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = thin
            this.color = color
            letterSpacing = if (n.turning != null) -0.04f else -0.02f
        }
        val top = pad + dp(20f)
        val bottom = belowBaseline - dp(18f)
        val maxW = w - 2 * pad
        var size = (bottom - top) * 1.18f
        bigPaint.textSize = size
        val measured = bigPaint.measureText(big)
        if (measured > maxW) {
            size *= maxW / measured
            bigPaint.textSize = size
        }
        c.drawText(big, pad - dp(2f), bottom, bigPaint)
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
            val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = withAlpha(color, 0.14f) }
            c.drawCircle(cx, cy, inner, fill)
            val initials = n.entry.full.split(" ").filter { it.isNotBlank() }.take(2)
                .joinToString("") { it.substring(0, 1).uppercase() }
            val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = light
                textSize = size * 0.36f
                this.color = color
                textAlign = Paint.Align.CENTER
            }
            val fm = t.fontMetrics
            c.drawText(initials, cx, cy - (fm.ascent + fm.descent) / 2, t)
        }
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dp(1.2f)
            this.color = color
        }
        c.drawCircle(cx, cy, size / 2 - dp(0.6f), ring)
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
