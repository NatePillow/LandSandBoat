/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x1a7_get_char_profile.h"

#include "entities/charentity.h"
#include "map_session_container.h"
#include "packets/s2c/0x1a8_char_profile.h"
#include "utils/zoneutils.h"

#include "common/logging.h"

#include <cstring>
#include <string>

namespace
{
    // Same authorization model as 0x18F GET_CHAR_INV: target must be the
    // requester themselves OR a headless sessioned under the requester.
    // Returns nullptr on unknown / unauthorized targets so the response
    // path can still send an empty packet to unblock the addon's pending
    // callback.
    CCharEntity* resolveAuthorizedTarget(CCharEntity* PRequester, const std::string& name)
    {
        if (name.empty() || PRequester == nullptr)
        {
            return nullptr;
        }
        if (name == PRequester->getName())
        {
            return PRequester;
        }
        CCharEntity* PTarget = zoneutils::GetCharByName(name);
        if (PTarget == nullptr || PTarget->PSession == nullptr)
        {
            return nullptr;
        }
        if (PTarget->PSession->parentCharId != PRequester->id)
        {
            return nullptr;
        }
        return PTarget;
    }
} // namespace

auto GP_CLI_COMMAND_GET_CHAR_PROFILE::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_GET_CHAR_PROFILE::process(MapSession* PSession, CCharEntity* PChar) const
{
    if (PChar == nullptr)
    {
        return;
    }

    const std::string name(CharName, strnlen(CharName, sizeof(CharName)));
    CCharEntity*      PTarget = resolveAuthorizedTarget(PChar, name);
    if (PTarget == nullptr)
    {
        ShowDebug(fmt::format("GetCharProfile: refused or unknown target '{}' from '{}'",
                              name, PChar->getName()));
        // Fire an empty (zero-initialized) profile so the addon's pending
        // callback fires and the loading state clears.
        PChar->pushPacket<GP_SERV_COMMAND_CHAR_PROFILE>(PChar);
        return;
    }

    PChar->pushPacket<GP_SERV_COMMAND_CHAR_PROFILE>(PTarget);
}
