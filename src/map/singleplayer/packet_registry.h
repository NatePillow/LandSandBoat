/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#pragma once

#include "packet_system.h"

// Include every fork-specific custom packet header so registerPacket<T> can
// see the type at compile time. Order matches the registration block below.
#include "packets/c2s/0x151_addon_relay.h"
#include "packets/c2s/0x153_request_server_ident.h"
#include "packets/c2s/0x165_autoscroll.h"
#include "packets/c2s/0x168_autowarp.h"
#include "packets/c2s/0x169_autoinvite.h"
#include "packets/c2s/0x16a_instance_enter.h"
#include "packets/c2s/0x16f_ah_cat_query.h"
#include "packets/c2s/0x173_equip_by_id.h"
#include "packets/c2s/0x175_spawn_headless.h"
#include "packets/c2s/0x176_headless_command.h"
#include "packets/c2s/0x178_set_lot_assignment.h"
#include "packets/c2s/0x17d_use_food_config.h"
#include "packets/c2s/0x184_lot_list_action.h"
#include "packets/c2s/0x185_list_alliance_pcs.h"
#include "packets/c2s/0x18b_list_bot_spells.h"
#include "packets/c2s/0x191_set_autoskill.h"
#include "packets/c2s/0x193_list_autoskill.h"
#include "packets/c2s/0x194_automog_transfer.h"
#include "packets/c2s/0x196_automog_box_pull.h"
#include "packets/c2s/0x19a_automog_synth.h"
#include "packets/c2s/0x162_automog_change_look.h"
#include "packets/c2s/0x19c_automog_change_job.h"
#include "packets/c2s/0x19e_automog_get_job_info.h"
#include "packets/c2s/0x1a0_bot_command.h"
#include "packets/c2s/0x1a1_autoequip_copy_xml.h"
#include "packets/c2s/0x1a2_set_puller_name_filter.h"
#include "packets/c2s/0x171_equip_bot_item.h"
#include "packets/c2s/0x1a7_get_char_profile.h"

#include <array>

namespace singleplayer
{
    // Runtime initialization of fork-specific subsystems (config cache,
    // auction bot, etc.). Called from MapNetworking's constructor — NOT from
    // the consteval packet registration. See packet_registry.cpp for body.
    void initializeRuntime();

    // Compile-time registrar invoked from buildPacketHandlers() in
    // packet_system.cpp. Each entry maps a custom 0x150-0x1FF opcode to
    // ValidatedPacketHandler<T> via the registerPacket<T> template from
    // packet_system.h. Sizes are auto-derived from sizeof(T) (and the
    // optional T::getMinSize() for variable-length packets).
    consteval void registerCustomPackets(std::array<PacketHandler, 512>& handlers)
    {
        registerPacket<GP_CLI_COMMAND_ADDON_RELAY>(handlers);
        registerPacket<GP_CLI_COMMAND_REQUEST_SERVER_IDENT>(handlers);
        registerPacket<GP_CLI_COMMAND_AUTOSCROLL>(handlers);
        registerPacket<GP_CLI_COMMAND_WARP>(handlers);
        registerPacket<GP_CLI_COMMAND_AUTOINVITE>(handlers);
        registerPacket<GP_CLI_COMMAND_INSTANCE_ENTER>(handlers);
        registerPacket<GP_CLI_COMMAND_AH_CAT_QUERY>(handlers);
        registerPacket<GP_CLI_COMMAND_EQUIP_BY_ID>(handlers);
        registerPacket<GP_CLI_COMMAND_SPAWN_HEADLESS>(handlers);
        registerPacket<GP_CLI_COMMAND_HEADLESS_COMMAND>(handlers);
        registerPacket<GP_CLI_COMMAND_SET_LOT_ASSIGNMENT>(handlers);
        registerPacket<GP_CLI_COMMAND_USE_FOOD_CONFIG>(handlers);
        registerPacket<GP_CLI_COMMAND_LOT_LIST_ACTION>(handlers);
        registerPacket<GP_CLI_COMMAND_LIST_ALLIANCE_PCS>(handlers);
        registerPacket<GP_CLI_COMMAND_LIST_BOT_SPELLS>(handlers);
        registerPacket<GP_CLI_COMMAND_SET_AUTOSKILL>(handlers);
        registerPacket<GP_CLI_COMMAND_LIST_AUTOSKILL>(handlers);
        registerPacket<GP_CLI_COMMAND_AUTOMOG_TRANSFER>(handlers);
        registerPacket<GP_CLI_COMMAND_AUTOMOG_BOX_PULL>(handlers);
        registerPacket<GP_CLI_COMMAND_AUTOMOG_SYNTH>(handlers);
        registerPacket<GP_CLI_COMMAND_AUTOMOG_CHANGE_JOB>(handlers);
        registerPacket<GP_CLI_COMMAND_AUTOMOG_CHANGE_LOOK>(handlers);
        registerPacket<GP_CLI_COMMAND_AUTOMOG_GET_JOB_INFO>(handlers);
        registerPacket<GP_CLI_COMMAND_BOT_COMMAND>(handlers);
        registerPacket<GP_CLI_COMMAND_AUTOEQUIP_COPY_XML>(handlers);
        registerPacket<GP_CLI_COMMAND_SET_PULLER_NAME_FILTER>(handlers);
        registerPacket<GP_CLI_COMMAND_GET_CHAR_PROFILE>(handlers);
        registerPacket<GP_CLI_COMMAND_EQUIP_BOT_ITEM>(handlers);
    }
}
