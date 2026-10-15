# Green TD (Dota 2 custom game)

Port pentru Dota 2 al hărții de Warcraft III **Green TD v36.0** (autor: Sencility).
Toate valorile (turnuri, upgrade-uri, valuri, HP, armură, bounty, trasee, grilă de construcție)
sunt extrase automat din fișierul original `.w3x`, nu sunt copiate de mână.

*A Dota 2 custom game port of the Warcraft III map Green TD v36.0 by Sencility, with the same gameplay.*

Steam Workshop (Dota 2 Arcade): https://steamcommunity.com/sharedfiles/filedetails/?id=3820224535

## Credite

- Harta originală **Green TD v36.0**: Sencility. Acest proiect e un port neoficial, făcut de fani;
  gameplay-ul, numele turnurilor și valorile îi aparțin autorului hărții.
- Modelele, efectele și sunetele sunt din Dota 2 (Valve). Nu e folosit niciun fișier grafic sau audio din Warcraft III.
- Warcraft III este marcă Blizzard Entertainment; Dota 2 este marcă Valve. Proiectul nu e afiliat cu ele.

## Structură

```
game/dota_addons/green_td/       -> legat (junction) în dota 2 beta/game/dota_addons/green_td
  scripts/npc/                   unități (generat), abilități, eroul builder
  scripts/vscripts/gtd/          logica jocului (Lua)
  scripts/vscripts/gtd/data/     date generate din harta WC3 (nu se editează de mână)
  scripts/vscripts/modifiers/    atacul turnurilor, creepi, otravă, frost, fire trap
content/dota_addons/green_td/    -> legat în dota 2 beta/content/dota_addons/green_td
  maps/green_td.vmap             harta (generată: șablonul Valve + relieful, 16384 x 16384)
  panorama/                      interfața (HUD, meniu de construcție, panou turn)
tools/
  gen.py                         generatorul: date WC3 -> fișierele modului
  wc3/                           extractorul .w3x (MPQ); fetch_data.sh descarcă harta și creează wc3/data, wc3/slk
  luacheck_lite.py               verificare rapidă a sintaxei Lua
  dota_assets.txt                lista modelelor/efectelor din Dota (pentru validare)
  wearables.py                   cosmeticele implicite ale eroilor (din items_game.txt) -> default_wearables.json
  vpkls.py, vpkget.py            listare / extragere de fișiere din pak01_dir.vpk al jocului
```

## Regenerare date

Datele hărții originale și tabelele WC3 nu sunt în repository (aparțin autorului hărții și Blizzard).
Se descarcă și se extrag o singură dată; apoi `gen.py` reface toate fișierele generate din `game/` și `content/`:

```
./tools/wc3/fetch_data.sh
python -I tools/vpkls.py "<dota 2 beta>/game/dota/pak01_dir.vpk" tools/dota_assets.txt vpcf_c,vmdl_c,vsndevts_c
python -I tools/gen.py
python -I tools/luacheck_lite.py game/dota_addons/green_td/scripts/vscripts
```

`gen.py` verifică fiecare model și efect în `dota_assets.txt` și afișează `WARNING` dacă lipsește ceva.
Pentru hartă folosește Workshop Tools (`dmxconvert.exe` și harta-șablon `addon_template`); dacă Dota nu e în
locul implicit, setează `DOTA_DIR` la folderul `dota 2 beta`.
Modelele alese pentru fiecare turn/creep sunt în `TOWER_ART` și `CREEP_ART` din `gen.py`,
decorurile WC3 în `DOODAD_ART`, tastele de construcție în `BUILD_KEYS`.

Cosmeticele eroilor se regenerează doar după un update Dota (items_game.txt se extrage cu `vpkget.py`):

```
python -I tools/vpkget.py "<dota 2 beta>/game/dota/pak01_dir.vpk" _work/vpk scripts/items/items_game.txt
python -I tools/wearables.py _work/vpk/scripts/items/items_game.txt
```

## Compilare și pornire

```
resourcecompiler.exe -i content/dota_addons/green_td/maps/green_td.vmap -world -phys -vis -gridnav -nompi -nop4
resourcecompiler.exe -f -r -i "content/dota_addons/green_td/panorama/*" -nompi -nop4
resourcecompiler.exe -i content/dota_addons/green_td/particles/gtd/path_dirt.vpcf -nompi -nop4
resourcecompiler.exe -i content/dota_addons/green_td/materials/overviews/green_td.vmat -nompi -nop4
dota2.exe -steam -tools -addon green_td -condebug -novid -windowed -w 1280 -h 720 -netconport 29000 +sv_cheats 1 +dota_launch_custom_game green_td green_td
```

## Teste (în jocul pornit cu `-netconport 29000`)

- `tools/netcon.py "comanda"` trimite comenzi în consola jocului și afișează răspunsul.
- `tools/lua.py "cod"` sau `tools/lua.py @fisier.lua` rulează Lua pe server.
- `tools/relaunch.sh` repornește harta (implicit cu valurile oprite: `HOLD=0 NOLOSE=0` pentru reguli normale,
  `FAKE=1` umple sloturile cu jucători falși).
- `tools/perf.py 15` măsoară viteza serverului (secunde de joc / secunde reale) și FPS-ul clientului (`gtd_fps`).
- `tools/shot.ps1 out.png` face o captură a ferestrei jocului; `tools/click.ps1 x y` dă click în fereastră;
  `tools/key.ps1 S` apasă o tastă în fereastra jocului.
