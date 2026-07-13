"""
Generator for the jeuno-scoped cascade manifest (dry-run output of
singleplayer/docs/cascade_manifest_extraction.md).

This is NOT an automated Lua parser: the reward data below was hand-extracted
from scripts/quests/jeuno/**.lua (commit 2e374ed) and item/keyItem IDs resolved
from scripts/enum/{item,key_item}.lua. It exists to emit clean, valid, diffable
JSON from that curated data and to sanity-check counts.

Run from repo root:  python3 singleplayer/docs/gen_cascade_manifest_jeuno.py
Output:              singleplayer/data/cascade_manifest.jeuno.json

When re-running after quest-script changes: re-verify the data tables against
source (esp. source_commit, IDs, and the helper families) before trusting output.
"""
import json, collections

SP = "scripts/quests/jeuno/"
LOG_ID, LOG_NAME = 3, "JEUNO"

def grants(setLevelCap=None, setNewMainJobMaxLevel=None, unlockJob=None,
           unlockWeaponskill=None, expandInventory=None, addGil=None):
    return {"setLevelCap": setLevelCap, "setNewMainJobMaxLevel": setNewMainJobMaxLevel,
            "unlockJob": unlockJob, "unlockWeaponskill": unlockWeaponskill,
            "expandInventory": expandInventory, "addGil": addGil}

def rewards(items=None, keyItems=None, fame=None, fameArea=None, gil=0, bayld=0,
            exp=0, title=None, var=None):
    r = {"items": items or [], "keyItems": keyItems or [], "fame": fame,
         "fameArea": fameArea, "gil": gil, "bayld": bayld, "title": title,
         "var": var or {}}
    if exp:
        r["exp"] = exp
    return r

def it(i, q=1):
    return {"id": i, "qty": q}

quests = {}

def add(qid, name, src, rw, g=None, helper=None, branching=None, notes=""):
    quests[f"{LOG_ID}:{qid}"] = {
        "log_id": LOG_ID, "log_name": LOG_NAME, "quest_id": qid, "quest_name": name,
        "source_path": SP + src, "helper_base": helper,
        "rewards": rw, "post_complete_grants": g or grants(),
        "branching": branching, "notes": notes,
    }

JE = "JEUNO"

# ---------------- Standalone quests ----------------
add(6, "A_CANDLELIGHT_VIGIL", "A_Candlelight_Vigil.lua",
    rewards(items=[it(13094)], fame=30, fameArea=JE, title="ACTIVIST_FOR_KINDNESS"))
add(72, "A_CHOCOBOS_TALE", "A_Chocobos_Tale.lua",
    rewards(fame=30, fameArea=JE, gil=5200, title="CHOCOBO_LOVE_GURU"))
add(2, "A_CLOCK_MOST_DELICATE", "A_Clock_Most_Delicate.lua",
    rewards(items=[it(12727)], fame=30, fameArea=JE, gil=1200, title="PROFESSIONAL_LOAFER"))
add(12, "A_MINSTREL_IN_DESPAIR", "A_Minstrel_In_Despair.lua",
    rewards(fame=30, fameArea=JE, gil=2100))
add(89, "APOCALYPSE_NIGH", "Apocalypse_Nigh.lua",
    rewards(items=[it(15962), it(15963), it(15964), it(15965)]),
    branching={"type": "choose_one_of_many",
               "options": ["STATIC_EARRING", "MAGNETIC_EARRING", "HOLLOW_EARRING", "ETHEREAL_EARRING"]},
    notes="quest.reward is empty {}; earring granted via npcUtil.giveItem(STATIC+option-1) in event handler — captured here by flattening all 4.")
add(59, "AXE_THE_COMPETITION", "Axe_the_Competition.lua",
    rewards(fame=30, fameArea=JE),
    g=grants(unlockWeaponskill="DECIMATION"),
    notes="Grants player:addLearnedWeaponskill(DECIMATION). Mid-quest KIs/items (PICK_OF_TRIALS, ANNALS_OF_TRUTH) are not rewards.")
add(22, "CANDLE_MAKING", "Candle_Making.lua",
    rewards(keyItems=[50], fame=30, fameArea=JE, title="BELIEVER_OF_ALTANA"))
add(23, "CHILDS_PLAY", "Childs_Play.lua",
    rewards(keyItems=[113], fame=30, fameArea=JE, title="TRADER_OF_MYSTERIES"))
