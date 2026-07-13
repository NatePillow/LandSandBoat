_addon.author = 'Nate';
_addon.name = 'AutoBots';
_addon.version = '1.0';

require 'common';

local autoutil    = require('autoutil');
local autobots_ui = require('autobots_ui');

-- Configs live server-side now. The picker lists are pulled via 0x17A/0x17B
-- and cached on autoutil.server_configs[category]. The addon no longer reads
-- local disk for alliance / food / invite configs.

ashita.register_event('load', function()
    autoutil.tag = 'AutoBots';
    autobots_ui.on_load();
    autoutil.send_request_server_ident();
end);

ashita.register_event('unload', function()
    autobots_ui.on_unload();
end);

ashita.register_event('incoming_packet', function(id, size, data)
    if id == 0x150 then
        local was_unlocked = autoutil.unlocked;
        autoutil.check_for_server_ident(id, size, data);
        -- Re-sync any pre-existing autoskill overrides ONCE per unlock so the
        -- Active Config Info "Skill:" line reflects server state on addon load.
        -- Without the rising-edge guard this fires every server-ident heartbeat
        -- (~1Hz) and spams 0x193 → 0x192 → push_skillup_state_to over and over.
        if not was_unlocked then
            autoutil.send_list_autoskill();
            -- Pull the server's full alliance + per-bot state snapshot so
            -- the addon UI re-seeds local vars (formations, thresholds,
            -- puller config, per-bot toggles, active config name, etc.)
            -- after a /addon reload that wiped them to defaults. Fetched
            -- via GET /bot-state?for=<primaryName>; registered callbacks
            -- (autobots_ui.lua's seeder) apply the JSON.
            autoutil.fetch_bot_state();
            -- Config subscribe moved to lazy-on-first-UI-render (see
            -- autobots_ui.ensure_subscribed). Subscribing at unlock pushed
            -- the full small-category set on every login regardless of
            -- whether the user opened the addon — wasted bandwidth and one
            -- of the contributors to the login-time watchdog spike.
        end
        return false;
    end
    -- Detect battlefield entry: packet 0x075 with Flags > 0 means active battlefield.
    -- Byte 37 (1-indexed) = Flags field in PacketData (after 4B header + 32B of fields).
    -- On the rising edge, ask the server for the authoritative PC roster (0x185)
    -- so the BF picker doesn't have to guess trust-vs-PC client-side.
    if id == 0x075 and size >= 37 then
        local flags = struct.unpack('B', data, 37);
        local was = autobots_ui.in_instance;
        autobots_ui.in_instance = (flags > 0);
        if autobots_ui.in_instance and not was then
            autoutil.send_list_alliance_pcs();
        end
    end
    -- Zone change: clear battlefield flag and stale roster.
    if id == 0x00A then
        autobots_ui.in_instance = false;
        autoutil.alliance_pcs = {};
        -- Puller nearby-name cache accumulates within a zone. Mob names don't
        -- carry across zones, so clear on every zone change.
        autobots_ui.clear_puller_name_cache();
    end
    if not autoutil.unlocked then return false; end
    if id == 0x152 then
        autoutil.check_for_relay(id, size, data);
    elseif id == 0x179 then
        autoutil.check_for_headless_event(id, size, data);
    -- Config CRUD packet dispatchers (0x17b/0x17f/0x188/0x18a) removed —
    -- the addon now talks to the server over loopback HTTP via
    -- libs/http_client.lua.
    elseif id == 0x186 then
        autoutil.check_for_alliance_pc_list(id, size, data);
    elseif id == 0x1A0 then
        autoutil.check_for_instance_enter_result(id, size, data);
    elseif id == 0x18c then
        autoutil.check_for_bot_spells_list(id, size, data);
    -- 0x18E CHARS_LIST receive handler retired; char roster now flows
    -- through GET /chars (loopback HTTP) via autoutil.fetch_chars().
    elseif id == 0x191 then
        autoutil.check_for_party_status(id, size, data);
    elseif id == 0x192 then
        autoutil.check_for_autoskill_state(id, size, data);
    elseif id == 0x1A3 then
        -- Sync ACK from server-side cascade. Kind 0 = quests, 1 = missions,
        -- 2 = teleports. Clear the matching in-flight guard so the button
        -- re-enables.
        local kind, count = autoutil.check_for_sync_ack(id, size, data);
        if kind == 0 then
            autobots_ui.clear_sync_quests_in_flight();
            autoutil.log('AutoBots', string.format('Sync Quests: %d completion(s) applied.', count or 0));
        elseif kind == 1 then
            autobots_ui.clear_sync_missions_in_flight();
            autoutil.log('AutoBots', string.format('Sync Missions: %d completion(s) applied.', count or 0));
        elseif kind == 2 then
            autobots_ui.clear_sync_teleports_in_flight();
            autoutil.log('AutoBots', string.format('Sync Teleports: %d added.', count or 0));
        end
    elseif id == 0x1A4 then
        -- Puller nearby-names refresh — server scanned 255y of camp anchor
        -- and returned up to 20 { name, count } entries sorted desc by count.
        -- Merge into the addon cache (accumulates as user clicks Refresh).
        local list = autoutil.check_for_puller_nearby_names(id, size, data);
        if list ~= nil then
            autobots_ui.merge_puller_names(list);
        end
    end
    return false;
end);

-- Quote-aware tokenizer for the /bot command line. Lifted from autobuy's parser
-- pattern. Splits on whitespace, treats "quoted segments" as single tokens so
-- spell / ability / item names with spaces (`"Cure VI"`, `"Sneak Attack"`)
-- arrive intact.
local function tokenize_quoted(line)
    local result = {};
    local i = 1;
    while i <= #line do
        local c = line:sub(i, i);
        if c == ' ' then
            i = i + 1;
        elseif c == '"' then
            local j = line:find('"', i + 1, true);
            if j then
                table.insert(result, line:sub(i + 1, j - 1));
                i = j + 1;
            else
                table.insert(result, line:sub(i + 1));
                break;
            end
        else
            local j = line:find(' ', i, true);
            if j then
                table.insert(result, line:sub(i, j - 1));
                i = j + 1;
            else
                table.insert(result, line:sub(i));
                break;
            end
        end
    end
    return result;
end

-- Resolve a target token (`<t>`, `<me>`, `<player name>`) to a server entity ID.
-- Returns nil for <me> (sentinel — server resolves to bot itself).
-- Returns 0 if resolution failed (caller should reject).
local function resolve_target_token(tok)
    if tok == nil or tok == '' then return nil; end
    if tok == '<me>' then return 0; end
    if tok == '<t>' or tok == '<bt>' then
        local entMgr = AshitaCore:GetMemoryManager():GetTarget();
        if entMgr == nil then return 0; end
        local idx = tok == '<bt>' and entMgr:GetBattleTargetIndex(0) or entMgr:GetTargetIndex(0);
        if idx == 0 then return 0; end
        local serverId = AshitaCore:GetMemoryManager():GetEntity():GetServerId(idx);
        return serverId or 0;
    end
    -- Specific player name → walk Ashita party slots for a server ID.
    local party = AshitaCore:GetMemoryManager():GetParty();
    if party then
        for slot = 0, 17 do
            if party:GetMemberName(slot) == tok then
                return party:GetMemberServerId(slot) or 0;
            end
        end
    end
    return 0;
end

ashita.register_event('command', function(cmd, nType)
    local args = cmd:args();

    -- /bot <name> /<verb> [args...]
    if args[1] == '/bot' then
        if not autoutil.unlocked then
            autoutil.log('Bot', 'Not unlocked (waiting for server ident).');
            return true;
        end
        -- Ashita ADKv3 exposes the full raw command via cmd:get_command(); fall
        -- back to args-concat (quote-stripped) if that's unavailable. Quoted
        -- multi-word names work via get_command path; users on the fallback
        -- need to avoid spaces in spell/item names or use the `_` form
        -- (most spells/items in FFXI accept that too — e.g. "Cure VI" vs
        -- "cure_vi" both resolve server-side).
        local raw = (cmd.get_command and cmd:get_command())
                 or table.concat(args, ' ');
        -- Strip the leading "/bot " before quote-tokenizing so quoted names work.
        local tail = raw:sub(#'/bot ' + 1);
        local toks = tokenize_quoted(tail);
        if #toks < 2 then
            autoutil.log('Bot', 'Usage: /bot <name> /<ma|ja|ws|ra|item> "<thing>" [<target>]');
            return true;
        end
        local botName = toks[1];
        local verb    = toks[2];
        if verb:sub(1, 1) == '/' then verb = verb:sub(2); end
        verb = verb:lower();
        local thingName, targetTok;
        if verb == 'ws' then
            thingName = toks[3];     -- no target
            targetTok = nil;
        elseif verb == 'ra' then
            thingName = '';          -- no name
            targetTok = toks[3];
        else
            thingName = toks[3];
            targetTok = toks[4];
        end
        local targetId = 0;
        if targetTok ~= nil then
            local resolved = resolve_target_token(targetTok);
            if resolved == nil then
                -- <me> sentinel → keep 0
                targetId = 0;
            elseif resolved == 0 and targetTok ~= '<me>' then
                autoutil.log('Bot', string.format('could not resolve target "%s"', targetTok));
                return true;
            else
                targetId = resolved;
            end
        end
        autoutil.send_bot_command(botName, verb, thingName or '', targetId);
        return true;
    end

    if args[1] ~= '/autobots' then
        return false;
    end

    -- Bare `/autobots` (no args) toggles the window — matches every other
    -- addon's convention (`/autoequip`, `/autolot`, `/automog`, ...). Anything
    -- requiring a server round-trip still gates on unlocked below.
    if args[2] == nil or args[2] == 'ui' or args[2] == 'show' then
        autobots_ui.toggle();
        return true;
    end

    if not autoutil.unlocked then
        autoutil.log('AutoBots', 'Not unlocked (waiting for server ident).');
        return true;
    end

    -- /autobots stop = "Stop Actions" — pause every owned headless's AI
    -- without despawning. The destructive variant is the Despawn Alliance UI
    -- button (or /autobots despawn for the chat equivalent).
    if args[2] == 'stop' then
        autoutil.send_bot_set_alliance_mode(0);  -- BotMode::Off
        return true;
    end

    if args[2] == 'despawn' then
        autoutil.send_bot_despawn_all();
        autobots_ui.on_stop();
        return true;
    end

    if args[2] == 'finish' then
        autoutil.send_bot_finish();
        return true;
    end

    if args[2] == 'instance' or args[2] == 'bcnm' then
        local scope = args[3];
        if scope ~= 'party' and scope ~= 'alliance' then
            autoutil.log('AutoBots', 'Usage: /autobots instance|bcnm party|alliance');
            return true;
        end
        local subcmd = (scope == 'party') and 0 or 1;
        autoutil.send_instance_enter(subcmd);
        return true;
    end

    if args[2] == 'food' then
        local name = args[3];
        if name == nil then
            -- Async HTTP GET — usage lines print when the response arrives.
            local http = require('http_client');
            local json = require('json');
            http.get('/configs/food', function(code, body)
                local available = {};
                if code == 200 then
                    local ok, parsed = pcall(json.decode, json, body);
                    if ok and parsed and parsed.names then available = parsed.names; end
                end
                autoutil.log('AutoBots', 'Usage: /autobots food <config>');
                if #available > 0 then
                    autoutil.log('AutoBots', 'Available: ' .. table.concat(available, ', '));
                else
                    autoutil.log('AutoBots', 'No food configs found on server.');
                end
            end);
            return true;
        end
        autoutil.send_use_food_config(name);
        autoutil.log('AutoBots', string.format("food requested config '%s'.", name));
        return true;
    end

    -- Tell the assist to engage the player's current target. Same payload
    -- as the Attack button in the Setup tab.
    if args[2] == 'attack' then
        autoutil.send_bot_attack();
        return true;
    end

    -- /autobots conntest : verify the HTTP coroutine scheduler doesn't
    -- freeze the client on a failed connection. Fires a GET against
    -- 127.0.0.1:1 (nothing listens there → instant 'connection refused'
    -- from the OS) and then immediately fires a GET against the real
    -- configured HOST/PORT. Both responses should arrive without the
    -- client locking up; the second proves the scheduler survived the
    -- failure. Open the AutoBots window beforehand so you can watch the
    -- chat log; the responses print there.
    if args[2] == 'conntest' then
        local http = require('http_client');
        autoutil.log('AutoBots', string.format(
            'conntest: firing GET against bad address (127.0.0.1:1) and good address (%s:%d) - neither should freeze',
            http.HOST, http.PORT));
        local t0 = os.clock();
        http.get_at('127.0.0.1', 1, '/healthz', function(code, body, _, err)
            local elapsed_ms = math.floor((os.clock() - t0) * 1000);
            if code == nil then
                autoutil.log('AutoBots', string.format(
                    'conntest[bad]: failed cleanly after %dms with err=%s - PASS',
                    elapsed_ms, tostring(err)));
            else
                autoutil.log('AutoBots', string.format(
                    'conntest[bad]: unexpectedly got HTTP %s - FAIL', tostring(code)));
            end
        end);
        http.get('/healthz', function(code, body, _, err)
            local elapsed_ms = math.floor((os.clock() - t0) * 1000);
            if code == 200 and body == 'ok' then
                autoutil.log('AutoBots', string.format(
                    'conntest[good]: HTTP 200 after %dms - PASS (scheduler alive)',
                    elapsed_ms));
            elseif code == nil then
                autoutil.log('AutoBots', string.format(
                    'conntest[good]: connection failed after %dms with err=%s - investigate (host=%s port=%d reachable?)',
                    elapsed_ms, tostring(err), http.HOST, http.PORT));
            else
                autoutil.log('AutoBots', string.format(
                    'conntest[good]: got HTTP %s body=%q - unexpected',
                    tostring(code), tostring(body)));
            end
        end);
        return true;
    end

    -- /autobots start <config>  : spawn that alliance config (creates sessions).
    -- /autobots start           : "Start Actions" — flip every owned headless's
    --                             m_botMode to Full so their AI ticks resume.
    if args[2] == 'start' then
        local cfgName = args[3];
        if cfgName == nil then
            autoutil.send_bot_set_alliance_mode(2);  -- BotMode::Full
            return true;
        end
        autoutil.send_spawn_headless(cfgName);
        autoutil.log('AutoBots', string.format("start requested config '%s'.", cfgName));
        return true;
    end

    autoutil.log('AutoBots', 'Usage: /autobots start [<config>] | stop | attack | despawn | finish | food <config> | instance|bcnm party|alliance | ui');
    return true;
end);
