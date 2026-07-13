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

#include "0x16f_ah_cat_query.h"

#include "common/database.h"
#include "entities/charentity.h"
#include "packets/s2c/0x170_ah_cat_result.h"

auto GP_CLI_COMMAND_AH_CAT_QUERY::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar)
        .range("CatId", this->CatId, 1, 65);
}

void GP_CLI_COMMAND_AH_CAT_QUERY::process(MapSession* PSession, CCharEntity* PChar) const
{
    constexpr uint8_t BATCH = 30;

    // Separate single vs stack min prices so the client can quote stack
    // listings at the actual stack ask, not the per-unit single ask (which is
    // almost always lower → underbids → server rejects). NULL → 0 via COALESCE
    // for items that only have one listing type; client treats 0 as "no
    // listings, can't buy."
    const auto rset = db::preparedStmt(
        "SELECT ah.itemid, "
        "SUM(ah.stack = 0) AS single_count, "
        "SUM(ah.stack = 1) AS stack_count, "
        "COALESCE(MIN(CASE WHEN ah.stack = 0 THEN ah.price END), 0) AS min_single_price, "
        "COALESCE(MIN(CASE WHEN ah.stack = 1 THEN ah.price END), 0) AS min_stack_price "
        "FROM auction_house ah "
        "JOIN item_basic ib ON ib.itemid = ah.itemid "
        "WHERE ib.aH = ? AND ah.buyer_name IS NULL AND ah.sale = 0 "
        "GROUP BY ah.itemid "
        "ORDER BY ah.itemid",
        this->CatId);

    GP_SERV_COMMAND_AH_CAT_RESULT::Entry batch[BATCH];
    uint8_t batchCount = 0;
    uint8_t offset     = 0;

    auto flush = [&](bool isLast)
    {
        PChar->pushPacket<GP_SERV_COMMAND_AH_CAT_RESULT>(
            this->CatId, offset, batchCount, isLast ? 1u : 0u, batch);
        offset += batchCount;
        batchCount = 0;
    };

    if (rset)
    {
        while (rset->next())
        {
            batch[batchCount].ItemId         = rset->get<uint16_t>("itemid");
            batch[batchCount].SingleCount    = static_cast<uint8_t>(std::min<uint32_t>(rset->get<uint32_t>("single_count"), 255));
            batch[batchCount].StackCount     = static_cast<uint8_t>(std::min<uint32_t>(rset->get<uint32_t>("stack_count"), 255));
            batch[batchCount].MinSinglePrice = rset->get<uint32_t>("min_single_price");
            batch[batchCount].MinStackPrice  = rset->get<uint32_t>("min_stack_price");
            ++batchCount;

            if (batchCount == BATCH)
            {
                flush(false);
            }
        }
    }

    // Final (or only) packet — always sent so client knows the query is complete
    flush(true);
}
