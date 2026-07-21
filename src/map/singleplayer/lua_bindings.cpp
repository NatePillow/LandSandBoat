/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

// Out-of-line definitions for singleplayer-fork CLuaBaseEntity bindings
// (weaponSkill / rangedAttack / useItem / isHeadless / spawnHeadless /
// formAllianceFromSpec / botLot* / isBot* / startBotResting / etc.).
// Declarations stay in lua_baseentity.h (wrapped with SINGLEPLAYER markers)
// and the SOL_REGISTER calls stay in CLuaBaseEntity::Register() in the
// upstream file (also wrapped) — but the bodies live here so upstream
// lua_baseentity.cpp keeps closer to its vanilla footprint.

#include "lua/lua_baseentity.h"
#include "lua/luautils.h"

#include "ability.h"
#include "ai/ai_container.h"
#include "ai/helpers/action_queue.h"
#include "ai/states/ability_state.h"
#include "ai/states/magic_state.h"
#include "ai/states/range_state.h"
#include "ai/states/weaponskill_state.h"
#include "alliance.h"
#include "battlefield_handler.h"
#include "common/database.h"
#include "common/logging.h"
#include "entities/charentity.h"
#include "entities/mobentity.h"
#include "entities/trustentity.h"
#include "items/item_equipment.h"
#include "items/item_general.h"
#include "items/item_usable.h"
#include "items/item_weapon.h"
#include "map_session.h"
#include "map_session_container.h"
#include "navmesh/navmesh.h"
#include "packets/basic.h"
#include "packets/char_sync.h"
#include "packets/s2c/0x01d_item_same.h"
#include "packets/s2c/0x020_item_attr.h"
#include "packets/s2c/0x051_grap_list.h"
#include "packets/s2c/0x192_autoskill_state.h"
#include "packets/s2c/0x1a4_puller_nearby_names.h"
#include "party.h"
#include "singleplayer/bot_state_cache.h"
#include "spell.h"
#include "status_effect.h"
#include "status_effect_container.h"
#include "treasure_pool.h"

#include "utils/battleutils.h"
#include "utils/charutils.h"
#include "utils/itemutils.h"
#include "utils/petutils.h"
#include "utils/trustutils.h"
#include "utils/zoneutils.h"

#include <algorithm>

void CLuaBaseEntity::weaponSkill(uint16 wsId, const sol::object& target)
{
    uint16 targid = 0;

    if (target != sol::lua_nil && target.is<CLuaBaseEntity*>())
    {
        CLuaBaseEntity* PLuaBaseEntity = target.as<CLuaBaseEntity*>();
        if (PLuaBaseEntity->m_PBaseEntity)
        {
            targid = PLuaBaseEntity->m_PBaseEntity->targid;
        }
    }

    m_PBaseEntity->PAI->QueueAction(queueAction_t(0ms, true, [targid, wsId](auto PEntity) {
        if (targid)
        {
            PEntity->PAI->WeaponSkill(targid, wsId);
        }
    }));
    m_PBaseEntity->PAI->checkQueueImmediately();
}

/************************************************************************
 *  Function: rangedAttack()
 *  Purpose : Queue a ranged attack on a target. Mirrors PAI->RangedAttack
 *            for server-side AI use.
 ************************************************************************/
void CLuaBaseEntity::rangedAttack(const sol::object& target)
{
    uint16 targid = 0;

    if (target != sol::lua_nil && target.is<CLuaBaseEntity*>())
    {
        CLuaBaseEntity* PLuaBaseEntity = target.as<CLuaBaseEntity*>();
        if (PLuaBaseEntity->m_PBaseEntity)
        {
            targid = PLuaBaseEntity->m_PBaseEntity->targid;
        }
    }

    m_PBaseEntity->PAI->QueueAction(queueAction_t(0ms, true, [targid](auto PEntity) {
        if (targid)
        {
            PEntity->PAI->RangedAttack(targid);
        }
    }));
    m_PBaseEntity->PAI->checkQueueImmediately();
}

/************************************************************************
 *  Function: useItem()
 *  Purpose : Queue an item use from a specific container slot on a target.
 *            Mirrors PAI->UseItem for server-side AI use (consumables, food).
 ************************************************************************/
void CLuaBaseEntity::useItem(uint8 location, uint8 slotId, const sol::object& target)
{
    uint16 targid = 0;

    if (target != sol::lua_nil && target.is<CLuaBaseEntity*>())
    {
        CLuaBaseEntity* PLuaBaseEntity = target.as<CLuaBaseEntity*>();
        if (PLuaBaseEntity->m_PBaseEntity)
        {
            targid = PLuaBaseEntity->m_PBaseEntity->targid;
        }
    }

    m_PBaseEntity->PAI->QueueAction(queueAction_t(0ms, true, [targid, location, slotId](auto PEntity) {
        if (targid)
        {
            PEntity->PAI->UseItem(targid, location, slotId);
        }
    }));
    m_PBaseEntity->PAI->checkQueueImmediately();
}

