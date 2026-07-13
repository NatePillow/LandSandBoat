/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  Server-side in-memory cache of editable config files. Replaces synchronous
  disk reads in OnGetConfigContent etc. so the request hot path is a map
  lookup instead of a file open + read. Also gives us a single chokepoint to
  observe writes (for Phase 5 delta push) and external file-system edits
  (via the poll() routine).

===========================================================================
*/

#pragma once

#include "common/cbasetypes.h"

#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace singleplayer
{
namespace configcache
{

struct ConfigEntry
{
    std::string body;     // raw file body (binary-safe)
    int64_t     mtime;    // last-modified time, seconds since epoch
    std::string ext;      // file extension including dot (".json", ".xml") — used for write-back
};

struct Key
{
    std::string category;
    std::string name;

    bool operator==(const Key& rhs) const
    {
        return category == rhs.category && name == rhs.name;
    }
};

struct KeyHash
{
    size_t operator()(const Key& k) const
    {
        return std::hash<std::string>{}(k.category) ^ (std::hash<std::string>{}(k.name) << 1);
    }
};

using Map = std::unordered_map<Key, ConfigEntry, KeyHash>;

// Reasons emitted to change subscribers. Allows the subscriber to distinguish
// "the client just wrote this and we already echoed back to them" from "an
// external edit happened that all clients need to refresh from."
enum class ChangeReason
{
    Created,  // new file (CRUD create or watcher saw a new file)
    Updated,  // body changed (CRUD update or watcher saw mtime change)
    Deleted,  // file removed (CRUD delete or watcher saw it vanish)
};

using ChangeCallback = std::function<void(const std::string& category,
                                          const std::string& name,
                                          const ConfigEntry* entry, // nullptr when reason == Deleted
                                          ChangeReason       reason)>;

// One-shot: walk singleplayer/config/** at boot and load everything.
// Safe to call multiple times (idempotent rebuild).
void initialize();

// Lookup. Returns nullptr if absent.
const ConfigEntry* get(const std::string& category, const std::string& name);

// Iteration: visit every entry, or all entries in a single category.
void forEach(const std::function<void(const std::string& category,
                                      const std::string& name,
                                      const ConfigEntry& entry)>& fn);
void forEachInCategory(const std::string& category,
                       const std::function<void(const std::string& name,
                                                const ConfigEntry& entry)>& fn);

// Write a body to disk and update cache. Persists at
// singleplayer/config/<category>/<name><ext>. If a previous entry
// exists with a different extension, the new ext wins (the old file is left
// — caller should ensure ext consistency).
//
// Returns false if disk write failed (filesystem error etc.). On success,
// fires the Created or Updated callback to subscribers.
bool putAndPersist(const std::string& category,
                   const std::string& name,
                   std::string        body,
                   const std::string& ext);

// Erase from disk + cache. Returns true if a file was actually removed.
// Fires the Deleted callback on success.
bool erase(const std::string& category, const std::string& name);

// Mtime poll. Walks the config dir, compares to cache mtimes, reads anything
// that changed, removes anything that's missing. Cheap at ~50 files. Call
// from a low-frequency task (every ~2s is fine — config files change rarely).
void poll();

// Subscribe to change events. Subscribers stay registered for the process
// lifetime; the only subscriber today is the Phase 5 delta-push wire, but
// the hook is general so anything else (logging, audit) can attach later.
void subscribeChanges(ChangeCallback cb);

} // namespace configcache
} // namespace singleplayer
