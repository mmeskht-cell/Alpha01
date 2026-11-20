#!/usr/bin/env bash
set -euo pipefail
OUT="$GITHUB_WORKSPACE/game-build-evidence"
TMP="$RUNNER_TEMP/zt-game-build"
mkdir -p "$OUT" "$TMP/project" "$OUT/windows" "$TMP/packboot"
exec > >(tee "$OUT/build.log") 2>&1
printf 'commit=%s\nrun_id=%s\n' "$GITHUB_SHA" "$GITHUB_RUN_ID" | tee "$OUT/identity.txt"
python3 game/tools/prepare_runtime_assets.py
cp -a game/. "$TMP/project/"
rm -rf "$TMP/project/.godot"
PROFILE=legacy_debug
if grep -Fxq 'profile=integrated_b_eval' development/BUILD_REQUEST.txt; then
  PROFILE=integrated_b_eval
  # Fail closed on any change to the verified runtime, assets, tests or helper
  # inputs. The export driver and evaluation README are the only new packaging.
  grep -Fx 'verified_game_source=10866b86894a734daed2e2139585b3c35473dbf2' development/BUILD_REQUEST.txt
  while read -r expected path; do
    actual="$(git rev-parse "HEAD:$path")"
    [[ "$actual" == "$expected" ]] || { echo "Unverified build input: $path"; exit 1; }
  done <<'PINS'
d26d2a168ff0e42651a1d74fa409a1c8709e81de game/.gitattributes
7927407d9b793e7a161fda40191800ed63a832e4 game/.gitignore
890fb1bd4c320427c87f299dbcb25aa50939e132 game/README.md
2652e5e6f0202ccee62fa478e7b01fadd7ee1239 game/assets
5681fe4cbfeabfc5bf8e95e1fc34058bbc630400 game/data
3da4f64760293b3b56c3ef848184403439cb0840 game/docs
7f187f31e78831c42d85ad009e3b72bc1469ca14 game/export_presets.cfg
ea18306a7b46a056722173c1234df8b41c5f7e76 game/locales
3f9e232436baa2e692967da94df39cf7702ad299 game/project.godot
ecf40be623bcd664193ae7e8d3d5c4af6282ed36 game/scenes
44559bd9691f274e75665b6c0a0d831cf00205b4 game/src
4f4c0a40a6e1d769ddfb13a0b632885f71a69f32 game/tests
e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 game/tools/.gitkeep
a1476cd75ca0f5040b813e1a2af0d29522a62160 game/tools/check_foundation.py
0f891526193b944451efaa492d472e8011f706dd game/tools/compose_score.py
df7b480c5aeb291fb8e2371f155c6b7a476d4f3b game/tools/localization.py
57760d5890100bd16c9d28c6e8d71f778d1f717b game/tools/prepare_runtime_assets.py
PINS
  # Ensure no unexpected additional game paths or helper files bypass the pins.
  [[ "$(git ls-tree --name-only HEAD:game | wc -l)" -eq 13 ]]
  [[ "$(git ls-tree --name-only HEAD:game/tools | wc -l)" -eq 6 ]]
  python3 - "$TMP/project" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
def replace_once(path, old, new):
    content=path.read_text(encoding="utf-8")
    assert content.count(old)==1, (path,old)
    path.write_text(content.replace(old,new),encoding="utf-8")
scene="res://scenes/app/integrated_b_candidate.tscn"
assert (p/scene.removeprefix("res://")).is_file()
replace_once(p/"project.godot",'run/main_scene="res://scenes/app/demo7.tscn"',f'run/main_scene="{scene}"')
replace_once(p/"project.godot",'config/custom_user_dir_name="zone_trader_lite"','config/custom_user_dir_name="zone_trader_integrated_b_eval"')
replace_once(p/"export_presets.cfg",'package/unique_name="com.zonetrader.lite.dev"','package/unique_name="com.zonetrader.lite.integratedb"')
replace_once(p/"export_presets.cfg",'package/name="ZONE TRADER Dev"','package/name="EXIT NOT INCLUDED B Test"')
replace_once(p/"export_presets.cfg",'version/name="0.1.0-dev"','version/name="0.2.0-b-test"')
PY
  printf 'profile=%s\nverified_game_source=10866b86894a734daed2e2139585b3c35473dbf2\nscene=res://scenes/app/integrated_b_candidate.tscn\nuser_dir=zone_trader_integrated_b_eval\nandroid_package=com.zonetrader.lite.integratedb\n' "$PROFILE" | tee -a "$OUT/identity.txt"
elif grep -Fxq 'profile=gate2_condition_v2' development/BUILD_REQUEST.txt; then
  PROFILE=gate2_condition_v2
  # Export a disposable evaluation copy. Never promote the repository default
  # or write over an existing application/save namespace.
  python3 - "$TMP/project" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
def replace_once(path, old, new):
    content=path.read_text(encoding="utf-8")
    assert content.count(old)==1, (path, old)
    path.write_text(content.replace(old,new),encoding="utf-8")
scene='res://scenes/app/civilian_condition_candidate_v2.tscn'
assert (p/scene.removeprefix("res://")).is_file()
replace_once(p/"project.godot",'run/main_scene="res://scenes/app/demo7.tscn"',f'run/main_scene="{scene}"')
replace_once(p/"project.godot",'config/custom_user_dir_name="zone_trader_lite"','config/custom_user_dir_name="zone_trader_gate2_eval_v2"')
replace_once(p/"export_presets.cfg",'package/unique_name="com.zonetrader.lite.dev"','package/unique_name="com.zonetrader.lite.gate2eval"')
replace_once(p/"export_presets.cfg",'package/name="ZONE TRADER Dev"','package/name="EXIT NOT INCLUDED Gate2 Test"')
replace_once(p/"export_presets.cfg",'version/name="0.1.0-dev"','version/name="0.2.0-gate2-test"')
PY
  printf 'profile=%s\nscene=res://scenes/app/civilian_condition_candidate_v2.tscn\nuser_dir=zone_trader_gate2_eval_v2\nandroid_package=com.zonetrader.lite.gate2eval\n' "$PROFILE" | tee -a "$OUT/identity.txt"
