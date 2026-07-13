/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#pragma once

#include "common/cbasetypes.h"
#include "common/utils.h"
#include "packets/basic.h"
#include "packets/c2s/rate_limiter.h"

#include "entities/charentity.h"

#include "utils/moduleutils.h"

#include <array>
#include <utility>

struct MapSession;

// SINGLEPLAYER BEGIN
// PacketHandler typedef + packetSizeRange/ValidatedPacketHandler/registerPacket
// templates moved out of packet_system.cpp's anonymous namespace so the
// singleplayer fork's compile-time custom packet registration
// (src/map/singleplayer/packet_registry.h) can call registerPacket<T> for its
// custom packets from inside buildPacketHandlers(). The bodies are byte-for-byte
// the upstream definitions — only their location changed. If upstream's bodies
// change, sync them here too.
using PacketHandler = void (*)(MapSession* const, CCharEntity* const, CBasicPacket&);

template <typename T>
constexpr auto packetSizeRange() -> std::pair<std::size_t, std::size_t>
{
    constexpr auto maxSize = roundUpToNearestFour(static_cast<uint32>(sizeof(T)));
    if constexpr (requires { T::getMinSize(); })
    {
        return { T::getMinSize(), maxSize };
    }
    else
    {
        return { maxSize, maxSize };
    }
}

template <typename T>
void ValidatedPacketHandler(MapSession* const PSession, CCharEntity* const PChar, CBasicPacket& data)
{
    TracyZoneScoped;

    constexpr auto packetId   = static_cast<uint16>(T::packetId);
    constexpr auto sizeRange  = packetSizeRange<T>();
    constexpr auto minSize    = sizeRange.first;
    constexpr auto maxSize    = sizeRange.second;
    const auto     actualSize = data.getSize();

    if (actualSize < minSize || actualSize > maxSize)
    {
        ShowWarningFmt("Bad packet size for {} ({:#05x}) from {}: got {}, expected [{}, {}]",
                       T::name,
                       packetId,
                       PChar->getName(),
                       actualSize,
                       minSize,
                       maxSize);
        return;
    }

    const T* packet = data.as<T>();

    if (const auto result = packet->validate(PSession, PChar); result.valid())
    {
        PChar->m_LastPacketType = packetId;

        // Modules can optionally block processing of packets by returning true from OnIncomingPacket
        if (moduleutils::OnIncomingPacket(PSession, PChar, data))
        {
            return;
        }

        packet->process(PSession, PChar);
    }
    else
    {
        ShowWarningFmt("Invalid {} packet from {}: {} ", T::name, PChar->getName(), result.errorString());
    }
}

template <typename T>
constexpr void registerPacket(std::array<PacketHandler, 512>& handlers)
{
    handlers[static_cast<uint16>(T::packetId)] = &ValidatedPacketHandler<T>;
}

// SINGLEPLAYER END

class PacketSystem
{
public:
    void dispatch(uint16 packetId, MapSession* PSession, CCharEntity* PChar, CBasicPacket& data);

private:
    PacketRateLimiter rateLimiter_;
};
