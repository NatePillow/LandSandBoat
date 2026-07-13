local autoutil = {};

-- Each Ashita addon loads its own copy of this lib (separate Lua state per
-- addon). The lib's internal logs would mis-tag as 'AutoBots' if we hardcoded;
-- instead every addon sets autoutil.tag at load time (e.g. 'AutoEquip') and
-- the lib's call sites read from it. Addons that haven't set a tag still see
-- their own logs under the 'Auto' generic fallback.
autoutil.tag = nil;

local function libtag() return autoutil.tag or 'Auto'; end

function autoutil.log(tag, msg)
    -- Empty tag = server packed "[Name][Role] msg" into the message body
    -- itself (see server-side autoutil.log). Render the message directly
    -- so the prefix appears verbatim without an extra "[]" wrapper.
    if tag == nil or tag == '' then
        print('\31\130' .. tostring(msg));
        return;
    end
    print('\31\200[\31\05' .. tostring(tag) .. '\31\200]\31\130 ' .. tostring(msg));
end

autoutil.jobs = {'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN'};

-- ─── Active alliance config ───────────────────────────────────────────────
-- Single source of truth for the currently-spawned alliance's parsed JSON.
-- Owned by autobots_ui (set on on_start, cleared on on_stop). Other tabs
-- and addons read from here instead of duplicating per-tab caches. nil when
-- no alliance is running.
--
-- TODO (autobots UI rework, [[char-settings-tab]]): wire on-demand fetch via
-- 0x17E get_config_content when this is nil but a row references a bot the
-- caller wants to act on. Right now the assumption is "if nil, the addon
-- doesn't render the role-gated UI" — which is fine for nudge/heal toggles
-- but won't scale to a dedicated Char Settings tab.
autoutil.activeAllianceConfig = nil;

-- Lookup: is `name` listed in cfg.roles[roleKey]? Returns false when no
-- alliance is loaded. Case-insensitive name match against the JSON config
-- so 'brutus' matches a configured "Brutus" entry. roleKey is the bucket
-- name from the alliance JSON ('tank', 'heal', 'rdm', 'nuke', 'melee').
function autoutil.bot_has_role(name, roleKey)
    local cfg = autoutil.activeAllianceConfig;
    if cfg == nil or cfg.roles == nil or name == nil or roleKey == nil then return false; end
    local bucket = cfg.roles[roleKey];
    if type(bucket) ~= 'table' then return false; end
    local lname = name:lower();
    for _, n in ipairs(bucket) do
        if type(n) == 'string' and n:lower() == lname then return true; end
    end
    return false;
end

function autoutil.table_contains(tbl, val)
	if tbl == nil then
		print(debug.traceback());
		return
	end
	for i, value in ipairs(tbl) do
		if value == val then
			return true;
		end
	end
	return false;
end

function autoutil.table_contains_any(tblB, tblA)
	for _, valueA in pairs(tblA) do
		if autoutil.table_contains(tblB, valueA) then
			return true
		end
	end
	return false
end

function autoutil.starts_with(val, start)
	if val == nil or start == nil or #start > #val then
		return false;
	end
	return val:find('^' .. start) ~= nil;
end

function autoutil.round_to_two_decimals(num)
    return math.floor(num * 100 + 0.5) / 100
end

function autoutil.get_entity_distance(serverId)
    for x = 0, 2303 do
        local entity = GetEntity(x);
        if (entity ~= nil and entity.ServerId == serverId) then
			local rawDistance = entity.Distance;
			local square = math.sqrt(rawDistance);
            return square;
        end
    end
    return nil;
end

function autoutil.get_entity(serverId)
    for x = 0, 2303 do
        local entity = GetEntity(x);
        if (entity ~= nil and entity.ServerId == serverId) then
            return entity;
        end
    end
    return nil;
end

function autoutil.get_entity_name(serverId)
    local entity = autoutil.get_entity(serverId);
    if entity ~= nil then
        return entity.Name;
    end
    return nil;
end

function autoutil.get_target_index(serverId)
	local entity = autoutil.get_entity(serverId);
	if entity ~= nil then
		return entity.TargetIndex;
	else
		return nil;
	end
end

function autoutil.get_ms_since_epoch()
    local seconds_since_epoch = os.time();
    local fractional_time = os.clock() % 1.0;
    local milliseconds = math.floor(seconds_since_epoch * 1000 + fractional_time * 1000);
    return milliseconds;
end

function autoutil.remove_element(tbl, val)
	for i, value in ipairs(tbl) do
        if value == val then
            return table.remove(tbl, i);
        end
    end
    return nil;
end

function autoutil.index_of(array, value)
    for i, v in ipairs(array) do
        if v == value then
            return i
        end
    end
    return nil
end

function autoutil.get_party_server_ids()
	local party = AshitaCore:GetDataManager():GetParty();
	local ids = {};
	for x = 0, 17 do
		table.insert(ids, party:GetMemberServerId(x));
	end
	return ids;
end

function autoutil.get_lowest_key_by_value(tbl)
	local lowestKey = nil;
	local lowestValue = nil;

	for key, value in pairs(tbl) do
		if value ~= nil and (lowestValue == nil or value < lowestValue) then
			lowestKey = key;
			lowestValue = value;
		end
	end

	return lowestKey;
end

function autoutil.current_mp_percent()
	return AshitaCore:GetDataManager():GetParty():GetMemberCurrentMPP(0);
end

function autoutil.current_hp_percent()
	return AshitaCore:GetDataManager():GetParty():GetMemberCurrentHPP(0);
end

function autoutil.get_current_target_server_id()
	return AshitaCore:GetDataManager():GetTarget():GetTargetServerId();
end

function autoutil.get_current_target_index()
	return AshitaCore:GetDataManager():GetTarget():GetTargetIndex();
end

function autoutil.get_member_index(name)
	local party = AshitaCore:GetDataManager():GetParty();
	for x = 0, 17 do
		if name == party:GetMemberName(x) then
			return x;
		end
	end
	return nil;
end

function autoutil.get_member_job(name)
	local party = AshitaCore:GetDataManager():GetParty();
	for x = 0, 17 do
		if name == party:GetMemberName(x) then
			return party:GetMemberMainJob(x);
		end
	end
	return nil;
end

function autoutil.get_member_name(serverId)
	local party = AshitaCore:GetDataManager():GetParty();
	for x = 0, 17 do
		if serverId == party:GetMemberServerId(x) then
			return party:GetMemberName(x);
		end
	end
	return nil;
end

function autoutil.get_member_names_with_job(jobName)
	local party = AshitaCore:GetDataManager():GetParty();
	local names = {};
	for i = 1, 17 do
		local job = party:GetMemberMainJob(i);
		local name = party:GetMemberName(i);
		if job ~= nil and autoutil.jobs[job] == jobName then
			table.insert(names, name)
		end
	end
	return names;
end

function autoutil.is_effect_active(buffId)
    if buffId == nil then
        return false;
    end
	local buffs = AshitaCore:GetDataManager():GetPlayer():GetBuffs();
	if buffs[0] ~= nil and buffs[0] == buffId then
		return true;
	end
	for _,buff in ipairs(buffs) do
		if (buffId == buff) then
			return true;
		end
	end
	return false;
end

function autoutil.is_any_effect_active(buffTbl)
	local buffs = AshitaCore:GetDataManager():GetPlayer():GetBuffs();
	if buffs[0] ~= nil and autoutil.table_contains(buffTbl, buffs[0]) then
		return true;
	end
	for _,buff in ipairs(buffs) do
		if autoutil.table_contains(buffTbl, buff) then
			return true;
		end
	end
	return false;
end

local neutralizingEffects = { 0, 2, 7, 14, 17, 19, 28 };
function autoutil.has_neutralizing_effect()
	for _, buffId in ipairs(neutralizingEffects) do
		if autoutil.is_effect_active(buffId) then
			return true;
		end
	end
	return false;
end

function autoutil.weakened()
	return autoutil.is_effect_active(1);
end

function autoutil.silenced()
	return autoutil.is_effect_active(6);
end

function autoutil.poisoned()
	return autoutil.is_effect_active(3);
end

function autoutil.paralyzed_or_silenced()
	return autoutil.is_effect_active(4) or autoutil.is_effect_active(6);
end

function autoutil.paralyzed_or_silenced_or_poisoned()
	return autoutil.is_effect_active(4) or autoutil.is_effect_active(6) or autoutil.is_effect_active(3);
end

local status_that_prevent_rest = { 3, 128, 129, 130, 131, 132, 133, 134, 135,
                                   0, 2, 7, 14, 17, 19
};
function autoutil.can_rest()
	for _, buffId in ipairs(status_that_prevent_rest) do
		if autoutil.is_effect_active(buffId) then
			return false;
		end
	end
	return true;
end

function autoutil.is_resting()
	local em = AshitaCore:GetDataManager():GetEntity();
	local party = AshitaCore:GetDataManager():GetParty();
	local status = em:GetStatus(party:GetMemberTargetIndex(0));
	return status == 33;
end

function autoutil.start_rest()
	AshitaCore:GetChatManager():QueueCommand('/heal on', 2);
end

function autoutil.stop_rest()
	AshitaCore:GetChatManager():QueueCommand('/heal off', 2);
end

function autoutil.get_ranged_delay()
	local inv     = AshitaCore:GetDataManager():GetInventory();
	local res_mgr = AshitaCore:GetResourceManager();
	local delay   = 0;

	local range_item = inv:GetEquippedItem(EquipmentSlots.Range); -- int: 2
	local ammo_item  = inv:GetEquippedItem(EquipmentSlots.Ammo);  -- int: 3

	if range_item and range_item.Id ~= 0 then
		local res = res_mgr:GetItemById(range_item.Id);
		if res then delay = delay + (res.Delay or 0); end
	end

	if ammo_item and ammo_item.Id ~= 0 then
		local res = res_mgr:GetItemById(ammo_item.Id);
		if res then delay = delay + (res.Delay or 0); end
	end

	return delay;
end

function autoutil.debug_equipped()
    local inv     = AshitaCore:GetDataManager():GetInventory();
    local res_mgr = AshitaCore:GetResourceManager();

    local function describe(label, item)
        if item == nil then
            autoutil.log('AutoUtil', string.format('%s -> nil', label));
        elseif item.Id == nil then
            autoutil.log('AutoUtil', string.format('%s -> item exists but Id is nil', label));
        elseif item.Id == 0 then
            autoutil.log('AutoUtil', string.format('%s -> Id=0 (empty slot)', label));
        else
            local res = res_mgr:GetItemById(item.Id);
            local name = res and res.Name and res.Name[0] or '?';
            local delay = res and res.Delay or '?';
            autoutil.log('AutoUtil', string.format('%s -> Id=%d name="%s" delay=%s', label, item.Id, name, tostring(delay)));
        end
    end

    describe('GetEquippedItem(2)         [int Range]', inv:GetEquippedItem(2));
    describe('GetEquippedItem(3)         [int Ammo]', inv:GetEquippedItem(3));
    describe('GetEquippedItem("Range")   [str Range]', inv:GetEquippedItem('Range'));
    describe('GetEquippedItem("Ammo")    [str Ammo]', inv:GetEquippedItem('Ammo'));