fi
cp game/assets/fonts/OFL-Noto.txt "$OUT/OFL-Noto.txt"
cp game/docs/ASSET_LICENSES.md "$OUT/ASSET_LICENSES.md"
if [[ "$PROFILE" == integrated_b_eval ]]; then
  cp development/INTEGRATED_B_PLAYTEST.md "$OUT/README.txt"
elif [[ "$PROFILE" == gate2_condition_v2 ]]; then
  cp development/GATE2_PLAYTEST.md "$OUT/README.txt"
else
  cp game/docs/DEBUG_BUILD_NOTICE.txt "$OUT/README.txt"
fi
curl -fL --retry 2 --max-time 120 -o "$TMP/godot.zip" 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip'
echo "cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4  $TMP/godot.zip" | sha256sum -c -
unzip -q "$TMP/godot.zip" -d "$TMP"
ENGINE="$TMP/Godot_v4.7.2-stable_linux.x86_64"
chmod +x "$ENGINE"
VERSION="$("$ENGINE" --version)"
echo "Godot: $VERSION"
[[ "$VERSION" == 4.7.2.stable* ]]
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_CONFIG_HOME="$TMP/xdg-config"
export JAVA_HOME="${JAVA_HOME_17_X64:?runner must have JDK 17}"
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:?runner must have Android SDK}}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
java -version
test -d "$ANDROID_HOME/platform-tools"
if ! test -d "$ANDROID_HOME/build-tools/35.0.1" || ! test -d "$ANDROID_HOME/platforms/android-35"; then
  sdkmanager --sdk_root="$ANDROID_HOME" 'build-tools;35.0.1' 'platforms;android-35'
fi
curl -fL --retry 2 --max-time 180 -o "$TMP/templates.tpz" 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
echo "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011  $TMP/templates.tpz" | sha256sum -c -
unzip -q "$TMP/templates.tpz" -d "$TMP/template-extract"
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable"
mkdir -p "$TEMPLATE_DIR"
cp -a "$TMP/template-extract/templates/." "$TEMPLATE_DIR/"
"$ENGINE" --headless --editor --path "$TMP/project" --import --quit 2>&1 | tee "$OUT/import.log"
if grep -E 'SCRIPT ERROR:|^ERROR:|^FAIL:' "$OUT/import.log"; then exit 1; fi
"$ENGINE" --headless --path "$TMP/project" --export-debug Windows "$OUT/windows/zone-trader-dev.exe"
test -s "$OUT/windows/zone-trader-dev.exe"
test -s "$OUT/windows/zone-trader-dev.pck"
python3 - "$OUT/windows/zone-trader-dev.exe" <<'PY'
import sys
with open(sys.argv[1], 'rb') as f:
    assert f.read(2) == b'MZ'
PY
echo 'windows=PASS' | tee -a "$OUT/status.txt"
# Boot the actual exported PCK rather than the source project. Linux editor can run platform-neutral data.
(cd "$TMP/packboot" && XDG_DATA_HOME="$TMP/pack-data" XDG_CONFIG_HOME="$TMP/pack-config" timeout 35s "$ENGINE" --headless --main-pack "$OUT/windows/zone-trader-dev.pck" --quit-after 30 2>&1) | tee "$OUT/packboot.log"
if grep -E 'SCRIPT ERROR:|^ERROR:|^FAIL:|ZT_FONT_NOT_PREPARED' "$OUT/packboot.log"; then exit 1; fi
if [[ "$PROFILE" == gate2_condition_v2 || "$PROFILE" == integrated_b_eval ]]; then
  grep -F 'ZT_DEMO_HOST_READY' "$OUT/packboot.log"
  grep -F 'ZT_SPATIAL_COUNTER_READY' "$OUT/packboot.log"
  echo 'gate2_spatial_packboot=PASS' | tee -a "$OUT/status.txt"
fi
echo 'packboot=PASS' | tee -a "$OUT/status.txt"
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$TMP/disposable-debug.keystore"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
keytool -genkeypair -keystore "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" -storepass android -keypass android -alias androiddebugkey -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 3650 >/dev/null 2>&1
"$ENGINE" --headless --path "$TMP/project" --export-debug Android "$OUT/zone-trader-dev.apk"
test -s "$OUT/zone-trader-dev.apk"
"$ANDROID_HOME/build-tools/35.0.1/apksigner" verify --print-certs "$OUT/zone-trader-dev.apk"
python3 - "$OUT/zone-trader-dev.apk" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    names = z.namelist()
    assert 'AndroidManifest.xml' in names
    assert any(n.startswith('lib/arm64-v8a/') and n.endswith('.so') for n in names)
PY
if [[ "$PROFILE" == integrated_b_eval ]]; then
  "$ANDROID_HOME/build-tools/35.0.1/aapt" dump badging "$OUT/zone-trader-dev.apk" > "$OUT/android-badging.txt"
  grep -F "package: name='com.zonetrader.lite.integratedb'" "$OUT/android-badging.txt"
fi
echo 'android=PASS' | tee -a "$OUT/status.txt"
(cd "$OUT" && sha256sum windows/zone-trader-dev.exe windows/zone-trader-dev.pck zone-trader-dev.apk OFL-Noto.txt ASSET_LICENSES.md > SHA256SUMS)
echo 'ZT_GAME_DEBUG_BUILD_OK'