/************************************************************************
 *  Function: isHeadless() / getBotMode() / setBotMode() / getLastClientMoveInputMs()
 *  Purpose : Bot AI module helpers — let Lua read/write the C++-side state
 *            populated by createHeadlessSession and the 0x015 stamp.
 ************************************************************************/
bool CLuaBaseEntity::isHeadless() const
{
    if (auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity))
    {
        return PChar->PSession != nullptr && PChar->PSession->parentCharId != 0;
    }
    return false;
}

uint32 CLuaBaseEntity::getParentCharId() const
{
    if (auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity))
    {
        if (PChar->PSession != nullptr)
        {
            return PChar->PSession->parentCharId;
        }
    }
    return 0;
}

uint8 CLuaBaseEntity::getBotMode() const
{
    if (auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity))
    {
        return static_cast<uint8>(PChar->m_botMode);
    }
    return 0;
}

void CLuaBaseEntity::setBotMode(uint8 mode)
{
    if (auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity))
    {
        if (mode <= static_cast<uint8>(BotMode::MovementOnly))
        {
            PChar->m_botMode = static_cast<BotMode>(mode);
        }
    }
}

// Role-order tick priority (lower ticks earlier). Set at role assignment; the
// zone char-tick loop stable_sorts by it so healers resolve WHM->...->BLM.
void CLuaBaseEntity::setBotTickPriority(uint8 priority)
{
    if (auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity))
    {
        PChar->m_botTickPriority = priority;
    }
}

uint8 CLuaBaseEntity::getAggroMode() const
{
    if (auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity))
    {
        return PChar->m_aggroMode;
    }
    return 0;
}

void CLuaBaseEntity::setAggroMode(uint8 mode)
{
    if (auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity))
    {
        PChar->m_aggroMode = mode;
    }
}

namespace
{
    // Mirrors the lambda in src/map/packets/c2s/0x053_lockstyle.cpp — push
    // the regenerated visible look out to every client that can see this
    // char. GRAP_LIST refreshes equip-slot icons; CharSync repaints the
    // 3D model. Inline here so the binding doesn't depend on the packet
    // module's anonymous namespace helper.
    inline void pushStyleAppearance(CCharEntity* PChar)
    {
        PChar->pushPacket<GP_SERV_COMMAND_GRAP_LIST>(PChar);
        PChar->pushPacket<CCharSyncPacket>(PChar);
    }
} // namespace

void CLuaBaseEntity::applyStyleLock(sol::table slotItemIds)
{
    auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity);
    if (PChar == nullptr)
    {
        return;
    }

    // Engage Style Lock first so UpdateWeaponStyle/UpdateArmorStyle below
    // route their writes into mainlook rather than the live look. Order
    // matches the 0x053 SET handler.
    charutils::SetStyleLock(PChar, true);

    // Zero every visual slot, then overlay whatever the caller asked for.
    // styleItems is 10 entries (slots 0..9) — the 0x053 Set path mirrors
    // this. Slots > 9 (accessories) don't contribute to the visible model
    // so we leave them alone.
    for (uint8 i = 0; i < 10; ++i)
    {
        PChar->styleItems[i] = 0;
    }
    for (const auto& kv : slotItemIds)
    {
        const auto slot = kv.first.as<uint32>();
        if (slot >= 10)
        {
            continue;
        }
        const auto itemId = static_cast<uint16>(kv.second.as<uint32>());

        // Same validity gauntlet as the 0x053 Set handler: only allow
        // equipment / weapons, and the item must actually fit in the
        // claimed slot. Anything else gets clamped to 0 (no item shown).
        const auto* PItem = xi::items::lookup<CItemEquipment>(itemId);
        if (PItem == nullptr || !(PItem->isType(ITEM_WEAPON) || PItem->isType(ITEM_EQUIPMENT)))
        {
            PChar->styleItems[slot] = 0;
            continue;
        }
        if ((PItem->getEquipSlotId() & (1 << slot)) == 0)
        {
            PChar->styleItems[slot] = 0;
            continue;
        }
        PChar->styleItems[slot] = itemId;
    }

    // Conflict resolution copied from the 0x053 Set handler — if any of
    // the new style items reserve slots (two-handed weapons hide sub, full
    // body sets hide head etc.), clear the conflicting style slots so the
    // composite render doesn't double up.
    for (uint8 i = 0; i < 10; ++i)
    {
        const auto* PItem = xi::items::lookup<CItemEquipment>(PChar->styleItems[i]);
        if (PItem == nullptr)
        {
            continue;
        }
        const auto removeMask = PItem->getRemoveSlotId();
        for (uint8 x = 0; x < sizeof(removeMask) * 8; ++x)
        {
            if (removeMask & (1 << x))
            {
                PChar->styleItems[x] = 0;
            }
        }
    }

    // Walk the slots and rebuild mainlook from the chosen styleItems. We
    // also have to feed UpdateWeaponStyle the currently-equipped weapon
    // pointer because the helper composites material/dye state on top of
    // styleItems for the visible model.
    bool hasH2HInMainSlot = false;
    if (const auto* PMain = xi::items::lookup<CItemEquipment>(PChar->styleItems[0]))
    {
        const auto* PWeapon = dynamic_cast<const CItemWeapon*>(PMain);
        if (PWeapon != nullptr && PWeapon->isHandToHand())
        {
            hasH2HInMainSlot = true;
        }
    }
    for (uint8 i = 0; i < 10; ++i)
    {
        auto* PEquipped = PChar->getEquip(static_cast<SLOTTYPE>(i));
        switch (i)
        {
            case SLOT_SUB:
                if (hasH2HInMainSlot)
                {
                    continue;
                }
                charutils::UpdateWeaponStyle(PChar, i, PEquipped);
                break;
            case SLOT_MAIN:
            case SLOT_RANGED:
            case SLOT_AMMO:
                charutils::UpdateWeaponStyle(PChar, i, PEquipped);
                break;
            case SLOT_HEAD:
            case SLOT_BODY:
            case SLOT_HANDS:
            case SLOT_LEGS:
            case SLOT_FEET:
                charutils::UpdateArmorStyle(PChar, i);
                break;
            default:
                break;
        }
    }
    charutils::UpdateRemovedSlotsLookForLockStyle(PChar);

    // Persist + ship the new visible look to other clients (and the locked
    // owner's own client, since FFXI's /lockstyle also affects the local
    // self-render via this same packet pair).
    PChar->RequestPersist(CHAR_PERSIST::EQUIP);
    pushStyleAppearance(PChar);
}

