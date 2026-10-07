"""Adatta i file Android/iOS generati da `flutter create` alle esigenze dell'app.
Eseguito automaticamente da GitHub Actions prima della compilazione."""
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "android" / "app"

kts = APP / "build.gradle.kts"
groovy = APP / "build.gradle"
if kts.exists():
    g = kts.read_text()
    g = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = maxOf(23, flutter.minSdkVersion)", g)
    g = re.sub(r"targetSdk\s*=\s*flutter\.targetSdkVersion", "targetSdk = 36", g)
    g = re.sub(r"compileSdk\s*=\s*flutter\.compileSdkVersion", "compileSdk = 36", g)
    if "isCoreLibraryDesugaringEnabled" not in g:
        g = g.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    if "desugar_jdk_libs" not in g:
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    if 'create("family")' not in g:
        g = g.replace("    buildTypes {", '''    signingConfigs {
        // Chiave fissa del repository: l'APK si aggiorna sopra le versioni installate.
        create("family") {
            storeFile = file("../../keystore/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        // Chiave di caricamento Play Store (dai Secrets di GitHub), usata per l'AAB.
        create("upload") {
            val ks = System.getenv("RECIPES_KEYSTORE")
            if (!ks.isNullOrEmpty() && file("../../" + ks).exists()) {
                storeFile = file("../../" + ks)
                storePassword = System.getenv("RECIPES_STORE_PASS")
                keyAlias = System.getenv("RECIPES_KEY_ALIAS")
                keyPassword = System.getenv("RECIPES_KEY_PASS")
            }
        }
    }

    buildTypes {''', 1)
        g = g.replace('signingConfigs.getByName("debug")',
                      'signingConfigs.getByName(if (System.getenv("RECIPES_SIGN") == "upload") "upload" else "family")')
        if 'getByName(if (System.getenv("RECIPES_SIGN")' not in g:
            raise SystemExit("Impossibile impostare la firma")
    kts.write_text(g)
    print("Patched", kts)
elif groovy.exists():
    g = groovy.read_text()
    g = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdk = 23", g)
    g = re.sub(r"ndkVersion\s*=?\s*flutter\.ndkVersion", 'ndkVersion = "27.0.12077973"', g)
    if "coreLibraryDesugaringEnabled" not in g:
        g = g.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
    if "desugar_jdk_libs" not in g:
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    if "familyKey" not in g:
        g = g.replace("    buildTypes {", '''    signingConfigs {
        familyKey {
            storeFile file("../../keystore/debug.keystore")
            storePassword "android"
            keyAlias "androiddebugkey"
            keyPassword "android"
        }
    }

    buildTypes {''', 1)
        g = g.replace("signingConfigs.debug", "signingConfigs.familyKey")
    groovy.write_text(g)
    print("Patched", groovy)
else:
    raise SystemExit("build.gradle non trovato")

gjson = ROOT / "tool" / "google-services.json"
if gjson.exists():
    shutil.copy(gjson, APP / "google-services.json")
    sk = ROOT / "android" / "settings.gradle.kts"
    sg = ROOT / "android" / "settings.gradle"
    if sk.exists():
        t = sk.read_text()
        if "com.google.gms.google-services" not in t:
            t, n = re.subn(r'(id\("dev\.flutter\.flutter-plugin-loader"\)[^\n]*)',
                           r'\1\n    id("com.google.gms.google-services") version "4.4.2" apply false', t, count=1)
            if n == 0:
                raise SystemExit("settings.gradle.kts: plugin loader non trovato")
            sk.write_text(t)
    elif sg.exists():
        t = sg.read_text()
        if "com.google.gms.google-services" not in t:
            t, n = re.subn(r'(id\s+"dev\.flutter\.flutter-plugin-loader"[^\n]*)',
                           r'\1\n    id "com.google.gms.google-services" version "4.4.2" apply false', t, count=1)
            if n == 0:
                raise SystemExit("settings.gradle: plugin loader non trovato")
            sg.write_text(t)
    if kts.exists():
        t = kts.read_text()
        if "com.google.gms.google-services" not in t:
            t, n = re.subn(r'(id\("com\.android\.application"\))',
                           r'\1\n    id("com.google.gms.google-services")', t, count=1)
            if n == 0:
                raise SystemExit("build.gradle.kts: plugin android non trovato")
            kts.write_text(t)
    else:
        t = groovy.read_text()
        if "com.google.gms.google-services" not in t:
            t, n = re.subn(r'(id\s+"com\.android\.application")',
                           r'\1\n    id "com.google.gms.google-services"', t, count=1)
            if n == 0:
                raise SystemExit("build.gradle: plugin android non trovato")
            groovy.write_text(t)
    print("Firebase google-services configurato")

