/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "bot_state_cache.h"

#include <shared_mutex>
#include <unordered_map>

namespace botstate
{
    namespace
    {
        std::shared_mutex                            gMutex;
        std::unordered_map<std::string, std::string> gByName;
    } // namespace

    void publishSnapshot(const std::string& charName, std::string json)
    {
        std::unique_lock lock(gMutex);
        if (json.empty())
        {
            gByName.erase(charName);
            return;
        }
        gByName[charName] = std::move(json);
    }

    auto getSnapshot(const std::string& charName) -> std::string
    {
        std::shared_lock lock(gMutex);
        const auto       it = gByName.find(charName);
        if (it == gByName.end())
        {
            return {};
        }
        return it->second;
    }
} // namespace botstate
