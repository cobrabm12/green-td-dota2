"""Green TD generator.

Reads the data extracted from the original Warcraft III map (tools/wc3/data/*.json, war3map.wpm)
and writes the Dota 2 addon data files:

  game/.../scripts/npc/npc_units_custom.txt        tower + creep units
  game/.../scripts/vscripts/gtd/data/towers.lua     tower definitions (stats, abilities, upgrades)
  game/.../scripts/vscripts/gtd/data/creeps.lua     creep definitions
  game/.../scripts/vscripts/gtd/data/waves.lua      the 66 waves
  game/.../scripts/vscripts/gtd/data/map.lua        regions, creep paths, build grid
  game/.../resource/addon_english.txt               unit names
  content/.../panorama/scripts/custom_game/gtd_data.js   tower definitions for the UI

Run from the repo root:  python -I tools/gen.py
"""
import json, math, os, re, struct, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WC3 = os.path.join(ROOT, 'tools', 'wc3')
GAME = os.path.join(ROOT, 'game', 'dota_addons', 'green_td')
CONTENT = os.path.join(ROOT, 'content', 'dota_addons', 'green_td')

sys.path.insert(0, WC3)
from slk import read_slk  # noqa: E402

ASSETS_TXT = os.path.join(ROOT, 'tools', 'dota_assets.txt')
if not os.path.exists(ASSETS_TXT) or not os.path.exists(os.path.join(WC3, 'data', 'resolved.json')):
    sys.exit('missing input files - see "Regenerare date" in README.md (tools/wc3/fetch_data.sh, tools/vpkls.py)')
R = json.load(open(os.path.join(WC3, 'data', 'resolved.json'), encoding='utf-8'))
W = json.load(open(os.path.join(WC3, 'data', 'waves.json'), encoding='utf-8'))
WTS = json.load(open(os.path.join(WC3, 'data', 'wts.json'), encoding='utf-8'))
U, A = R['units'], R['abilities']
_, STOCK_ABIL = read_slk(os.path.join(WC3, 'slk', 'abilitydata.slk'))
_, STOCK_UDATA = read_slk(os.path.join(WC3, 'slk', 'unitdata.slk'))
ASSETS = set(l.strip() for l in open(ASSETS_TXT, encoding='utf-8'))

BUILDER = 'uaco'
WARNINGS = []


# ----------------------------------------------------------------------------- helpers
def num(v, default=None):
    if v is None:
        return default
    if isinstance(v, (int, float)):
        return v
    s = str(v).strip()
    if s in ('', '-', '_', 'None'):
        return default
    try:
        return float(s) if '.' in s else int(s)
    except ValueError:
        return default


def clean(s):
    s = re.sub(r'\|[cC][0-9a-fA-F]{8}', '', str(s or ''))
    s = s.replace('|r', '').replace('|R', '').replace('|n', ' ').replace('\r', ' ').replace('\n', ' ')
    return re.sub(r'\s+', ' ', s).strip()


def tset(v):
    return set(x.strip().lower() for x in str(v or '').split(',') if x.strip())


def asset(path, fallback, kind):
    """Return path if it exists in the Dota VPK listing, else fallback (and remember a warning)."""
    if path and (path + '_c') in ASSETS:
        return path
    if path:
        WARNINGS.append('missing %s: %s -> %s' % (kind, path, fallback))
    return fallback


def lua(v, ind=0):
    pad = '\t' * ind
    if v is None:
        return 'nil'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        if isinstance(v, float) and v.is_integer():
            return str(int(v))
        return repr(round(v, 6)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (list, tuple)):
        if not v:
            return '{}'
        if all(not isinstance(x, (dict, list)) for x in v):
            return '{' + ', '.join(lua(x) for x in v) + '}'
        return '{\n' + ''.join(pad + '\t' + lua(x, ind + 1) + ',\n' for x in v) + pad + '}'
    if isinstance(v, dict):
        if not v:
            return '{}'
        out = '{\n'
        for k in v:
            key = k if re.fullmatch(r'[A-Za-z_]\w*', str(k)) else '[%s]' % lua(k)
            out += pad + '\t' + key + ' = ' + lua(v[k], ind + 1) + ',\n'
        return out + pad + '}'
    raise TypeError(type(v))


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote', os.path.relpath(path, ROOT))


def ability_levels(aid):
    """Level-1 data for an ability id, from map data or stock SLK."""
    if aid in A:
        r = A[aid]
        lv = r['lv'].get('1') or r['lv'].get(1) or {}
        return r['_base'], lv, clean(r.get('Name') or r.get('Tip') or '')
    st = STOCK_ABIL.get(aid)
    if st:
        lv = {}
        for col in ('targs', 'Dur', 'Cool', 'Area', 'Rng', 'BuffID'):
            v = st.get(col + '1')
            if v not in (None, '-', '_'):
                lv[col] = v
        for x in 'ABCDEFGHI':
            v = st.get('Data%s1' % x)
            if v not in (None, '-', '_'):
                lv['Data' + x] = v
        return st.get('code', aid), lv, aid
    return aid, {}, aid


