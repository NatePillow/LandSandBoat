/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "config_cache.h"

#include "common/logging.h"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <mutex>

namespace fs = std::filesystem;

namespace singleplayer
{
namespace configcache
{

namespace
{
    Map                            gCache;
    std::vector<ChangeCallback>    gSubscribers;
    std::mutex                     gMutex;

    const fs::path kBaseDir{ "singleplayer/config" };

    int64_t fileMtimeSeconds(const fs::path& p)
    {
        std::error_code ec;
        auto            ft = fs::last_write_time(p, ec);
        if (ec)
        {
            return 0;
        }
        // file_time_type epoch is implementation-defined; convert by going through
        // system_clock via the std::filesystem::file_time_type→sys_time path that
        // C++20 provides. Use a simpler portable conversion: duration_cast to
        // seconds and treat as an opaque monotonic value — we only compare for
        // change detection, not for human-readable timestamps.
        auto dur = ft.time_since_epoch();
        return std::chrono::duration_cast<std::chrono::seconds>(dur).count();
    }

    bool readFile(const fs::path& p, std::string& out)
    {
        std::ifstream f(p, std::ios::binary);
        if (!f.is_open())
        {
            return false;
        }
        out.assign(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
        return true;
    }

    void notify(const std::string& category, const std::string& name, const ConfigEntry* entry, ChangeReason reason)
    {
        // Copy subscriber list under lock, dispatch outside to avoid holding
        // gMutex while subscriber code runs (which could re-enter the cache
        // and deadlock).
        std::vector<ChangeCallback> subs;
        {
            std::lock_guard<std::mutex> guard(gMutex);
            subs = gSubscribers;
        }
        for (auto& cb : subs)
        {
            try
            {
                cb(category, name, entry, reason);
            }
            catch (const std::exception& e)
            {
                ShowWarning(fmt::format("configcache: subscriber threw on notify {}/{}: {}", category, name, e.what()));
            }
        }
    }

    // Read a single file at <base>/<category>/<file> and apply it to the cache.
    // Returns true if the entry was created or updated.
    bool loadOne(const std::string& category, const fs::path& filePath, bool fireNotify)
    {
        if (!fs::is_regular_file(filePath))
        {
            return false;
        }
        const std::string name = filePath.stem().string();
        const std::string ext  = filePath.extension().string();
        std::string       body;
        if (!readFile(filePath, body))
        {
            return false;
        }
        const int64_t mtime = fileMtimeSeconds(filePath);

        const Key      key{ category, name };
        ConfigEntry    entry{ std::move(body), mtime, ext };
        ChangeReason   reason;
        ConfigEntry    snapshot;
        {
            std::lock_guard<std::mutex> guard(gMutex);
            auto                        it      = gCache.find(key);
            reason                              = (it == gCache.end()) ? ChangeReason::Created : ChangeReason::Updated;
            gCache[key]                         = std::move(entry);
            snapshot                            = gCache[key];
        }
        if (fireNotify)
        {
            notify(category, name, &snapshot, reason);
        }
        return true;
    }

} // namespace

void initialize()
{
    {
        std::lock_guard<std::mutex> guard(gMutex);
        gCache.clear();
    }

    if (!fs::exists(kBaseDir) || !fs::is_directory(kBaseDir))
    {
        ShowWarning(fmt::format("configcache: base dir not found at {}", kBaseDir.string()));
        return;
    }

    size_t fileCount = 0;
    for (const auto& catEntry : fs::directory_iterator(kBaseDir))
    {
        if (!catEntry.is_directory())
        {
            continue;
        }
        const std::string catName = catEntry.path().filename().string();
        for (const auto& fileEntry : fs::directory_iterator(catEntry.path()))
        {
            // Skip nested subdirs (e.g. autoitem/food in the original Ashita tree).
            // The LSB port's editable categories are all flat one-level.
            if (loadOne(catName, fileEntry.path(), false))
            {
                ++fileCount;
            }
        }
    }
    ShowInfo(fmt::format("configcache: loaded {} files from {}", fileCount, kBaseDir.string()));
}

const ConfigEntry* get(const std::string& category, const std::string& name)
{
    std::lock_guard<std::mutex> guard(gMutex);
    auto                        it = gCache.find(Key{ category, name });
    return (it == gCache.end()) ? nullptr : &it->second;
}

void forEach(const std::function<void(const std::string&, const std::string&, const ConfigEntry&)>& fn)
{
    // Snapshot under lock, iterate outside — keeps the lock window tiny and
    // lets subscribers/callers re-enter the cache without deadlock.
    std::vector<std::pair<Key, ConfigEntry>> snapshot;
    {
        std::lock_guard<std::mutex> guard(gMutex);
        snapshot.reserve(gCache.size());
        for (const auto& [k, v] : gCache)
        {
            snapshot.emplace_back(k, v);
        }
    }
    for (const auto& [k, v] : snapshot)
    {
        fn(k.category, k.name, v);
    }
}

void forEachInCategory(const std::string&                                                   category,
                       const std::function<void(const std::string&, const ConfigEntry&)>& fn)
{
    std::vector<std::pair<std::string, ConfigEntry>> snapshot;
    {
        std::lock_guard<std::mutex> guard(gMutex);
        for (const auto& [k, v] : gCache)
        {
            if (k.category == category)
            {
                snapshot.emplace_back(k.name, v);
            }
        }
    }
    for (const auto& [n, v] : snapshot)
    {
        fn(n, v);
    }
}

bool putAndPersist(const std::string& category, const std::string& name, std::string body, const std::string& ext)
{
    if (category.empty() || name.empty() || ext.empty() || ext[0] != '.')
    {
        return false;
    }
    const fs::path catDir = kBaseDir / category;
    std::error_code ec;
    fs::create_directories(catDir, ec);
    const fs::path filePath = catDir / (name + ext);

    {
        std::ofstream f(filePath, std::ios::binary | std::ios::trunc);
        if (!f.is_open())
        {
            ShowWarning(fmt::format("configcache: failed to open {} for write", filePath.string()));
            return false;
        }
        f.write(body.data(), body.size());
        if (!f.good())
        {
            ShowWarning(fmt::format("configcache: write failed for {}", filePath.string()));
            return false;
        }
    }

    const Key    key{ category, name };
    ChangeReason reason;
    ConfigEntry  snapshot;
    {
        std::lock_guard<std::mutex> guard(gMutex);
        auto                        it = gCache.find(key);
        reason                         = (it == gCache.end()) ? ChangeReason::Created : ChangeReason::Updated;
        ConfigEntry entry{ std::move(body), fileMtimeSeconds(filePath), ext };
        gCache[key]                    = std::move(entry);
        snapshot                       = gCache[key];
    }
    notify(category, name, &snapshot, reason);
    return true;
}

bool erase(const std::string& category, const std::string& name)
{
    const Key   key{ category, name };
    std::string ext;
    bool        hadEntry = false;
    {
        std::lock_guard<std::mutex> guard(gMutex);
        auto                        it = gCache.find(key);
        if (it != gCache.end())
        {
            ext      = it->second.ext;
            hadEntry = true;
            gCache.erase(it);
        }
    }

    bool removedFromDisk = false;
    if (!ext.empty())
    {
        const fs::path  filePath = kBaseDir / category / (name + ext);
        std::error_code ec;
        removedFromDisk          = fs::remove(filePath, ec);
    }
    else
    {
        // We don't know the extension because the entry wasn't cached. Try the
        // two common ones; harmless if neither exists.
        for (const auto& tryExt : { ".json", ".xml" })
        {
            std::error_code ec;
            if (fs::remove(kBaseDir / category / (name + tryExt), ec))
            {
                removedFromDisk = true;
                break;
            }
        }
    }

    if (hadEntry || removedFromDisk)
    {
        notify(category, name, nullptr, ChangeReason::Deleted);
        return true;
    }
    return false;
}

void poll()
{
    if (!fs::exists(kBaseDir) || !fs::is_directory(kBaseDir))
    {
        return;
    }

    // Two passes: (1) reconcile disk → cache (new + changed), (2) reconcile
    // cache → disk (deletions). Doing them in this order means a rename
    // operation (delete + create) emits one Deleted + one Created instead of
    // a possibly racy Updated.
    std::unordered_map<Key, bool, KeyHash> seen;

    for (const auto& catEntry : fs::directory_iterator(kBaseDir))
    {
        if (!catEntry.is_directory())
        {
            continue;
        }
        const std::string catName = catEntry.path().filename().string();
        for (const auto& fileEntry : fs::directory_iterator(catEntry.path()))
        {
            if (!fileEntry.is_regular_file())
            {
                continue;
            }
            const std::string name  = fileEntry.path().stem().string();
            const int64_t     mtime = fileMtimeSeconds(fileEntry.path());
            const Key         key{ catName, name };
            seen[key]               = true;

            bool needReload = false;
            {
                std::lock_guard<std::mutex> guard(gMutex);
                auto                        it = gCache.find(key);
                if (it == gCache.end() || it->second.mtime != mtime)
                {
                    needReload = true;
                }
            }
            if (needReload)
            {
                loadOne(catName, fileEntry.path(), true);
            }
        }
    }

    // Pass 2: find cache entries that no longer exist on disk.
    std::vector<Key> deletedKeys;
    {
        std::lock_guard<std::mutex> guard(gMutex);
        for (const auto& [k, _] : gCache)
        {
            if (!seen.count(k))
            {
                deletedKeys.push_back(k);
            }
        }
        for (const auto& k : deletedKeys)
        {
            gCache.erase(k);
        }
    }
    for (const auto& k : deletedKeys)
    {
        notify(k.category, k.name, nullptr, ChangeReason::Deleted);
    }
}

void subscribeChanges(ChangeCallback cb)
{
    std::lock_guard<std::mutex> guard(gMutex);
    gSubscribers.push_back(std::move(cb));
}

} // namespace configcache
} // namespace singleplayer
