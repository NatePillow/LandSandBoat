/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

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

#include "0x1a1_autoequip_copy_xml.h"

#include "common/logging.h"
#include "entities/charentity.h"
#include "packets/s2c/0x1a2_autoequip_copy_xml_result.h"

#include <cstring>
#include <filesystem>
#include <string>

namespace
{

constexpr uint8_t STATUS_OK            = 0;
constexpr uint8_t STATUS_SRC_NOT_FOUND = 1;
constexpr uint8_t STATUS_INVALID_NAME  = 2;
constexpr uint8_t STATUS_FS_ERROR      = 3;

auto sanitize(const char* raw, std::size_t cap) -> std::string
{
    if (raw == nullptr)
    {
        return {};
    }
    std::string s(raw, strnlen(raw, cap));
    while (!s.empty() && s.back() == '\0')
    {
        s.pop_back();
    }
    return s;
}

// Same path-safety check used by GET_CONFIG_CONTENT and friends — reject any
// '/' or '\\' or '.' so callers can't escape singleplayer/config/equip.
auto isPathSafe(const std::string& s) -> bool
{
    return !s.empty() && s.find_first_of("/\\.") == std::string::npos;
}

} // namespace

auto GP_CLI_COMMAND_AUTOEQUIP_COPY_XML::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_AUTOEQUIP_COPY_XML::process(MapSession* PSession, CCharEntity* PChar) const
{
    namespace fs = std::filesystem;

    const std::string srcName = sanitize(SourceName, sizeof(SourceName));
    const std::string dstName = sanitize(DestName,   sizeof(DestName));

    auto sendResult = [&](uint8_t status)
    {
        PChar->pushPacket<GP_SERV_COMMAND_AUTOEQUIP_COPY_XML_RESULT>(dstName, status);
    };

    if (!isPathSafe(srcName) || !isPathSafe(dstName))
    {
        ShowWarningFmt("AUTOEQUIP_COPY_XML: invalid src='{}' or dst='{}' from {}",
                       srcName, dstName, PChar->getName());
        sendResult(STATUS_INVALID_NAME);
        return;
    }

    const fs::path baseDir = fs::path("modules") / "singleplayer" / "config" / "equip";
    const fs::path srcPath = baseDir / (srcName + ".xml");
    const fs::path dstPath = baseDir / (dstName + ".xml");

    std::error_code ec;
    if (!fs::exists(srcPath, ec) || ec)
    {
        sendResult(STATUS_SRC_NOT_FOUND);
        return;
    }

    fs::copy_file(srcPath, dstPath, fs::copy_options::overwrite_existing, ec);
    if (ec)
    {
        ShowErrorFmt("AUTOEQUIP_COPY_XML: copy_file failed src='{}' dst='{}' err={}",
                     srcPath.string(), dstPath.string(), ec.message());
        sendResult(STATUS_FS_ERROR);
        return;
    }

    ShowDebugFmt("AUTOEQUIP_COPY_XML: copied '{}' → '{}' by {}",
                 srcName, dstName, PChar->getName());
    sendResult(STATUS_OK);
}
