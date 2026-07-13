-----------------------------------
-- Bar-spell mappings — which bar* spell to use against a given mob.
--
-- Lookup priority (used by bot_magic.get_bar_*_spell):
--   1. bySpecies[species_id] — exact enemy type; used for single-element foes
--      (elementals + elemental avatars) that share a family but differ by
--      element, so family/ecosystem can't tell them apart.
--   2. byFamily[family_id]  — fine-grained, set per-encounter by player
--   3. byEcosystem[eco_id]  — sensible defaults based on typical FFXI patterns
--
-- All tables use { element = xi.magic.spell.BARX, status = xi.magic.spell.BARY }
-- structure. nil values mean "no recommendation" — bot_magic skips bar casting.
--
-- These defaults are NOT authoritative — different mobs in the same ecosystem
-- use different elements and statuses. They're a starting point; override via
-- byFamily for specific encounters that matter.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_bar_spells')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.ai_bar_spells = xi.singleplayer.bots.ai_bar_spells or {}
local ai_bar_spells = xi.singleplayer.bots.ai_bar_spells

-----------------------------------
-- Species-level overrides (exact enemy type — highest priority).
-- Single-element foes whose family/ecosystem can't distinguish them: the
-- elementals (family 103) and the elemental avatars (family 102) all share
-- ecosystem ELEMENTAL, so byEcosystem is nil for them and byFamily would need
-- one entry per element. Keying on mob:getSpecies() pins the right bar. The
-- Prime-avatar battlefield mobs reuse the base avatar species (e.g. Shiva_Prime
-- is species 253 Shiva), so one entry covers wild + Prime. Light/Dark elementals
-- and non-elemental avatars (Carbuncle, Diabolos, ...) have no matching bar and
-- are intentionally absent. Species IDs from sql/mob_species_system.sql.
-----------------------------------
ai_bar_spells.bySpecies = ai_bar_spells.bySpecies or {
    -- Elemental avatars (family 102)
    [247] = { element = xi.magic.spell.BARAERA    }, -- Garuda    (wind)
    [248] = { element = xi.magic.spell.BARFIRA    }, -- Ifrit     (fire)
    [249] = { element = xi.magic.spell.BARWATERA  }, -- Leviathan (water)
    [252] = { element = xi.magic.spell.BARTHUNDRA }, -- Ramuh     (thunder)
    [253] = { element = xi.magic.spell.BARBLIZZARA }, -- Shiva    (ice)
    [255] = { element = xi.magic.spell.BARSTONRA  }, -- Titan     (earth)
    -- Elementals (family 103)
    [256] = { element = xi.magic.spell.BARAERA    }, -- Air Elemental     (wind)
    [260] = { element = xi.magic.spell.BARSTONRA  }, -- Earth Elemental   (earth)
    [261] = { element = xi.magic.spell.BARFIRA    }, -- Fire Elemental    (fire)
    [263] = { element = xi.magic.spell.BARBLIZZARA }, -- Ice Elemental    (ice)
    [265] = { element = xi.magic.spell.BARTHUNDRA }, -- Thunder Elemental (thunder)
    [267] = { element = xi.magic.spell.BARWATERA  }, -- Water Elemental   (water)
}