end

function autoutil.is_job(jobName)
    local jobIndex = AshitaCore:GetDataManager():GetParty():GetMemberMainJob(0);
    return autoutil.jobs[jobIndex] == jobName;
end

function autoutil.is_dead()
	local party = AshitaCore:GetDataManager():GetParty();
	local entityManager = AshitaCore:GetDataManager():GetEntity();
	local status = entityManager:GetStatus(party:GetMemberTargetIndex(0));
	return status == 2 or status == 3;
end

function autoutil.is_dead()
	local party = AshitaCore:GetDataManager():GetParty();
	local entityManager = AshitaCore:GetDataManager():GetEntity();
	local status = entityManager:GetStatus(party:GetMemberTargetIndex(0));
	return status == 2 or status == 3;
end

local _spells     = require('spells');
local _abilities  = require('job_abilities');

local function resolve_param(category, param)
	if category == 4 or category == 5 or category == 8 then
		local s = _spells[param];
		return s and (s.en .. '(spell#' .. param .. ')') or ('spell#' .. param);
	elseif category == 6 or category == 9 then
		local a = _abilities[param];
		return a and (a.en .. '(ability#' .. param .. ')') or ('ability#' .. param);
	end
	return tostring(param);
end

-- Debug helper for 0x28 (battle action) packets
function autoutil.debug_battle2(id, size, data)
	local category = ashita.bits.unpack_be(data, 82, 4);
	if category == 1 or category == 2 then return; end
	local actorId     = struct.unpack('I', data, 0x05 + 1);
	local targetCount = struct.unpack('b', data, 0x09 + 1);
	local param       = ashita.bits.unpack_be(data, 86, 16);
	local targetId    = ashita.bits.unpack_be(data, 82 + 4 + 64, 32);
	local msg         = ashita.bits.unpack_be(data, 230, 10);
	local actorName   = autoutil.get_entity_name(actorId) or tostring(actorId);
	local targetName  = autoutil.get_entity_name(targetId) or tostring(targetId);
	local paramStr    = resolve_param(category, param);
	autoutil.log('0x28', string.format('t=%d actor="%s"(%d) target="%s"(%d) count=%d category=%d param=%s msg=%d',
		autoutil.get_ms_since_epoch(), actorName, actorId, targetName, targetId, targetCount, category, paramStr, msg));
end

-- Debug helper for 0x29 (battle message) packets
function autoutil.debug_battle_message(id, size, data)
	local actorId    = struct.unpack('L', data, 0x04 + 1);
	local targetId   = struct.unpack('L', data, 0x08 + 1);
	local message    = struct.unpack('H', data, 0x18 + 1);
	local param1     = struct.unpack('H', data, 0x0C + 1);
	local param2     = struct.unpack('H', data, 0x10 + 1);
	local actorName  = autoutil.get_entity_name(actorId) or tostring(actorId);
	local targetName = autoutil.get_entity_name(targetId) or tostring(targetId);
	local p1Spell    = _spells[param1] and (_spells[param1].en .. '(spell#' .. param1 .. ')') or tostring(param1);
	local p2Spell    = _spells[param2] and (_spells[param2].en .. '(spell#' .. param2 .. ')') or tostring(param2);
	autoutil.log('0x29', string.format('t=%d actor="%s"(%d) target="%s"(%d) msg=%d param1=%s param2=%s',
		autoutil.get_ms_since_epoch(), actorName, actorId, targetName, targetId, message, p1Spell, p2Spell));
end

-- Debug helper for outgoing chat packets (0x0B5).
-- Prints the Kind byte and message string so we can verify what the client sends for slash commands.
function autoutil.debug_outgoing_chat(id, size, data)
    local kind = struct.unpack('B', data, 0x04 + 1);
    local msg = data:sub(0x07, 0x07 + 127):gsub('%z', '');
    print(string.format('[0x%03X] t=%d kind=0x%02X msg="%s"', id, autoutil.get_ms_since_epoch(), kind, msg));
end

local COMMAND_RES_RAISE   = 1;
local COMMAND_RES_TRACTOR = 2;

function autoutil.check_for_raise_or_tractor(id, size, data)
    local resType = struct.unpack('H', data, 0x0A + 1);
    if resType == COMMAND_RES_RAISE or resType == COMMAND_RES_TRACTOR then
        local label = resType == COMMAND_RES_RAISE and 'Raise' or 'Tractor';
        autoutil.log('AutoUtil', string.format('Auto-accepting %s', label));
        local party = AshitaCore:GetDataManager():GetParty();
        local selfId    = party:GetMemberServerId(0);
        local selfIndex = party:GetMemberTargetIndex(0);
        -- 0x01A: ActionID=0x0D (RaiseMenu), HomepointMenu.StatusId=0 (Accept), ActionBuf[4] fully populated
        local packet = struct.pack('HHLHHLLLL', 0x01A, 0x08, selfId, selfIndex, 0x0D, 0, 0, 0, 0);
        AddOutgoingPacket(0x01A, packet:totable());
    end
end

autoutil.unlocked = false;
autoutil.serverIdent = nil;

-- 0x153 REQUEST_SERVER_IDENT: ask the server "is this our singleplayer fork?".
-- Empty body besides the standard 4-byte header (id+size in the LE u16 + sync).
-- Each addon calls this from its `load` event handler; the server replies with
-- one 0x150 GP_SERV_COMMAND_SERVER_IDENT, which trips check_for_server_ident()
-- below to set unlocked = true. Against a non-fork server the request goes
-- unhandled and the addon stays inert — exactly the desired security behavior.
function autoutil.send_request_server_ident()
    local bytes = {};
    for i = 1, 4 do bytes[i] = 0; end
    bytes[1] = 0x53; bytes[2] = 0x01;  -- opcode 0x153 LE
    AddOutgoingPacket(0x153, bytes);
end

function autoutil.check_for_server_ident(id, size, data)
    local ident = data:sub(0x05, 0x05 + 31):gsub('%z', '');
    local was_unlocked = autoutil.unlocked;
    autoutil.unlocked = true;
    autoutil.serverIdent = ident;
    -- Configs live server-side now; addons fetch what they need on demand
    -- over loopback HTTP (singleplayer/client/addons/libs/http_client.lua →
    -- src/map/singleplayer/config_http_server.cpp). No more bulk listing
    -- at ident-time — each consumer (autobots_ui, gear_tab, ...) does its
    -- own GET /configs/<cat> when it needs the picker names.
end

local relay_handlers = {};

-- Register a handler for relay messages with a given prefix.
-- handler(senderServerId, args) where args is the payload string after "PREFIX:".
function autoutil.on_relay(prefix, handler)
    relay_handlers[prefix] = handler;
end

-- payload format: "PREFIX:arg1:arg2:..."  max 240 bytes
function autoutil.send_relay(payload)
    local bytes = {};
    for i = 1, 244 do bytes[i] = 0; end
    bytes[1] = 0x51; bytes[2] = 0x01;  -- opcode 0x151 LE
    for i = 1, 240 do
        bytes[4 + i] = payload:byte(i) or 0;
    end
    AddOutgoingPacket(0x151, bytes);
end

