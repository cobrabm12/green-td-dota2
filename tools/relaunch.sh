#!/bin/sh
# Relaunch the green_td map in the running Dota 2 tools instance and wait until the game is in progress.
#   HOLD=0 NOLOSE=0   normal wave rules (default: waves held, no lives lost - for tests)
#   FAKE=1            fill the empty slots with fake clients (9-player tests)
G="/c/Program Files (x86)/Steam/steamapps/common/dota 2 beta/game/dota"
cd "$(dirname "$0")/.."
before=$(wc -l < "$G/console.log")
python -I tools/netcon.py --wait 1 "dota_launch_custom_game green_td green_td" > /dev/null
if [ "${FAKE:-0}" = "1" ]; then
  for i in $(seq 1 60); do
    if tail -n +$before "$G/console.log" | grep -aq "entering state 'DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP'"; then break; fi
    python -I -c "import time; time.sleep(1)"
  done
  python -I tools/netcon.py --wait 2 "dota_create_fake_clients" > /dev/null
fi
for i in $(seq 1 60); do
  if tail -n +$before "$G/console.log" | grep -aq "terrain obstructions"; then break; fi
  python -I -c "import time; time.sleep(2)"
done
python -I tools/netcon.py --wait 1 "gtd_hold ${HOLD:-1}" "gtd_nolose ${NOLOSE:-1}" > /dev/null
tail -n +$before "$G/console.log" | grep -aE "GTD|unknown modifier|Script Runtime|rror|attempt to" | grep -avE "Shader|dynamic_images|vmat_c|Failed loading resource" | tail -${LINES_SHOWN:-15}