add(92, "CHOCOBO_ON_THE_LOOSE", "Chocobo_on_the_Loose.lua",
    rewards(items=[it(2312)]),
    notes="In-script TODO: verify the egg item id.")
add(4, "CHOCOBOS_WOUNDS", "Chocobos_Wounds.lua",
    rewards(keyItems=[138], fame=30, fameArea=JE, title="CHOCOBO_TRAINER"))
add(15, "COMMUNITY_SERVICE", "Community_Service.lua",
    rewards(fame=30, fameArea=JE, title="TORCHBEARER"),
    notes="Optional post-complete KI LAMP_LIGHTERS_MEMBERSHIP_CARD (option-gated, outside quest.reward).")
add(0, "CREST_OF_DAVOI", "Crest_of_Davoi.lua",
    rewards(keyItems=[21], fame=30, fameArea=JE))
add(26, "DEAL_WITH_TENSHODO", "Deal_with_Tenshodo.lua",
    rewards(keyItems=[19], fame=30, fameArea=JE, title="TRADER_OF_RENOWN"))
add(96, "THE_UNFINISHED_WALTZ", "DNC_AF1_The_Unfinished_Waltz.lua",
    rewards(items=[it(19203)], title="PROMISING_DANCER"))
add(97, "THE_ROAD_TO_DIVADOM", "DNC_AF2_The_Road_to_Divadom.lua",
    rewards(items=[it(15659), it(15660)], title="STARDUST_DANCER"),
    branching={"type": "gender_variant", "options": ["DANCERS_TIGHTS_M", "DANCERS_TIGHTS_F"]},
    notes="Reward item is gender-specific (DANCERS_TIGHTS_M/F) via npcUtil.giveItem outside quest.reward — both flattened.")
add(98, "COMEBACK_QUEEN", "DNC_AF3_Comeback_Queen.lua",
    rewards(items=[it(14578), it(14579)], title="ELEGANT_DANCER"),
    branching={"type": "gender_variant", "options": ["DANCERS_CASAQUE_M", "DANCERS_CASAQUE_F"]},
    notes="Reward item is gender-specific (DANCERS_CASAQUE_M/F) outside quest.reward — both flattened.")
add(68, "DUCAL_HOSPITALITY", "Ducal_Hospitality.lua",
    rewards(fame=50, fameArea=JE, gil=4000, title="DUCAL_DUPE"),
    notes="Repeatable quest. Repeat path re-grants gil 4000 + fame 50 via giveCurrency/addFame (not addGil, repeat-only).")
add(70, "EMPTY_MEMORIES", "Empty_Memories.lua",
    rewards(fame=5, fameArea=JE,
            items=[it(5262), it(5261), it(5263), it(17208), it(13177), it(17466)]),
    branching={"type": "choose_one_of_many",
               "options": ["BOTTLE_OF_HYSTEROANIMA", "BOTTLE_OF_PSYCHOANIMA", "BOTTLE_OF_TERROANIMA",
                           "HAMAYUMI", "STONE_GORGET", "DIA_WAND"]},
    notes="quest.reward carries only fame=5; chosen item + extra 25 fame applied in handler. First three options cost 2000 gil (delGil).")
add(71, "HOOK_LINE_AND_SINKER", "Hook_Line_and_Sinker.lua",
    rewards(gil=3000, title="ROD_RETRIEVER"))
add(69, "IN_THE_MOOD_FOR_LOVE", "In_the_Mood_for_Love.lua",
    rewards(gil=4800, fame=30, fameArea=JE, title="PICK_UP_ARTIST"))
add(95, "LAKESIDE_MINUET", "Lakeside_Minuet.lua",
    rewards(fame=30, fameArea=JE, title="TROUPE_BRILIOTH_DANCER"),
    g=grants(unlockJob="DNC"),
    notes="Unlocks DNC in onEventFinish[10118] alongside quest:complete.")
# Limit-break ladder
add(128, "IN_DEFIANT_CHALLENGE", "LB01_In_Defiant_Challenge.lua",
    rewards(fame=30, fameArea=JE, title="HORIZON_BREAKER"), g=grants(setLevelCap=55))
add(129, "ATOP_THE_HIGHEST_MOUNTAINS", "LB02_Atop_the_Highest_Mountains.lua",
    rewards(fame=40, fameArea=JE, title="SUMMIT_BREAKER"), g=grants(setLevelCap=60))
add(130, "WHENCE_BLOWS_THE_WIND", "LB03_Whence_Blows_the_wind.lua",
    rewards(fame=50, fameArea=JE, title="SKY_BREAKER"), g=grants(setLevelCap=65))
