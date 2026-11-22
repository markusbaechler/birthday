package ch.markusbaechler.geburtstage

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import java.util.Calendar

/**
 * Home screen widgets. The app stores all birthdays as JSON ("people");
 * the widgets compute the days themselves, so they stay correct even when
 * the app has not been opened for days (Android refreshes every 30 min).
 */
data class Entry(
    val name: String,
    val day: Int,
    val month: Int,
    val year: Int?,
    val color: Int,
)

data class Next(val entry: Entry, val days: Int, val turning: Int?, val weekday: Int)

object BirthdayCalc {
    private const val ROSE = 0xFFE9A7C0.toInt()
    private val PALETTE = intArrayOf(
        0xFF8FB4E8.toInt(), // blue
        0xFF8FD0AA.toInt(), // green
        0xFFE3C27A.toInt(), // amber
    )
    private val WEEKDAYS = arrayOf(
        "", "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag",
    )

    fun parse(json: String?): List<Entry> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Entry(
                    name = o.optString("n"),
                    day = o.getInt("d"),
                    month = o.getInt("m"),
                    year = if (o.isNull("y")) null else o.getInt("y"),
                    color = o.optInt("c", 0),
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
            Next(e, days, turning, date.get(Calendar.DAY_OF_WEEK))
        }.sortedBy { it.days }
    }

    fun color(n: Next): Int = if (n.days == 0) ROSE else PALETTE[Math.floorMod(n.entry.color, PALETTE.size)]

    fun weekday(n: Next): String = WEEKDAYS[n.weekday]

    /** Big number: age today, otherwise the days until. */
    fun number(n: Next): String = when {
        n.days == 0 && n.turning != null -> n.turning.toString()
        n.days == 0 -> "Heute"
        else -> n.days.toString()
    }

    fun top(n: Next): String = when {
        n.days == 0 -> "Heute"
        n.turning != null -> "${n.entry.name} · ${n.turning}"
        else -> n.entry.name
    }

    fun bottom(n: Next): String = when {
        n.days == 0 -> n.entry.name
        n.days == 1 -> "Tag, morgen"
        else -> "Tage, ${weekday(n)}"
    }
}

private fun fillHero(views: RemoteViews, first: Next?) {
    if (first == null) {
        views.setTextViewText(R.id.w_top, "Geburtstage")
        views.setTextViewText(R.id.w_number, "–")
        views.setTextColor(R.id.w_number, 0xFF9C95A8.toInt())
        views.setTextViewText(R.id.w_bottom, "Noch niemand erfasst")
        return
    }
    views.setTextViewText(R.id.w_top, BirthdayCalc.top(first))
    views.setTextViewText(R.id.w_number, BirthdayCalc.number(first))
    views.setTextColor(R.id.w_number, BirthdayCalc.color(first))
    views.setTextViewText(R.id.w_bottom, BirthdayCalc.bottom(first))
}

class LargeBirthdayWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val list = BirthdayCalc.upcoming(BirthdayCalc.parse(widgetData.getString("people", null)))
        val rowNames = intArrayOf(R.id.w_row1_name, R.id.w_row2_name, R.id.w_row3_name)
        val rowDays = intArrayOf(R.id.w_row1_days, R.id.w_row2_days, R.id.w_row3_days)
        val rowDots = intArrayOf(R.id.w_row1_dot, R.id.w_row2_dot, R.id.w_row3_dot)
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_large)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            fillHero(views, list.firstOrNull())
            for (i in 0 until 3) {
                val n = list.getOrNull(i + 1)
                if (n == null) {
                    views.setTextViewText(rowNames[i], "")
                    views.setTextViewText(rowDays[i], "")
                    views.setTextViewText(rowDots[i], "")
                } else {
                    views.setTextViewText(rowNames[i], n.entry.name)
                    views.setTextViewText(rowDays[i], if (n.days == 0) "heute" else n.days.toString())
                    views.setTextViewText(rowDots[i], "●")
                    views.setTextColor(rowDots[i], BirthdayCalc.color(n))
                }
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

class SmallBirthdayWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val first = BirthdayCalc.upcoming(BirthdayCalc.parse(widgetData.getString("people", null))).firstOrNull()
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_small)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            fillHero(views, first)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
