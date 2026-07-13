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

#include "common/mmo.h"

#include <cfloat>
#include <utility>
#include <vector>

class INavMesh
{
public:
    virtual ~INavMesh() = default;

    virtual auto findPath(const position_t& start, const position_t& end) -> std::vector<pathpoint_t>                              = 0;
    virtual auto findRandomPosition(const position_t& start, float maxRadius) -> std::pair<int16, position_t>                      = 0;
    virtual auto raycast(const position_t& start, const position_t& end) -> bool                                                   = 0;
    virtual auto validPosition(const position_t& position) -> bool                                                                 = 0;
    virtual auto findClosestValidPoint(const position_t& position, float* validPoint) -> bool                                      = 0;
    virtual auto findFurthestValidPoint(const position_t& startPosition, const position_t& endPosition, float* validPoint) -> bool = 0;
    virtual void snapToValidPosition(position_t& position)                                                                         = 0;

    // SINGLEPLAYER BEGIN
    // Parametric distance (0..1) along [start, end] of the most recent
    // raycast() call's first wall hit. FLT_MAX = no hit. Read by the bot AI's
    // step-clamp logic to stop bots at wall surfaces instead of letting setPos
    // teleport them through geometry. CNavMesh returns the real value; the
    // null nav mesh (zone with missing nav data) returns FLT_MAX.
    virtual auto lastRaycastT() const -> float = 0;
    // SINGLEPLAYER END
};

class NullNavMesh final : public INavMesh
{
public:
    auto findPath(const position_t&, const position_t&) -> std::vector<pathpoint_t> override
    {
        return {};
    }

    auto findRandomPosition(const position_t& start, float) -> std::pair<int16, position_t> override
    {
        return { 0, start };
    }

    auto raycast(const position_t&, const position_t&) -> bool override
    {
        return true;
    }

    auto validPosition(const position_t&) -> bool override
    {
        return true;
    }

    auto findClosestValidPoint(const position_t&, float*) -> bool override
    {
        return false;
    }

    auto findFurthestValidPoint(const position_t&, const position_t&, float*) -> bool override
    {
        return false;
    }

    void snapToValidPosition(position_t&) override
    {
        // NOOP
    }

    // SINGLEPLAYER BEGIN
    auto lastRaycastT() const -> float override
    {
        // No nav data → no wall hit; bot step-clamp treats as "open" and uses
        // the requested end position unmodified.
        return FLT_MAX;
    }
    // SINGLEPLAYER END
};