void CLuaBaseEntity::clearStyleLock()
{
    auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity);
    if (PChar == nullptr || !PChar->getStyleLocked())
    {
        return;
    }
    ShowInfo(fmt::format("[STYLELOCK] caller=lua_bindings.clearStyleLock char={}", PChar->getName()));
    charutils::SetStyleLock(PChar, false);
    PChar->RequestPersist(CHAR_PERSIST::EQUIP);
    pushStyleAppearance(PChar);
}

uint32 CLuaBaseEntity::getLastClientMoveInputMs() const
{
    if (auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity))
    {
        if (PChar->m_lastClientMoveInput == timer::time_point{})
        {
            return std::numeric_limits<uint32>::max();
        }
        const auto delta = timer::now() - PChar->m_lastClientMoveInput;
        return static_cast<uint32>(std::chrono::duration_cast<std::chrono::milliseconds>(delta).count());
    }
    return std::numeric_limits<uint32>::max();
}

/************************************************************************
 *  Function: spawnHeadless(name, spawnIndex)
 *  Purpose : Spawn a synthetic-session character with `this` as parent.
 *            Replaces the inline spawn loop that used to live in the 0x175
 *            handler — driven from bot_spawn.lua now.
 *  Returns : the spawned bot as a CLuaBaseEntity, or sol::lua_nil on failure.
 ************************************************************************/
auto CLuaBaseEntity::spawnHeadless(const std::string& name, uint8 spawnIndex) -> sol::object
{
    auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity);
    if (PChar == nullptr)
    {
        return sol::lua_nil;
    }

    if (name.empty())
    {
        return sol::lua_nil;
    }

    const auto rset = db::preparedStmt("SELECT charid FROM chars WHERE charname = ? LIMIT 1", name);
    if (!rset || rset->rowsCount() == 0 || !rset->next())
    {
        ShowWarning(fmt::format("spawnHeadless: unknown char '{}'", name));
        return sol::lua_nil;
    }

    const uint32 charId = rset->get<uint32>("charid");

    if (charId == PChar->id)
    {
        ShowWarning(fmt::format("spawnHeadless: cannot spawn primary char '{}' as headless", name));
        return sol::lua_nil;
    }

    if (zoneutils::GetCharByName(name) != nullptr)
    {
        ShowWarning(fmt::format("spawnHeadless: '{}' is already in the world", name));
        return sol::lua_nil;
    }

    // Same-account headless siblings are allowed in singleplayer LSB — the
    // retail one-char-per-account rule is enforced at the lobby layer
    // (which headless sessions bypass entirely), and every per-char DB
    // table keys on charid, not accid, so multiple sessions on one account
    // don't race on shared rows. If a real client later logs into an
    // account that has sibling headlesses, the 0x0A LOGIN handler evicts
    // them so the real client takes precedence.
    auto&       container = mapsessions::get();
    MapSession* spawned   = container.createHeadlessSession(charId, PChar, spawnIndex);
    if (spawned == nullptr || spawned->PChar == nullptr)
    {
        ShowWarning(fmt::format("spawnHeadless: failed to spawn '{}'", name));
        return sol::lua_nil;
    }

    return sol::make_object(lua, CLuaBaseEntity(spawned->PChar.get()));
}

