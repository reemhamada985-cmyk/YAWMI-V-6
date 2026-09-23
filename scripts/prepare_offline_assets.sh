#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AS="$ROOT/app/src/main/assets"
DATA="$AS/data"
RESRAW="$ROOT/app/src/main/res/raw"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DATA_REPO="https://github.com/mohammed-2-5/islamic-library-data.git"
QURAN_REPO="https://github.com/quran-ws/quran-svg.git"
ADHAN_URL="https://upload.wikimedia.org/wikipedia/commons/e/e7/Adhan.ogg"

mkdir -p "$DATA/azkar" "$DATA/hadith" "$DATA/forties" "$DATA/names_of_allah" "$DATA/tafseer" "$DATA/prophet_stories" \
         "$DATA/quran/chapters/ar" "$AS/quran-pages" "$AS/adhan" "$AS/audio" "$RESRAW"

rm -rf "$DATA"/azkar/* "$DATA"/hadith/* "$DATA"/forties/* "$DATA"/names_of_allah/* \
       "$DATA"/tafseer/* "$DATA"/prophet_stories/* "$DATA/quran"/* "$AS/quran-pages"/* \
       "$AS/adhan"/* "$RESRAW/adhan.ogg"

# Use sparse git checkouts instead of dozens of CDN requests. This avoids stale CDN mirrors
# and 404s while still downloading only the content required by the app.
echo '1/5 — Clone required Islamic datasets'
git clone --depth 1 --filter=blob:none --no-checkout "$DATA_REPO" "$TMP/islamic-data"
git -C "$TMP/islamic-data" sparse-checkout init --no-cone
git -C "$TMP/islamic-data" sparse-checkout set \
  'azkar/*.json' \
  'hadith/bukhari.json' 'hadith/muslim.json' \
  'forties/nawawi40.json' 'forties/qudsi40.json' 'forties/shahwaliullah40.json' \
  'names_of_allah/names_of_allah.json' \
  'tafseer/muyassar.json' \
  'prophet_stories/index.json' 'prophet_stories/*.json' 'prophet_stories/quizzes/*.json' \
  'quran/chapters/ar/*.json' \
  'quran/qcf_v2_pages.json' 'quran/mushaf_pages.json' 'quran/qcf_surah_starts.json' \
  'quran/quran_segments.json' 'quran/quran_symbols.json' 'quran/quran_duas.json' 'quran/hizb_quarters.json'
git -C "$TMP/islamic-data" checkout --force

cp -a "$TMP/islamic-data/azkar/." "$DATA/azkar/"
cp -a "$TMP/islamic-data/hadith/." "$DATA/hadith/"
cp -a "$TMP/islamic-data/forties/." "$DATA/forties/"
cp -a "$TMP/islamic-data/names_of_allah/." "$DATA/names_of_allah/"
cp -a "$TMP/islamic-data/tafseer/." "$DATA/tafseer/"
cp -a "$TMP/islamic-data/prophet_stories/." "$DATA/prophet_stories/"
cp -a "$TMP/islamic-data/quran/chapters/ar/." "$DATA/quran/chapters/ar/"
for f in qcf_v2_pages.json mushaf_pages.json qcf_surah_starts.json quran_segments.json quran_symbols.json quran_duas.json hizb_quarters.json; do
  cp "$TMP/islamic-data/quran/$f" "$DATA/quran/$f"
done

# Validate the documented dataset structure.
test -s "$DATA/hadith/bukhari.json"
test -s "$DATA/hadith/muslim.json"
test -s "$DATA/tafseer/muyassar.json"
test -s "$DATA/names_of_allah/names_of_allah.json"
test -s "$DATA/prophet_stories/index.json"
test "$(find "$DATA/quran/chapters/ar" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 114

# quran-ws documents this sparse-clone method for the complete 604-page Mushaf.
echo '2/5 — Clone 604-page Hafs/KFQC Mushaf'
git clone --depth 1 --filter=blob:none --sparse "$QURAN_REPO" "$TMP/quran-svg"
git -C "$TMP/quran-svg" sparse-checkout set mushafs/hafs/kfqc/svg
git -C "$TMP/quran-svg" checkout --force
cp "$TMP/quran-svg"/mushafs/hafs/kfqc/svg/*.svg "$AS/quran-pages/"
test "$(find "$AS/quran-pages" -maxdepth 1 -type f -name '*.svg' | wc -l)" -eq 604

# Keep one known CC0 adhan recording locally so Native Android can play it without WebView/network access.
echo '3/5 — Bundle local adhan audio'
curl -fL --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 20 --max-time 180 -sS \
  "$ADHAN_URL" -o "$RESRAW/adhan.ogg"
test -s "$RESRAW/adhan.ogg"
cp "$RESRAW/adhan.ogg" "$AS/adhan/adhan.ogg"
cp "$RESRAW/notification.wav" "$AS/audio/notification.wav"

# The app reads these directories locally through WebViewAssetLoader.
echo '4/5 — Offline manifest'
cat > "$AS/OFFLINE_CONTENT.txt" <<'EOT'
YAWMY v1.0.5 — offline bundle

All required in-app content is copied into the APK at build time.
The running Android app reads the bundled local files; it does not require an internet
connection to open Quran, Adhkar, Hadith, stories, tafseer, names, or the Mushaf pages.

Bundled resources:
- 604 Hafs/KFQC Madinah Mushaf SVG pages
- 114 Arabic Quran chapter JSON files + page/reference indexes
- Sahih al-Bukhari and Sahih Muslim
- 3 forty-hadith collections
- 99 Names of Allah
- Tafseer Muyassar
- 25 Prophet stories + quiz data
- 14+ Azkar/Dua datasets
- CC0 adhan audio
- Local notification sound
EOT

cat > "$AS/ATTRIBUTIONS_OFFLINE.txt" <<'EOT'
Quran page artwork/data:
- quran-ws/quran-svg, Hafs/KFQC 604-page SVG release.
  https://github.com/quran-ws/quran-svg

Islamic datasets:
- Islamic App Data by mohammed-2-5.
  https://github.com/mohammed-2-5/islamic-library-data

Adhan:
- Adhan.ogg by Aishatu98 on Wikimedia Commons; CC0 1.0.
  https://commons.wikimedia.org/wiki/File:Adhan.ogg
EOT

echo '5/5 — Verify offline bundle'
echo "Quran pages: $(find "$AS/quran-pages" -maxdepth 1 -type f -name '*.svg' | wc -l)"
echo "Quran chapters: $(find "$DATA/quran/chapters/ar" -maxdepth 1 -type f -name '*.json' | wc -l)"
echo "Prophet stories: $(find "$DATA/prophet_stories" -maxdepth 1 -type f -name '*.json' | wc -l)"
echo "Azkar files: $(find "$DATA/azkar" -maxdepth 1 -type f -name '*.json' | wc -l)"
echo "Total offline assets:"; du -sh "$AS"
echo 'Offline assets prepared successfully.'