# ----------------------------------------------------------------------------- WC3 tables
ATTACK_TABLE = {  # attack type -> multipliers vs defense types (miscgame.txt, TFT 1.30)
    'normal': [1.00, 1.50, 1.00, 0.70, 1.00, 1.00, 0.05, 1.00],
    'pierce': [2.00, 0.75, 1.00, 0.35, 1.00, 0.50, 0.05, 1.50],
    'siege':  [1.00, 0.50, 1.00, 1.50, 1.00, 0.50, 0.05, 1.50],
    'magic':  [1.25, 0.75, 2.00, 0.35, 1.00, 0.50, 0.05, 1.00],
    'chaos':  [1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
    'spells': [1.00, 1.00, 1.00, 1.00, 1.00, 0.75, 0.05, 1.00],
    'hero':   [1.00, 1.00, 1.00, 0.50, 1.00, 1.00, 0.05, 1.00],
}
DEFENSE_TYPES = ['small', 'medium', 'large', 'fort', 'normal', 'hero', 'divine', 'none']

# ----------------------------------------------------------------------------- art mapping
H = 'models/heroes/'
C = 'models/creeps/'
N = 'models/creeps/neutral_creeps/'
LANE = 'models/creeps/lane_creeps/'
P = 'particles/units/heroes/'

DEFAULT_TOWER_MODEL = 'models/props_structures/tower_good.vmdl'
DEFAULT_CREEP_MODEL = LANE + 'creep_bad_melee/creep_bad_melee.vmdl'
DEFAULT_PROJECTILE = 'particles/base_attacks/ranged_tower_good.vpcf'

# per tower id: (model, scale)
TOWER_ART = {
    # Siege (cannon tower base) - ground only, splash
    'h000': (H + 'nightstalker/nightstalker.vmdl', 0.75), 'h002': (H + 'terrorblade/terrorblade.vmdl', 0.75),
    'h003': (H + 'axe/axe.vmdl', 0.8), 'h004': (H + 'warlock/warlock.vmdl', 0.8),
    'h005': (H + 'shadowshaman/shadowshaman.vmdl', 0.85), 'h006': (H + 'juggernaut/juggernaut.vmdl', 0.85),
    'h001': (H + 'juggernaut/juggernaut.vmdl', 0.95), 'h007': (H + 'doom/doom.vmdl', 0.8),
    'h00K': (H + 'warlock/warlock_demon.vmdl', 0.75), 'h00L': (H + 'terrorblade/demon.vmdl', 0.8),
    'h00M': (H + 'broodmother/broodmother.vmdl', 0.8), 'h00S': (H + 'siren/siren.vmdl', 0.85),
    'h00R': (H + 'earthshaker/earthshaker.vmdl', 0.85), 'h00T': (H + 'abaddon/abaddon.vmdl', 0.9),
    'h00W': (N + 'n_creep_golem_a/neutral_creep_golem_a.vmdl', 0.9), 'h01B': (H + 'wraith_king/wraith_king.vmdl', 0.9),
    'h01D': (H + 'warlock/warlock.vmdl', 1.05), 'h01E': (H + 'pudge/pudge.vmdl', 0.9),
    'h01U': (H + 'winterwyvern/winterwyvern.vmdl', 0.75), 'h01L': (H + 'elder_titan/elder_titan.vmdl', 0.95),
    'h01S': (H + 'beastmaster/beastmaster.vmdl', 1.0), 'h01Z': (H + 'brewmaster/brewmaster.vmdl', 1.0),
    'h01X': (H + 'invoker/invoker.vmdl', 1.1),
    # Poison (guard tower base)
    'h008': (H + 'lich/lich.vmdl', 0.7), 'h00D': (H + 'lich/lich.vmdl', 0.8), 'h00C': (H + 'keeper_of_the_light/keeper_of_the_light.vmdl', 0.75),
    'h00B': (N + 'n_creep_ghost_a/n_creep_ghost_a.vmdl', 0.9), 'h00A': (H + 'necrolyte/necrolyte.vmdl', 0.8),
    'h009': (H + 'vengeful/vengeful.vmdl', 0.85), 'h00E': (H + 'enigma/enigma.vmdl', 0.8),
    'h00J': (H + 'tidehunter/tidehunter.vmdl', 0.75), 'h00N': (C + 'item_creeps/i_creep_necro_archer/necro_archer.vmdl', 1.0),
    'h00F': (H + 'clinkz/clinkz.vmdl', 0.9), 'h00U': (H + 'shadowshaman/shadowshaman.vmdl', 1.0),
    'h00V': (H + 'windrunner/windrunner.vmdl', 0.9), 'h012': (H + 'sven/sven.vmdl', 0.9),
    'h00Y': (H + 'queenofpain/queenofpain.vmdl', 0.9), 'h013': (H + 'life_stealer/life_stealer.vmdl', 0.95),
    'h01N': (H + 'disruptor/disruptor.vmdl', 0.9), 'h01K': (H + 'siren/siren.vmdl', 1.0),
    'h01O': (H + 'slardar/slardar.vmdl', 1.0), 'h022': (H + 'viper/viper.vmdl', 1.0),
    # Multishot (guard tower base)
    'h00X': (H + 'drow/drow_base.vmdl', 0.75), 'h014': (H + 'windrunner/windrunner.vmdl', 0.75),
    'h015': (H + 'enchantress/enchantress.vmdl', 0.75), 'h016': (H + 'chen/chen.vmdl', 0.7),
    'h017': (H + 'troll_warlord/troll_warlord.vmdl', 0.8), 'h018': (H + 'antimage/antimage.vmdl', 0.85),
    'h019': (H + 'vengeful/vengeful.vmdl', 0.9), 'h01A': (H + 'witchdoctor/witchdoctor.vmdl', 0.85),
    'h01C': (H + 'medusa/medusa.vmdl', 0.8), 'h028': (H + 'windrunner/windrunner.vmdl', 1.0),
    'h029': (H + 'drow/drow_base.vmdl', 1.0), 'h02A': (H + 'chaos_knight/chaos_knight.vmdl', 0.85),
    'h02B': (H + 'troll_warlord/troll_warlord.vmdl', 1.05),
    # Naisha (huntress base) - bouncing glaive
    'ensh': (H + 'luna/luna.vmdl', 0.7), 'e008': (H + 'luna/luna.vmdl', 0.75), 'e009': (H + 'luna/luna.vmdl', 0.8),
    'e00A': (H + 'luna/luna.vmdl', 0.85), 'e00B': (H + 'luna/luna.vmdl', 0.9), 'e00C': (H + 'luna/luna.vmdl', 0.95),
    'e007': (H + 'luna/luna.vmdl', 1.0), 'e00D': (H + 'luna/luna.vmdl', 1.05), 'e00E': (H + 'luna/luna.vmdl', 1.1),
    'e00F': (H + 'luna/luna.vmdl', 1.15), 'n00U': (H + 'mirana/mirana.vmdl', 1.2),
    # AntiAir
    'h021': ('models/props_structures/tower_good.vmdl', 0.6), 'h027': ('models/props_structures/tower_good2.vmdl', 0.6),
    'h026': ('models/props_structures/tower_good3.vmdl', 0.6), 'h025': ('models/props_structures/tower_good4.vmdl', 0.6),
    # Chaos
    'h023': ('models/props_structures/tower_bad.vmdl', 0.55), 'h024': ('models/props_structures/tower_bad.vmdl', 0.6),
    'h01Y': ('models/props_structures/tower_bad.vmdl', 0.65), 'h020': ('models/props_structures/tower_dragon_black.vmdl', 0.6),
    'h02C': ('models/props_structures/tower_dragon_black.vmdl', 0.7),
    # Fire traps (circle on the ground + burning effect)
    'n00A': ('models/props_gameplay/default_ward.vmdl', 0.6), 'n00C': ('models/props_gameplay/default_ward.vmdl', 0.65),
    'n00F': ('models/props_gameplay/default_ward.vmdl', 0.7), 'n00G': ('models/props_gameplay/default_ward.vmdl', 0.75),
    'n00E': ('models/props_gameplay/default_ward.vmdl', 0.8), 'n00H': ('models/props_gameplay/default_ward.vmdl', 0.85),
    'n002': ('models/props_gameplay/default_ward.vmdl', 0.9),
    # Air
    'n00M': ('models/props_gameplay/chicken.vmdl', 1.6), 'n00B': (H + 'puck/puck.vmdl', 0.8),
    'n00D': (H + 'batrider/batrider.vmdl', 0.8), 'n000': (N + 'n_creep_black_drake/n_creep_black_drake.vmdl', 0.9),
    'n003': (H + 'phoenix/phoenix_bird.vmdl', 0.6), 'n001': (H + 'viper/viper.vmdl', 0.8),
    'n005': (H + 'visage/visage.vmdl', 0.8), 'n004': ('models/events/frostivus/penguin/penguin.vmdl', 1.6),
    'n00J': (H + 'jakiro/jakiro.vmdl', 0.8), 'n008': ('models/props_gameplay/sheep01.vmdl', 1.8),
    'n009': (H + 'death_prophet/death_prophet.vmdl', 0.9), 'n00S': (H + 'winterwyvern/winterwyvern.vmdl', 0.8),
    'n00O': (H + 'dragon_knight/dragon_knight_dragon.vmdl', 0.6), 'n00X': (N + 'n_creep_black_dragon/n_creep_black_dragon.vmdl', 0.9),
    # Frost
    'n006': ('models/props_gameplay/treasure_chest001.vmdl', 1.4), 'n00I': (H + 'crystal_maiden/crystal_maiden.vmdl', 0.8),
    'n00K': (N + 'n_creep_troll_dark_b/n_creep_troll_dark_frost.vmdl', 1.1), 'n007': (H + 'mirana/mirana.vmdl', 0.9),
    'n00R': (C + 'ice_biome/giant/ice_giant01.vmdl', 0.9),
    # Aura towers
    'h00H': ('models/props_structures/radiant_tower001.vmdl', 0.45), 'h00O': ('models/props_structures/radiant_tower001.vmdl', 0.5),
    'h00Z': ('models/props_structures/radiant_tower001.vmdl', 0.55), 'h01F': ('models/props_structures/radiant_tower001.vmdl', 0.6),
    'h01M': ('models/props_structures/radiant_tower001.vmdl', 0.65), 'h01R': ('models/props_structures/radiant_tower001.vmdl', 0.7),
    'h00I': ('models/props_structures/dire_tower001.vmdl', 0.45), 'h010': ('models/props_structures/dire_tower001.vmdl', 0.5),
    'h00P': ('models/props_structures/dire_tower001.vmdl', 0.55), 'h01P': ('models/props_structures/dire_tower001.vmdl', 0.6),
    'h01V': ('models/props_structures/dire_tower001.vmdl', 0.65), 'h01G': ('models/props_structures/dire_tower001.vmdl', 0.7),
    'h00G': ('models/props_structures/radiant_tower002.vmdl', 0.45), 'h011': ('models/props_structures/radiant_tower002.vmdl', 0.5),
    'h00Q': ('models/props_structures/radiant_tower002.vmdl', 0.55), 'h01Q': ('models/props_structures/radiant_tower002.vmdl', 0.6),
    'h01H': ('models/props_structures/radiant_tower002.vmdl', 0.65), 'h01W': ('models/props_structures/radiant_tower002.vmdl', 0.7),
}

FAMILY_PROJECTILE = {
    'siege': 'particles/base_attacks/ranged_siege_good.vpcf',
    'poison': P + 'hero_venomancer/venomancer_base_attack.vpcf',
    'multishot': P + 'hero_drow/drow_base_attack.vpcf',
    'naisha': P + 'hero_luna/luna_moon_glaive.vpcf',
    'antiair': P + 'hero_gyrocopter/gyro_base_attack.vpcf',
    'chaos': P + 'hero_terrorblade/terrorblade_metamorphosis_base_attack.vpcf',
    'air': P + 'hero_jakiro/jakiro_base_attack_fire.vpcf',
    'frost': P + 'hero_crystalmaiden/maiden_base_attack.vpcf',
    'aura': None, 'firetrap': None,
}

# per creep id: (model, scale, display name)
CREEP_ART = {
    'hfoo': (LANE + 'creep_radiant_melee/radiant_melee.vmdl', 1.0, 'Footman'),
    'hrif': (H + 'sniper/sniper.vmdl', 0.9, 'Rifleman'),
    'hsor': (H + 'lina/lina.vmdl', 0.85, 'Sorceress'),
    'hspt': (H + 'antimage/antimage.vmdl', 0.85, 'Spell Breaker'),
    'hmpr': (H + 'chen/chen.vmdl', 0.75, 'Priest'),
    'hkni': (H + 'techies/techies.vmdl', 0.9, 'Mortar Team'),
    'hgyr': (H + 'gyro/gyro.vmdl', 0.8, 'Flying Machine'),
    'hmtm': (LANE + 'creep_bad_siege/creep_bad_siege.vmdl', 0.9, 'Siege Engine'),
    'h01T': (N + 'n_creep_harpy_b/n_creep_harpy_b.vmdl', 1.1, 'Gryphon Rider'),
    'ogru': (LANE + 'creep_bad_melee/creep_bad_melee.vmdl', 1.0, 'Grunt'),
    'ohun': (N + 'n_creep_forest_trolls/n_creep_forest_troll_berserker.vmdl', 1.0, 'Troll Headhunter'),
    'o003': (H + 'huskar/huskar.vmdl', 0.9, 'Troll Berserker'),
    'odoc': (H + 'witchdoctor/witchdoctor.vmdl', 0.85, 'Witch Doctor'),
    'oshm': (H + 'shadowshaman/shadowshaman.vmdl', 0.85, 'Shaman'),
    'n00P': (LANE + 'creep_bad_melee/creep_bad_melee_mega.vmdl', 1.0, 'Chaos Grunt'),
    'orai': (N + 'n_creep_worg_large/n_creep_worg_large.vmdl', 1.0, 'Raider'),
    'otbr': (H + 'batrider/batrider.vmdl', 0.8, 'Troll Batrider'),
    'okod': (N + 'n_creep_thunder_lizard/n_creep_thunder_lizard_big.vmdl', 0.9, 'Kodo Beast'),
    'ospw': (H + 'elder_titan/ancestral_spirit.vmdl', 0.9, 'Spirit Walker'),
    'otau': (N + 'n_creep_centaur_lrg/n_creep_centaur_lrg.vmdl', 1.0, 'Tauren'),
    'owyv': (N + 'n_creep_vulture_a/n_creep_vulture_a.vmdl', 1.1, 'Wind Rider'),
    'earc': (H + 'drow/drow_base.vmdl', 0.85, 'Archer'),
    'esen': (H + 'luna/luna.vmdl', 0.85, 'Huntress'),
    'edot': (H + 'skywrath_mage/skywrath_mage.vmdl', 0.8, 'Druid of the Talon'),
    'edry': (H + 'enchantress/enchantress.vmdl', 0.85, 'Dryad'),
    'edoc': (H + 'lone_druid/true_form.vmdl', 0.8, 'Druid of the Claw'),
    'ehip': (N + 'n_creep_harpy_a/n_creep_harpy_a.vmdl', 1.1, 'Hippogryph'),
    'ewsp': (H + 'wisp/wisp.vmdl', 0.8, 'Wisp'),
    'e003': (H + 'treant_protector/treant_protector.vmdl', 0.7, 'Mountain Giant'),
    'e005': (H + 'jakiro/jakiro.vmdl', 0.7, 'Chimaera'),
    'ugho': (H + 'life_stealer/life_stealer.vmdl', 0.8, 'Ghoul'),
    'unec': (H + 'necrolyte/necrolyte.vmdl', 0.8, 'Necromancer'),
    'uban': (H + 'death_prophet/death_prophet.vmdl', 0.8, 'Banshee'),
    'ucry': (H + 'nerubian_assassin/nerubian_assassin.vmdl', 0.8, 'Crypt Fiend'),
    'ugar': (N + 'n_creep_gargoyle/n_creep_gargoyle.vmdl', 1.0, 'Gargoyle'),
    'uobs': (LANE + 'creep_good_siege/creep_good_siege.vmdl', 1.0, 'Dead Machine'),
    'uabo': (H + 'pudge/pudge.vmdl', 0.8, 'Abomination'),
    'ufro': (H + 'winterwyvern/winterwyvern.vmdl', 0.7, 'Frost Wyrm'),
    'Hmkg': (H + 'sven/sven.vmdl', 0.9, 'Mountain King'),
    'Hpal': (H + 'omniknight/omniknight.vmdl', 0.9, 'Paladin'),
    'Hblm': (H + 'invoker/invoker.vmdl', 0.9, 'Blood Mage'),
    'Hamg': (H + 'keeper_of_the_light/keeper_of_the_light.vmdl', 0.9, 'Archmage'),
    'Obla': (H + 'juggernaut/juggernaut.vmdl', 0.9, 'Blademaster'),
    'O004': (H + 'elder_titan/elder_titan.vmdl', 0.85, 'Tauren Chieftain'),
    'Ofar': (H + 'disruptor/disruptor.vmdl', 0.85, 'Far Seer'),
    'Oshd': (H + 'dazzle/dazzle.vmdl', 0.9, 'Shadow Hunter'),
    'Ekee': (H + 'furion/furion.vmdl', 0.9, 'Keeper of the Grove'),
    'nrdr': (H + 'phoenix/phoenix_bird.vmdl', 0.6, 'Phoenix'),
    'Edem': (H + 'terrorblade/terrorblade.vmdl', 0.9, 'Demon Hunter'),
    'Emoo': (H + 'mirana/mirana.vmdl', 0.9, 'Priestess of the Moon'),
    'Ewar': (H + 'phantom_assassin/phantom_assassin.vmdl', 0.9, 'Warden'),
    'Udre': (H + 'nightstalker/nightstalker.vmdl', 0.85, 'Dreadlord'),
    'nbdk': (H + 'puck/puck.vmdl', 0.9, 'Faerie Dragon'),
    'Udea': (H + 'abaddon/abaddon.vmdl', 0.9, 'Death Knight'),
    'Ulic': (H + 'lich/lich.vmdl', 0.9, 'Lich'),
    'Ucrl': (H + 'sand_king/sand_king.vmdl', 0.8, 'Crypt Lord'),
    'ninf': (H + 'warlock/warlock_demon.vmdl', 0.8, 'Fire Infernal'),
    'o001': (H + 'slardar/slardar.vmdl', 0.95, 'Naga Royal Guard'),
    'nnsw': (H + 'siren/siren.vmdl', 0.95, 'Naga Siren'),
    'o000': (H + 'tidehunter/tidehunter.vmdl', 0.8, 'Naga Myrmidon'),
    'hmil': (LANE + 'creep_radiant_melee/radiant_melee_mega.vmdl', 1.0, 'Militia'),
    'osw1': (N + 'n_creep_worg_small/n_creep_worg_small.vmdl', 1.4, 'Spirit Wolf'),
    'ucs1': (H + 'weaver/weaver.vmdl', 0.8, 'Scarab'),
    'o002': (H + 'broodmother/broodmother.vmdl', 0.7, 'Nerubian'),
    'ngdk': (H + 'obsidian_destroyer/obsidian_destroyer.vmdl', 0.7, 'Destroyer'),
    'U002': (H + 'wraith_king/wraith_king.vmdl', 1.4, 'Lich King'),
    'nzom': (H + 'undying/undying_minion.vmdl', 1.0, 'Zombie'),
}

FAMILY_BY_BASE = {'hctw': 'siege', 'ntt1': 'air', 'ndt2': 'frost', 'hatw': 'aura', 'ncp2': 'firetrap',
                  'ensh': 'naisha', 'ncap': 'naisha'}


def family_of(uid, u):
    name = clean(u.get('name')).lower()
    for key, fam in (('multishot', 'multishot'), ('poison', 'poison'), ('antiair', 'antiair'), ('chaos tower', 'chaos'),
                     ('siege', 'siege'), ('air tower', 'air'), ('frost', 'frost'), ('fire trap', 'firetrap'),
                     ('naisha', 'naisha')):
        if key in name:
            return fam
    if 'aura' in name or 'damage tower' in name or 'speed tower' in name:
        return 'aura'
    return FAMILY_BY_BASE.get(u['_base'], 'misc')


# ----------------------------------------------------------------------------- towers
def tower_abilities(u, rec):
    for aid in [a.strip() for a in str(u.get('abilities') or '').split(',') if a.strip()]:
        base, lv, nm = ability_levels(aid)
        da = lambda k, d=0: num(lv.get(k), d)  # noqa: E731
        if base in ('AOcr', 'ACct'):
            rec.setdefault('crits', []).append({'chance': da('DataA'), 'mult': da('DataB', 1), 'bonus': da('DataC')})
        elif base in ('ACbh', 'AHbh'):
            rec['bash'] = {'chance': da('DataA'), 'bonus': da('DataC'), 'duration': num(lv.get('Dur'), 1),
                           'ground_only': 'air' not in tset(lv.get('targs'))}
        elif base == 'Aspo':
            rec['poison'] = {'dps': da('DataA'), 'slow': da('DataB'), 'duration': num(lv.get('Dur'), 1)}
        elif base in ('Afra', 'Afr2'):
            rec['frost'] = {'slow': 0.5, 'duration': num(lv.get('Dur'), 5)}
        elif base == 'Aroc':
            rec['multishot'] = {'targets': int(da('DataC', 1)), 'radius': num(lv.get('Area'), 900)}
        elif base == 'ANpi':
            targs = tset(lv.get('targs'))
            rec['immolation'] = {'dps': da('DataA'), 'radius': num(lv.get('Area'), 250),
                                 'air': 'air' in targs, 'ground': 'ground' in targs or not targs}
        elif base in ('AEar', 'ACat'):
            rec.setdefault('auras', []).append({'kind': 'damage', 'value': da('DataA'), 'radius': num(lv.get('Area'), 900)})
        elif base == 'ACac':
            rec.setdefault('auras', []).append({'kind': 'command', 'value': da('DataA'), 'radius': num(lv.get('Area'), 900)})
        elif base in ('AOae', 'SCae'):
            rec.setdefault('auras', []).append({'kind': 'speed', 'value': da('DataB'), 'radius': num(lv.get('Area'), 900)})
        # Cleave (ACce) only works for melee attacks in WC3 -> towers are ranged, so it has no effect.
        # Amgr / Aflk / Adts / Abds / ACua have no effect on tower attacks in this map.


def footprint_cells(u):
    pt = u.get('upat') or STOCK_UDATA.get(u['_base'], {}).get('pathTex') or ''
    m = re.search(r'(\d+)x\d+', str(pt))
    return int(m.group(1)) if m else 4


def tower_rec(uid):
    u = U[uid]
    fam = family_of(uid, u)
    model, scale = TOWER_ART.get(uid, (DEFAULT_TOWER_MODEL, 0.6))
    rec = {
        'id': uid, 'unit': 'gtd_t_' + uid, 'family': fam,
        'name': clean(u.get('name')), 'tip': clean(u.get('tip')), 'desc': clean(u.get('ubertip')),
        'hotkey': clean(u.get('hotkey')) or None,
        'cost': int(num(u.get('gold'), 0)), 'sell': int(num(u.get('points'), 0)),
        'build_time': num(u.get('buildtime'), 1),
        'footprint': footprint_cells(u),
        'upgrades': [x.strip() for x in str(u.get('upgradesTo') or '').split(',') if x.strip()],
        'model': asset(model, DEFAULT_TOWER_MODEL, 'model'), 'scale': scale,
    }
    if int(num(u.get('attacksEnabled'), 0)) & 1:
        targets = tset(u.get('targets1'))
        rec['attack'] = {
            'base': num(u.get('dmgBase1'), 0), 'dice': num(u.get('dmgDice1'), 1), 'sides': num(u.get('dmgSides1'), 1),
            'cooldown': num(u.get('cool1'), 1), 'range': num(u.get('range1'), 600), 'type': str(u.get('atkType1') or 'normal').lower(),
            'weapon': str(u.get('weapType1') or 'missile').lower(),
            'air': 'air' in targets, 'ground': 'ground' in targets,
            'missile_speed': num(u.get('missileSpeed1'), 1200),
        }
        at = rec['attack']
        if at['type'] not in ATTACK_TABLE:
            WARNINGS.append('%s unknown attack type %s' % (uid, at['type']))
            at['type'] = 'normal'
        if at['weapon'] in ('msplash', 'artillery', 'aline'):
            st = tset(u.get('splashTargets1')) or targets
            at['splash'] = {'full': num(u.get('areaFull1'), 0), 'medium': num(u.get('areaMed1'), 0), 'small': num(u.get('areaSmall1'), 0),
                            'f_medium': num(u.get('factorMed1'), 0), 'f_small': num(u.get('factorSmall1'), 0),
                            'air': 'air' in st, 'ground': 'ground' in st}
        if at['weapon'] == 'mbounce':
            at['bounce'] = {'targets': int(num(u.get('maxTargets1'), 1)), 'loss': num(u.get('dmgLoss1'), 0),
                            'range': num(u.get('areaFull1'), 500)}
        proj = FAMILY_PROJECTILE.get(fam) or DEFAULT_PROJECTILE
        at['projectile'] = asset(proj, DEFAULT_PROJECTILE, 'particle')
    tower_abilities(u, rec)
    return rec


# Build hotkeys of the builder. WC3 used S (Siege, Chaos), P (Poison, AntiAir) and M (both Multishots)
# twice; the most used tower keeps the WC3 letter and the other one gets a free letter.
BUILD_KEYS = {'h000': 'S', 'h008': 'P', 'h00X': 'M', 'n00M': 'A', 'n006': 'C', 'h00H': 'X', 'n00A': 'F',
              'ensh': 'N', 'h021': 'T', 'h023': 'H', 'h02A': 'K'}


def assign_upgrade_keys(towers):
    """WC3: the upgrade button uses the hotkey of the tower it upgrades to (the family letter).
    Options of one tower must differ: fall back to the first free letter of the name, then digits."""
    for t in towers.values():
        used, keys = set(), {}
        for up in t['upgrades']:
            target = towers.get(up)
            if not target:
                continue
            fixed = {'Aura Tower': 'X', 'Damage Tower': 'D', 'Speed Tower': 'S'}
            family_key = next((k for n, k in fixed.items() if target['name'].startswith(n)), None)
            cands = [family_key, target.get('hotkey')] + [c.upper() for c in re.sub(r'[^A-Za-z]', '', target['name'])] + list('123456789')
            for c in cands:
                if c and c not in used:
                    keys[up] = c
                    used.add(c)
                    break
        t['upgrade_keys'] = keys


def collect_towers():
    roots = [x.strip() for x in str(U[BUILDER].get('builds')).split(',') if x.strip()]
    seen, order = set(), []
    stack = list(reversed(roots))
    while stack:
        t = stack.pop()
        if t in seen or t not in U:
            continue
        seen.add(t)
        order.append(t)
        for n in reversed([x.strip() for x in str(U[t].get('upgradesTo') or '').split(',') if x.strip()]):
            stack.append(n)
    return roots, order


# ----------------------------------------------------------------------------- creeps
def creep_rec(uid):
    u = U[uid]
    model, scale, name = CREEP_ART.get(uid, (DEFAULT_CREEP_MODEL, 1.0, clean(u.get('tip')) or uid))
    targeted = tset(u.get('targetedAs'))
    rec = {
        'id': uid, 'unit': 'gtd_c_' + uid, 'name': name,
        'hp': int(num(u.get('hp'), 100)), 'regen': num(u.get('hpRegen'), 0) or 0,
        'armor': num(u.get('armor'), 0), 'defense': str(u.get('defType') or 'none').lower(),
        'speed': num(u.get('moveSpeed'), 300), 'air': 'air' in targeted,
        'bounty': int(num(u.get('bountyBase'), 0)), 'bounty_dice': int(num(u.get('bountyDice'), 0)),
        'bounty_sides': int(num(u.get('bountySides'), 0)),
        'mechanical': 'mechanical' in str(u.get('classification') or '').lower(),
        'model': asset(model, DEFAULT_CREEP_MODEL, 'model'), 'scale': scale * (num(u.get('scale'), 1) or 1),
    }
    if rec['defense'] not in DEFENSE_TYPES:
        WARNINGS.append('%s unknown defense %s' % (uid, rec['defense']))
        rec['defense'] = 'none'
    for aid in [a.strip() for a in str(u.get('abilities') or '').split(',') if a.strip()]:
        base, lv, nm = ability_levels(aid)
        da = lambda k, d=0: num(lv.get(k), d)  # noqa: E731
        if base in ('Amim', 'ACmi'):
            rec['immune'] = True
        elif base == 'ACev':
            if da('DataA') > rec.get('evasion', 0):
                rec['evasion'] = da('DataA')
        elif base == 'ACav':
            if da('DataA') > rec.get('devotion', {}).get('armor', 0):
                rec['devotion'] = {'armor': da('DataA'), 'radius': num(lv.get('Area'), 900)}
        elif base == 'ACua':
            rec['unholy'] = {'speed': da('DataA'), 'regen': da('DataB'), 'radius': num(lv.get('Area'), 900)}
        elif base in ('SCae', 'AOae'):
            rec['endurance'] = {'speed': da('DataA'), 'radius': num(lv.get('Area'), 900)}
        elif base == 'ANpi' and da('DataA') < 0 and 'self' in tset(lv.get('targs')):
            rec['regen'] = rec['regen'] - da('DataA')   # "Lifeboost": negative immolation heals itself
    return rec


# ----------------------------------------------------------------------------- waves
def wts(s):
    m = re.fullmatch(r'TRIGSTR_(\d+)', s or '')
    return WTS.get(str(int(m.group(1))), s) if m else s


def wave_list():
    waves = []
    for n in sorted((int(k) for k in W['waves'])):
        w = W['waves'][str(n)]
        text = next((clean(x[6:]) for x in w['notes'] if x.startswith('text: ')), 'Wave %d' % n)
        sound = next((x[7:] for x in w['notes'] if x.startswith('sound: ')), 'Wave_Normal')
        kind = {'Wave_Air': 'air', 'Wave_Immune': 'immune', 'Wave_Hero': 'hero', 'Wave_Boss': 'boss'}.get(sound, 'normal')
        seq = []
        for ev in w['seq']:
            if ev[0] == 'spawn':
                seq.append({'spawn': ev[2], 'count': ev[1], 'region': ev[3], 'slot': ev[4]})
            elif ev[0] == 'wait':
                seq.append({'wait': ev[1]})
            elif ev[0] == 'handicap':
                seq.append({'handicap': ev[1]})
        start = W['starts'].get(str(n), {})
        gold = int(start['gold_all'][0]) if start.get('gold_all') else 0
        waves.append({'n': n, 'text': text, 'kind': kind, 'sound': sound, 'seq': seq,
                      'start_gold': gold, 'start_delay': start.get('delay', 0) or 0})
    return waves


# ----------------------------------------------------------------------------- map
def build_grid():
    d = open(os.path.join(WC3, 'data', 'war3map.wpm'), 'rb').read()
    _, _, w, h = struct.unpack_from('<4sIII', d, 0)
    cells = d[16:16 + w * h]

    def ch(v):
        if v & 0x02:
            return 'x'          # not walkable (cliffs, edges)
        if v & 0x08:
            return 'w'          # walkable, not buildable (creep paths)
        return 'b'              # buildable
    rows = [''.join(ch(cells[y * w + x]) for x in range(w)) for y in range(h)]
    # sanity check orientation: waypoint centers must be on walkable, unbuildable cells
    def at(px, py, rws):
        cx, cy = int((px + 6144) // 32), int((py + 6144) // 32)
        return rws[cy][cx]
    pts = [r['center'] for k, r in W['rects'].items() if re.match(r'^(\d[a-e]|.*go\d?|topleft|topright)$', k)]
    ok = sum(1 for p in pts if at(p[0], p[1], rows) == 'w')
    flipped = list(reversed(rows))
    ok_f = sum(1 for p in pts if at(p[0], p[1], flipped) == 'w')
    if ok_f > ok:
        rows = flipped
    print('grid orientation check: %d/%d waypoints on path cells' % (max(ok, ok_f), len(pts)))
    rle = []
    for row in rows:
        out, i = [], 0
        while i < len(row):
            j = i
            while j < len(row) and row[j] == row[i]:
                j += 1
            out.append('%s%d' % (row[i], j - i))
            i = j
        rle.append(''.join(out))
    return {'origin': [-6144, -6144], 'cell': 32, 'width': w, 'height': h, 'rows': rle}


SLOT_COLORS = ['red', 'blue', 'teal', 'purple', 'yellow', 'orange', 'green', 'pink', 'gray']
START_LOCATIONS = [(64, 256), (-832, -2752), (832, -2752), (-4416, -2048), (4416, -2048),
                   (-4800, 4736), (4800, 4736), (-4864, 2304), (4864, 2176)]
SLOT_SPAWNS = {0: ['5_Red_Spawn_A', '5_Red_Spawn_B'], 1: ['8_Blue_Spawn'], 2: ['9_Teal_Spawn'], 3: ['6_Purple_Spawn'],
               4: ['7_Yellow_Spawn'], 5: ['3_Orange_Spawn'], 6: ['4_Green_Spawn'], 7: ['1_Pink_Spawn'], 8: ['2_Gray_Spawn']}
SLOT_ZONES = {0: ['RedZone'], 1: ['BlueZone', 'BlueZone2'], 2: ['TealZone', 'TealZone2'], 3: ['PurpleZone'], 4: ['YellowZone'],
              5: ['OrangeZone'], 6: ['GreenZone'], 7: ['PinkZone'], 8: ['GreyZone']}


def map_data():
    rects = {k: {'min': v['min'], 'max': v['max']} for k, v in W['rects'].items()}
    return {
        'rects': rects, 'next': W['graph'], 'end_region': 'END',
        'slots': [{'slot': i, 'color': SLOT_COLORS[i], 'start': list(START_LOCATIONS[i]),
                   'spawns': SLOT_SPAWNS[i], 'zones': SLOT_ZONES[i]} for i in range(9)],
        'grid': build_grid(),
        'doodads': doodad_list(),
    }


# WC3 doodads of the map -> Dota prop models / ambient particles, and the cells their pathing texture covers
# (in WC3 those cells cannot be built on). Irregular textures use their bounding box.
DOODAD_ART = {
    'ZPfw': {'models': ['models/props_nature/flowers001.vmdl', 'models/props_nature/flowers002.vmdl', 'models/props_nature/flowers003.vmdl'], 'scale': 0.9},
    'APct': {'models': ['models/props_nature/cattails001.vmdl', 'models/props_nature/cattails002.vmdl', 'models/props_nature/cattails003.vmdl'], 'scale': 0.8},
    'LRrk': {'models': ['models/props_rock/riveredge_rock006a.vmdl', 'models/props_rock/riveredge_rock007a.vmdl', 'models/props_rock/riveredge_rock008a.vmdl'], 'scale': 0.5},
    'YSll': {'models': ['models/props_debris/lantern001.vmdl'], 'scale': 1.0},
    'YSaw': {'models': ['models/props_structures/ancient_column001.vmdl'], 'scale': 0.6, 'pair': 160},
    'YScd': {'models': ['models/props_structures/ancient_column002.vmdl'], 'scale': 0.6, 'pair': 300},
    'YScs': {'models': ['models/props_structures/ancient_column003.vmdl'], 'scale': 0.6},
    'YSc2': {'models': ['models/props_structures/ancient_column003.vmdl'], 'scale': 0.6},
    'YSc3': {'models': ['models/props_structures/ancient_column003.vmdl'], 'scale': 0.6},
    'YSc4': {'models': ['models/props_structures/ancient_column003.vmdl'], 'scale': 0.6},
    'YOob': {'models': ['models/props_structures/obelisk001.vmdl'], 'scale': 0.5},
    'LOsk': {'models': ['models/props_bones/skull_ram001.vmdl'], 'scale': 1.4},
    'YObb': {'models': ['models/props/creep_banners/creep_banner_radiant.vmdl'], 'scale': 1.0},
    'YOwb': {'models': ['models/props/creep_banners/creep_banner_radiant.vmdl'], 'scale': 1.0},
    'YOks': {'models': ['models/props_structures/classical_statue001.vmdl'], 'scale': 0.6},
    'YOst': {'models': ['models/props_structures/classical_statue002.vmdl'], 'scale': 0.6},
    'VOfl': {'models': ['models/props_debris/wood_fence001a.vmdl'], 'scale': 1.0},
    'DOtp': {'models': ['models/props_gameplay/treasure_chest_gold.vmdl'], 'scale': 1.2},
    'YOf2': {'particle': 'particles/world_environmental_fx/fire_camp_01.vpcf'},
    'YOr2': {'particle': 'particles/units/heroes/hero_crystalmaiden/maiden_frostbite_buff.vpcf'},
    'YOfb': {'particle': 'particles/world_environmental_fx/bluetorch_flame.vpcf'},
}
PATH_TEXTURE_CELLS = {'2x2Default': (2, 2), '4x4Default': (4, 4), '8x8Default': (8, 8), '8x2Default': (8, 2),
                      '22x4DoubleColumn': (22, 4), 'CityArch': (12, 4), 'ColumnSemiCircle3': (6, 6)}


def doodad_list():
    _, slk = read_slk(os.path.join(WC3, 'slk', 'doodads.slk'))
    d = open(os.path.join(WC3, 'data', 'war3map.doo'), 'rb').read()
    _, ver, sub, n = struct.unpack_from('<4sIII', d, 0)
    pos, out = 16, []
    for _ in range(n):
        tid = d[pos:pos + 4].decode('latin-1')
        var = struct.unpack_from('<I', d, pos + 4)[0]
        x, y, z, ang, sx, sy, sz = struct.unpack_from('<7f', d, pos + 8)
        pos += 36 + 2
        _, nsets = struct.unpack_from('<ii', d, pos)
        pos += 8
        for _ in range(nsets):
            ni = struct.unpack_from('<i', d, pos)[0]
            pos += 4 + ni * 8
        pos += 4
        art = DOODAD_ART.get(tid)
        row = slk.get(tid, {})
        rec = {'id': tid, 'x': round(x, 1), 'y': round(y, 1), 'yaw': round(math.degrees(ang) % 360, 1)}
        tex = re.sub(r'.*\\|\.tga$', '', str(row.get('pathTex') or ''))
        if tex in PATH_TEXTURE_CELLS:
            w, h = PATH_TEXTURE_CELLS[tex]
            fixed = num(row.get('fixedRot'), -1)
            quarter = int(round((fixed if fixed is not None and fixed >= 0 else math.degrees(ang)) / 90.0)) % 4
            if quarter % 2 == 1:
                w, h = h, w
            rec['block'] = [w, h]
        if art:
            if 'models' in art:
                rec['model'] = asset(art['models'][var % len(art['models'])], None, 'model')
                rec['scale'] = round(art['scale'] * (sx or 1), 3)
                if art.get('pair'):
                    rec['pair'] = art['pair']
            else:
                rec['particle'] = asset(art['particle'], None, 'particle')
        if rec.get('model') or rec.get('particle') or rec.get('block'):
            out.append(rec)
    return out


def write_minimap(grid):
    """Minimap like the WC3 one: dirt paths, grass where towers can be built, dark blocked cells.
    Dota maps the minimap to the tile grid bounds (-8192..8192)."""
    size, world = 512, 8192.0
    colors = {'b': (58, 110, 46), 'w': (150, 118, 72), 'x': (28, 34, 26)}
    rows = []
    for rle in grid['rows']:
        row = []
        for ch, n in re.findall(r'([a-z])(\d+)', rle):
            row.extend(ch * int(n))
        rows.append(row)
    px = bytearray()
    for py in range(size):   # TGA written top-down
        wy = world - (py + 0.5) * (2 * world / size)
        cy = int((wy - grid['origin'][1]) // grid['cell'])
        for pxx in range(size):
            wx = -world + (pxx + 0.5) * (2 * world / size)
            cx = int((wx - grid['origin'][0]) // grid['cell'])
            if 0 <= cy < grid['height'] and 0 <= cx < grid['width']:
                r, g, b = colors[rows[cy][cx]]
            else:
                r, g, b = (0, 0, 0)
            px += bytes((b, g, r))
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, size, size, 24, 0x20)
    out = os.path.join(CONTENT, 'materials', 'overviews')
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, 'green_td.tga'), 'wb').write(header + bytes(px))
    write(os.path.join(out, 'green_td.vmat'),
          '"Layer0"\n{\n\t"Shader"\t"ui.vfx"\n\t"F_TRANSLUCENT"\t"0"\n\t"Texture"\t"materials/overviews/green_td.tga"\n}\n')
    write(os.path.join(out, 'green_td.txt'),
          '"settings"\n{\n\t"clampu" "1"\n\t"clampv" "1"\n\t"nocompress" "1"\n\t"nomip" "1"\n\n}\n')
    print('wrote minimap', os.path.relpath(os.path.join(out, 'green_td.tga'), ROOT))


# ----------------------------------------------------------------------------- KV output
def kv_block(name, d, ind=1):
    pad = '\t' * ind
    out = '%s"%s"\n%s{\n' % (pad, name, pad)
    for k, v in d.items():
        if isinstance(v, dict):
            out += kv_block(k, v, ind + 1)
        else:
            out += '%s\t"%s"\t"%s"\n' % (pad, k, v)
    return out + pad + '}\n'


WEARABLES = json.load(open(os.path.join(ROOT, 'tools', 'default_wearables.json'), encoding='utf-8'))
# hero-folder models that are not the hero's normal body: no default cosmetics on those
NO_WEARABLES = ('warlock_demon', 'terrorblade/demon', 'lone_druid/true_form', 'ancestral_spirit', 'undying_minion',
                'dragon_knight_dragon', 'spirit_bear', 'lycan_wolf')


# Every cosmetic item is one more entity to network and draw; with ~340 towers the full sets cost ~10 FPS.
# Towers only get the two most visible items (usually head and weapon), which hide most of the bare hero body,
# plus the mount of riders (Batrider's bat, Chaos Knight's horse).
# items_game leaves item_slot out for weapons ('' here)
WEARABLE_SLOTS = ('', 'weapon', 'head', 'offhand_weapon', 'body_head', 'back', 'shoulder', 'arms', 'armor', 'neck',
                  'belt', 'legs', 'tail')
WEARABLES_PER_TOWER = 2


def wearables_kv(model):
    """Creature block attaching the hero's two most visible default items, for units using a hero model."""
    if not model.startswith('models/heroes/') or any(x in model for x in NO_WEARABLES):
        return None
    entry = WEARABLES.get(model.rsplit('/', 1)[0] + '/')
    if not entry:
        return None
    rank = lambda pair: WEARABLE_SLOTS.index(pair[1]) if pair[1] in WEARABLE_SLOTS else len(WEARABLE_SLOTS)
    pairs = list(zip(entry['items'], entry['slots']))
    ids = [iid for iid, slot in pairs if slot == 'mount']
    ids += [iid for iid, _ in sorted((p for p in pairs if p[1] != 'mount'), key=rank)[:WEARABLES_PER_TOWER]]
    if not ids:
        return None
    return {'AttachWearables': {'Wearable%d' % (i + 1): {'ItemDef': iid} for i, iid in enumerate(ids)}}


MIN_ATTACK_INTERVAL = 0.25   # keep in sync with GTD.MIN_ATTACK_INTERVAL in gtd/init.lua


def tower_kv(t):
    at = t.get('attack')
    d = {
        'BaseClass': 'npc_dota_creature', 'Model': t['model'], 'ModelScale': t['scale'], 'Level': 1,
        'Ability1': 'gtd_tower_core',
        'ArmorPhysical': 0, 'MagicalResistance': 0,
        'MovementCapabilities': 'DOTA_UNIT_CAP_MOVE_NONE', 'MovementSpeed': 0, 'MovementTurnRate': 1.0,
        'StatusHealth': 1000, 'StatusHealthRegen': 0, 'StatusMana': 0,
        'BountyXP': 0, 'BountyGoldMin': 0, 'BountyGoldMax': 0,
        'BoundsHullName': 'DOTA_HULL_SIZE_SMALL', 'RingRadius': 16 * t['footprint'], 'HealthBarOffset': 220,
        'VisionDaytimeRange': 1200, 'VisionNighttimeRange': 1200,
        'TeamName': 'DOTA_TEAM_GOODGUYS', 'UnitRelationshipClass': 'DOTA_NPC_UNIT_RELATIONSHIP_TYPE_DEFAULT',
        'HasInventory': 0, 'IsSummoned': 0,
    }
    if at:
        dmin = at['base'] + at['dice']
        dmax = at['base'] + at['dice'] * at['sides']
        d.update({
            # Instant (melee type) attack with the WC3 range: the missile is launched from Lua
            # (GTD.Combat:LaunchAttack), so towers never use the engine's limited projectile attack records.
            'AttackCapabilities': 'DOTA_UNIT_CAP_MELEE_ATTACK',
            'AttackDamageMin': int(dmin), 'AttackDamageMax': int(dmax),
            'AttackRate': max(at['cooldown'], MIN_ATTACK_INTERVAL), 'AttackAnimationPoint': 0.0,
            'AttackAcquisitionRange': 0, 'AttackRange': int(at['range']),
        })
    else:
        d['AttackCapabilities'] = 'DOTA_UNIT_CAP_NO_ATTACK'
    creature = wearables_kv(t['model'])
    if creature:
        d['Creature'] = creature
    return d


def creep_kv(c):
    d = {
        'BaseClass': 'npc_dota_creature', 'Model': c['model'], 'ModelScale': round(c['scale'], 3), 'Level': 1,
        'Ability1': 'gtd_creep_core',
        'ArmorPhysical': 0, 'MagicalResistance': 0,
        'AttackCapabilities': 'DOTA_UNIT_CAP_NO_ATTACK',
        'MovementCapabilities': 'DOTA_UNIT_CAP_MOVE_FLY' if c['air'] else 'DOTA_UNIT_CAP_MOVE_GROUND',
        'MovementSpeed': int(c['speed']), 'MovementTurnRate': 1.0,
        'StatusHealth': c['hp'], 'StatusHealthRegen': c['regen'], 'StatusMana': 0,
        'BountyXP': 0, 'BountyGoldMin': 0, 'BountyGoldMax': 0,
        'BoundsHullName': 'DOTA_HULL_SIZE_SMALL', 'HealthBarOffset': 180,
        'VisionDaytimeRange': 400, 'VisionNighttimeRange': 400,
        'TeamName': 'DOTA_TEAM_BADGUYS', 'UnitRelationshipClass': 'DOTA_NPC_UNIT_RELATIONSHIP_TYPE_DEFAULT',
        'HasInventory': 0,
    }
    # No cosmetics on creeps: a late wave has hundreds of them and every cosmetic item is one more
    # entity to network and draw (wave 65 with creep cosmetics: ~11 FPS instead of ~40).
    return d


# ----------------------------------------------------------------------------- main
def main():
    roots, order = collect_towers()
    towers = {t: tower_rec(t) for t in order}
    assign_upgrade_keys(towers)
    for t, key in BUILD_KEYS.items():
        towers[t]['build_key'] = key
    creep_ids = []
    for n in sorted(int(k) for k in W['waves']):
        for ev in W['waves'][str(n)]['seq']:
            if ev[0] == 'spawn' and ev[2] not in creep_ids:
                creep_ids.append(ev[2])
    creeps = {c: creep_rec(c) for c in creep_ids}
    waves = wave_list()
    mp = map_data()
    write_minimap(mp['grid'])

    header = '-- GENERATED by tools/gen.py from the Green TD v36.0 map data. Do not edit by hand.\n'
    vs = os.path.join(GAME, 'scripts', 'vscripts', 'gtd', 'data')
    write(os.path.join(vs, 'towers.lua'), header + 'return ' + lua({'roots': roots, 'list': towers,
                                                                      'attack_table': ATTACK_TABLE,
                                                                      'defense_types': DEFENSE_TYPES}) + '\n')
    write(os.path.join(vs, 'creeps.lua'), header + 'return ' + lua(creeps) + '\n')
    write(os.path.join(vs, 'waves.lua'), header + 'return ' + lua(waves) + '\n')
    write(os.path.join(vs, 'map.lua'), header + 'return ' + lua(mp) + '\n')

    kv = '// GENERATED by tools/gen.py. Do not edit by hand.\n"DOTAUnits"\n{\n\t"Version"\t"1"\n'
    for t in towers.values():
        kv += kv_block(t['unit'], tower_kv(t))
    for c in creeps.values():
        kv += kv_block(c['unit'], creep_kv(c))
    kv += '}\n'
    write(os.path.join(GAME, 'scripts', 'npc', 'npc_units_custom.txt'), kv)

    tokens = {}
    for t in towers.values():
        tokens[t['unit']] = t['name']
    for c in creeps.values():
        tokens[c['unit']] = c['name']
    tokens.update({
        'addon_game_name': 'Green TD', 'DOTA_Tooltip_ability_gtd_build': 'Build',
        'DOTA_Tooltip_ability_gtd_build_Description': 'Build the tower selected in the build menu.',
        'npc_dota_hero_wisp': 'Shadow',
    })
    lang = '"lang"\n{\n\t"Language"\t"English"\n\t"Tokens"\n\t{\n'
    for k, v in tokens.items():
        lang += '\t\t"%s"\t"%s"\n' % (k, v.replace('"', "'"))
    lang += '\t}\n}\n'
    write(os.path.join(GAME, 'resource', 'addon_english.txt'), lang)

    js = '// GENERATED by tools/gen.py. Do not edit by hand.\n"use strict";\nGameUI.CustomUIConfig().gtd = ' + json.dumps({
        'roots': roots,
        'towers': {k: {kk: v[kk] for kk in v if kk not in ('model',)} for k, v in towers.items()},
        'creeps': {k: {'name': v['name'], 'unit': v['unit']} for k, v in creeps.items()},
        'unit_to_tower': {v['unit']: k for k, v in towers.items()},
    }, ensure_ascii=False, indent=1) + ';\n'
    write(os.path.join(CONTENT, 'panorama', 'scripts', 'custom_game', 'gtd_data.js'), js)

    print('%d towers (%d roots), %d creeps, %d waves' % (len(towers), len(roots), len(creeps), len(waves)))
    for w_ in WARNINGS:
        print('WARNING', w_)


if __name__ == '__main__':
    main()