function autoutil.check_for_relay(id, size, data)
    local senderServerId = struct.unpack('I', data, 0x04 + 1);
    local payload = data:sub(0x09, 0x09 + 239):gsub('%z', '');
    local prefix = payload:match('^([^:]+)');
    if prefix and relay_handlers[prefix] then
        local args = payload:sub(#prefix + 2);
        relay_handlers[prefix](senderServerId, args);
    end
end

-----------------------------------
-- Headless / bot AI packet helpers (server-side migration plumbing)
--
-- 0x175 SPAWN_HEADLESS: tells the server to spin up one or more headless char
-- sessions tied to this primary client. Layout matches the C++ packet:
--   Count (u8) + CountPadding[3] + 16 × { Name[16] + Role(u8) + TrustCount(u8)
--   + Padding[2] + Trusts[4]uint16 }
-- chars: array of { name = "...", role = 0..7, trusts = { spellId, ... } }
-----------------------------------
autoutil.BotRole = {
    Idle   = 0,
    Tank   = 1,
    Healer = 2,
    Nuker  = 3,
    Rdm    = 4,
    Melee  = 5,
};

autoutil.BotMode = {
    Off        = 0,
    CombatOnly = 1,
    Full       = 2,
};

local function pack_name(bytes, offset, name, maxLen)
    local cap = (maxLen or 16) - 1;  -- reserve a NUL terminator
    local s   = (name or ''):sub(1, cap);
    for i = 1, #s do
        bytes[offset + i - 1] = s:byte(i);
    end
end

-- 0x175 SPAWN_HEADLESS: server reads the named alliance config from
-- singleplayer/config/alliance/<configName>.json and drives spawn +
-- party formation + trust queuing entirely server-side. Packet payload is just
-- ConfigName[32] null-padded.
function autoutil.send_spawn_headless(configName)
    if configName == nil or configName == '' then
        autoutil.log(libtag(), 'send_spawn_headless: empty config name');
        return;
    end

    -- 36 byte packet: 4 header + 32 ConfigName
    local bytes = {};
    for i = 1, 36 do bytes[i] = 0; end
    bytes[1] = 0x75; bytes[2] = 0x01;  -- opcode 0x175 LE
    -- bytes[3..4] sync (left zero; Ashita fills)
    pack_name(bytes, 5, configName, 32);  -- 32-byte null-padded slot

    AddOutgoingPacket(0x175, bytes);
end

-- 0x176 HEADLESS_COMMAND: runtime bot control.
-- namespace + subcommand + 12-byte payload. Constants mirror C++ side.
autoutil.HeadlessNs       = { Autobots = 0x01 };
-- 0x10 was SetNmMode; opcode retired with the NM Mode toggle removal and
-- available for reuse (prefer reusing vacated opcodes before counting up).
-- 0x1C RequestBotState retired (#231) — bot state now fetched via GET
-- /bot-state?for=<name> over the loopback HTTP server. Slot reserved.
autoutil.AutobotsSubcmd   = { SetBotMode = 0x01, Attack = 0x02, Disengage = 0x03, SetRole = 0x04, DespawnAll = 0x05, Finish = 0x06, SetHealMode = 0x07, UpdateConfig = 0x08, SummonTrusts = 0x09, ScPause = 0x0A, SetAllianceMode = 0x0B, SpawnDead = 0x0C, SetFormation = 0x0D, SyncQuests = 0x0E, SyncMissions = 0x0F, TankWalkToMe = 0x10, FireAllWs = 0x11, SetScThreshold = 0x12, SetSataMode = 0x13, TankNudge = 0x14, SetPuller = 0x15, SetPullerRange = 0x16, SetPullerConRange = 0x17, RequestPullerNames = 0x18, GiveSignet = 0x19, SetHealScope = 0x1A, SetAggroMode = 0x1B, SetAddControlMode = 0x1D, SetStunMode = 0x1E, SetThfRaDelay = 0x1F, SetRoleAiMode = 0x20, SetRoleAiStatusFlag = 0x21, SyncTeleports = 0x22, SetBrdSongRoster = 0x23, SetSmnAvatar = 0x24, SetMultiEngageMode = 0x25, SetPullerPaused = 0x26, SetPullerResumeMpp = 0x27, SetCasualNukeRotation = 0x28, SetCasualNukeMbMode = 0x29 };

-- Role AI policy wire-format constants. Server-side mirrors live in
-- modules/singleplayer/bots/role_policy.lua (ROLE_BY_INDEX / TYPE_BY_INDEX /
-- MODE_BY_INDEX / STATUS_LIST). Keep both ends in sync.
autoutil.RoleAiRole = { tank = 0, melee = 1, heal = 2, rdm = 3, nuke = 4, brd = 5, smn = 6 };
autoutil.RoleAiType = { hp = 0, mp = 1, status = 2 };
-- Role AI mode wire-format. Three values across HP / MP / Status:
--   0 = Off, 1 = NM Only, 2 = Always.
-- (A fourth "Poison" mode was retired — it scoped to rest-blockers, which
-- is fully expressible by ticking only the Poison checkbox with Status=Always.)
autoutil.RoleAiMode = { off = 0, nm = 1, always = 2 };
-- Statuses with at least one item cure path. Plague / Petrify / Slow /
-- Bind / Doom omitted — no item cures them, so a checkbox would be
-- inert. Curse stays (Holy Water).
autoutil.RoleAiStatusList = {
    { key = 0, label = 'Poison'   },
    { key = 1, label = 'Silence'  },
    { key = 2, label = 'Blind'    },
    { key = 3, label = 'Paralyze' },
    { key = 4, label = 'Curse'    },
    { key = 5, label = 'Disease'  },
};

function autoutil.send_headless_command(namespaceId, subcommand, payload)
    -- 40 byte packet: 4 header + 1 ns + 1 sub + 2 pad + 32 payload
    -- (Payload was 12 bytes originally; bumped to 32 on 2026-06-28 to fit
    -- SetBrdSongRoster's Name[10] + 4*uint16 = 18 bytes. Existing senders
    -- that pass <=12-byte payloads continue to work — the unused tail
    -- bytes are zero-padded and ignored by server handlers that read
    -- fixed offsets.)
    local bytes = {};
    for i = 1, 40 do bytes[i] = 0; end
    bytes[1] = 0x76; bytes[2] = 0x01;  -- opcode 0x176 LE
    bytes[5] = namespaceId;
    bytes[6] = subcommand;
    -- bytes[7..8] padding
    payload = payload or {};
    for i = 1, math.min(#payload, 32) do
        bytes[8 + i] = payload[i] or 0;
    end
    AddOutgoingPacket(0x176, bytes);
end

-- Helper: ATTACK with the player's current target.
function autoutil.send_bot_attack()
    local target = AshitaCore:GetDataManager():GetTarget();
    if target == nil then return; end
    local serverId = target:GetTargetServerId();  -- main target slot
    if serverId == 0 then return; end
    local payload = {
        serverId % 256,
        math.floor(serverId / 256) % 256,
        math.floor(serverId / 65536) % 256,
        math.floor(serverId / 16777216) % 256,
        0, 0, 0, 0, 0, 0, 0, 0,
    };
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.Attack, payload);
end

function autoutil.send_bot_disengage()
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.Disengage, {});
end

-- Server-side: walk all headless sessions whose parentCharId == us, destroy each.
function autoutil.send_bot_despawn_all()
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.DespawnAll, {});
end

-- Server-side: flag every linked headless's magic state with nukeUntilDead = true.
function autoutil.send_bot_finish()
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.Finish, {});
end

-- Server-side: cascade primary's completed quests / missions onto every linked
-- headless via xi.singleplayer.bots.bots_progression_cascade.sync_{quests,missions}. Reply: S2C 0x1A3 SYNC_ACK
-- which check_for_sync_ack parses + clears the addon UI's in-flight guard.
function autoutil.send_bot_sync_quests()
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SyncQuests, {});
end

function autoutil.send_bot_sync_missions()
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SyncMissions, {});
end

-- Cascade primary's full teleport bitfield surface (all 13 TELEPORT_TYPE
-- values — homepoints, survival guides, waypoints, abyssea conflux,
-- eschan portals, runic portal, past maw, campaign zones, outposts) onto
-- every linked headless. Reply: SYNC_ACK kind=2.
function autoutil.send_bot_sync_teleports()
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SyncTeleports, {});
end

-- Parse incoming S2C 0x1A3 SYNC_ACK. Layout (after 4-byte ashita header):
--   [5]   Kind   (1 byte: 0 = quests, 1 = missions)
--   [6-8] Padding
--   [9-12] Count (uint32 little-endian)
-- Returns kind, count on success; nil if size insufficient.
function autoutil.check_for_sync_ack(id, size, data)
    if id ~= 0x1A3 or size < 12 then return nil; end
    local kind  = struct.unpack('B', data, 5);
    local count = struct.unpack('I4', data, 9);
    return kind, count;
end

-- Server-side: walk active alliance config, fire summonTrustDirect on each
-- party leader per listed trust. Direct spawn (no cast time) — server still
-- validates has-spell / not-duplicated / recast-inactive.
function autoutil.send_bot_summon_trusts()
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SummonTrusts, {});
end

-- Server-side: revive every owned headless that's currently dead. Applies
-- the standard homepoint XP loss + Weakness debuff and snaps the bots to
-- the primary's current zone/position (mirrors "homepoint then /welcome").
function autoutil.send_bot_spawn_dead()
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SpawnDead, {});
end

-- Grant SIGNET to the primary + every owned headless. Server runs the same
-- gate-guard overseer path each nation's guard uses, per-bot — each member
-- gets their own duration from their own nation/rank. Strips competing
-- INFLUENCE-flagged effects (sigil/sanction) first.
function autoutil.send_bot_give_signet()
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.GiveSignet, {});
end

-- Toggle sc1/sc2 pause across every linked headless. scId 0=both, 1=sc1, 2=sc2.
-- Replaces the legacy 0x151/0x152 SC:PAUSE relay path.
function autoutil.send_bot_sc_pause(scId, paused)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = scId or 0;
    payload[2] = paused and 1 or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.ScPause, payload);
end

-- Toggle auto-rest behavior on linked headless. on=true sits/stands based on
-- HP/MP thresholds.
--
-- Targeting:
--   bot_name == nil or ''  -> apply to every owned headless (alliance-wide)
--   bot_name (string)      -> apply to that single owned headless
--
-- Wire layout (12 bytes): on (uint8) + name (char[10], NUL-padded) + reserved.
-- Replaces the prior (on, mages_only) signature. The mages-only narrowing
-- was a hardwired special case with no UI consumer after the Controls-tab
-- rebuild; callers wanting per-role selection now iterate roles client-side
-- and emit one packet per bot.
function autoutil.send_bot_set_heal_mode(on, bot_name)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = on and 1 or 0;
    if type(bot_name) == 'string' and bot_name ~= '' then
        -- Name slot is bytes 1..10 of the payload (Lua-indexed 2..11). Server
        -- side strnlen-truncates to 10 so longer names just clip silently.
        local nm = bot_name:sub(1, 10);
        for i = 1, #nm do
            payload[1 + i] = nm:byte(i);
        end
    end
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetHealMode, payload);
end

-- send_bot_set_nm_mode dropped — `is_nm` is now always engine-autodetect
-- (Dynamis OR battlefield OR mob:isNM()); no user-facing toggle remains.

-- Force every linked bot (primary + owned headless) to use their configured WS
-- right now, bypassing the AI's SC/MB-window gates. Engine still rejects below
-- 1000 TP / not engaged. No payload.
function autoutil.send_bot_fire_all_ws()
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.FireAllWs, {});
end

-- (Retired) send_bot_request_state — the legacy C2S 0x176 sub 0x1C path is
-- gone. Bot state is now fetched via autoutil.fetch_bot_state() over HTTP
-- (GET /bot-state?for=<primaryName>). See the dispatcher block below for
-- the addon-side callback shape. Server-side, the snapshot is published
-- to the cache on every onBotTick (~400ms), so callers can fetch at any
-- time and get something fresh.

-- Alliance-wide stun behavior. Replaces the legacy BOT_STUN_PERSIST_UNTIL_FIRED
-- settings flag. Decides whether the interrupt window stays open until a
-- stunner fires ('always', default) or strictly tracks the mob's actual WS
-- castTime ('window'). Wire layout: uint8 Mode (0=always, 1=window) + reserved.
function autoutil.send_bot_set_stun_mode(mode_byte)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = mode_byte or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetStunMode, payload);
end

-- Alliance-wide multi-engagement toggle (#173). 0 = single-mob legacy,
-- 1 = per-party mode. Server seeds all 3 party targets from allianceTarget
-- on false→true, clears per-party state on true→false.
-- Wire layout: uint8 Mode (0/1) + reserved.
function autoutil.send_bot_set_multi_engage_mode(mode_byte)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = mode_byte or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetMultiEngageMode, payload);
end

-- PLD-only add-control mode toggle (status-tab dropdown). Tells the named
-- bot which tool to use on peelable adds:
--   mode_byte 0 -> 'provoke' (legacy: Provoke on both main + adds)
--   mode_byte 1 -> 'flash'   (Flash on adds, no Provoke on adds)
--   mode_byte 2 -> 'both'    (both Provoke + Flash interleave on adds)
-- Wire layout (12 bytes): char Name[10] + uint8 Mode + uint8 reserved.
function autoutil.send_bot_set_add_control(bot_name, mode_byte)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    if type(bot_name) == 'string' and bot_name ~= '' then
        local nm = bot_name:sub(1, 10);
        for i = 1, #nm do payload[i] = nm:byte(i); end
    end
    payload[11] = mode_byte or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetAddControlMode, payload);
end

-- ====================================================================
-- Bot state snapshot fetch (HTTP).
-- ====================================================================
-- The server publishes the full alliance + per-bot config state to the
-- loopback HTTP server's cache every onBotTick (~400ms). Addons that need
-- to seed UI from the server's authoritative values call fetch_bot_state()
-- at unlock; registered callbacks fire on a successful response. The
-- legacy 0x1A5 BOT_STATE_SNAPSHOT packet path was retired — see task #231.
autoutil.bot_state_snapshot_callbacks = autoutil.bot_state_snapshot_callbacks or {};
function autoutil.on_bot_state_snapshot(cb)
    table.insert(autoutil.bot_state_snapshot_callbacks, cb);