/************************************************************************
 *  Function: formAllianceFromSpec(allianceSpec)
 *  Purpose : Mirrors 0x169 autoinvite — forms 1-3 parties and (if >1) chains
 *            them into an alliance, all in one call from Lua.
 ************************************************************************/
bool CLuaBaseEntity::formAllianceFromSpec(sol::table allianceSpec)
{
    struct SlotChars
    {
        CCharEntity*              leader = nullptr;
        std::vector<CCharEntity*> members;
    };

    std::vector<SlotChars> slots;
    slots.reserve(3);

    // Walk the spec and resolve every char up-front; fail closed before mutating.
    for (size_t i = 1; i <= 3; ++i)
    {
        sol::object entry = allianceSpec[i];
        if (!entry.valid())
        {
            break;
        }

        sol::table partySpec = entry.as<sol::table>();
        SlotChars  sc;

        sol::object       leaderObj  = partySpec["leader"];
        const std::string leaderName = (leaderObj.valid() && leaderObj.is<std::string>()) ? leaderObj.as<std::string>() : std::string();
        if (leaderName.empty())
        {
            ShowWarning(fmt::format("formAllianceFromSpec: pt{} leader name is empty", i));
            return false;
        }

        sc.leader = zoneutils::GetCharByName(leaderName);
        if (sc.leader == nullptr)
        {
            ShowWarning(fmt::format("formAllianceFromSpec: leader '{}' not found", leaderName));
            return false;
        }
        if (sc.leader->PParty != nullptr)
        {
            ShowWarning(fmt::format("formAllianceFromSpec: '{}' is already in a party", leaderName));
            return false;
        }

        sol::object membersObj = partySpec["members"];
        if (membersObj.valid() && membersObj.is<sol::table>())
        {
            sol::table membersTbl = membersObj.as<sol::table>();
            for (size_t m = 1; m <= 5; ++m)
            {
                sol::object name = membersTbl[m];
                if (!name.valid())
                {
                    break;
                }
                const std::string memberName = name.as<std::string>();
                if (memberName.empty())
                {
                    continue;
                }
                CCharEntity* PMember = zoneutils::GetCharByName(memberName);
                if (PMember == nullptr)
                {
                    ShowWarning(fmt::format("formAllianceFromSpec: member '{}' not found", memberName));
                    return false;
                }
                if (PMember->PParty != nullptr)
                {
                    ShowWarning(fmt::format("formAllianceFromSpec: '{}' is already in a party", memberName));
                    return false;
                }
                sc.members.push_back(PMember);
            }
        }

        slots.push_back(std::move(sc));
    }

    if (slots.empty())
    {
        ShowWarning("formAllianceFromSpec: empty spec");
        return false;
    }

    // Form parties.
    for (auto& sc : slots)
    {
        sc.leader->PParty = new CParty(sc.leader);
        for (auto* PMember : sc.members)
        {
            sc.leader->PParty->AddMember(PMember);
        }
    }

    // Chain into an alliance if >1 party.
    if (slots.size() > 1)
    {
        slots[0].leader->PParty->m_PAlliance = new CAlliance(slots[0].leader);
        for (size_t s = 1; s < slots.size(); ++s)
        {
            slots[0].leader->PParty->m_PAlliance->addParty(slots[s].leader->PParty);
        }
    }

    return true;
}

/************************************************************************
 *  Function: formPartyAlone()
 *  Purpose : Make this entity the leader of a newly-created singleton
 *            party. No-op if PParty is already set. Used by the diff-based
 *            alliance update path (bots_spawn.update_alliance_diff) when
 *            a fresh headless needs to be its own leader before being
 *            attached to an existing alliance.
 ************************************************************************/
void CLuaBaseEntity::formPartyAlone()
{
    if (m_PBaseEntity == nullptr || m_PBaseEntity->objtype != TYPE_PC)
    {
        return;
    }
    auto* PChar = static_cast<CCharEntity*>(m_PBaseEntity);
    if (PChar->PParty != nullptr)
    {
        return;
    }
    PChar->PParty = new CParty(PChar);
}

/************************************************************************
 *  Function: partyAddMember(other)
 *  Purpose : Add `other` to this entity's party. Caller must guarantee
 *            this->PParty is non-null and `other` is not already in a
 *            party (engine asserts on double-membership).
 ************************************************************************/
