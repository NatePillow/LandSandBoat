-- loading_overlay: generic tab-scoped "this section is busy" lock.
--
-- Any addon tab (or subsection) can call begin(key, label) to mark itself
-- busy, then done(key) when the operation completes. Renderers check
-- is_locked(key) at the top of their body — if true, they render the
-- overlay instead of the normal tab content and early-return. Full-tab
-- replacement, not a modal — the user can't interact with the tab's
-- normal controls while it's locked.
--
-- Typical usage inside an addon tab:
--     if loading_overlay.is_locked('automog:ah') then
--         loading_overlay.render('automog:ah');
--         return;
--     end
--     -- ... normal tab content ...
--     if imgui.Button('Sell') then
--         loading_overlay.begin('automog:ah', 'Listing item...');
--         http_client.await_op('/ah/sell', body, nil, function(result, err)
--             loading_overlay.done('automog:ah');
--             if err then autoutil.log('AutoSell', 'sell: ' .. err); end
--         end);
--     end
--
-- Keys are freeform strings so different tabs don't collide (prefer
-- 'addon:tab' or 'addon:section' shape). Multiple keys can be locked
-- simultaneously; each is independent.
--
-- Safety: if a caller forgets to call done(), the lock hangs. Every begin
-- stamps the start time so the overlay shows elapsed seconds — a lock
-- that's been up 30s+ is a bug worth investigating. There is intentionally
-- NO auto-unlock timer; that would mask forgotten done() calls.

local M = {};

local locks = {};  -- key -> { label = str, started_at = os.clock() }

function M.begin(key, label)
    locks[key] = { label = tostring(label or 'Working...'), started_at = os.clock() };
end

function M.done(key)
    locks[key] = nil;
end

function M.is_locked(key)
    return locks[key] ~= nil;
end

function M.label(key)
    local L = locks[key];
    return L and L.label or nil;
end

function M.elapsed_s(key)
    local L = locks[key];
    return L and (os.clock() - L.started_at) or 0;
end

-- Render the overlay centered in the current window's content area. Uses
-- only imgui primitives so it composes with any tab layout. Renders three
-- lines: label, elapsed, and a spinner (dots animating on the seconds tick).
-- Caller should render()->return at the top of their tab body.
function M.render(key)
    local L = locks[key];
    if L == nil then return; end
    local elapsed = os.clock() - L.started_at;
    imgui.Spacing();
    imgui.Spacing();
    imgui.Text(L.label);
    imgui.Spacing();
    -- ASCII spinner: dots cycle 1..3 based on 3Hz clock. Keeps things
    -- visibly moving so the user knows the UI isn't stuck.
    local dot_count = math.floor(elapsed * 3) % 4;
    local dots      = string.rep('.', dot_count);
    imgui.TextDisabled(string.format('%s%s', dots, string.rep(' ', 3 - dot_count)));
    imgui.Spacing();
    imgui.TextDisabled(string.format('%.1fs elapsed', elapsed));
end

return M;
