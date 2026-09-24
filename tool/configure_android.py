#!/usr/bin/env python3
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / 'android'
MANIFEST = ANDROID / 'app/src/main/AndroidManifest.xml'
BANNER_SRC = ROOT / 'assets/brand/tv_banner.png'
BANNER_DST = ANDROID / 'app/src/main/res/drawable/tv_banner.png'
ANDROID_NS = 'http://schemas.android.com/apk/res/android'
A = '{%s}' % ANDROID_NS
ET.register_namespace('android', ANDROID_NS)

if not MANIFEST.exists():
    raise SystemExit(f'Missing {MANIFEST}')

root = ET.parse(MANIFEST).getroot()

def ensure_top(tag, name, required=None):
    for el in root.findall(tag):
        if el.get(A + 'name') == name:
            if required is not None:
                el.set(A + 'required', required)
            return el
    el = ET.Element(tag)
    el.set(A + 'name', name)
    if required is not None:
        el.set(A + 'required', required)
    root.insert(0, el)
    return el

ensure_top('uses-permission', 'android.permission.INTERNET')
ensure_top('uses-feature', 'android.software.leanback', 'false')
ensure_top('uses-feature', 'android.hardware.touchscreen', 'false')

application = root.find('application')
if application is None:
    raise SystemExit('Android application node not found')
application.set(A + 'label', 'НЕИГРЫ')
application.set(A + 'banner', '@drawable/tv_banner')

main_activity = None
for activity in application.findall('activity'):
    for intent in activity.findall('intent-filter'):
        if any(a.get(A + 'name') == 'android.intent.action.MAIN' for a in intent.findall('action')):
            main_activity = activity
            categories = {c.get(A + 'name') for c in intent.findall('category')}
            if 'android.intent.category.LEANBACK_LAUNCHER' not in categories:
                category = ET.SubElement(intent, 'category')
                category.set(A + 'name', 'android.intent.category.LEANBACK_LAUNCHER')
            break
    if main_activity is not None:
        break

if main_activity is None:
    raise SystemExit('Main Android activity not found')
main_activity.set(A + 'resizeableActivity', 'true')

ET.ElementTree(root).write(MANIFEST, encoding='utf-8', xml_declaration=True)

BANNER_DST.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(BANNER_SRC, BANNER_DST)

candidates = [
    ANDROID / 'app/build.gradle.kts',
    ANDROID / 'app/build.gradle',
]
build = next((p for p in candidates if p.exists()), None)
if build is None:
    raise SystemExit('Android app Gradle file not found')
text = build.read_text(encoding='utf-8')

replacements = [
    (r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'),
    (r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24'),
]
patched = text
for pattern, replacement in replacements:
    patched, count = re.subn(pattern, replacement, patched, count=1)
    if count:
        break
else:
    if not re.search(r'\bminSdk(?:Version)?\b.*24', patched):
        raise SystemExit('Could not patch Android minSdk to 24')

build.write_text(patched, encoding='utf-8')
print(f'Configured TV manifest: {MANIFEST}')
print(f'Configured minSdk=24: {build}')
print(f'Installed TV banner: {BANNER_DST}')
