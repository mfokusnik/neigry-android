#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
build = ROOT / 'android/app/build.gradle.kts'
if not build.exists():
    raise SystemExit('Expected Kotlin Gradle file android/app/build.gradle.kts')

text = build.read_text(encoding='utf-8')
if 'keystorePropertiesFile' in text:
    print('Signing already configured')
    raise SystemExit(0)

imports = '''import java.io.FileInputStream\nimport java.util.Properties\n\n'''
text = imports + text

plugins_marker = '}\n\nandroid {'
if plugins_marker not in text:
    raise SystemExit('Could not find plugins/android boundary')

properties = '''}\n\nval keystoreProperties = Properties()\nval keystorePropertiesFile = rootProject.file("key.properties")\nif (keystorePropertiesFile.exists()) {\n    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n}\n\nandroid {'''
text = text.replace(plugins_marker, properties, 1)

build_types_marker = '    buildTypes {'
signing_block = '''    signingConfigs {\n        create("release") {\n            keyAlias = keystoreProperties["keyAlias"] as String\n            keyPassword = keystoreProperties["keyPassword"] as String\n            storeFile = file(keystoreProperties["storeFile"] as String)\n            storePassword = keystoreProperties["storePassword"] as String\n        }\n    }\n\n'''
if build_types_marker not in text:
    raise SystemExit('Could not find buildTypes block')
text = text.replace(build_types_marker, signing_block + build_types_marker, 1)

old = 'signingConfig = signingConfigs.getByName("debug")'
if old not in text:
    raise SystemExit('Could not find default debug release signing assignment')
text = text.replace(old, 'signingConfig = signingConfigs.getByName("release")', 1)

build.write_text(text, encoding='utf-8')
print('Configured stable release signing')
