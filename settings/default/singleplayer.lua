-----------------------------------
-- SINGLEPLAYER FORK SETTINGS
-----------------------------------
-- Settings that are specific to the singleplayer fork — kept in a separate
-- file from upstream LSB defaults so upstream merges don't conflict.
-----------------------------------

xi = xi or {}
xi.settings = xi.settings or {}

xi.settings.singleplayer =
{
    -- NOTE: HEADLESS_MOB_AGGRO was removed — replaced by a runtime alliance
    -- toggle that the autobots addon's Quick Menu / Controls tab manipulates
    -- via 0x176 SET_AGGRO_MODE (cascades to each headless's m_aggroMode).
    -- Default behavior is unchanged: trust-like (no aggro) until the user
    -- flips the picker to Full. See bots_spawn.set_alliance_aggro_mode.

    -- Loopback config HTTP server (src/map/singleplayer/config_http_server.cpp).
    -- Map process spawns a cpp-httplib listener at boot; addons hit it for
    -- config CRUD over GET/PUT/DELETE. Replaced the chunked 0x17E/0x180/...
    -- packet pipeline that was triggering wire-zlib errors on big XMLs.
    --
    -- CONFIG_HTTP_BIND_ADDR:
    --   '127.0.0.1'  loopback only — server and client on the same machine
    --   '0.0.0.0'    all interfaces — needed when client is in a VM/container
    --                or on another machine on the LAN
    --   <specific>   bind to one interface IP (e.g. '192.168.1.10')
    -- Same value isn't required on the client; the client just needs to
    -- dial an IP that the server is bound on. See
    -- singleplayer/client/addons/libs/http_client.lua → http_client.HOST.
    --
    -- CONFIG_HTTP_PORT:
    --   Change if 51220 conflicts with another service on the host. The
    --   addon-side constant in libs/http_client.lua has to match.
    CONFIG_HTTP_BIND_ADDR = '0.0.0.0',
    CONFIG_HTTP_PORT      = 51220,

    -- Hard cap on crafting skills. Value is in display units (100 = display
    -- level 100, internally storage ×10 = 1000). The cap is FUNCTIONAL, not
    -- cosmetic: skillup attempts are rejected once RealSkills hits the cap,
    -- so the skill never rises above this value regardless of rank or job
    -- level. Combined with CRAFT_CAP_2X_HIGHEST_JOB, the effective cap is
    -- min(rankCap, highestJobLevel*2, CRAFT_SKILL_HARD_CAP).
    -- Applies to skills 49-56 (woodworking through cooking). Fishing (48)
    -- and synergy (57) are unaffected.
    CRAFT_SKILL_HARD_CAP = 100,

    -- When true, crafting skills are capped at 2 × the character's highest
    -- ever-leveled job (across all 22 jobs, not just the currently equipped
    -- one). Tied to combat progression: a level-1-everything char caps at
    -- display 2; a lv99 char caps at 198 (effectively uncapped).
    CRAFT_CAP_2X_HIGHEST_JOB = true,

    -- In-process AH bot (#197). See settings/singleplayer.lua for full docs.
    AUCTION_BOT_ENABLED               = true,
    AUCTION_BOT_SELLER_CHAR_ID        = 0,
    AUCTION_BOT_SELLER_NAME           = 'M.H.M.U.',
    AUCTION_BOT_TICK_INTERVAL_S       = 2,
    AUCTION_BOT_MAX_SELLBACK_LISTINGS = 25,
    -- Seconds to hold restocking an item after a buyer buys the bot's stock of
    -- it (0 = restock immediately, the default). e.g. 900 = wait 15 min. Only
    -- delays the bot re-listing its own sold-out stock; buying items players
    -- list on the AH is unaffected and still happens on the next tick.
    AUCTION_BOT_RESTOCK_DELAY_S       = 0,

    -- New-character headstart flags. All default true. Set to false to walk
    -- the normal questing path on a fresh char.
    NEW_CHAR_MISSION_HEADSTART  = false, -- start with nation missions at rank 10, RoZ through Mithra-and-Crystal, and CoP at Dawn. Set false for a "play from M1" playthrough.
    NEW_CHAR_TRUSTS_HEADSTART   = false, -- start with 20 trust spells pre-learned. Set false to learn trusts via the normal quest path.
    NEW_CHAR_TELEPORT_HEADSTART = false, -- start with all homepoint + survival teleports AND all 6 gate-crystal KIs (Holla/Dem/Mea/Vahzl/Yhoator/Altepa). Set false to earn them naturally.
    NEW_CHAR_LB_HEADSTART       = false, -- start with all Limit Break fetch KIs (Orcish/Quadav/Yagudo Crests + Smiling/Scowling/Somber/Spirited Stones). Set false to do the LB chain normally.

    -- (BOT_STUN_PERSIST_UNTIL_FIRED removed - now alliance.stunMode, exposed
    -- via the AutoBots AI Settings > Stun Behavior toggle. See user-facing
    -- comment in settings/singleplayer.lua for migration details.)

    -- (BOT_CURE_PARTY_ONLY removed - the toggle was superseded by the
    -- per-bot healScope setting on role_heal / role_rdm, exposed via the
    -- AutoBots status-tab "Heal" dropdown. Shared cure helpers in
    -- ai_magic.lua now default to party-only; alliance-scope cures
    -- dispatch from the role's own healScope='allianceMain' / 'allianceAssist'
    -- branches.)

    -- When true (default), the fork's custom trust spawn logic in
    -- modules/singleplayer/lua/trust_overrides/<name>.lua fires in place of
    -- upstream's spellObject.onMobSpawn for every fork-customized trust
    -- (Curilla, Joachim, Ayame, etc. — see directory listing). When false,
    -- the SINGLEPLAYER hook at the top of each upstream trust file falls
    -- through to vanilla LSB behavior, restoring upstream's gambit/mod
    -- priority ordering exactly as shipped. Toggle for A/B testing fork
    -- enhancements vs vanilla, or to "audit upstream" without ripping the
    -- override files out.
    CUSTOM_TRUST_LOGIC = true,

    -- When true, bot movement clamps each per-tick step at the first wall hit
    -- via navmesh raycast (#189's wall-clearance behavior). Bots will refuse
    -- to walk into terrain — gives "realistic" path-following but can leave
    -- bots stuck against geometry if the formation target lands inside a wall,
    -- a navmesh has tight corners the pathfinder can't squeeze through, etc.
    --
    -- When false (default), the fork still uses navmesh for path PLANNING
    -- (pathTo picks routes around major obstacles) but skips the per-tick
    -- step-clamp — bots can pass through walls when they need to. Trades
    -- realism for robustness; matches the fork's pre-rebase behavior where
    -- the engine had no navmesh data and bots straight-line-walked. Best
    -- choice when you'd rather have bots in the right spot ugly than stuck
    -- in the wrong spot pretty.
    BOT_RESPECT_GEOMETRY = false,

    -- When true, bot AI role-tick decisions are logged to the primary's chat
    -- line via ai_util.log (e.g. "[Zariah][AutoTank] provoke_is_up",
    -- "[Freya][AutoSC] use_weapon_skill", "[Malfina][AutoHeal] Cure_P2").
    -- Fires every tick per bot per branch — a firehose meant for AI dev, NOT
    -- normal play. Default off. Flip true when diagnosing why a specific bot
    -- is (or isn't) taking an expected action.
    BOT_AI_CHAT_LOG = false,

}

-- EOF