add(131, "RIDING_ON_THE_CLOUDS", "LB04_Riding_on_the_clouds.lua",
    rewards(fame=60, fameArea=JE, title="CLOUD_BREAKER"), g=grants(setLevelCap=70))
add(132, "SHATTERING_STARS", "LB05_1_Shattering_Stars.lua",
    rewards(fame=80, fameArea=JE, title="STAR_BREAKER"), g=grants(setLevelCap=75),
    notes="addTitle MAAT_MASHER and SCROLL_OF_INSTANT_WARP are mid-quest battlefield grants, not completion rewards.")
add(76, "BEYOND_THE_SUN", "LB05_2_Beyond_the_Sun.lua",
    rewards(items=[it(15194)], title="ULTIMATE_CHAMPION_OF_THE_WORLD"))
add(133, "NEW_WORLDS_AWAIT", "LB06_New_Worlds_Await.lua",
    rewards(fame=50, fameArea=JE), g=grants(setLevelCap=80),
    notes="Grants KI LIMIT_BREAKER mid-quest (event option 4). Spends 3 merits.")
add(134, "EXPANDING_HORIZONS", "LB07_Expanding_Horizons.lua",
    rewards(fame=50, fameArea=JE), g=grants(setLevelCap=85), notes="Spends 4 merits.")
add(135, "BEYOND_THE_STARS", "LB08_Beyond_the_Stars.lua",
    rewards(fame=50, fameArea=JE), g=grants(setLevelCap=90), notes="Spends 5 merits.")
add(136, "DORMANT_POWERS_DISLODGED", "LB09_1_Dormant_Powers_Dislodged.lua",
    rewards(fame=50, fameArea=JE, keyItems=[2052]), g=grants(setLevelCap=95), notes="Spends 10 merits.")
add(170, "PRELUDE_TO_PUISSANCE", "LB09_2_Prelude_to_Puissance.lua",
    rewards(fame=50, fameArea=JE, keyItems=[2053]),
    notes="No setLevelCap here — level cap to 99 is handled by Beyond Infinity (qid 137). Auto-adds BEYOND_INFINITY on completion.")
add(137, "BEYOND_INFINITY", "LB10_Beyond_Infinity.lua",
    rewards(fame=50, fameArea=JE, title="BUSHIN_ASPIRANT"), g=grants(setLevelCap=99),
    notes="SCROLL_OF_INSTANT_WARP and KIs (SOUL_GEM_CLASP, JOB_BREAKER) are mid-quest grants, not completion rewards.")
add(90, "LURE_OF_THE_WILDCAT", "Lure_of_the_Wildcat_Jeuno.lua",
    rewards(fame=150, fameArea=JE, keyItems=[756]))
add(167, "MARTIAL_MASTERY", "Martial_Mastery.lua",
    rewards(keyItems=[2059], title="BUSHIN_RYU_INHERITOR"), notes="Spends 15 merits.")
add(32, "MYSTERIES_OF_BEADEAUX_II", "Mysteries_of_Beadeaux_II.lua",
    rewards(fame=30, fameArea=JE, keyItems=[47]))
add(31, "MYSTERIES_OF_BEADEAUX_I", "Mysteries_of_Beadeaux_I.lua",
    rewards(fame=30, fameArea=JE, keyItems=[46]), notes="On begin also addQuest MYSTERIES_OF_BEADEAUX_II.")
add(24, "NORTHWARD", "Northward.lua",
    rewards(exp=2000, fame=30, fameArea=JE, gil=2000, keyItems=[412], title="ENVOY_TO_THE_NORTH"))
add(63, "PAINFUL_MEMORY", "Painful_Memory.lua",
    rewards(items=[it(16766)]))
add(20, "PATH_OF_THE_BARD", "Path_of_the_Bard.lua",
    rewards(fame=30, fameArea=JE, gil=3000, keyItems=[1747], title="WANDERING_MINSTREL"),
    g=grants(unlockJob="BRD"))
add(19, "PATH_OF_THE_BEASTMASTER", "Path_of_the_Beastmaster.lua",
    rewards(fame=30, fameArea=JE, keyItems=[1746], title="ANIMAL_TRAINER"),
    g=grants(unlockJob="BST"))
add(43, "PRETTY_LITTLE_THINGS", "Pretty_Little_Things.lua",
    rewards(fame=30, fameArea=JE),
    notes="On complete sets Mog House exit flag (setMoghouseFlag 0x0008) — out of cascade scope.")
