/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

// HTTP-backed custom AH for automog. Retail path (walk to a real AH NPC and
// speak 0x04E AUC) is untouched.
//
// Routes registered in config_http_server.cpp startup:
//   GET  /ah/listings?for=<char>            — my active listings (JSON array)
//   GET  /ah/stock?items=<id>:<stack>,...   — active-listing count per pair
//   POST /ah/sell                           — list an item (async op)
//   POST /ah/buy                            — buy a listing (async op)
//   POST /ah/cancel                         — cancel my listing (async op)
//   GET  /ops/<opId>                        — poll op status (see op_registry)
//
// Read endpoints run synchronously on httplib's worker pool (DB-only). Keep
// them there: an AH DB query on the map tick thread will trip the inactivity
// watchdog, which is what retired the 0x162 AH_QUERY packet /ah/stock replaced.
// Write endpoints enqueue an op_registry record and return 202 Accepted
// with { opId }; post_tick drains the queue on the main thread and applies
// the mutation (inventory + gil deducts). Client polls /ops/<opId>.
//
// AH_LIST_LIMIT enforcement dropped — single-player fork, the retail 7-slot
// cap is retail-UI leftover, not a data-model constraint. Sellers can list
// as many items as they want.

#pragma once

#include <httplib.h>

namespace singleplayer::auction_http
{
    // Register /ah/* and /ops/<opId> routes on the shared config HTTP server.
    // Called from config_http_server.cpp startup.
    void registerRoutes(httplib::Server& server);

    // Called from post_tick each map main-thread tick. Walks the op_registry
    // for anything with kind starting "ah_" and applies the mutation. Fast
    // no-op when no pending AH ops exist.
    void drainOps();
}
