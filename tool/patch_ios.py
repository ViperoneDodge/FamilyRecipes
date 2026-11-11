"""Adatta il progetto iOS generato da `flutter create` alle esigenze dell'app.
Eseguito da GitHub Actions (su macOS) prima della compilazione per iPhone."""
import json
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"
RUNNER = IOS / "Runner"
MIN_IOS = "15.5"  # richiesto da Google ML Kit (lettura del testo dalle foto)

if not RUNNER.exists():
    raise SystemExit("Cartella ios/Runner mancante: esegui prima flutter create")

cfg = (ROOT / "lib" / "firebase_config.dart").read_text()
ios_client_id = re.search(r"iosClientId = '([^']*)'", cfg).group(1)
langs = re.findall(r"'([a-z]{2})': '", (ROOT / "lib" / "l10n.dart").read_text())


def plist_entry(key, value):
    if isinstance(value, bool):
        return f"\t<key>{key}</key>\n\t<{'true' if value else 'false'}/>\n"
    if isinstance(value, list):
        items = "".join(f"\t\t<string>{v}</string>\n" for v in value)
        return f"\t<key>{key}</key>\n\t<array>\n{items}\t</array>\n"
    return f"\t<key>{key}</key>\n\t<string>{value}</string>\n"


# ---- Info.plist: nome, permessi, lingue, cifratura, accesso con Google ----
plist = RUNNER / "Info.plist"
p = plist.read_text()


def set_key(p, key, value):
    """Sostituisce la voce se c'è (stringa semplice), altrimenti la aggiunge in cima al dizionario."""
    entry = plist_entry(key, value)
    pattern = re.compile(rf"\t<key>{re.escape(key)}</key>\n\t(<string>[^<]*</string>|<true/>|<false/>|<array>.*?</array>)\n", re.S)
    if pattern.search(p):
        return pattern.sub(lambda _: entry, p, count=1)
    return p.replace("<dict>\n", "<dict>\n" + entry, 1)


p = set_key(p, "CFBundleDisplayName", "FamilyRecipes")
p = set_key(p, "CFBundleName", "FamilyRecipes")
p = set_key(p, "ITSAppUsesNonExemptEncryption", False)
p = set_key(p, "NSCameraUsageDescription",
            "Serve per fotografare i piatti, i passaggi e le ricette da leggere, e per inquadrare i QR.")
p = set_key(p, "NSPhotoLibraryUsageDescription", "Serve per scegliere le foto delle ricette.")
p = set_key(p, "NSPhotoLibraryAddUsageDescription", "Serve per salvare le foto e i PDF delle ricette.")
p = set_key(p, "CFBundleLocalizations", langs)
p = set_key(p, "UIBackgroundModes", ["remote-notification"])
# Solo verticale, come su Android (l'app è solo per iPhone).
p = set_key(p, "UISupportedInterfaceOrientations", ["UIInterfaceOrientationPortrait"])
if ios_client_id:
    reversed_id = ".".join(reversed(ios_client_id.split(".")))
    p = set_key(p, "GIDClientID", ios_client_id)
    if "CFBundleURLTypes" not in p:
        url_types = (
            "\t<key>CFBundleURLTypes</key>\n\t<array>\n\t\t<dict>\n\t\t\t<key>CFBundleURLSchemes</key>\n"
            f"\t\t\t<array>\n\t\t\t\t<string>{reversed_id}</string>\n\t\t\t</array>\n\t\t</dict>\n\t</array>\n"
        )
        p = p.replace("<dict>\n", "<dict>\n" + url_types, 1)
else:
    print("ATTENZIONE: iosClientId vuoto in lib/firebase_config.dart: accesso con Google non configurato su iPhone")
plist.write_text(p)
print("Patched", plist)

# ---- Capacità: notifiche push e Accedi con Apple ----
(RUNNER / "Runner.entitlements").write_text("""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>production</string>
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
</dict>
</plist>
""")

# ---- Progetto Xcode: entitlements, solo iPhone, iOS minimo ----
pbx = RUNNER.parent / "Runner.xcodeproj" / "project.pbxproj"
x = pbx.read_text()
if "CODE_SIGN_ENTITLEMENTS" not in x:
    x = re.sub(r"(\n(\t+)PRODUCT_BUNDLE_IDENTIFIER = it\.familyrecipes\.familyrecipes;)",
               r"\n\2CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\1", x)
x = re.sub(r'TARGETED_DEVICE_FAMILY = "1,2";', "TARGETED_DEVICE_FAMILY = 1;", x)
x = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", f"IPHONEOS_DEPLOYMENT_TARGET = {MIN_IOS};", x)
if x.count("CODE_SIGN_ENTITLEMENTS") < 3:
    raise SystemExit("Impossibile collegare Runner.entitlements al progetto Xcode")
pbx.write_text(x)
print("Patched", pbx)

# ---- Podfile (generato qui se manca) con iOS minimo ----
podfile = IOS / "Podfile"
if not podfile.exists():
    podfile.write_text(f"""platform :ios, '{MIN_IOS}'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {{
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{{generated_xcode_build_settings_path}} must exist. Run flutter pub get first"
  end
  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{{generated_xcode_build_settings_path}}"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

flutter_ios_podfile_setup

target 'Runner' do
  use_frameworks!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '{MIN_IOS}'
    end
  end
end
""")
else:
    pf = re.sub(r"^#?\s*platform :ios, '[0-9.]+'", f"platform :ios, '{MIN_IOS}'", podfile.read_text(), flags=re.M)
    podfile.write_text(pf)
print("Patched", podfile)

# ---- Icona: App Store vuole un'unica immagine 1024×1024 senza trasparenza ----
icon_set = RUNNER / "Assets.xcassets" / "AppIcon.appiconset"
src = ROOT / "tool" / "branding" / "ios-icon-1024.png"
if src.exists():
    shutil.rmtree(icon_set, ignore_errors=True)
    icon_set.mkdir(parents=True)
    shutil.copy(src, icon_set / "Icon-1024.png")
    (icon_set / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "Icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))
    print("Icona iOS copiata")