add(1, "SAVE_MY_SISTER", "Save_My_Sister.lua",
    rewards(items=[it(17041)], gil=3000, title="EXORCIST_IN_TRAINING"))
add(5, "SAVE_MY_SON", "Save_My_Son.lua",
    rewards(items=[it(13110)], fame=30, fameArea=JE, gil=2100, title="LIFE_SAVER"))
add(3, "SAVE_THE_CLOCK_TOWER", "Save_the_Clock_Tower.lua",
    rewards(fame=30, fameArea=JE, title="CLOCK_TOWER_PRESERVATIONIST"))
add(61, "SCATTERED_INTO_SHADOW", "Scattered_into_Shadow.lua",
    rewards(items=[it(14097)], fame=30, fameArea=JE))
add(88, "SHADOWS_OF_THE_DEPARTED", "Shadows_of_the_Departed.lua",
    rewards(),
    notes="quest.reward = {} (completion-only). Mid-quest KIs only. Sets var/mustZone for APOCALYPSE_NIGH follow-up.")
add(86, "STORMS_OF_FATE", "Storms_of_Fate.lua",
    rewards(),
    notes="quest.reward = {} (completion-only). Mid-quest KI WHISPER_OF_THE_WYRMKING only.")
add(17, "TENSHODO_MEMBERSHIP", "Tenshodo_Membership.lua",
    rewards(items=[it(548)], keyItems=[118]))
add(25, "THE_ANTIQUE_COLLECTOR", "The_Antique_Collector.lua",
    rewards(exp=2000, fame=30, fameArea=JE, gil=2000, keyItems=[410], title="TRADER_OF_ANTIQUITIES"),
    notes="In-code TODO questions whether XP/gil are granted without the KI.")
add(21, "THE_CLOCKMASTER", "The_Clockmaster.lua",
    rewards(items=[it(17083)], fame=30, fameArea=JE, title="TIMEKEEPER"))
add(42, "THE_GOBLIN_TAILOR", "The_Goblin_Tailor.lua",
    rewards(fame=30, fameArea=JE, title="GOBLINS_EXCLUSIVE_FASHION_MANNEQUIN",
            items=[it(12654), it(12761), it(12871), it(13015),   # HUME_M
                   it(12655), it(12762), it(12872), it(13016),   # HUME_F
                   it(12656), it(12763), it(12873), it(13017),   # ELVAAN_M
                   it(12657), it(12764), it(12874), it(13018),   # ELVAAN_F
                   it(12658), it(12765), it(12875), it(13019),   # TARU
                   it(12659), it(12766), it(12876), it(13020),   # MITHRA
                   it(12660), it(12767), it(12877), it(13021)]), # GALKA
    branching={"type": "race_and_choice_variant",
               "options": ["RSE: 7 races x 4 pieces (body/hands/legs/feet) — player picks one for their race"]},
    notes="Reward is a single race/gender-appropriate RSE piece granted via npcUtil.giveItem at completion, NOT in quest.reward. All 28 flattened (over-grants across races, acceptable in singleplayer).")
add(11, "THE_OLD_MONUMENT", "The_Old_Monument.lua",
    rewards(items=[it(634)], title="RESEARCHER_OF_CLASSICS"))
add(91, "THE_ROAD_TO_AHT_URHGAN", "The_Road_to_Aht_Urhgan.lua",
    rewards(fame=30, fameArea=JE),
    notes="Gated by ENABLE_TOAU. Grants KIs BOARDING_PERMIT / MAP_OF_WAJAOM_WOODLANDS mid-quest; has a delGil(500000) sink (not a reward).")
add(77, "UNLISTED_QUALITIES", "Unlisted_Qualities.lua",
    rewards(),
    notes="No quest.reward table. Completion is currently DISABLED (the quest:complete + giveItem SILVER_INGOT block is commented out pending core Fellow-save support). Intended reward: SILVER_INGOT.")
add(60, "WINGS_OF_GOLD", "Wings_of_Gold.lua",
    rewards(items=[it(16680)], fame=20, fameArea=JE))
add(9, "YOUR_CRYSTAL_BALL", "Your_Crystal_Ball.lua",
    rewards(fame=30, fameArea=JE, title="FORTUNE_TELLER_IN_TRAINING"))