end

-- Fire the HTTP fetch for the given primary's snapshot, decode JSON, and
-- fan out to registered callbacks. Falls through silently when:
--   * No primary name available (Ashita party not populated yet).
--   * 404 — server hasn't published a snapshot for this primary yet (e.g.
--     fresh boot before the first onBotTick). Caller can retry later.
--   * JSON decode fails — log it, drop the response.
-- Re-firing while a request is in flight is a silent no-op to avoid
-- multiple addons stampeding on unlock.
function autoutil.fetch_bot_state()
    if autoutil.bot_state_inflight then return; end
    local party = AshitaCore:GetDataManager():GetParty();
    local primary_name = (party and party:GetMemberName(0)) or '';
    if primary_name == '' then return; end

    autoutil.bot_state_inflight = true;
    local http = require('http_client');
    local path = '/bot-state?for=' .. primary_name;
    http.get(path, function(code, body, _, err)
        autoutil.bot_state_inflight = false;
        if code ~= 200 or type(body) ~= 'string' or body == '' then
            -- 404 = no snapshot yet (boot race); silent. Log other failures
            -- since they're more interesting.
            if code ~= 404 then
                autoutil.log(libtag(), string.format(
                    'fetch_bot_state: HTTP %s err=%s', tostring(code), tostring(err)));
            end
            return;
        end
        local json = require('json');
        local ok, parsed = pcall(json.decode, json, body);
        if not ok or type(parsed) ~= 'table' then
            autoutil.log(libtag(), 'fetch_bot_state: JSON decode failed: ' .. tostring(parsed));
            return;
        end
        for _, cb in ipairs(autoutil.bot_state_snapshot_callbacks) do
            local cb_ok, cb_err = pcall(cb, parsed);
            if not cb_ok then
                autoutil.log(libtag(), 'fetch_bot_state cb error: ' .. tostring(cb_err));
            end
        end
    end);
end

-- 0x1A0 BOT_COMMAND: dispatch a one-shot action verb at a single headless. The
-- 64-byte layout matches src/map/packets/c2s/0x1a0_bot_command.h exactly:
--   bytes[1..2]   opcode 0x1A0 (LE)
--   bytes[3..4]   code (Ashita fills)
--   bytes[5..20]  BotName[16]    null-padded
--   bytes[21..28] ActionKind[8]  null-padded ("ma"/"ja"/"ws"/"ra"/"item")
--   bytes[29..60] ActionName[32] null-padded (spell/ability/item/ws name)
--   bytes[61..64] TargetId u32   LE; 0 = self (server resolves to bot)
function autoutil.send_bot_command(botName, actionKind, actionName, targetId)
    local bytes = {};
    for i = 1, 64 do bytes[i] = 0; end
    bytes[1] = 0xA0; bytes[2] = 0x01;            -- opcode 0x1A0 LE
    local function pack_str(str, offset, max_len)
        if str == nil then return end
        local s = str:sub(1, max_len);
        for i = 1, #s do bytes[offset + i - 1] = s:byte(i); end
    end
    pack_str(botName,    5,  16);
    pack_str(actionKind, 21,  8);
    pack_str(actionName, 29, 32);
    local tid = targetId or 0;
    bytes[61] = tid % 256;                    tid = math.floor(tid / 256);
    bytes[62] = tid % 256;                    tid = math.floor(tid / 256);
    bytes[63] = tid % 256;                    tid = math.floor(tid / 256);
    bytes[64] = tid % 256;
    AddOutgoingPacket(0x1A0, bytes);
end

-- Update one of the runtime SC HP-percent thresholds.
--   which: 0 = Start (upperHP),  1 = Stop (lowerHP),  2 = NoMore (rescue/no-MB).
--   value: HP percent, clamped server-side to [0,100].
function autoutil.send_bot_set_sc_threshold(which, value)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = which or 0;
    payload[2] = value or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetScThreshold, payload);
end

-- Update one bot's SATA scheduling mode. 0 = Combined (SA→TA→WS in one combo),
-- 1 = Split (alternate SA and TA across WSes). botName must belong to the
-- requesting primary (server rejects otherwise). Layout matches SET_BOT_MODE:
-- char Name[11] + uint8 Mode in the 12-byte 0x176 payload.
function autoutil.send_bot_set_sata_mode(botName, mode)
    if botName == nil or botName == '' then return; end
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    local s = botName:sub(1, 11);
    for i = 1, #s do payload[i] = s:byte(i); end
    payload[12] = mode or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetSataMode, payload);
end

-- Casual-nuke rotation for a named bot. value: 1..6 spells, 0 = All.
function autoutil.send_bot_set_casual_nuke_rotation(botName, value)
    if botName == nil or botName == '' then return; end
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    local s = botName:sub(1, 11);
    for i = 1, #s do payload[i] = s:byte(i); end
    payload[12] = value or 3;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetCasualNukeRotation, payload);
end

-- Casual-nuke MB-spell mode for a named bot. mode: 0 = exclude, 1 = include.
function autoutil.send_bot_set_casual_nuke_mb_mode(botName, mode)
    if botName == nil or botName == '' then return; end
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    local s = botName:sub(1, 11);
    for i = 1, #s do payload[i] = s:byte(i); end
    payload[12] = mode or 1;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetCasualNukeMbMode, payload);
end

-- Per-bot THF utility-RA cadence in seconds. Wire = char Name[10..11] +
-- DelaySec[12]. The 0-second sentinel is the picker's "Off" — server-side
-- role_melee.should_ra skips RA entirely at 0. Eligibility (job + level)
-- is enforced client-side before the dropdown renders.
function autoutil.send_bot_set_thf_ra_delay(botName, delaySec)
    if botName == nil or botName == '' then return; end
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    local s = botName:sub(1, 11);
    for i = 1, #s do payload[i] = s:byte(i); end
    -- Clamp to 0..240 to match the server-side guard.
    local d = delaySec or 15;
    if d < 0 then d = 0; end
    if d > 240 then d = 240; end
    payload[12] = d;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetThfRaDelay, payload);
end

-- Per-bot BRD song-roster override (#252). Uses the bumped 32-byte
-- 0x176 payload — older 12-byte payload couldn't fit Name[10] + 4×uint16.
-- slot0..slot3 are spell IDs in SLOT_ORDER (front_minuet, front_madrigal,
-- back_ballad_a, back_ballad_b). 0 = "auto" sentinel — server-side
-- role_brd falls through to best_tier for that slot.
function autoutil.send_brd_song_roster(botName, slot0, slot1, slot2, slot3)
    if botName == nil or botName == '' then return; end
    local payload = {};
    for i = 1, 32 do payload[i] = 0; end
    local s = botName:sub(1, 10);
    for i = 1, #s do payload[i] = s:byte(i); end
    -- payload[11..12] reserved/padding
    -- 4 uint16 spell IDs at offsets 13/14, 15/16, 17/18, 19/20 (1-indexed)
    local function setU16(idx, v)
        v = v or 0;
        payload[idx]     = v % 256;
        payload[idx + 1] = math.floor(v / 256) % 256;
    end
    setU16(13, slot0);
    setU16(15, slot1);
    setU16(17, slot2);
    setU16(19, slot3);
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetBrdSongRoster, payload);
end

-- Per-bot SMN avatar dropdown selection (#220). avatarSpellId is the
-- summon spell ID (296 = Carbuncle default). 0 = "auto" sentinel
-- (server-side role_smn falls back to Carbuncle).
function autoutil.send_smn_avatar(botName, avatarSpellId)
    if botName == nil or botName == '' then return; end
    local payload = {};
    for i = 1, 32 do payload[i] = 0; end
    local s = botName:sub(1, 10);
    for i = 1, #s do payload[i] = s:byte(i); end
    -- payload[11..12] reserved/padding
    -- uint16 avatar spell ID at offsets 13/14 (1-indexed)
    local v = avatarSpellId or 0;
    payload[13] = v % 256;
    payload[14] = math.floor(v / 256) % 256;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetSmnAvatar, payload);
end

-- Role AI policy — set one mode toggle for one (role, type) pair.
-- Wire = uint8 Role + uint8 Type + uint8 Mode (rest padded with 0).
-- Indices map through autoutil.RoleAiRole / .RoleAiType / .RoleAiMode.
function autoutil.send_role_ai_set_mode(roleIdx, typeIdx, modeIdx)
    if roleIdx == nil or typeIdx == nil or modeIdx == nil then return; end
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = roleIdx;
    payload[2] = typeIdx;
    payload[3] = modeIdx;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetRoleAiMode, payload);
end

-- Role AI policy — set one per-status checkbox under a role's Status section.
-- Wire = uint8 Role + uint8 StatusKey + uint8 On (1/0). statusKey indexes
-- into autoutil.RoleAiStatusList (mirrors server's role_policy.STATUS_LIST).
function autoutil.send_role_ai_set_status_flag(roleIdx, statusKey, on)
    if roleIdx == nil or statusKey == nil then return; end
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = roleIdx;
    payload[2] = statusKey;
    payload[3] = (on and 1) or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetRoleAiStatusFlag, payload);
end

-- Update one bot's role_heal scope. 0 = Party (default), 1 = AllianceAssist
-- (party + BLM-tier fallback on alliance), 2 = AllianceMain (WHM-tier + -na
-- widened to alliance). Same wire layout as SetSataMode.
function autoutil.send_bot_set_heal_scope(botName, mode)
    if botName == nil or botName == '' then return; end
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    local s = botName:sub(1, 11);
    for i = 1, #s do payload[i] = s:byte(i); end
    payload[12] = mode or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetHealScope, payload);
end

-- Tank Nudge: snap one bot ±1y along the vector toward its currently engaged
-- target. direction: 0 = forward (toward), 1 = backward (away). Silent no-op
-- server-side if the bot isn't engaged or isn't owned by primary.
function autoutil.send_bot_tank_nudge(botName, direction)
    if botName == nil or botName == '' then return; end
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    local s = botName:sub(1, 11);
    for i = 1, #s do payload[i] = s:byte(i); end
    payload[12] = direction or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.TankNudge, payload);
end

-- Tank Walk To Me: snap one bot to the primary's current xyz. Used to recover
-- a stuck tank or pass aggro at primary's feet. Silent no-op server-side if
-- the bot isn't owned by primary or isn't in the same zone.
function autoutil.send_bot_tank_walk_to_me(botName)
    if botName == nil or botName == '' then return; end
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    local s = botName:sub(1, 11);
    for i = 1, #s do payload[i] = s:byte(i); end
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.TankWalkToMe, payload);
end

-- Puller Start/Stop. Gates only the IDLE→SCOUTING transition — a pull
-- already in flight finishes naturally. Fresh set_puller assignments
-- default to paused, so user hits Start explicitly.
function autoutil.send_bot_set_puller_paused(paused)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = paused and 1 or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetPullerPaused, payload);
end

