"""Patches the Android project that `flutter create` generates in CI.

- app name «Geburtstage»
- permission to read contacts
"""
import pathlib
import re
import sys

manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
if not manifest.exists():
    sys.exit("AndroidManifest.xml not found")

text = manifest.read_text(encoding="utf-8")

text = re.sub(r'android:label="[^"]*"', 'android:label="Geburtstage"', text, count=1)

permissions = [
    "android.permission.READ_CONTACTS",
]
for perm in permissions:
    tag = f'<uses-permission android:name="{perm}"/>'
    if perm not in text:
        text = text.replace("<application", f"{tag}\n    <application", 1)

manifest.write_text(text, encoding="utf-8")
print("Patched", manifest)
print(text[:600])