- Comenzi de consolă (doar cu `sv_cheats 1`): `gtd_selftest` (construcție, gold, upgrade, sell, grilă,
  kill, bounty), `gtd_selftest2` (splash, multishot, bounce, frost, poison, aer/sol, fire trap, aure,
  devotion, evasion, END), `gtd_state`, `gtd_gold`, `gtd_build`, `gtd_wave`, `gtd_hold`, `gtd_nolose`,
  `gtd_fps 10` (FPS-ul clientului), `gtd_soundcheck` (ce sunete există în joc).
- `dota_create_fake_clients` (în timpul setup-ului) umple sloturile cu jucători falși pentru teste cu 9 spawn-uri.

## Reguli (ca în WC3)

- 9 jucători (Red ... Gray), fiecare cu zona lui și spawn propriu; creepii se unesc spre END (jos).
- 60 de vieți comune („Chances”); un creep care ajunge la END ia o viață.
- 66 de valuri (60 + 6 extra). Primul val după 45 s; următorul doar când mor toți creepii,
  apoi bonus de gold pentru toți. HP-ul creepilor: x2 (handicap 200%), x1.5 la valul 36, x2.5 la 39-42, x4 de la 43.
- Gold de start: 850 (Red 1100). Bounty la fiecare kill pentru cel care a omorât creepul.
- Vânzare: primești valoarea „points” a turnului (nivel 1 = preț întreg).
- Daune WC3: tabelul tip de atac × tip de armură, formula de armură WC3 (0.06), splash pe 3 zone,
  bounce (Naisha), multishot, critical, bash, evasion, imunitate la magie, slow poison, frost, fire trap,
  aure (damage / command / speed; aceeași aură nu se cumulează).
- Armura Dota nu e folosită: formula Dota se strică la armura valurilor târzii (până la 8500).
- Decorurile WC3 (statui, coloane, pietre, felinare, capcanele de foc și gheață) sunt puse pe hartă
  și blochează construcția exact ca în WC3 (grila `war3map.wpm` include deja decorurile).

## Taste (hotkeys)

- Cu builder-ul selectat, tastele din WC3 aleg turnul de construit: S Siege, P Poison, M Multishot,
  A Air, C Frost, X Aura, F Fire Trap, N Naisha, T AntiAir, H Chaos, K Multishot Chaos.
- Cu un turn al tău selectat, tasta afișată pe butonul de upgrade face upgrade-ul
  (ca în WC3: de regulă litera familiei, de ex. S pentru Siege; aurele: X / D / S).
- Litera apare în colțul fiecărui buton. Tastele nu se declanșează când scrii în chat sau ții Alt / Ctrl.

## Sunete

- La fiecare val: un sunet după tipul valului (normal, aerian, imun la magie, erou, boss),
  plus un avertisment cu o secundă înainte de primul val.
- Construcție / upgrade / vânzare, jucător care pleacă, victorie și înfrângere.
- Toate sunt din Dota; lista e în `gtd/sounds.lua`.

## Diferențe tehnice față de WC3

- Turnurile foarte rapide (cooldown sub 0.25 s, de ex. 0.01 s) atacă de cel mult 4 ori pe secundă,
  dar fac proporțional mai multe daune pe atac, deci DPS-ul e același. Constanta e `GTD.MIN_ATTACK_INTERVAL`.
- Atacul motorului Dota e instant; proiectilul WC3 e lansat din Lua și daunele se aplică la impact.
  Altfel, cu sute de turnuri, motorul rămâne fără „attack records” (aserțiune în dota_attack_records.cpp).
- Modelele sunt din Dota (eroi, creepi, structuri). Turnurile cu model de erou poartă doar 2 cosmetice
  implicite (de regulă arma și capul) plus „montura” (liliacul lui Batrider, calul lui Chaos Knight);
  creepii nu au cosmetice. Setul complet pe ~340 de turnuri costa ~10 FPS, așa costă ~2.
- În WC3 harta e plată. Aici drumurile creepilor sunt cu un nivel (128) mai jos decât zonele de construit,
  ca niște șanțuri cu faleze (`terrain_heights` în `gen.py` scrie înălțimile în grila de dale Dota).
  Grila Dota are celule de 256, iar panta ocupă mijlocul celulei; pe jumătatea de jos a pantei nu se poate
  construi (~6% din celulele de construit WC3, `Grid:MarkCliffs`), pe buza falezei și jos lângă drum da.
  Builder-ul zboară, ca să treacă peste șanțuri. Drumurile au și particule de pământ (`particles/gtd/path_dirt`),
  stâncile WC3 blochează mersul prin obstacole invizibile, iar minimapa e generată din grilă și relief.

## Performanță (măsurată, client în modul -tools, 1280x720)

- 9 jucători, 342 de turnuri, valul 65 la vârf (~220 de creepi): serverul merge la 0.93–0.98x timp real,
  clientul la ~14 FPS. După vârf și în valurile obișnuite FPS-ul e mult mai mare (~95 FPS cu 342 de turnuri
  și fără creepi). Cea mai mare parte din cost: creepii și cele ~460 de proiectile pe secundă (~5 FPS).