-- Designate (or clear) the alliance puller. Empty botName clears.
function autoutil.send_bot_set_puller(botName)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    if botName ~= nil and botName ~= '' then
        local s = botName:sub(1, 11);
        for i = 1, #s do payload[i] = s:byte(i); end
    end
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetPuller, payload);
end

-- Set the puller scan range in yalms. Server clamps to [5, 250].
function autoutil.send_bot_set_puller_range(rangeYalms)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = rangeYalms or 50;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetPullerRange, payload);
end

-- Set puller difficulty window. minCon/maxCon are EXPCHAIN ints
-- (0=TW, 1=EP, 2=DC, 3=EM, 4=T, 5=VT, 6=IT). Server clamps to [0,6] and
-- swaps if reversed.
function autoutil.send_bot_set_puller_con_range(minCon, maxCon)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = minCon or 1;
    payload[2] = maxCon or 6;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetPullerConRange, payload);
end

-- Set the minimum heal-role MP% (0..100) before the puller resumes pulling.
-- Server clamps to [0, 100].
function autoutil.send_bot_set_puller_resume_mpp(mpp)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = mpp or 60;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetPullerResumeMpp, payload);
end

-- Ask the server to scan within 255y of the camp anchor (falls back to primary
-- position if unanchored) and reply with top-20 mob names by count via the
-- S2C 0x1A4 PULLER_NEARBY_NAMES packet.
function autoutil.send_bot_request_puller_names()
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.RequestPullerNames, {});
end

-- Set the puller's allowed mob-name filter. names is a Lua array of strings
-- (UTF-8, ≤23 chars each), max 16 entries. Empty list means "no filter"
-- (any name passes). Sent as a dedicated C2S 0x1A2 packet rather than 0x176
-- because 16×24 bytes doesn't fit the 12-byte 0x176 payload.
function autoutil.send_bot_set_puller_name_filter(names)
    names = names or {};
    local count = math.min(#names, 16);

    -- Wire layout: 4 header + Count(1) + _pad(3) + Names[16][24] = 392 bytes.
    -- Server PacketSize[0x1A2] = 0xC4 = 392 bytes (size byte = bytes/2).
    local total = 392;
    local bytes = {};
    for i = 1, total do bytes[i] = 0; end
    bytes[1] = 0xA2; bytes[2] = 0x01;  -- opcode 0x1A2 LE
    -- bytes[3..4] sync (Ashita fills)

    bytes[5] = count;
    -- bytes[6..8] are _pad

    local base = 9;  -- first Name slot
    for i = 1, count do
        pack_name(bytes, base + (i - 1) * 24, names[i], 24);
    end

    AddOutgoingPacket(0x1A2, bytes);
end

-- Parse incoming S2C 0x1A4 PULLER_NEARBY_NAMES. Wire layout (after 4-byte
-- ashita header):
--   [5]   Count (1 byte)
--   [6-8] Padding
--   [9..]  Entries[20] of { Name[24], Count uint16 } = 26 bytes each
--          (1 byte trail pad inside Entry struct rounds to 26)
-- Returns a sorted array of { name = "...", count = N }, or nil on bad size.
function autoutil.check_for_puller_nearby_names(id, size, data)
    if id ~= 0x1A4 then return nil; end
    if size < 12 then return nil; end

    local count = data:byte(0x05) or 0;
    if count > 20 then count = 20; end

    local list = {};
    local base = 0x09;  -- first Entry byte
    -- Entry layout from 0x1a4_puller_nearby_names.h: char Name[16] + uint16
    -- Count. Name ends at 16 (already 2-aligned), Count starts at 16,
    -- sizeof(Entry) == 18, no trailing pad. (Was Name[24]/stride=26 originally;
    -- shrunk because 20×26 + header overflowed PACKET_SIZE 511. FFXI names
    -- cap at 15 chars so 16 is sufficient.)
    local stride = 18;
    for i = 0, count - 1 do
        local off  = base + i * stride;
        local name = data:sub(off, off + 15):gsub('%z.*$', '');
        local lo   = data:byte(off + 16) or 0;
        local hi   = data:byte(off + 17) or 0;
        local n    = lo + hi * 256;
        if name ~= '' then
            table.insert(list, { name = name, count = n });
        end
    end
    return list;
end

-- Hot-swap the active alliance config: server despawns current bots (with full
-- save) then respawns from the named config. Brief flicker on screen.
function autoutil.send_bot_update_config(configName)
    if configName == nil or configName == '' then
        autoutil.log(libtag(), 'send_bot_update_config: empty configName');
        return;
    end
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    local s = configName:sub(1, 11);
    for i = 1, #s do payload[i] = s:byte(i); end
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.UpdateConfig, payload);
end

-- Server-side: set m_botMode on every linked headless without despawning.
-- mode: 0=Off (Stop Actions — bots stand idle), 1=CombatOnly, 2=Full (Start
-- Actions — normal AI). Distinct from despawn (which destroys sessions).
function autoutil.send_bot_set_alliance_mode(mode)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = mode or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetAllianceMode, payload);
end

function autoutil.send_bot_set_mode(charName, mode)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    local s = (charName or ''):sub(1, 11);
    for i = 1, #s do payload[i] = s:byte(i); end
    payload[12] = mode or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetBotMode, payload);
end

function autoutil.send_bot_set_role(charName, role)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    local s = (charName or ''):sub(1, 10);
    for i = 1, #s do payload[i] = s:byte(i); end
    payload[11] = role or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetRole, payload);
end

-- Set the primary's formation. kind = 0 (battle) or 1 (walking). name is
-- the formation identifier (e.g. "default", "camp", "column", "role").
function autoutil.send_bot_set_formation(kind, name)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = kind or 0;
    local s = (name or ''):sub(1, 11);
    for i = 1, #s do payload[i + 1] = s:byte(i); end
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetFormation, payload);
end

-- Alliance-wide headless mob-aggro toggle. mode is the numeric wire value
-- (0=Off / 1=Full). Replaces the prior singleplayer.HEADLESS_MOB_AGGRO
-- static setting; the addon picker sits alongside the formation pickers
-- in the Quick Menu / Controls tab so users can flip hard mode at runtime.
function autoutil.send_bot_set_aggro_mode(mode)
    local payload = {};
    for i = 1, 12 do payload[i] = 0; end
    payload[1] = mode or 0;
    autoutil.send_headless_command(autoutil.HeadlessNs.Autobots, autoutil.AutobotsSubcmd.SetAggroMode, payload);
end

-----------------------------------
-- 0x179 HEADLESS_EVENT receive: server-pushed log messages and broadcasts.
-- Payload layout per EventType:
--   0x01 LOG_MESSAGE: Tag[16] + Message[44]
-----------------------------------
function autoutil.check_for_headless_event(id, size, data)
    if id ~= 0x179 then return; end
    local eventType = data:byte(0x05);  -- offset 4 (header) + 0 = bytes[5] 1-indexed
    if eventType == 0x01 then
        local tag = data:sub(0x09, 0x09 + 15):gsub('%z', '');
        local msg = data:sub(0x19, 0x19 + 43):gsub('%z', '');
        autoutil.log(tag, msg);
    end
    -- Other event types added as Phase 3 roles emit them
end

-- (Config enumeration was sent/received over 0x17A/0x17B chunked packets.
--  Replaced by GET /configs and GET /configs/{cat} on the loopback HTTP
--  server — see singleplayer/client/addons/libs/http_client.lua. The
--  packet pipeline + send_list_configs / on_config_list / check_for_config_list
--  / server_configs cache are all deleted.)

-----------------------------------
-- 0x17D USE_FOOD_CONFIG send: server reads config/food/<name>.json and fires
-- bot:useItem on each linked headless + the primary if listed. Single
-- round-trip replaces the upstream cross-client /mst /item chain (which
-- dead-ended for headless chars since they have no client to receive).
-----------------------------------
function autoutil.send_use_food_config(configName)
    if configName == nil or configName == '' then
        autoutil.log(libtag(), 'send_use_food_config: empty config name');
        return;
    end
    -- 36 byte packet: 4 header + 32 ConfigName
    local bytes = {};
    for i = 1, 36 do bytes[i] = 0; end
    bytes[1] = 0x7d; bytes[2] = 0x01;  -- opcode 0x17D LE
    pack_name(bytes, 5, configName, 32);
    AddOutgoingPacket(0x17d, bytes);
end

-----------------------------------
-- 0x178 SET_LOT_ASSIGNMENT — toggle a single group on/off for one alliance
-- member's runtime autolot state. Spawned-only on the server side; if the
-- named char isn't a live PC at receive time, the server silently no-ops.
-- Payload: char CharName[12] + char GroupName[12] + uint8 On + uint8 Pad[3].
-----------------------------------
function autoutil.send_set_lot_assignment(charName, groupName, on)
    if charName == nil or charName == '' or groupName == nil or groupName == '' then
        return;
    end
    -- 32 byte packet: 4 header + 12 CharName + 12 GroupName + 1 On + 3 pad
    local bytes = {};
    for i = 1, 32 do bytes[i] = 0; end
    bytes[1] = 0x78; bytes[2] = 0x01;  -- opcode 0x178 LE
    pack_name(bytes, 5,  charName,  12);
    pack_name(bytes, 17, groupName, 12);
    bytes[29] = (on and 1) or 0;
    AddOutgoingPacket(0x178, bytes);
end

-- (Config CRUD over 0x17E/0x17F (get), 0x180/0x181 (set subtree),
--  0x182/0x183 (create) was deleted. All migrated to loopback HTTP — see
--  libs/http_client.lua. The chunked-reassembly buffers, callback
--  registries, and server_config_content cache are all gone.)

-----------------------------------
-- 0x184 LOT_LIST_ACTION send — mutate the autolot lot-list table:
--   action = 1 ADD   : add botName to (primary, itemId)
--   action = 2 REMOVE: drop botName from (primary, itemId)
--   action = 3 CLEAR : clear the entire list for itemId
-- No reply packet; server applies immediately.
-----------------------------------
function autoutil.send_lot_list_action(action, itemId, botName)
    if action == nil or itemId == nil or itemId == 0 then
        autoutil.log('AutoLot', 'send_lot_list_action: missing field');
        return;
    end
    -- 28 byte packet: 4 header + 1 Action + 3 Padding + 4 ItemId + 16 BotName
    local bytes = {};
    for i = 1, 28 do bytes[i] = 0; end
    bytes[1] = 0x84; bytes[2] = 0x01;             -- opcode 0x184 LE
    bytes[5] = action;                             -- Action @ 0x04
    -- ItemId @ 0x08 (LE u32)
    bytes[9]  = itemId % 256;
    bytes[10] = math.floor(itemId / 256) % 256;
    bytes[11] = math.floor(itemId / 65536) % 256;
    bytes[12] = math.floor(itemId / 16777216) % 256;
    -- BotName @ 0x0C (15 chars + NUL)
    if botName ~= nil then
        local b = botName:sub(1, 15);
        for i = 1, #b do bytes[12 + i] = b:byte(i) end
    end
    AddOutgoingPacket(0x184, bytes);