void CLuaBaseEntity::partyAddMember(CLuaBaseEntity* other)
{
    if (m_PBaseEntity == nullptr || m_PBaseEntity->objtype != TYPE_PC) { return; }
    if (other == nullptr || other->m_PBaseEntity == nullptr
        || other->m_PBaseEntity->objtype != TYPE_PC) { return; }

    auto* PSelf  = static_cast<CCharEntity*>(m_PBaseEntity);
    auto* POther = static_cast<CCharEntity*>(other->m_PBaseEntity);

    if (PSelf->PParty == nullptr)
    {
        ShowWarning(fmt::format("partyAddMember: {} has no party", PSelf->getName()));
        return;
    }
    if (POther->PParty != nullptr)
    {
        ShowWarning(fmt::format("partyAddMember: {} is already in a party", POther->getName()));
        return;
    }
    // Room check — FFXI parties hold 6 max (CParty::IsFull tests size > 5).
    // Silent-no-op refusal beats AddMember half-applying state and leaving
    // packet broadcasts confused.
    if (PSelf->PParty->IsFull())
    {
        ShowWarning(fmt::format("partyAddMember: party led by {} is full ({}/6); refusing {}",
                                PSelf->getName(), PSelf->PParty->members.size(), POther->getName()));
        return;
    }
    PSelf->PParty->AddMember(POther);
}

/************************************************************************
 *  Function: partyRemoveMember(other)
 *  Purpose : Remove `other` from this entity's party. No-op if `other`
 *            isn't in this party. Engine handles the empty-party case
 *            (RemoveMember on the last member dissolves the CParty and
 *            cascades into the alliance if the party was the last in it).
 ************************************************************************/
void CLuaBaseEntity::partyRemoveMember(CLuaBaseEntity* other)
{
    if (m_PBaseEntity == nullptr || m_PBaseEntity->objtype != TYPE_PC) { return; }
    if (other == nullptr || other->m_PBaseEntity == nullptr
        || other->m_PBaseEntity->objtype != TYPE_PC) { return; }

    auto* PSelf  = static_cast<CCharEntity*>(m_PBaseEntity);
    auto* POther = static_cast<CCharEntity*>(other->m_PBaseEntity);

    if (PSelf->PParty == nullptr || POther->PParty != PSelf->PParty)
    {
        return;
    }
    PSelf->PParty->RemoveMember(POther);
}

/************************************************************************
 *  Function: attachToAlliance(anchorEntity)
 *  Purpose : Attach this entity's party to anchorEntity's alliance. If
 *            anchor has no alliance yet (anchor is a solo party), creates
 *            a new alliance with anchor as the seed and this entity's
 *            party as the second slot. Caller must guarantee both this
 *            and anchor have a valid PParty.
 ************************************************************************/
void CLuaBaseEntity::attachToAlliance(CLuaBaseEntity* anchor)
{
    if (m_PBaseEntity == nullptr || m_PBaseEntity->objtype != TYPE_PC) { return; }
    if (anchor == nullptr || anchor->m_PBaseEntity == nullptr
        || anchor->m_PBaseEntity->objtype != TYPE_PC) { return; }

    auto* PSelf   = static_cast<CCharEntity*>(m_PBaseEntity);
    auto* PAnchor = static_cast<CCharEntity*>(anchor->m_PBaseEntity);

    if (PSelf->PParty == nullptr || PAnchor->PParty == nullptr)
    {
        ShowWarning(fmt::format("attachToAlliance: {} or {} has no party",
                                PSelf->getName(), PAnchor->getName()));
        return;
    }
    if (PSelf->PParty == PAnchor->PParty)
    {
        // Same party — nothing to attach.
        return;
    }
    if (PAnchor->PParty->m_PAlliance == nullptr)
    {
        // Anchor is solo. Mirror formAllianceFromSpec:527 — create the
        // alliance object with anchor as seed, then chain self's party.
        PAnchor->PParty->m_PAlliance = new CAlliance(PAnchor);
    }
    else if (PAnchor->PParty->m_PAlliance->partyList.size() >= 3)
    {
        // Alliance is at 3-party cap. Refusing here keeps the engine's own
        // warning ladder (CAlliance::addParty asserts on >= 3) from firing
        // mid-state-transition.
        ShowWarning(fmt::format("attachToAlliance: alliance led by {} already at 3 parties; refusing",
                                PAnchor->getName()));
        return;
    }
    PAnchor->PParty->m_PAlliance->addParty(PSelf->PParty);
}

/************************************************************************
 *  Function: destroyAsHeadless()
 *  Purpose : Despawn this entity if it's a headless bot. Mirrors what the
 *            0x176 DESPAWN_ALL handler does for one bot at a time. Engine
 *            persists position/effects via removeCharFromZone first, so a
 *            future resummon picks up where they left off. Used by the
 *            diff-based alliance update path (#230) for DROP entries.
 ************************************************************************/
