"""Patches the Android project that `flutter create` generates in CI.

- app name «Geburtstage»
- permission to read contacts
- home screen widgets: Kotlin providers, layouts, resources, receivers
"""
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(".")
OVERLAY = ROOT / "tool" / "android"
MAIN = ROOT / "android" / "app" / "src" / "main"
KOTLIN_DIR = MAIN / "kotlin" / "ch" / "markusbaechler" / "geburtstage"

manifest = MAIN / "AndroidManifest.xml"
if not manifest.exists():
    sys.exit("AndroidManifest.xml not found")
if not (KOTLIN_DIR / "MainActivity.kt").exists():
    sys.exit(f"MainActivity.kt not found in {KOTLIN_DIR}")

# 1. Copy widget code and resources
shutil.copy(OVERLAY / "kotlin" / "BirthdayWidgets.kt", KOTLIN_DIR / "BirthdayWidgets.kt")
# MainActivity with the share bridge (replaces the generated one)
shutil.copy(OVERLAY / "kotlin" / "MainActivity.kt", KOTLIN_DIR / "MainActivity.kt")
for src in (OVERLAY / "res").rglob("*.xml"):
    dest = MAIN / "res" / src.relative_to(OVERLAY / "res")
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, dest)
    print("copied", dest)

# 2. Manifest: label, permissions, widget receivers
text = manifest.read_text(encoding="utf-8")
text = re.sub(r'android:label="[^"]*"', 'android:label="Geburtstage"', text, count=1)

for perm in [
    "android.permission.READ_CONTACTS",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.VIBRATE",
    "android.permission.USE_EXACT_ALARM",
]:
    if perm not in text:
        text = text.replace(
            "<application", f'<uses-permission android:name="{perm}"/>\n    <application', 1)

if "SCHEDULE_EXACT_ALARM" not in text:
    text = text.replace(
        "<application",
        '<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32"/>\n    <application', 1)

receivers = ""
# Scheduled notifications (flutter_local_notifications)
if "ScheduledNotificationReceiver" not in text:
    receivers += """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
for name, info, label in [
    ("LargeBirthdayWidget", "widget_large_info", "widget_large_label"),
    ("SmallBirthdayWidget", "widget_small_info", "widget_small_label"),
]:
    if name in text:
        continue
    receivers += f"""
        <receiver android:name=".{name}" android:exported="false" android:label="@string/{label}">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/{info}" />
        </receiver>
"""
# Share target: text and images from other apps (e.g. ChatGPT)
if "android.intent.action.SEND" not in text:
    text = text.replace("</activity>", """    <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="image/*" />
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="text/plain" />
            </intent-filter>
        </activity>""", 1)

# File provider: card images go out to WhatsApp and the share sheet
if ".greetings" not in text:
    receivers += """
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.greetings"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/greeting_paths" />
        </provider>
"""
text = text.replace("</application>", receivers + "    </application>", 1)

manifest.write_text(text, encoding="utf-8")
print("Patched", manifest)
print(text)

# 3. Gradle: core library desugaring (needed by flutter_local_notifications)
gradle = ROOT / "android" / "app" / "build.gradle.kts"
g = gradle.read_text(encoding="utf-8")
if "isCoreLibraryDesugaringEnabled" not in g:
    g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", g, count=1)
if "desugar_jdk_libs" not in g:
    g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n    implementation("androidx.core:core-ktx:1.13.1")\n}\n'
gradle.write_text(g, encoding="utf-8")
print("Patched", gradle)
print(g)