(APP / "proguard-rules.pro").write_text(
    """-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
-dontwarn com.google.android.play.core.**
"""
)

man = APP / "src" / "main" / "AndroidManifest.xml"
m = man.read_text()
perms = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
"""
queries = """    <queries>
        <intent>
            <action android:name="android.intent.action.SENDTO"/>
            <data android:scheme="mailto"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
    </queries>
"""
if "xmlns:tools" not in m:
    m = m.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
media_remove = """    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" tools:node="remove"/>
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" tools:node="remove"/>
    <uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" tools:node="remove"/>
    <uses-permission android:name="com.google.android.gms.permission.AD_ID" tools:node="remove"/>
"""
if "READ_MEDIA_IMAGES" not in m:
    m = m.replace("<application", media_remove + "    <application", 1)
if "android.intent.action.SENDTO" not in m:
    m = m.replace("<application", queries + "    <application", 1)
if "POST_NOTIFICATIONS" not in m:
    m = m.replace("<application", perms + "    <application", 1)
receivers = """
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
        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="famiglia"/>
        <meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/ic_stat_notify"/>
        <meta-data android:name="com.google.firebase.messaging.default_notification_color" android:resource="@color/notify_color"/>
"""
if "ScheduledNotificationReceiver" not in m:
    m = m.replace("</application>", receivers + "    </application>", 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="FamilyRecipes"', m, count=1)
if "resizeableActivity" not in m:
    m = m.replace("<activity", '<activity\n            android:resizeableActivity="true"', 1)
man.write_text(m)
print("Patched", man)

icons = ROOT / "tool" / "icons"
res = APP / "src" / "main" / "res"
if icons.exists():
    for d in icons.iterdir():
        if d.is_dir():
            (res / d.name).mkdir(parents=True, exist_ok=True)
            for f in d.iterdir():
                shutil.copy(f, res / d.name / f.name)
    print("Icons copied")
launch = '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item><color android:color="#B4532A"/></item>
</layer-list>
'''
for d in ("drawable", "drawable-v21"):
    (res / d).mkdir(parents=True, exist_ok=True)
    (res / d / "launch_background.xml").write_text(launch)
(res / "drawable" / "splash_empty.xml").write_text(
    '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#00000000"/>
    <size android:width="1dp" android:height="1dp"/>
</shape>
''')
(res / "values").mkdir(parents=True, exist_ok=True)
(res / "values" / "app_colors.xml").write_text(
    '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="notify_color">#B4532A</color>
</resources>
''')
styles31 = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">#B4532A</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_empty</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
'''
for d in ("values-v31", "values-night-v31"):
    (res / d).mkdir(parents=True, exist_ok=True)
    (res / d / "styles.xml").write_text(styles31)
print("Splash patched")

(res / "raw").mkdir(parents=True, exist_ok=True)
(res / "raw" / "keep.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<resources xmlns:tools="http://schemas.android.com/tools" '
    'tools:keep="@drawable/ic_stat_notify,@drawable/splash_logo,@mipmap/ic_launcher*" />\n'
)

plist = ROOT / "ios" / "Runner" / "Info.plist"
if plist.exists():
    p = plist.read_text()
    extra = """	<key>NSCameraUsageDescription</key>
	<string>Serve per fotografare i piatti e i passaggi delle ricette e per inquadrare il QR dei gruppi.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Serve per scegliere le foto delle ricette.</string>
"""
    if "NSCameraUsageDescription" not in p:
        p = p.replace("<dict>", "<dict>\n" + extra, 1)
    plist.write_text(p)
    print("Patched", plist)
