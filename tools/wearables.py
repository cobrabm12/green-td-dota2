"""Default cosmetic items of every hero, from Dota's scripts/items/items_game.txt.
Creature units that use a hero model only show the bare body unless these items are attached
(npc_units_custom: "Creature" { "AttachWearables" { "Wearable1" { "ItemDef" "<id>" } ... } }).

Usage: python -I tools/wearables.py <items_game.txt>   -> writes tools/default_wearables.json
       { "models/heroes/lina/": [ids...], ... }  keyed by the hero model folder."""
import json, os, re, sys

TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|([{}])|//[^\n]*')


def parse(text):
    stack = [{}]
    key = None
    for m in TOKEN.finditer(text):
        s, brace = m.group(1), m.group(2)
        if brace == '{':
            d = {}
            parent = stack[-1]
            if key in parent and isinstance(parent[key], dict):
                d = parent[key]          # duplicate block names merge
            else:
                parent[key] = d
            stack.append(d)
            key = None
        elif brace == '}':
            stack.pop()
            key = None
        elif s is not None:
            if key is None:
                key = s
            else:
                stack[-1][key] = s
                key = None
    return stack[0]


SKIP_SLOTS = {'taunt', 'voice', 'loading_screen', 'ambient_effects', 'summon', 'persona_selector', 'misc',
              'courier', 'ward', 'music', 'announcer', 'hud_skin', 'cursor_pack', 'emblem', 'action_item'}


def main():
    text = open(sys.argv[1], encoding='utf-8', errors='replace').read()
    root = parse(text)
    items = root.get('items_game', {}).get('items', {})
    by_hero = {}
    for item_id, it in items.items():
        if not isinstance(it, dict) or it.get('prefab') != 'default_item' or not it.get('model_player'):
            continue
        heroes = it.get('used_by_heroes')
        if not isinstance(heroes, dict) or len(heroes) != 1:
            continue
        slot = it.get('item_slot', '')
        if slot in SKIP_SLOTS or 'persona' in slot:
            continue
        hero = next(iter(heroes))
        by_hero.setdefault(hero, []).append((slot, int(item_id), it['model_player']))
    out = {}
    for hero, lst in by_hero.items():
        # the hero's own model folder (e.g. models/heroes/lina/) identifies it from a unit model path
        folders = {m.rsplit('/', 1)[0] + '/' for _, _, m in lst if m.startswith('models/heroes/')}
        seen_slots, ids, slots = set(), [], []
        for slot, iid, model in sorted(lst, key=lambda x: x[1]):
            if slot in seen_slots:
                continue
            seen_slots.add(slot)
            ids.append(iid)
            slots.append(slot)
        for folder in folders:
            out.setdefault(folder, {'hero': hero, 'items': ids, 'slots': slots})
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'default_wearables.json')
    json.dump(out, open(dst, 'w', encoding='utf-8'), indent=1, sort_keys=True)
    print('%d heroes, %d model folders -> %s' % (len(by_hero), len(out), dst))


if __name__ == '__main__':
    main()
