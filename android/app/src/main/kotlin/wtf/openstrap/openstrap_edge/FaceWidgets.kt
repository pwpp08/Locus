package wtf.openstrap.openstrap_edge

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * The home-screen widgets. Each is one picture the app draws (lib/widget/
 * widget_faces.dart) with its own rings, numerals and mark, and writes to
 * files/widget_faces; this side only shows it and opens the app on a tap.
 *
 * Whether the picture is still today's answer is decided HERE, at render
 * time, from the snapshot's age (StrapWidgets.fresh): a phone that stops
 * syncing keeps its last picture on disk, and a week-old score must not sit
 * on the home screen looking like this morning's. A missing picture or a
 * stale snapshot shows the no-data card instead.
 */
abstract class FaceWidgetProvider(private val file: String) : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, build(context, widgetData))
        }
    }

    private fun build(context: Context, prefs: SharedPreferences): RemoteViews {
        val picture = File(File(context.filesDir, "widget_faces"), file)
        val bmp = if (StrapWidgets.fresh(prefs) && picture.exists()) {
            runCatching { BitmapFactory.decodeFile(picture.path) }.getOrNull()
        } else null
        if (bmp == null) return noData(context)
        val views = RemoteViews(context.packageName, R.layout.widget_face)
        views.setImageViewBitmap(R.id.face, bmp)
        views.setOnClickPendingIntent(R.id.widget_root, StrapWidgets.openAppIntent(context))
        return views
    }

    private fun noData(context: Context): RemoteViews {
        val pal = StrapWidgets.darkPal()
        val views = RemoteViews(context.packageName, R.layout.widget_openstrap_nodata)
        views.setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
        views.setOnClickPendingIntent(R.id.widget_root, StrapWidgets.openAppIntent(context))
        views.setTextColor(R.id.nodata_title, pal.ink)
        views.setTextColor(R.id.nodata_body, pal.inkMuted)
        return views
    }
}

class OpenStrapWidgetProvider : FaceWidgetProvider("dials.png")
class RingsWideWidgetProvider : FaceWidgetProvider("ringsWide.png")
class RingsWidgetProvider : FaceWidgetProvider("rings.png")
class SleepWidgetProvider : FaceWidgetProvider("sleep.png")
class RecoveryWidgetProvider : FaceWidgetProvider("recovery.png")
class StrainWidgetProvider : FaceWidgetProvider("strain.png")