-----------------------------------
-- Family-level overrides (player-populated, fine-grained).
-- Format: ai_bar_spells.byFamily[<family_id>] = { element = ..., status = ... }
-- Family IDs are from sql/mob_family_system.sql; mob:getFamily() returns them.
-----------------------------------
ai_bar_spells.byFamily = ai_bar_spells.byFamily or {
    -- 180 entries derived from the canonical bar-spell recommendation
    -- table. Spell IDs use the -ra tier (party-wide AoE). Unmapped
    -- families fall through to byEcosystem below.
    [  2] = { element = xi.magic.spell.BARSTONRA }, -- adamantoise
    [  3] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPETRA }, -- aern
    [  4] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARPETRA }, -- ahriman
    [  6] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARSILENCERA }, -- amphiptere
    [ 25] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARSILENCERA }, -- antica
    [ 26] = { status = xi.magic.spell.BARBLINDRA }, -- antlion
    [ 27] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARSLEEPRA }, -- apkallu
    [ 39] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARSILENCERA }, -- monoceros
    [ 47] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARPETRA }, -- battrio
    [ 48] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARPOISONRA }, -- bee
    [ 51] = { element = xi.magic.spell.BARTHUNDRA }, -- behemoth
    [ 52] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARBLINDRA }, -- ghost
    [ 56] = { element = xi.magic.spell.BARFIRA }, -- bomb
    [ 58] = { element = xi.magic.spell.BARTHUNDRA }, -- bugard
    [ 62] = { element = xi.magic.spell.BARFIRA, status = xi.magic.spell.BARPARALYZRA }, -- cerberus
    [ 63] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- chariot
    [ 65] = { element = xi.magic.spell.BARWATERA }, -- clionid
    [ 68] = { element = xi.magic.spell.BARFIRA }, -- bomb
    [ 70] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARPETRA }, -- cockatrice
    [ 71] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARPETRA }, -- coeurl
    [ 73] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- corpselight
    [ 77] = { element = xi.magic.spell.BARWATERA }, -- crab
    [ 78] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- craver
    [ 79] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARPOISONRA }, -- crawler
    [ 80] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARSILENCERA }, -- dhalmel
    [ 81] = { element = xi.magic.spell.BARSTONRA }, -- diremite
    [ 82] = { element = xi.magic.spell.BARFIRA }, -- bomb
    [ 92] = { element = xi.magic.spell.BARFIRA }, -- goblin
    [ 97] = { element = xi.magic.spell.BARFIRA, status = xi.magic.spell.BARPETRA }, -- lizard
    [ 98] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPOISONRA }, -- eft
    [109] = { status = xi.magic.spell.BARSLEEPRA }, -- euvhi
    [111] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARPOISONRA }, -- frog
    [112] = { element = xi.magic.spell.BARTHUNDRA }, -- flan
    [113] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARPOISONRA }, -- fly
    [114] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARPOISONRA }, -- flytrap
    [115] = { element = xi.magic.spell.BARTHUNDRA }, -- fomor
    [116] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- funguar
    [118] = { element = xi.magic.spell.BARSTONRA }, -- gargouille
    [121] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARBLINDRA }, -- ghost
    [122] = { element = xi.magic.spell.BARTHUNDRA }, -- ghrah
    [125] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARBLINDRA }, -- greater_bird
    [132] = { element = xi.magic.spell.BARTHUNDRA }, -- gnole
    [133] = { element = xi.magic.spell.BARFIRA }, -- goblin
    [136] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- goobbue
    [137] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- gorger
    [138] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- gorger
    [139] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARPETRA }, -- hecteyes
    [140] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARPARALYZRA }, -- hippogryph
    [142] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- hound
    [143] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- hound
    [144] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- hpemde
    [163] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- hydra
    [164] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- hydra
    [165] = { element = xi.magic.spell.BARFIRA, status = xi.magic.spell.BARAMNESRA }, -- imp
    [166] = { element = xi.magic.spell.BARFIRA, status = xi.magic.spell.BARAMNESRA }, -- imp
    [168] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPETRA }, -- khimaira
    [170] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARAMNESRA }, -- ladybug
    [171] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARAMNESRA }, -- lamiae
    [172] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARBLINDRA }, -- leech
    [173] = { element = xi.magic.spell.BARFIRA }, -- limule
    [174] = { element = xi.magic.spell.BARFIRA, status = xi.magic.spell.BARPETRA }, -- lizard
    [175] = { element = xi.magic.spell.BARAERA }, -- magic_pot
    [178] = { status = xi.magic.spell.BARSLEEPRA }, -- mandragora
    [179] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARBLINDRA }, -- manticore
    [183] = { element = xi.magic.spell.BARTHUNDRA }, -- mimic
    [186] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARSLEEPRA }, -- morbol
    [188] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- opo_opo
    [191] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARSLEEPRA }, -- orobon
    [192] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARPOISONRA }, -- peiste
    [194] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARSILENCERA }, -- phuabo
    [196] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARSILENCERA }, -- poroggo
    [197] = { element = xi.magic.spell.BARWATERA }, -- pugil
    [198] = { element = xi.magic.spell.BARAERA }, -- puk
    [199] = { status = xi.magic.spell.BARBLINDRA }, -- qiqirn
    [203] = { element = xi.magic.spell.BARTHUNDRA }, -- qutrub
    [206] = { status = xi.magic.spell.BARBLINDRA }, -- rabbit
    [207] = { status = xi.magic.spell.BARSLEEPRA }, -- rafflesia
    [208] = { status = xi.magic.spell.BARSLEEPRA }, -- ram
    [210] = { element = xi.magic.spell.BARTHUNDRA }, -- raptor
    [211] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- ruszor
    [213] = { element = xi.magic.spell.BARWATERA }, -- sahagin
    [214] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARBLINDRA }, -- sandworm
    [215] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARBLINDRA }, -- sandworm
    [216] = { status = xi.magic.spell.BARSLEEPRA }, -- sapling
    [217] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- scorpion
    [218] = { status = xi.magic.spell.BARBLINDRA }, -- sea_monk
    [219] = { status = xi.magic.spell.BARBLINDRA }, -- sea_monk
    [220] = { element = xi.magic.spell.BARTHUNDRA }, -- seether
    [226] = { status = xi.magic.spell.BARSLEEPRA }, -- sheep
    [227] = { status = xi.magic.spell.BARBLINDRA }, -- skeleton
    [231] = { element = xi.magic.spell.BARWATERA }, -- slug
    [232] = { element = xi.magic.spell.BARBLIZZARA }, -- snoll
    [232] = { element = xi.magic.spell.BARFIRA }, -- bomb
    [233] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- soulflayer
    [234] = { element = xi.magic.spell.BARTHUNDRA }, -- spheroid
    [235] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARPOISONRA }, -- spider
    [240] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARPOISONRA }, -- taurus
    [242] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- tiger
    [246] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPETRA }, -- troll
    [251] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARPARALYZRA }, -- uragnite
    [253] = { element = xi.magic.spell.BARFIRA }, -- wamoura
    [254] = { element = xi.magic.spell.BARFIRA, status = xi.magic.spell.BARBLINDRA }, -- wamouracampa
    [257] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- wivre
    [258] = { element = xi.magic.spell.BARSTONRA }, -- worm
    [269] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARBLINDRA }, -- xzomit
    [271] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPOISONRA }, -- yovra
    [272] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPETRA }, -- zdei
    [273] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- scorpion
    [274] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- scorpion
    [276] = { element = xi.magic.spell.BARSTONRA }, -- worm
    [277] = { element = xi.magic.spell.BARSTONRA }, -- adamantoise
    [279] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- tiger
    [280] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARBLINDRA }, -- greater_bird
    [281] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARBLINDRA }, -- manticore
    [286] = { element = xi.magic.spell.BARAERA }, -- puk
    [288] = { status = xi.magic.spell.BARBLINDRA }, -- qiqirn
    [289] = { element = xi.magic.spell.BARFIRA, status = xi.magic.spell.BARBLINDRA }, -- wamouracampa
    [294] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARSLEEPRA }, -- apkallu
    [296] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARSLEEPRA }, -- morbol
    [297] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARSILENCERA }, -- poroggo
    [299] = { element = xi.magic.spell.BARTHUNDRA }, -- botulus
    [300] = { element = xi.magic.spell.BARFIRA }, -- bomb
    [301] = { element = xi.magic.spell.BARFIRA, status = xi.magic.spell.BARAMNESRA }, -- imp
    [306] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- wivre
    [307] = { element = xi.magic.spell.BARFIRA }, -- wamoura
    [308] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPETRA }, -- troll
    [309] = { element = xi.magic.spell.BARTHUNDRA }, -- vampyr
    [311] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- soulflayer
    [312] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARSLEEPRA }, -- orobon
    [313] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- hydra
    [314] = { element = xi.magic.spell.BARFIRA, status = xi.magic.spell.BARPARALYZRA }, -- cerberus
    [315] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPETRA }, -- khimaira
    [326] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPETRA }, -- troll
    [327] = { element = xi.magic.spell.BARFIRA }, -- goblin
    [330] = { element = xi.magic.spell.BARSTONRA }, -- adamantoise
    [332] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- tiger
    [333] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARBLINDRA }, -- greater_bird
    [338] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARPARALYZRA }, -- twitherym
    [340] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARAMNESRA }, -- mantid
    [342] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARPARALYZRA }, -- velkk
    [342] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARAMNESRA }, -- king_velkk
    [344] = { element = xi.magic.spell.BARWATERA }, -- craklaw
    [345] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARSILENCERA }, -- acuex
    [347] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARPARALYZRA }, -- marolith
    [348] = { element = xi.magic.spell.BARWATERA }, -- matamata
    [350] = { element = xi.magic.spell.BARFIRA, status = xi.magic.spell.BARAMNESRA }, -- iron_giant
    [357] = { status = xi.magic.spell.BARBLINDRA }, -- antlion
    [359] = { element = xi.magic.spell.BARTHUNDRA }, -- fomor
    [360] = { element = xi.magic.spell.BARTHUNDRA }, -- fomor
    [369] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARBLINDRA }, -- leech
    [373] = { element = xi.magic.spell.BARFIRA }, -- goblin
    [390] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARAMNESRA }, -- ladybug
    [398] = { status = xi.magic.spell.BARSLEEPRA }, -- sheep
    [402] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- scorpion
    [404] = { status = xi.magic.spell.BARBLINDRA }, -- rabbit
    [410] = { element = xi.magic.spell.BARFIRA }, -- goblin
    [435] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- giant_gnat
    [437] = { status = xi.magic.spell.BARSLEEPRA }, -- sapling
    [447] = { element = xi.magic.spell.BARTHUNDRA }, -- dullahan
    [451] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- pteraketos
    [452] = { element = xi.magic.spell.BARWATERA }, -- rockfin
    [453] = { status = xi.magic.spell.BARSLEEPRA }, -- belladonna
    [455] = { element = xi.magic.spell.BARTHUNDRA }, -- leafkin
    [456] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARPARALYZRA }, -- bztavian
    [457] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- cehuetzi
    [459] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARPETRA }, -- yztarg
    [460] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- waktza
    [461] = { element = xi.magic.spell.BARFIRA }, -- gabbrath
    [463] = { element = xi.magic.spell.BARSTONRA, status = xi.magic.spell.BARSLEEPRA }, -- panopt
    [464] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- snapweed
    [465] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPARALYZRA }, -- yggdreant
    [467] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARAMNESRA }, -- gallu
    [468] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- umbril
    [469] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARAMNESRA }, -- lamiae
    [470] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARPOISONRA }, -- zilant
    [471] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARSLEEPRA }, -- harpeia
    [472] = { element = xi.magic.spell.BARBLIZZARA, status = xi.magic.spell.BARPARALYZRA }, -- naraka
    [490] = { element = xi.magic.spell.BARWATERA, status = xi.magic.spell.BARPOISONRA }, -- plovid
    [493] = { element = xi.magic.spell.BARTHUNDRA, status = xi.magic.spell.BARAMNESRA }, -- macuil
    [506] = { element = xi.magic.spell.BARAERA, status = xi.magic.spell.BARSILENCERA }, -- meeble
}