void CLuaBaseEntity::destroyAsHeadless()
{
    if (m_PBaseEntity == nullptr || m_PBaseEntity->objtype != TYPE_PC) { return; }
    auto* PChar = static_cast<CCharEntity*>(m_PBaseEntity);
    if (!PChar->isHeadless()) { return; }
    mapsessions::get().destroyHeadlessByCharId(PChar->id);
}

/************************************************************************
 *  Function: detachFromAlliance()
 *  Purpose : Remove this entity's party from its alliance. No-op if not
 *            in an alliance. The CParty itself survives — it just becomes
 *            a standalone party. CAlliance::removeParty dissolves the
 *            alliance if only one party remains afterward (engine logic).
 ************************************************************************/
void CLuaBaseEntity::detachFromAlliance()
{
    if (m_PBaseEntity == nullptr || m_PBaseEntity->objtype != TYPE_PC) { return; }
    auto* PSelf = static_cast<CCharEntity*>(m_PBaseEntity);
    if (PSelf->PParty == nullptr || PSelf->PParty->m_PAlliance == nullptr)
    {
        return;
    }
    PSelf->PParty->m_PAlliance->removeParty(PSelf->PParty);
}

/************************************************************************
 *  Function: botLotItem(slotId, lotValue) / botPassItem(slotId)
 *  Purpose : Bot-side treasure-pool actions. Mirrors what the autolot addon
 *            achieves by emitting C2S 0x041/0x042 — but skips the packet,
 *            calling CTreasurePool directly. Headless chars never had a real
 *            client to send those packets, so this is the only path that
 *            works for them.
 *  Notes   : lotValue defaults to 999 (max) if not provided.
 ************************************************************************/
void CLuaBaseEntity::botLotItem(uint8 slotId, sol::object lotValue)
{
    auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity);
    if (PChar == nullptr || PChar->PTreasurePool == nullptr)
    {
        return;
    }
    const uint16 lot = (lotValue.valid() && lotValue.is<uint16>()) ? lotValue.as<uint16>() : static_cast<uint16>(999);
    PChar->PTreasurePool->lotItem(PChar, slotId, lot);
}

void CLuaBaseEntity::botPassItem(uint8 slotId)
{
    auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity);
    if (PChar == nullptr || PChar->PTreasurePool == nullptr)
    {
        return;
    }
    PChar->PTreasurePool->passItem(PChar, slotId);
}

bool CLuaBaseEntity::isBotCasting() const
{
    if (m_PBaseEntity == nullptr || m_PBaseEntity->PAI == nullptr)
    {
        return false;
    }
    return m_PBaseEntity->PAI->IsCurrentState<CMagicState>();
}

bool CLuaBaseEntity::isBotRangedAttacking() const
{
    if (m_PBaseEntity == nullptr || m_PBaseEntity->PAI == nullptr)
    {
        return false;
    }
    return m_PBaseEntity->PAI->IsCurrentState<CRangeState>();
}

bool CLuaBaseEntity::isBotUsingAbility() const
{
    if (m_PBaseEntity == nullptr || m_PBaseEntity->PAI == nullptr)
    {
        return false;
    }
    return m_PBaseEntity->PAI->IsCurrentState<CAbilityState>();
}

bool CLuaBaseEntity::isBotWeaponSkilling() const
{
    if (m_PBaseEntity == nullptr || m_PBaseEntity->PAI == nullptr)
    {
        return false;
    }
    return m_PBaseEntity->PAI->IsCurrentState<CWeaponSkillState>();
}

auto CLuaBaseEntity::raycastClampTo(float tx, float ty, float tz) -> std::tuple<float, float, float>
{
    // Default: pass target through unchanged. Zones without a navmesh can't
    // be raycasted on; return the target so stepToward proceeds as before.
    if (m_PBaseEntity == nullptr || m_PBaseEntity->loc.zone == nullptr || m_PBaseEntity->loc.zone->navMesh() == nullptr)
    {
        return { tx, ty, tz };
    }

    // Wall clearance (#189): bot stops 1.5y before any wall instead of pressing
    // against it. Implementation: extend the raycast 1.5y PAST the requested
    // per-tick destination so we detect walls just beyond the step, then clamp
    // the final position back by 1.5y from the wall. Net effect: per-tick step
    // destination is the lesser of (requested) or (first_wall - 1.5y).
    constexpr float WALL_CLEARANCE_YALMS = 1.5f;

    const position_t start = m_PBaseEntity->loc.p;
    const float      dx    = tx - start.x;
    const float      dy    = ty - start.y;
    const float      dz    = tz - start.z;
    const float      stepLen = std::sqrt(dx * dx + dz * dz);

    if (stepLen < 0.001f)
    {
        // Coincident — nothing to clamp.
        return { tx, ty, tz };
    }

    // Extended endpoint: 1.5y past the requested destination along the same
    // direction. This is what we actually raycast.
    const float extendedLen    = stepLen + WALL_CLEARANCE_YALMS;
    const float extendFactor   = extendedLen / stepLen;
    const position_t extendedEnd{ start.x + dx * extendFactor,
                                  start.y + dy * extendFactor,
                                  start.z + dz * extendFactor, 0, 0 };

    const bool clear = m_PBaseEntity->loc.zone->navMesh()->raycast(start, extendedEnd);
    if (clear)
    {
        // Nothing within step + 1.5y → original target is safe.
        return { tx, ty, tz };
    }

    // Wall hit somewhere in the extended segment. Pull the destination back to
    // be 1.5y short of the wall, but never past the requested destination
    // (don't overshoot) and never negative (can't step backward through
    // ourselves). If the wall is within 1.5y of start, clamp_t lands at 0 and
    // the bot holds position this tick.
    const float t           = m_PBaseEntity->loc.zone->navMesh()->lastRaycastT();
    const float wallDist    = extendedLen * t;            // yalms from start to wall
    const float safeDist    = std::max(0.0f, wallDist - WALL_CLEARANCE_YALMS);
    const float safe_t_orig = safeDist / stepLen;         // parametric on [start, requested]
    const float clamped_t   = std::min(1.0f, safe_t_orig);

    const float nx = start.x + dx * clamped_t;
    const float ny = start.y + dy * clamped_t;
    const float nz = start.z + dz * clamped_t;
    return { nx, ny, nz };
}

