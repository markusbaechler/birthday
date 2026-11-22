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
for src in (OVERLAY / "res").rglob("*.xml"):
    dest = MAIN / "res" / src.relative_to(OVERLAY / "res")
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, dest)
    print("copied", dest)

# 2. Manifest: label, permissions, widget receivers
text = manifest.read_text(encoding="utf-8")
text = re.sub(r'android:label="[^"]*"', 'android:label="Geburtstage"', text, count=1)

for perm in ["android.permission.READ_CONTACTS"]:
    if perm not in text:
        text = text.replace(
            "<application", f'<uses-permission android:name="{perm}"/>\n    <application', 1)

receivers = ""
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
text = text.replace("</application>", receivers + "    </application>", 1)

manifest.write_text(text, encoding="utf-8")
print("Patched", manifest)
print(text)
