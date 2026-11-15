#!/usr/bin/env python3
"""
Configures Flutter Android platform files after `flutter create`
to ensure complete permissions and release signing with v1 & v2 signatures.
"""
import os
import shutil
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_KEYSTORE = os.path.join(ROOT, "android", "app", "release.keystore")
DEST_KEYSTORE = os.path.join(ROOT, "app", "android", "app", "release.keystore")
MANIFEST_PATH = os.path.join(ROOT, "app", "android", "app", "src", "main", "AndroidManifest.xml")
GRADLE_PATH = os.path.join(ROOT, "app", "android", "app", "build.gradle")
GRADLE_KTS_PATH = os.path.join(ROOT, "app", "android", "app", "build.gradle.kts")

def main():
    # 1. Copy release keystore
    if os.path.exists(SRC_KEYSTORE):
        os.makedirs(os.path.dirname(DEST_KEYSTORE), exist_ok=True)
        shutil.copy2(SRC_KEYSTORE, DEST_KEYSTORE)
        print(f"Copied {SRC_KEYSTORE} -> {DEST_KEYSTORE}")

    # 2. Add permissions to AndroidManifest.xml
    if os.path.exists(MANIFEST_PATH):
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            content = f.read()

        permissions = """
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.VIBRATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
"""
        if "android.permission.INTERNET" not in content:
            content = content.replace("<manifest", f"<manifest\n{permissions}", 1)
            # Fix if placed right inside <manifest ...>
            if f"<manifest\n{permissions}" in content:
                # Place right after opening <manifest ...> tag
                content = re.sub(r"(<manifest[^>]*>)", r"\1" + permissions, content)
            with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
                f.write(content)
            print("Injected required permissions into Flutter AndroidManifest.xml")

    # 3. Configure Release Signing in build.gradle / build.gradle.kts
    target_gradle = GRADLE_KTS_PATH if os.path.exists(GRADLE_KTS_PATH) else GRADLE_PATH
    if os.path.exists(target_gradle):
        with open(target_gradle, "r", encoding="utf-8") as f:
            gcontent = f.read()

        if target_gradle.endswith(".kts"):
            signing_block = """
    signingConfigs {
        create("release") {
            storeFile = file("release.keystore")
            storePassword = "zedremoterelease"
            keyAlias = "zedremote"
            keyPassword = "zedremoterelease"
            enableV1Signing = true
            enableV2Signing = true
        }
    }
"""
            if "signingConfigs" not in gcontent:
                gcontent = gcontent.replace("android {", f"android {{\n{signing_block}", 1)
            gcontent = re.sub(
                r'buildTypes\s*\{\s*release\s*\{',
                'buildTypes {\n        release {\n            signingConfig = signingConfigs.getByName("release")',
                gcontent
            )
        else:
            # Groovy
            signing_block = """
    signingConfigs {
        release {
            storeFile file("release.keystore")
            storePassword "zedremoterelease"
            keyAlias "zedremote"
            keyPassword "zedremoterelease"
            v1SigningEnabled true
            v2SigningEnabled true
        }
    }
"""
            if "signingConfigs" not in gcontent:
                gcontent = gcontent.replace("android {", f"android {{\n{signing_block}", 1)
            gcontent = re.sub(
                r'buildTypes\s*\{\s*release\s*\{',
                'buildTypes {\n        release {\n            signingConfig signingConfigs.release',
                gcontent
            )

        with open(target_gradle, "w", encoding="utf-8") as f:
            f.write(gcontent)
        print(f"Configured release signing in {target_gradle}")

if __name__ == "__main__":
    main()