auto CLuaBaseEntity::raycastClear(float ax, float ay, float az, float bx, float by, float bz) -> bool
{
    // Navmesh LoS between two arbitrary points. No navmesh (or no zone) -> we
    // can't test, so report clear and let the caller proceed unchanged. Both
    // endpoints are explicit, so callers can score candidate spots the entity
    // isn't standing on (unlike raycastClampTo, which starts at loc.p).
    if (m_PBaseEntity == nullptr || m_PBaseEntity->loc.zone == nullptr || m_PBaseEntity->loc.zone->navMesh() == nullptr)
    {
        return true;
    }
    const position_t start{ ax, ay, az, 0, 0 };
    const position_t end{ bx, by, bz, 0, 0 };
    return m_PBaseEntity->loc.zone->navMesh()->raycast(start, end);
}

bool CLuaBaseEntity::isBotResting() const
{
    if (m_PBaseEntity == nullptr)
    {
        return false;
    }
    return m_PBaseEntity->animation == ANIMATION_HEALING;
}

void CLuaBaseEntity::startBotResting()
{
    auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity);
    if (PChar == nullptr || PChar->animation == ANIMATION_HEALING)
    {
        return;
    }
    if (PChar->PAI && PChar->PAI->IsEngaged())
    {
        return; // can't rest while engaged
    }
    PChar->PAI->ClearStateStack();
    PChar->StatusEffectContainer->AddStatusEffect(
        new CStatusEffect(EFFECT_HEALING, 0, 0,
                          std::chrono::seconds(settings::get<uint8>("map.HEALING_TICK_DELAY")), 0s));
}

void CLuaBaseEntity::stopBotResting()
{
    auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity);
    if (PChar == nullptr || PChar->animation != ANIMATION_HEALING)
    {
        return;
    }
    PChar->StatusEffectContainer->DelStatusEffectSilent(EFFECT_HEALING);
}

bool CLuaBaseEntity::hasJobAbility(uint16 abilityId) const
{
    auto* PChar = dynamic_cast<CCharEntity*>(m_PBaseEntity);
    if (PChar == nullptr)
    {
        return false;
    }
    return charutils::hasAbility(PChar, abilityId) != 0;
}

void CLuaBaseEntity::pushPullerNearbyNames(const sol::table& entries) const
{
    // ai_puller.lua passes a Lua array of { name = "...", count = N } records,
    // already sorted by count descending. We pack the first up to 20 into the
    // S2C 0x1A4 payload and push to the primary. Out-of-bounds entries are
    // silently dropped; the addon expects at most 20.
    if (m_PBaseEntity == nullptr || m_PBaseEntity->objtype != TYPE_PC)
    {
        return;
    }

    using Entry = GP_SERV_COMMAND_PULLER_NEARBY_NAMES::Entry;
    Entry  buf[20]{};
    uint8_t count = 0;
    for (uint8_t i = 0; i < 20; ++i)
    {
        auto record = entries[i + 1];  // 1-indexed
        if (!record.valid() || record.get_type() != sol::type::table)
        {
            break;
        }
        sol::table row     = record;
        std::string name   = row.get_or<std::string>("name", "");
        uint16_t    rowCnt = row.get_or<uint16_t>("count", 0);
        if (name.empty()) { continue; }

        std::memset(buf[count].Name, 0, sizeof(buf[count].Name));
        std::strncpy(buf[count].Name, name.c_str(), sizeof(buf[count].Name) - 1);
        buf[count].Count = rowCnt;
        ++count;
    }

    auto* PChar = static_cast<CCharEntity*>(m_PBaseEntity);
    PChar->pushPacket<GP_SERV_COMMAND_PULLER_NEARBY_NAMES>(count, buf);
}

