---
name: bg-wiki request throttling
description: Must throttle WebFetch requests to bg-wiki with 1.5–4 seconds between each request
type: feedback
---

Never make parallel WebFetch calls to bg-wiki. Always fetch sequentially with a sleep of 1.5–4 seconds between each request.

**Why:** Risk of getting rate-limited by the server.

**How to apply:** When fetching multiple bg-wiki pages in one session, use `Bash sleep 2` (or similar) between each WebFetch call. Never batch bg-wiki fetches in parallel tool calls.