end

-- Optimistic client mirror of each item's lot list (itemId -> { name=true }).
-- The server applies 0x184 immediately and sends no reply, so both autolot tabs
-- (pool + recent) share this table to render persistent membership — open shows
-- who's on the list; unchecking removes. Not authoritative across an addon
-- reload, which matches the server's in-memory, despawn-cleared model.
autoutil.lot_list_members = autoutil.lot_list_members or {};

-- Fresh { name=true } copy of the tracked membership for itemId (popup seed).
function autoutil.lot_list_get(itemId)
    local out = {};
    for nm, on in pairs(autoutil.lot_list_members[itemId] or {}) do
        if on then out[nm] = true; end
    end
    return out;
end

-- Diff `selected` ({ name=true }) against the tracked membership: send ADD (1)
-- for newly-checked bots, REMOVE (2) for ones now unchecked, then store the set.
function autoutil.lot_list_apply(itemId, selected)
    if itemId == nil or itemId == 0 then return; end
    local prev = autoutil.lot_list_members[itemId] or {};
    local now  = {};
    for nm, picked in pairs(selected or {}) do
        if picked then
            now[nm] = true;
            if not prev[nm] then autoutil.send_lot_list_action(1, itemId, nm); end
        end
    end
    for nm, was in pairs(prev) do
        if was and not now[nm] then autoutil.send_lot_list_action(2, itemId, nm); end
    end
    autoutil.lot_list_members[itemId] = now;
end

-----------------------------------
-- Char roster — server's `chars` table, sorted by name. Returned as a
-- list of names + a parallel name -> mainjob byte map.
--
-- Replaces the chunked 0x18D LIST_CHARS / 0x18E CHARS_LIST packet pair
-- (retired 2026-06-20). Now fetched via GET /chars over the loopback HTTP
-- server (see src/map/singleplayer/config_http_server.cpp). Response is
-- a JSON array: [{"name":"Brutus","mjob":8}, ...].
--
-- API preserved verbatim from the old packet path so addon call sites
-- don't need to change beyond bootstrap dispatch:
--   * autoutil.char_names           - list of names (final state cached)
--   * autoutil.char_jobs            - name -> mainjob byte (DRK = 8; 0 = unknown)
--   * autoutil.char_names_final     - true once a fetch has completed
--   * autoutil.on_char_names(cb)    - subscribe; fires immediately if cached
--   * autoutil.fetch_chars()        - kick a refresh (formerly send_list_chars)
-----------------------------------
autoutil.char_names           = autoutil.char_names           or {};
autoutil.char_jobs            = autoutil.char_jobs            or {};  -- name -> mainjob byte (DRK = 8); 0 = unknown
autoutil.char_names_final     = autoutil.char_names_final     or false;
autoutil.char_names_callbacks = autoutil.char_names_callbacks or {};
-- Guard against concurrent in-flight requests. With sync packets this
-- wasn't an issue (one outgoing packet per call), but HTTP fires a real
-- coroutine and overlapping bootstrap calls would double-up.
autoutil.char_names_inflight  = autoutil.char_names_inflight  or false;

local function on_chars_fetched(parsed)
    autoutil.char_names = {};
    autoutil.char_jobs  = {};
    if type(parsed) == 'table' then
        for _, entry in ipairs(parsed) do
            if type(entry) == 'table' and type(entry.name) == 'string' and entry.name ~= '' then
                table.insert(autoutil.char_names, entry.name);
                autoutil.char_jobs[entry.name] = tonumber(entry.mjob) or 0;
            end
        end
    end
    autoutil.char_names_final    = true;
    autoutil.char_names_inflight = false;
    for _, cb in ipairs(autoutil.char_names_callbacks) do
        local ok, err = pcall(cb, autoutil.char_names);
        if not ok then autoutil.log(libtag(), 'char_names cb error: ' .. tostring(err)); end
    end
    autoutil.char_names_callbacks = {};
end

-- Fetch (or refresh) the char roster. Loopback HTTP, decoded JSON, then
-- subscribed callbacks fire on completion. Re-firing while a request is
-- in flight is a silent no-op so bootstrap callers in multiple addons
-- don't stampede.
function autoutil.fetch_chars()
    if autoutil.char_names_inflight then return; end
    autoutil.char_names_inflight = true;
    -- Local require avoids dragging http_client into addons that never
    -- need a char list (e.g. autowarp).
    local http = require('http_client');
    http.get('/chars', function(code, body, _, err)
        if code == 200 and type(body) == 'string' and body ~= '' then
            local json = require('json');
            local ok, parsed = pcall(json.decode, json, body);
            if ok then
                on_chars_fetched(parsed);
                return;
            end
            autoutil.log(libtag(), 'fetch_chars: JSON decode failed: ' .. tostring(parsed));
        else
            autoutil.log(libtag(), string.format('fetch_chars: HTTP %s err=%s',
                tostring(code), tostring(err)));
        end
        -- Failure path: release the in-flight latch so the next bootstrap
        -- attempt can retry. Leave callbacks queued for that retry.
        autoutil.char_names_inflight = false;
    end);
end

function autoutil.on_char_names(callback)
    if autoutil.char_names_final then
        callback(autoutil.char_names);
        return;
    end
    table.insert(autoutil.char_names_callbacks, callback);
end

-----------------------------------
-- 0x193 LIST_AUTOSKILL request — asks the server to re-push 0x192 for every
-- active override owned by us. Used by autobots on unlock so the AutoSkill
-- tab + "Skill:" line in Active Config Info start synced even when overrides
-- predate the addon opening.
-----------------------------------
function autoutil.send_list_autoskill()
    local bytes = {};
    for i = 1, 4 do bytes[i] = 0; end
    bytes[1] = 0x93; bytes[2] = 0x01;  -- opcode 0x193 LE
    AddOutgoingPacket(0x193, bytes);
end

-----------------------------------
-- 0x192 AUTOSKILL_STATE receive — server push after every override change.
-- Consumed by the autobots AutoSkill tab (row mirror) and the autobots
-- Active Config Info "Skill:" line so neither has to poll. Cache keyed by
-- char name; mode follows the same enum as the C2S 0x191 packet
-- (0=Off, 1=RA, 2=Magic).
-----------------------------------
autoutil.autoskill_state = autoutil.autoskill_state or {};
autoutil.autoskill_state_callbacks = autoutil.autoskill_state_callbacks or {};

function autoutil.on_autoskill_state(callback)
    table.insert(autoutil.autoskill_state_callbacks, callback);
end

function autoutil.check_for_autoskill_state(id, size, data)
    if id ~= 0x192 then return; end
    local name = data:sub(0x05, 0x05 + 15):gsub('%z', '');
    local mode = data:byte(0x15);
    if name == '' then return; end
    if mode == 0 then
        autoutil.autoskill_state[name] = nil;
    else
        autoutil.autoskill_state[name] = mode;
    end
    for _, cb in ipairs(autoutil.autoskill_state_callbacks) do
        local ok, err = pcall(cb, name, mode);
        if not ok then autoutil.log(libtag(), 'autoskill_state cb error: ' .. tostring(err)); end
    end
end

-----------------------------------
-- 0x18B LIST_BOT_SPELLS send → 0x18C BOT_SPELLS_LIST chunks.
-- Per-bot spell roster, filtered by group. Server walks the target's
-- charutils::hasSpell within SPELLGROUP_TRUST (groupFilter=1) or every other
-- magic spell group (groupFilter=0) and replies with { spell_id, name }
-- pairs. Cache keyed by (botName, groupFilter).
--
-- autoutil.bot_spells[botName][groupFilter] = {
--     entries   = { { id = u16, name = string }, ... }  -- sorted by name
--     final     = bool,
--     callbacks = { fn, ... },
-- }
-----------------------------------
autoutil.bot_spells = autoutil.bot_spells or {};

local function _bot_spells_slot(name, group)
    autoutil.bot_spells[name] = autoutil.bot_spells[name] or {};
    autoutil.bot_spells[name][group] = autoutil.bot_spells[name][group] or {
        entries = {}, final = false, callbacks = {},
    };
    return autoutil.bot_spells[name][group];
end

-- groupFilter: 0 = magic non-trust, 1 = trust only
function autoutil.send_list_bot_spells(botName, groupFilter)
    if botName == nil or botName == '' then return; end
    -- 24-byte packet: 4 header + 16 BotName + 1 GroupFilter + 3 Padding
    local bytes = {};
    for i = 1, 24 do bytes[i] = 0; end
    bytes[1] = 0x8B; bytes[2] = 0x01;             -- opcode 0x18B LE
    pack_name(bytes, 5, botName, 16);
    bytes[21] = groupFilter or 0;
    AddOutgoingPacket(0x18b, bytes);
end

-- Register a one-shot callback that fires once the final chunk for this
-- (name, group) arrives. Fires immediately with the cached list when already
-- final.
function autoutil.on_bot_spells(botName, groupFilter, callback)
    local slot = _bot_spells_slot(botName, groupFilter);
    if slot.final then
        callback(slot.entries);
        return;
    end
    table.insert(slot.callbacks, callback);
end

function autoutil.check_for_bot_spells_list(id, size, data)
    if id ~= 0x18c then return; end

    local botName     = data:sub(0x05, 0x05 + 15):gsub('%z', '');
    local groupFilter = data:byte(0x15);
    local isFinal     = data:byte(0x16);
    local count       = data:byte(0x17);

    local slot = _bot_spells_slot(botName, groupFilter);

    -- A new first chunk after a previously-final response = fresh refresh.
    if slot.final then
        slot.entries = {};
        slot.final   = false;
    end

    -- Entries[14]{SpellId[u16] + Name[30] = 32 bytes per entry}, starting at 0x19.
    local base = 0x19;
    for i = 0, math.min(count, 14) - 1 do
        local off  = base + i * 32;
        local id   = data:byte(off) + data:byte(off + 1) * 256;
        local name = data:sub(off + 2, off + 31):gsub('%z', '');
        if name ~= '' then table.insert(slot.entries, { id = id, name = name }); end
    end

    if isFinal == 1 then
        table.sort(slot.entries, function(a, b) return a.name < b.name; end);
        slot.final = true;
        for _, cb in ipairs(slot.callbacks) do
            local ok, err = pcall(cb, slot.entries);
            if not ok then autoutil.log(libtag(), 'bot_spells cb error: ' .. tostring(err)); end
        end
        slot.callbacks = {};
    end
end

