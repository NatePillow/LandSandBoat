/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#pragma once

// This header is intentionally minimal — the bulk of singleplayer's headless
// session management is implemented in bot_sessions.cpp as out-of-line
// definitions for MapSessionContainer member methods (createHeadlessSession,
// destroyHeadlessForParent, etc.) plus the mapsessions::init/get namespace.
// Declarations stay in map_session_container.h (where they have to be — class
// member methods can't be declared elsewhere) but the bodies live here so
// upstream map_session_container.cpp keeps its original footprint and any
// future upstream changes there merge cleanly.
//
// =============================================================================
// TODO(cross-process headless): moveHeadlessToPrimaryZone only handles in-process
// zone moves (single map server). When the destination zone lives on a different
// map process the headless can't simply DecreaseZoneCounter→IncreaseZoneCounter
// — the new zone isn't in this process's m_zoneList. Needs an IPC path: persist
// the headless to char_inventory + chars (already current via the bot's own
// PersistData), destroy the local session, then signal the receiving process to
// re-spawn the headless attached to the primary's session there. Single-process
// LSB singleplayer setups don't hit this today; flag for the day someone shards
// zones across processes.
// =============================================================================

#include "map_session_container.h"