# ---------------- Gobbiebag helper (GobbiebagQuest) ----------------
GOBBIE = "xi.jeuno.helpers.GobbiebagQuest"
gobbie = [
    (27, "THE_GOBBIEBAG_PART_I", "The_Gobbiebag_Part_I.lua", None),
    (28, "THE_GOBBIEBAG_PART_II", "The_Gobbiebag_Part_II.lua", None),
    (29, "THE_GOBBIEBAG_PART_III", "The_Gobbiebag_Part_III.lua", None),
    (30, "THE_GOBBIEBAG_PART_IV", "The_Gobbiebag_Part_IV.lua", None),
    (74, "THE_GOBBIEBAG_PART_V", "The_Gobbiebag_Part_V.lua", "GREEDALOX"),
    (75, "THE_GOBBIEBAG_PART_VI", "The_Gobbiebag_Part_VI.lua", None),
    (93, "THE_GOBBIEBAG_PART_VII", "The_Gobbiebag_Part_VII.lua", None),
    (94, "THE_GOBBIEBAG_PART_VIII", "The_Gobbiebag_Part_VIII.lua", None),
    (123, "THE_GOBBIEBAG_PART_IX", "The_Gobbiebag_Part_IX.lua", None),
    (124, "THE_GOBBIEBAG_PART_X", "The_Gobbiebag_Part_X.lua", "GRAND_GREEDALOX"),
]
for qid, name, src, title in gobbie:
    add(qid, name, src, rewards(fame=30, fameArea=JE, title=title),
        g=grants(expandInventory=5), helper=GOBBIE,
        notes="GobbiebagQuest helper. Reward = fame/title only; bag expansion is player:changeContainerSize(INVENTORY,+5) (and MOGSATCHEL) in quest:complete — recorded as expandInventory.")

# ---------------- Borghertz helper (BorghertzQuests) ----------------
BORG = "xi.jeuno.helpers.BorghertzQuests"
borg = [
    (44, "BORGHERTZS_WARRING_HANDS", "Borghertzs_Warring_Hands.lua", 13961),
    (45, "BORGHERTZS_STRIKING_HANDS", "Borghertzs_Striking_Hands.lua", 13962),
    (46, "BORGHERTZS_HEALING_HANDS", "Borghertzs_Healing_Hands.lua", 13963),
    (47, "BORGHERTZS_SORCEROUS_HANDS", "Borghertzs_Sorcerous_Hands.lua", 13964),
    (48, "BORGHERTZS_VERMILLION_HANDS", "Borghertzs_Vermillion_Hands.lua", 13965),
    (49, "BORGHERTZS_SNEAKY_HANDS", "Borghertzs_Sneaky_Hands.lua", 13966),
    (50, "BORGHERTZS_STALWART_HANDS", "Borghertzs_Stalwart_Hands.lua", 13967),
    (51, "BORGHERTZS_SHADOWY_HANDS", "Borghertzs_Shadowy_Hands.lua", 13968),
    (52, "BORGHERTZS_WILD_HANDS", "Borghertzs_Wild_Hands.lua", 13969),
    (53, "BORGHERTZS_HARMONIOUS_HANDS", "Borghertzs_Harmonious_Hands.lua", 13970),
    (54, "BORGHERTZS_CHASING_HANDS", "Borghertzs_Chasing_Hands.lua", 13971),
    (55, "BORGHERTZS_LOYAL_HANDS", "Borghertzs_Loyal_Hands.lua", 13972),
    (56, "BORGHERTZS_LURKING_HANDS", "Borghertzs_Lurking_Hands.lua", 13973),
    (57, "BORGHERTZS_DRAGON_HANDS", "Borghertzs_Dragon_Hands.lua", 13974),
    (58, "BORGHERTZS_CALLING_HANDS", "Borghertzs_Calling_Hands.lua", 13975),
]
for qid, name, src, af in borg:
    add(qid, name, src, rewards(items=[it(af)]), helper=BORG,
        notes="BorghertzQuests helper. quest.reward.item = handAFId (AF gloves). The 2 optional AF pieces per job come from Treasure Coffers (xi.treasure.onTrade), not quest.reward — not captured.")

