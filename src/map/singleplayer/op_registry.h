/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

// Generic async-op tracker for HTTP-triggered work that has to run on the
// map main thread. HTTP handlers execute on httplib's worker pool; any op
// that mutates CCharEntity / inventory / gil is main-thread-only, so the
// handler enqueues an op record here and post_tick drains + applies.
//
// Not AH-specific by design — any future async op (delivery-box ops,
// item-trade, whatever) can reuse the same registry. The `kind` string
// is the type discriminator and the payload is a std::any so callers
// stay free to shape their own inputs.
//
// Client contract: POST /kind/... returns { "opId": "<id>" } 202 Accepted.
// Client polls GET /ops/<opId> which returns
//   { "status": "pending" | "success" | "failed", "message": "..." }
// until non-pending. See loading_overlay.lua for the FE side.
//
// Completed op records live in the registry for kRecordTtl after they
// finish so a slow poll still gets an answer, then get GC'd on the next
// enqueue call.

#pragma once

#include <any>
#include <chrono>
#include <functional>
#include <optional>
#include <string>

namespace singleplayer::op_registry
{
    enum class Status : uint8_t
    {
        Pending = 0,
        Success = 1,
        Failed  = 2,
    };

    struct Record
    {
        std::string                           kind;      // "ah_sell", "ah_buy", etc.
        Status                                status;
        std::string                           message;   // failure reason on Failed; empty otherwise
        std::any                              payload;   // op-specific input struct — cast in the applier
        std::chrono::steady_clock::time_point queuedAt;
        std::chrono::steady_clock::time_point finishedAt;// unset while Pending
    };

    // Register a new pending op. Returns the opId as a decimal string that
    // the HTTP handler passes back to the client. Thread-safe.
    auto enqueue(std::string kind, std::any payload) -> std::string;

    // Look up an op's current state. Thread-safe. Returns std::nullopt if
    // the opId doesn't exist or has been GC'd past its TTL. HTTP GET /ops/<id>
    // maps nullopt → 404.
    auto query(const std::string& opId) -> std::optional<Record>;

    // Called from post_tick on the main thread. Walks every Pending record,
    // dispatches to the caller's applier with the record's kind + payload,
    // and expects the applier to mark the record via markSuccess / markFailed.
    // The applier signature is (opId, kind, payload) -> void; it must set
    // one terminal state per call.
    //
    // Applier runs INSIDE the registry lock, so it must not re-enter enqueue()
    // or query() on the same thread. If it needs to spawn a follow-up op, do
    // it after drain() returns.
    using Applier = std::function<void(const std::string& opId,
                                       const std::string& kind,
                                       const std::any&    payload)>;
    void drain(Applier applier);

    // Terminal-state setters callable from the applier context. Both are
    // idempotent — a second call on the same opId is a no-op so a mistaken
    // double-mark doesn't corrupt the timestamp / message.
    void markSuccess(const std::string& opId, std::string message = {});
    void markFailed(const std::string&  opId, std::string message);
}