-----------------------------------
-- Ecosystem-level defaults (broad, fallback when family unknown).
-- Based on typical elemental affinities + common status inflictions of each
-- creature type in FFXI. Use these as starting points; refine per-family.
-----------------------------------
ai_bar_spells.byEcosystem = ai_bar_spells.byEcosystem or {
    [xi.ecosystem.AMORPH]   = { element = xi.magic.spell.BARWATERA,    status = xi.magic.spell.BARPOISONRA   },
    [xi.ecosystem.AQUAN]    = { element = xi.magic.spell.BARWATERA,    status = xi.magic.spell.BARSILENCERA  },
    [xi.ecosystem.ARCANA]   = { element = xi.magic.spell.BARSTONRA,    status = xi.magic.spell.BARPETRA  },
    [xi.ecosystem.BEAST]    = { element = nil,                         status = xi.magic.spell.BARBLINDRA    },
    [xi.ecosystem.BEASTMEN] = { element = nil,                         status = xi.magic.spell.BARPARALYZRA },
    [xi.ecosystem.BIRD]     = { element = xi.magic.spell.BARAERA,     status = xi.magic.spell.BARSILENCERA  },
    [xi.ecosystem.DEMON]    = { element = xi.magic.spell.BARFIRA,     status = xi.magic.spell.BARSLEEPRA    },
    [xi.ecosystem.DRAGON]   = { element = xi.magic.spell.BARFIRA,     status = xi.magic.spell.BARPARALYZRA },
    [xi.ecosystem.ELEMENTAL] = { element = nil,                        status = nil                        },
    [xi.ecosystem.LIZARD]   = { element = xi.magic.spell.BARSTONRA,    status = xi.magic.spell.BARPARALYZRA },
    [xi.ecosystem.LUMINIAN] = { element = nil,                         status = xi.magic.spell.BARAMNESRA  },
    [xi.ecosystem.LUMINION] = { element = nil,                         status = xi.magic.spell.BARAMNESRA  },
    [xi.ecosystem.PLANTOID] = { element = xi.magic.spell.BARFIRA,     status = xi.magic.spell.BARSLEEPRA    },
    [xi.ecosystem.UNDEAD]   = { element = nil,                         status = xi.magic.spell.BARPARALYZRA },
    [xi.ecosystem.VERMIN]   = { element = nil,                         status = xi.magic.spell.BARPOISONRA   },
    [xi.ecosystem.VORAGEAN] = { element = xi.magic.spell.BARFIRA,     status = xi.magic.spell.BARSLEEPRA    },
}

-----------------------------------
-- Lookup helpers (used by bot_magic.get_bar_*_spell)
-----------------------------------
local function lookup(mob)
    if mob == nil then return nil end
    local speciesId = (mob.getSpecies and mob:getSpecies()) or 0
    local entry = ai_bar_spells.bySpecies[speciesId]
    if entry then return entry end
    local familyId = (mob.getFamily and mob:getFamily()) or 0
    entry = ai_bar_spells.byFamily[familyId]
    if entry then return entry end
    local ecoId = (mob.getEcosystem and mob:getEcosystem()) or 0
    return ai_bar_spells.byEcosystem[ecoId]
end

function ai_bar_spells.get_element(mob)
    local entry = lookup(mob)
    return entry and entry.element or nil
end

function ai_bar_spells.get_status(mob)
    local entry = lookup(mob)
    return entry and entry.status or nil
end

return m
