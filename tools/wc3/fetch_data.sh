#!/bin/sh
# Downloads the original map (Green TD v36.0 by Sencility) and the stock WC3 1.30.4 tables, then extracts
# the data gen.py reads into tools/wc3/data and tools/wc3/slk. These files are not in the repository
# (they belong to the map author and to Blizzard).
#   DEST=<dir>   write somewhere else (default: tools/wc3)
set -e
cd "$(dirname "$0")/../.."
DEST="${DEST:-tools/wc3}"
MAP_URL="https://storagebox.wc3maps.com/153802/Green%20TD%2036.0.w3x"
SLK_URL="https://raw.githubusercontent.com/MatthewMarinets/war3-ap-maps/main/gamedata/1_30_4"
W=_work/wc3fetch
rm -rf "$W"; mkdir -p "$W/tools" "$W/slk" "$W/out" "$DEST/data" "$DEST/slk"
cp tools/wc3/mpq.py tools/wc3/od.py tools/wc3/slk.py tools/wc3/res.py tools/wc3/wav.py "$W/tools/"
curl -sfL -A "Mozilla/5.0" -o "$W/map.w3x" "$MAP_URL"
for f in unitbalance.slk unitweapons.slk unitdata.slk unitabilities.slk abilitydata.slk upgradedata.slk \
         unitmetadata.slk abilitymetadata.slk upgrademetadata.slk; do
  curl -sfL -o "$W/slk/$f" "$SLK_URL/custom_v1/units/$f"
done
curl -sfL -o "$W/slk/doodads.slk" "$SLK_URL/doodads/doodads.slk"
cd "$W"
python -I tools/mpq.py map.w3x ex > /dev/null
python -I tools/od.py ex out/obj.json > /dev/null
python -I tools/res.py > /dev/null
python -I tools/wav.py > /dev/null
cd - > /dev/null
cp "$W/out/resolved.json" "$W/out/waves.json" "$W/out/wts.json" "$W/ex/war3map.wpm" "$W/ex/war3map.doo" "$DEST/data/"
cp "$W/slk/abilitydata.slk" "$W/slk/unitdata.slk" "$W/slk/doodads.slk" "$DEST/slk/"
echo "WC3 data -> $DEST/data, $DEST/slk"