-- (0x189 SET_CONFIG_FILE / 0x18A SET_CONFIG_RESULT and
--  0x187 DELETE_CONFIG_FILE / 0x188 DELETE_CONFIG_RESULT chunked
--  pipelines were deleted. PUT /configs/{cat}/{name} and
--  DELETE /configs/{cat}/{name} on the loopback HTTP server replace them.)

local _last_enmity_print = 0;

local function enmity_job_abbrev(server_id)
    local name = autoutil.get_entity_name(server_id);
    if name then
        local ji = autoutil.get_member_job(name);
        if ji and autoutil.jobs[ji] then return autoutil.jobs[ji]; end
        return name:sub(1, 3):upper();
    end
    return '???';
end

-- Handler for 0x167 enmity packet. Throttled to once per 5s. Entries are pre-sorted by CE+VE desc.
-- Format per entry: JOB:CE/VE, packed up to 100 chars per line.
function autoutil.handle_enmity_packet(id, size, data)
    local now = os.time();
    if now - _last_enmity_print < 5 then return; end
    _last_enmity_print = now;

    local mob_id           = struct.unpack('I', data, 0x04 + 1);
    local battle_target_id = struct.unpack('I', data, 0x08 + 1);
    local entry_count      = struct.unpack('B', data, 0x0C + 1);

    local mob_name   = autoutil.get_entity_name(mob_id) or string.format('0x%08X', mob_id);
    local tgt_abbrev = enmity_job_abbrev(battle_target_id);
    autoutil.log('Enmity', string.format('mob=%s tgt=%s entries=%d', mob_name, tgt_abbrev, entry_count));

    local line = '';
    for i = 0, entry_count - 1 do
        local base      = 0x10 + i * 12;
        local entity_id = struct.unpack('I', data, base + 1);
        local ce        = struct.unpack('i', data, base + 4 + 1);
        local ve        = struct.unpack('i', data, base + 8 + 1);
        local entry     = string.format('%s:%d/%d', enmity_job_abbrev(entity_id), ce, ve);
        if #line == 0 then
            line = entry;
        elseif #line + 1 + #entry > 100 then
            autoutil.log('Enmity', line);
            line = entry;
        else
            line = line .. ' ' .. entry;
        end
    end
    if #line > 0 then autoutil.log('Enmity', line); end
end

-- ============================================================
-- Instance enter helper (0x16A custom C2S)
-- ============================================================

local INSTANCE_ENTER_OPCODE = 0x16A;

