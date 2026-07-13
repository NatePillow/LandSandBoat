---
name: ascii-only-in-chat-strings
description: HARD RULE — any string that reaches the FFXI client chat log must be ASCII. Em-dashes, smart quotes, en-dashes, ellipses, bullets all mangle into mojibake (CP932/Shift-JIS reinterpretation of UTF-8 bytes).
metadata:
  type: feedback
---

Any string literal that ends up in the FFXI client's chat log MUST be plain ASCII. No em-dashes (—), en-dashes (–), smart quotes ("" '' ‚ „), smart apostrophes ('), ellipses (…), bullets (•), or other typographic Unicode.

**Why:** The FFXI client renders chat text through a CP932 (Shift-JIS) decoder. A UTF-8 em-dash is three bytes (E2 80 94); the client reinterprets that as a Shift-JIS multi-byte sequence and renders garbage like `窶鈍` instead of `—`. The line becomes ambiguous to read and embarrassing in logs the user pastes back. This is a CHRONIC mistake on my part — the user has called it out multiple times across sessions and I keep regressing because my writing-style default leans typographic.

**How to apply:**

Before writing any of these, mentally check the string for non-ASCII:
- `autoutil.log(tag, msg)` — addon side, chat log
- `printf(...)` in server-side Lua under `modules/singleplayer/` — server stdout, but messages echo to client when relayed
- Any string passed to `AddChatString`, `SendChatString`, or similar Ashita chat sinks
- `ShowDebug` / `ShowInfo` / `ShowWarning` server-side strings, if they ever get forwarded to the client

Substitutions (always use the right column):

| Typographic (BAD)  | ASCII (GOOD)         |
|--------------------|----------------------|
| `—` (em-dash)      | ` - ` or ` -- `      |
| `–` (en-dash)      | ` - `                |
| `"` `"` (smart dq) | `"` (straight)       |
| `'` `'` (smart sq) | `'` (straight)       |
| `…` (ellipsis)     | `...`                |
| `•` (bullet)       | `*` or `-`           |
| `→` `←` `↑` `↓`    | `->` `<-` `^` `v`    |
| `×`                | `x`                  |
| `°`                | ` deg` or omit       |

**OK in:**
- Lua / C++ comments (never sent to chat).
- Markdown documentation files (READMEs, design docs).
- Commit messages.

**NOT OK in:**
- Any string literal that flows into a chat log on the client side.
- Strings shown in Ashita logging APIs that route to the FFXI chat window.

**Quick mechanical check before committing:**
```bash
grep -rn "autoutil\.log\|printf" singleplayer/client/addons modules/singleplayer/bots | grep -P "[—–''""…•→←↑↓×°]"
```
Should return nothing. If it returns anything, fix those lines.

**Root cause of the recurring lapse:** My default writing style prefers typographic punctuation (em-dashes for parenthetical asides, smart quotes for dialogue). When I write Lua string literals, I'm in "writing English" mode and the typographic chars slip in automatically. The fix is to enter "writing for a non-Unicode console" mode whenever I touch a `log(...)` or `printf(...)` call. The grep above is the safety net when the discipline fails.

See also: [[never_silence_logs]] for the broader log-hygiene posture.