# ---------------- Unlocking a Myth helper (UnlockingAMyth) ----------------
MYTH = "xi.jeuno.helpers.UnlockingAMyth"
myth = [  # file-suffix, qid, ws unlock
    ("WAR", 102, "KINGS_JUSTICE"), ("MNK", 103, "ASCETICS_FURY"), ("WHM", 104, "MYSTIC_BOON"),
    ("BLM", 105, "VIDOHUNIR"), ("RDM", 106, "DEATH_BLOSSOM"), ("THF", 107, "MANDALIC_STAB"),
    ("PLD", 108, "ATONEMENT"), ("DRK", 109, "INSURGENCY"), ("BST", 110, "PRIMAL_REND"),
    ("BRD", 111, "MORDANT_RIME"), ("RNG", 112, "TRUEFLIGHT"), ("SAM", 113, "TACHI_RANA"),
    ("NIN", 114, "BLADE_KAMU"), ("DRG", 115, "DRAKESBANE"), ("SMN", 116, "GARLAND_OF_BLISS"),
    ("BLU", 117, "EXPIACION"), ("COR", 118, "LEADEN_SALUTE"), ("PUP", 119, "STRINGING_PUMMEL"),
    ("DNC", 120, "PYRRHIC_KLEOS"), ("SCH", 121, "OMNISCIENCE"),
]
mythname = {
    "WAR": "UNLOCKING_A_MYTH_WARRIOR", "MNK": "UNLOCKING_A_MYTH_MONK", "WHM": "UNLOCKING_A_MYTH_WHITE_MAGE",
    "BLM": "UNLOCKING_A_MYTH_BLACK_MAGE", "RDM": "UNLOCKING_A_MYTH_RED_MAGE", "THF": "UNLOCKING_A_MYTH_THIEF",
    "PLD": "UNLOCKING_A_MYTH_PALADIN", "DRK": "UNLOCKING_A_MYTH_DARK_KNIGHT", "BST": "UNLOCKING_A_MYTH_BEASTMASTER",
    "BRD": "UNLOCKING_A_MYTH_BARD", "RNG": "UNLOCKING_A_MYTH_RANGER", "SAM": "UNLOCKING_A_MYTH_SAMURAI",
    "NIN": "UNLOCKING_A_MYTH_NINJA", "DRG": "UNLOCKING_A_MYTH_DRAGOON", "SMN": "UNLOCKING_A_MYTH_SUMMONER",
    "BLU": "UNLOCKING_A_MYTH_BLUE_MAGE", "COR": "UNLOCKING_A_MYTH_CORSAIR", "PUP": "UNLOCKING_A_MYTH_PUPPETMASTER",
    "DNC": "UNLOCKING_A_MYTH_DANCER", "SCH": "UNLOCKING_A_MYTH_SCHOLAR",
}
for suffix, qid, ws in myth:
    add(qid, mythname[suffix], f"Unlocking_A_Myth_{suffix}.lua",
        rewards(), g=grants(unlockWeaponskill=ws), helper=MYTH,
        notes="UnlockingAMyth helper. NO quest.reward; player keeps traded vigil weapon (net zero) and gets player:addLearnedWeaponskill — recorded as unlockWeaponskill. Not a keyItem.")

manifest = {
    "schema_version": 1,
    "generated_at": "2026-06-10T00:00:00Z",
    "source_commit": "2e374ed5710cd89820c6a88ea1ecffd56235070f",
    "scope": "scripts/quests/jeuno/ (dry-run, single-directory)",
    "quests": dict(sorted(quests.items(), key=lambda kv: kv[1]["quest_id"])),
    "missions": {},
    "unparseable": [],
}

with open("singleplayer/data/cascade_manifest.jeuno.json", "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")

# sanity
ids = [v["quest_id"] for v in quests.values()]
dups = [i for i, c in collections.Counter(ids).items() if c > 1]
print(f"entries: {len(quests)}")
print(f"duplicate quest_ids: {dups}")
print(f"helper Unlocking: {sum(1 for v in quests.values() if v['helper_base']==MYTH)}")
print(f"helper Borghertz: {sum(1 for v in quests.values() if v['helper_base']==BORG)}")
print(f"helper Gobbiebag: {sum(1 for v in quests.values() if v['helper_base']==GOBBIE)}")
print(f"branching: {sum(1 for v in quests.values() if v['branching'])}")
print(f"setLevelCap: {sum(1 for v in quests.values() if v['post_complete_grants']['setLevelCap'])}")
print(f"unlockJob: {sum(1 for v in quests.values() if v['post_complete_grants']['unlockJob'])}")
print(f"unlockWeaponskill: {sum(1 for v in quests.values() if v['post_complete_grants']['unlockWeaponskill'])}")
print(f"expandInventory: {sum(1 for v in quests.values() if v['post_complete_grants']['expandInventory'])}")