-- 0x16A packet layout (296 bytes) — server auto-detects which instance type
-- the sender is currently in (BCNM / Dynamis / INSTANCED) and dispatches:
--   header[4]
--   subcmd  @ 0x04  (0=PARTY, 1=ALLIANCE, 2=SPECIFIC)
--   count   @ 0x05  (only used by SPECIFIC)
--   pad[2]  @ 0x06
--   names[18][16] @ 0x08
-- Server uses the names list for subcmd=2; party/alliance subcmds ignore it.
-- Kept around as send_battlefield_enter alias for backwards compatibility
-- with any addon code that hasn't been renamed yet.
function autoutil.send_instance_enter(subcmd, names)
    local bytes = {};
    for i = 1, 296 do bytes[i] = 0; end
    bytes[1] = 0x6A; bytes[2] = 0x01; -- 0x16A LE; Ashita fills size bits
    bytes[5] = subcmd;
    if subcmd == 2 and type(names) == 'table' then
        local n = math.min(#names, 18);
        bytes[6] = n;
        for i = 1, n do
            local nm = (names[i] or ''):sub(1, 15);
            local base = 9 + (i - 1) * 16;  -- 1-indexed Lua: 0x08 + offset
            for k = 1, #nm do
                bytes[base + k - 1] = nm:byte(k);
            end
        end
    end
    AddOutgoingPacket(INSTANCE_ENTER_OPCODE, bytes);
end
autoutil.send_battlefield_enter = autoutil.send_instance_enter;

-----------------------------------
-- 0x185 LIST_ALLIANCE_PCS send → 0x186 ALLIANCE_PC_LIST receive.
-- The server is the authoritative source for "who's actually a PC in my
-- alliance" — naturally excludes trusts since alliance traversal only walks
-- CCharEntity members. Addon caches the latest list at autoutil.alliance_pcs
-- as a list of { name, party } entries.
-----------------------------------
autoutil.alliance_pcs = autoutil.alliance_pcs or {};

function autoutil.send_list_alliance_pcs()
    -- 4 byte header only (no payload).
    local bytes = {};
    for i = 1, 4 do bytes[i] = 0; end
    bytes[1] = 0x85; bytes[2] = 0x01;  -- opcode 0x185 LE
    AddOutgoingPacket(0x185, bytes);
end

-- 0x186 ALLIANCE_PC_LIST receive. Single-packet (alliance maxes at 18 members).
--   header[4]
--   Count   @ 0x04
--   Pad[3]  @ 0x05
--   Entries @ 0x08 : per-entry { Name[15], Party[1] }, 16 bytes each, up to 18
-- 0x191 PARTY_STATUS — periodic per-party status push from autostatus.lua.
-- Fan-out via registered callbacks; status_tab.lua subscribes on require.
autoutil.party_status_callbacks = autoutil.party_status_callbacks or {};

function autoutil.on_party_status(cb)
    table.insert(autoutil.party_status_callbacks, cb);
end

-- 0x191 layout (offsets relative to packet body, body starts at 0x05):
--   PartyNumber  @ 0x04
--   MemberCount  @ 0x05
--   Padding      @ 0x06 .. 0x07
--   Entries      @ 0x08 : 6 × {
--     Name[16],            -- offsets 0..15
--     EffectCount,         -- 16
--     Race, Face, Pad,     -- 17, 18, 19
--     ExpCurrent (u32),    -- 20..23
--     ExpToNext  (u32),    -- 24..27
--     EffectIds[20] (u16), -- 28..67
--   }
-- Per entry: 68 bytes. Total wire: 4 hdr + 4 (partyNum/count/pad) + 6*68 = 416.
function autoutil.check_for_party_status(id, size, data)
    if id ~= 0x191 then return; end
    local partyNumber = data:byte(0x05);
    local memberCount = data:byte(0x06);
    local members = {};
    local entryBase = 0x09;  -- offset 0x08 in PacketData + 1 for 1-indexed sub()
    local stride    = 68;
    local function u32(off)
        local b0 = data:byte(off);
        local b1 = data:byte(off + 1);
        local b2 = data:byte(off + 2);
        local b3 = data:byte(off + 3);
        return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
    end
    for i = 0, math.min(memberCount, 6) - 1 do
        local base       = entryBase + i * stride;
        local name       = data:sub(base, base + 15):gsub('%z+$', ''):gsub('^%z+', '');
        local count      = data:byte(base + 16);
        local race       = data:byte(base + 17);
        local face       = data:byte(base + 18);
        local expCurrent = u32(base + 20);
        local expToNext  = u32(base + 24);
        local effects    = {};
        for e = 0, math.min(count, 20) - 1 do
            local eo = base + 28 + e * 2;
            local lo = data:byte(eo);
            local hi = data:byte(eo + 1);
            table.insert(effects, lo + hi * 256);
        end
        if name and name ~= '' then
            table.insert(members, {
                name       = name,
                race       = race,
                face       = face,
                expCurrent = expCurrent,
                expToNext  = expToNext,
                effects    = effects,
            });
        end
    end
    for _, cb in ipairs(autoutil.party_status_callbacks) do
        local ok, err = pcall(cb, partyNumber, members);
        if not ok then autoutil.log(libtag(), 'party_status cb error: ' .. tostring(err)); end
    end
end

function autoutil.check_for_alliance_pc_list(id, size, data)
    if id ~= 0x186 then return; end
    local count = data:byte(0x05);
    local out = {};
    for i = 0, math.min(count, 18) - 1 do
        local base = 0x09 + i * 16;
        local nm   = data:sub(base, base + 14):gsub('%z', '');
        local pn   = data:byte(base + 15);
        if nm ~= '' then table.insert(out, { name = nm, party = pn }); end
    end
    autoutil.alliance_pcs = out;
end

-- ============================================================
-- AutoMog change-job (0x19C / 0x19D / 0x19E / 0x19F)
-- ============================================================

local AUTOMOG_CHANGE_JOB_OPCODE   = 0x19C;
local AUTOMOG_CHANGE_JOB_RESULT   = 0x19D;
local AUTOMOG_GET_JOB_INFO_OPCODE = 0x19E;
local AUTOMOG_JOB_INFO_RESULT     = 0x19F;

-- Per-char job info cache, keyed by char name.
-- Entry: { current_mj, current_sj, unlocked_mask, levels = { [jobId] = lvl } }
autoutil.char_job_info = autoutil.char_job_info or {};

-- Last change-job status (read by automog UI to surface errors).
autoutil.last_change_job_status = nil;

-- 0x19C send. flags bit 0 = change MJ, bit 1 = change SJ.
function autoutil.send_change_job(target_name, new_mj, new_sj, flags)
    local fmt  = 'HH' .. string.rep('B', 16) .. 'BBBB';
    local args = { AUTOMOG_CHANGE_JOB_OPCODE, 0 };
    local s    = (target_name or ''):sub(1, 15);
    for i = 1, 16 do args[#args + 1] = (i <= #s) and string.byte(s, i) or 0; end
    args[#args + 1] = new_mj or 0;
    args[#args + 1] = new_sj or 0;
    args[#args + 1] = flags or 0;
    args[#args + 1] = 0;  -- padding
    AddOutgoingPacket(AUTOMOG_CHANGE_JOB_OPCODE, struct.pack(fmt, unpack(args)):totable());
end

-- 0x19E send. Server replies with 0x19F.
function autoutil.send_get_job_info(target_name)
    local fmt  = 'HH' .. string.rep('B', 16);
    local args = { AUTOMOG_GET_JOB_INFO_OPCODE, 0 };
    local s    = (target_name or ''):sub(1, 15);
    for i = 1, 16 do args[#args + 1] = (i <= #s) and string.byte(s, i) or 0; end
    AddOutgoingPacket(AUTOMOG_GET_JOB_INFO_OPCODE, struct.pack(fmt, unpack(args)):totable());
end

-- 0x19F receive. Payload after header (offsets 1-indexed for :byte()):
--   TargetCharName[16]  @ 0x05  (bytes 5..20)
--   Status              @ 0x15  (byte 21)
--   CurrentMJob         @ 0x16  (byte 22)
--   CurrentSJob         @ 0x17  (byte 23)
--   padding             @ 0x18
--   UnlockedMask (LE)   @ 0x19..0x1C
--   JobLevels[24]       @ 0x1D..0x34  (bytes 29..52)
--   CurrentRace         @ 0x35        (byte 53)
--   CurrentFace         @ 0x36        (byte 54)
--   CurrentSize         @ 0x37        (byte 55)
function autoutil.check_for_job_info(id, size, data)
    if id ~= AUTOMOG_JOB_INFO_RESULT then return false; end
    local name   = data:sub(5, 20):gsub('%z', '');
    local status = data:byte(21);
    if name == '' then return false; end
    if status ~= 0 then
        autoutil.char_job_info[name] = nil;
        return false;
    end
    local entry = {
        current_mj    = data:byte(22),
        current_sj    = data:byte(23),
        unlocked_mask = data:byte(25)
                      + data:byte(26) * 0x100
                      + data:byte(27) * 0x10000
                      + data:byte(28) * 0x1000000,
        levels        = {},
        current_race  = data:byte(53) or 0,
        current_face  = data:byte(54) or 0,
        current_size  = data:byte(55) or 0,
    };
    for i = 0, 23 do
        entry.levels[i] = data:byte(29 + i) or 0;
    end
    autoutil.char_job_info[name] = entry;
    return true;
end

function autoutil.check_for_change_job_result(id, size, data)
    if id ~= AUTOMOG_CHANGE_JOB_RESULT then return false; end
    autoutil.last_change_job_status = data:byte(5);
    return true;
end

-- ============================================================
-- AutoMog change-look (0x162 / 0x163) — race/face/size
-- ============================================================

local AUTOMOG_CHANGE_LOOK_OPCODE = 0x162;
local AUTOMOG_CHANGE_LOOK_RESULT = 0x163;

-- Last change-look status (read by automog UI to surface errors).
autoutil.last_change_look_status = nil;

-- 0x162 send. flags bit 0 = change Race, bit 1 = change Face, bit 2 = change Size.
function autoutil.send_change_look(target_name, new_race, new_face, new_size, flags)
    local fmt  = 'HH' .. string.rep('B', 16) .. 'BBBB';
    local args = { AUTOMOG_CHANGE_LOOK_OPCODE, 0 };
    local s    = (target_name or ''):sub(1, 15);
    for i = 1, 16 do args[#args + 1] = (i <= #s) and string.byte(s, i) or 0; end
    args[#args + 1] = new_race or 0;
    args[#args + 1] = new_face or 0;
    args[#args + 1] = new_size or 0;
    args[#args + 1] = flags or 0;
    AddOutgoingPacket(AUTOMOG_CHANGE_LOOK_OPCODE, struct.pack(fmt, unpack(args)):totable());
end

function autoutil.check_for_change_look_result(id, size, data)
    if id ~= AUTOMOG_CHANGE_LOOK_RESULT then return false; end
    autoutil.last_change_look_status = data:byte(5);
    return true;
end

-- ============================================================
-- AutoEquip copy XML (0x1A1 / 0x1A2)
-- ============================================================

local AUTOEQUIP_COPY_XML_OPCODE = 0x1A1;
local AUTOEQUIP_COPY_XML_RESULT = 0x1A2;

-- Last copy-XML status from server, read by autoequip UI for toast/reload.
-- Shape: { dest_name, status } | nil
autoutil.last_copy_xml_result = nil;

function autoutil.send_copy_xml(source_name, dest_name)
    local fmt  = 'HH' .. string.rep('B', 32) .. string.rep('B', 32);
    local args = { AUTOEQUIP_COPY_XML_OPCODE, 0 };
    local src  = (source_name or ''):sub(1, 31);
    local dst  = (dest_name or ''):sub(1, 31);
    for i = 1, 32 do args[#args + 1] = (i <= #src) and string.byte(src, i) or 0; end
    for i = 1, 32 do args[#args + 1] = (i <= #dst) and string.byte(dst, i) or 0; end
    AddOutgoingPacket(AUTOEQUIP_COPY_XML_OPCODE, struct.pack(fmt, unpack(args)):totable());
end

function autoutil.check_for_copy_xml_result(id, size, data)
    if id ~= AUTOEQUIP_COPY_XML_RESULT then return false; end
    local dest = data:sub(5, 36):gsub('%z', '');
    autoutil.last_copy_xml_result = { dest_name = dest, status = data:byte(37) };
    return true;
end

-- ============================================================
-- Instance Enter result (0x1A0) — server's ack for 0x16A.
-- ============================================================

local INSTANCE_ENTER_RESULT = 0x1A0;

-- Last instance-enter result (read by autobots UI to surface success/error).
-- Shape: { status, branch, moved } | nil
autoutil.last_instance_enter_result = nil;

function autoutil.check_for_instance_enter_result(id, size, data)
    if id ~= INSTANCE_ENTER_RESULT then return false; end
    autoutil.last_instance_enter_result = {
        status = data:byte(5),
        branch = data:byte(6),
        moved  = data:byte(7),
    };
    return true;
end

-- ============================================================
-- Warp helpers (0x168 custom C2S)
-- ============================================================

local WARP_OPCODE = 0x168;

function autoutil.send_warp(subcmd, target_name)
    local bytes = {};
    bytes[1] = 0x68; bytes[2] = 0x01; -- 0x168 LE; Ashita fixes size bits
    bytes[3] = 0x00; bytes[4] = 0x00; -- sync = 0
    bytes[5] = subcmd;
    bytes[6] = 0; bytes[7] = 0; bytes[8] = 0;
    for i = 1, 24 do
        bytes[8 + i] = string.byte(target_name, i) or 0;
    end
    AddOutgoingPacket(WARP_OPCODE, bytes);
end

function autoutil.send_warp_self_sync()
    local bytes = {};
    bytes[1] = 0x68; bytes[2] = 0x01;
    bytes[3] = 0x00; bytes[4] = 0x00;
    bytes[5] = 2; -- subcmd=2: echo sender's server position back as WPOS
    for i = 6, 32 do bytes[i] = 0; end
    AddOutgoingPacket(WARP_OPCODE, bytes);
end

-- ====================================================================
-- UI helpers
-- ====================================================================

-- Push a more-opaque window background. Standard imgui dark-theme default
-- for ImGuiCol_WindowBg is ~0.94 alpha, NOT the ~0.30 I assumed in the
-- first attempt - pushing 0.55 there made the panel *more* transparent
-- against Ashita's baseline, which is why the earlier "less transparent"
-- tuning didn't visibly land. 0.95 here is just shy of fully opaque; the
-- FFXI scene still bleeds through faintly so the panel doesn't read like
-- an OS modal, but the text foreground is now the dominant layer for the
-- eye.
--
-- We push BOTH ImGuiCol_WindowBg (regular imgui.Begin windows) and
-- ImGuiCol_PopupBg (BeginPopupModal / BeginPopup) so child editor modals
-- like the food_tab / alliance_tab config dialogs inherit the same look.
--
-- Usage: push immediately BEFORE imgui.Begin, pop AFTER imgui.End. Early-
-- return paths (the standard `if not imgui.Begin(..) then imgui.End(); return; end`
-- pattern) need the matching pop on the early-return branch too.
function autoutil.push_solid_window_bg()
    imgui.PushStyleColor(ImGuiCol_WindowBg, 0.06, 0.06, 0.06, 0.95);
    imgui.PushStyleColor(ImGuiCol_PopupBg,  0.06, 0.06, 0.06, 0.95);
end
function autoutil.pop_solid_window_bg()
    imgui.PopStyleColor(2);
end

-- ----------------------------------------------------------------------
-- section_head(text) — shared section-header render.
--
-- Ashita v3's imgui binding doesn't expose font scaling, font swapping,
-- or GetWindowDrawList, so genuine "bigger" / "bold" / clean AddLine
-- underlines aren't available. We emulate visual weight with:
--   1) UPPERCASE the text         — more horizontal weight than mixed case
--   2) TextColored(1, 1, 1, 1)    — pure white, brighter than body text
--   3) 1px-tall BeginChild bar    — colored via ImGuiCol_ChildWindowBg
--      (the same Push/BeginChild/Pop trick autobots' col_divider uses for
--      its left/right column rule, the only paintable line primitive that
--      reliably colors in Ashita v3's binding).
--
-- No leading rule — callers that want one (e.g. autobots' section_label)
-- can render their own clipped Separator before calling this.
-- ----------------------------------------------------------------------
function autoutil.section_head(text)
    local upper = (text or ''):upper();
    -- Capture the X where the text actually renders so the underline can
    -- start there too. After TextColored() the cursor jumps to the left
    -- margin of the next line, which is wrong when callers pre-centered
    -- the header via SetCursorPosX (automog right-col headers, etc.) —
    -- the underline ends up left-aligned even though the text is centered.
    local startX = imgui.GetCursorPosX();
    imgui.TextColored(1.0, 1.0, 1.0, 1.0, upper);
    -- Text-width underline. CalcTextSize for an exact span.
    local tw = imgui.CalcTextSize(upper);
    local w;
    if type(tw) == 'number' then w = tw;
    elseif type(tw) == 'table' then w = tw.x or tw[1] or 0;
    else w = #upper * 7; end
    imgui.SetCursorPosX(startX);
    -- 0.50 gray reads as deliberate emphasis without competing with the
    -- pure-white header above. Body text is dimmer still so the
    -- underline lands as a clear second-tier element.
    imgui.PushStyleColor(ImGuiCol_ChildWindowBg, 0.50, 0.50, 0.50, 1.0);
    imgui.BeginChild('##sec_under_' .. upper, w, 1, false);
    imgui.EndChild();
    imgui.PopStyleColor();
    imgui.Dummy(0, 4);
end

-- Drop-in helper for tabbed addons: when the user switches from a wide
-- tab back to a narrow tab, the parent imgui window stays sized to the
-- wider tab's content. Ashita's imgui build doesn't reliably shrink the
-- window across tab swaps, so we force a one-shot "snap to preferred
-- size" on the frame the tab changed.
--
-- Usage (call ONCE per frame, immediately before imgui.Begin):
--   autoutil.resize_on_tab_change('AutoLot', active_tab, 640, 520)
--   autoutil.resize_on_tab_change('AutoBots', active_tab, 660, 0)
--
-- window_id    stable string per window (used as the last-tab key).
-- active_tab   the addon's current tab key/name.
-- w, h         preferred dimensions for the new tab. Pass 0 on either
--              axis to leave that axis unconstrained - useful for
--              windows with ImGuiWindowFlags_AlwaysAutoResize where
--              imgui will auto-fit content on the 0 axis.
--
-- The call is a no-op on frames where active_tab matches the last call -
-- cost is one table lookup + one comparison per frame.
--
-- Mechanism: ImGuiSetCond_Always wins over any prior FirstUseEver call
-- this frame, so the addon's own SetNextWindowSize(..., FirstUseEver)
-- still seeds the window on first render but this call governs after.
local _last_tab_by_window = {};
function autoutil.resize_on_tab_change(window_id, active_tab, w, h)
    if _last_tab_by_window[window_id] ~= active_tab then
        imgui.SetNextWindowSize(w or 0, h or 0, ImGuiSetCond_Always);
        _last_tab_by_window[window_id] = active_tab;
    end
end

return autoutil;