void CLuaBaseEntity::publishBotState(const std::string& json) const
{
    // bots.publish_state_snapshot (in bots.lua) builds the alliance-wide +
    // per-bot state JSON and calls this to drop it into the per-primary
    // thread-safe cache (botstate::publishSnapshot). The loopback HTTP
    // server's GET /bot-state?for=<name> handler reads from there.
    //
    // Migrated from the legacy push path (S2C 0x1A5 BOT_STATE_SNAPSHOT)
    // which was at FFXI's 504-byte wire ceiling and couldn't fit the per-
    // bot fields the addon Status tab needs. Empty json clears the entry
    // (e.g. on alliance teardown).
    if (m_PBaseEntity == nullptr || m_PBaseEntity->objtype != TYPE_PC)
    {
        return;
    }
    botstate::publishSnapshot(m_PBaseEntity->getName(), json);
}

void CLuaBaseEntity::acceptRaise() const
{
    // Mirror the 0x01A RaiseMenu/Accept handler (0x01a_action.cpp:362-377):
    // a real player's "Yes" click goes to CCharEntity::Raise(), which is the
    // FULL revive (OnRaise applies Weakness, restores HP/MP, pushes the action
    // packet, clears m_hasRaise; then Accept_Raise pops CDeathState; then
    // SetDeathTime clears the homepoint timer).
    //
    // The earlier version of this binding only called PAI->Accept_Raise(),
    // which is just one of those three steps. Symptom: bots_listeners polled
    // every tick, the engine reported the call succeeded, but m_hasRaise
    // stayed non-zero, hasRaiseTractorMenu() kept returning true, and the
    // bot never actually got HP back. The 0x176 SPAWN_DEAD path is a different
    // case — it does its own HP/Weakness handling, so just popping the state
    // was sufficient there.
    if (m_PBaseEntity == nullptr || m_PBaseEntity->objtype != TYPE_PC)
    {
        return;
    }
    static_cast<CCharEntity*>(m_PBaseEntity)->Raise();
}

void CLuaBaseEntity::equipItemUnique(uint16 itemID, uint8 containerID, uint8 equipSlot) const
{
    // Drop-in replacement for equipItem with one behavior change: when the
    // requested item exists in multiple inventory copies, prefer a copy that
    // isn't already equipped to a DIFFERENT equip slot than the target.
    // Plain equipItem uses SearchItem (first match) which silently moves the
    // first ring/earring between equip slots when the autoequip path tries
    // to equip the same item to two slots (e.g. two Sniper's Ring +1 →
    // ring1 + ring2). End result with the old binding: ring1 ends up empty,
    // the second inventory copy never touched.
    //
    // Lives in singleplayer/lua_bindings.cpp so this fork-specific autoequip
    // workflow doesn't perturb upstream LSB behavior; the original
    // equipItem stays as the canonical "equip first match" path.
    if (m_PBaseEntity->objtype != TYPE_PC)
    {
        ShowWarning("Invalid entity type calling function (%s).", m_PBaseEntity->getName());
        return;
    }

    auto* PChar = static_cast<CCharEntity*>(m_PBaseEntity);
    auto* PStorage = PChar->getStorage(containerID);
    if (PStorage == nullptr)
    {
        return;
    }

    const auto matches = PStorage->SearchItems(itemID);
    if (matches.empty())
    {
        return;
    }

    // Prefer a copy that isn't currently equipped to any OTHER slot. If
    // every copy is equipped elsewhere, fall back to the first match
    // (matches the legacy equipItem behavior — the engine's EquipItem will
    // then move it between slots).
    uint8 chosenInvSlot = matches.front();
    for (const uint8 candidateInvSlot : matches)
    {
        auto* PCandidate = PStorage->GetItem(candidateInvSlot);
        if (PCandidate == nullptr)
        {
            continue;
        }
        bool equippedElsewhere = false;
        for (uint8 esi = 0; esi < 16; ++esi)
        {
            if (esi == equipSlot)
            {
                continue;
            }
            if (PChar->getEquip(static_cast<SLOTTYPE>(esi)) == PCandidate)
            {
                equippedElsewhere = true;
                break;
            }
        }
        if (!equippedElsewhere)
        {
            chosenInvSlot = candidateInvSlot;
            break;
        }
    }

    if (auto* PItem = dynamic_cast<CItemEquipment*>(PStorage->GetItem(chosenInvSlot)))
    {
        (void)PItem;  // resolved above; charutils::EquipItem re-resolves internally
        charutils::EquipItem(PChar, chosenInvSlot, equipSlot, containerID);
        PChar->RequestPersist(CHAR_PERSIST::EQUIP);
    }
}
