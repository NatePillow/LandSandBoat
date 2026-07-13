-- http_client: non-blocking HTTP client over LuaSocket TCP. Drives the map
-- server's loopback / LAN config HTTP server (src/map/singleplayer/
-- config_http_server.cpp).
--
-- Why the rewrite (vs the sync socket.http wrapper that lived here before):
--   socket.http.request blocks the calling Lua thread for the duration of
--   the request. In Ashita v3 that thread is the FFXI client's main loop —
--   blocking it doesn't just freeze the UI, it stops the client from
--   pumping FFXI keepalive packets, so the server flags the session as a
--   disconnect after ~30 s. Even a single 5 s HTTP timeout was enough to
--   reliably trip that. The right answer is non-blocking sockets +
--   cooperative coroutines, scheduled off the per-frame `d3d_present`
--   event so requests advance one socket-step per frame and the main loop
--   stays free in between.
--
-- API:
--   local http = require('http_client');
--   http.get(path, function(code, body, headers, err) ... end);
--   http.put(path, body, content_type, function(code, body, headers, err) ... end);
--   http.delete_(path, function(code, body, headers, err) ... end);
--
--   Callbacks fire later (on a future frame). On HTTP response: code is the
--   numeric status (200/304/404/...), body is the response body string,
--   headers is a table { ['etag'] = '...', ... }, err is nil.
--   On connection-level failure: code is nil, body is nil, headers is nil,
--   err is the socket error string ('timeout', 'connection refused', ...).
--
-- Conditional GET:
--   http.get(path, function(...) end, { if_none_match = '"1234"' })
--
-- Lower-level: http.go(fn) spawns a coroutine for sequential multi-step
-- flows; inside fn you can call http.get_sync / put_sync / delete_sync
-- and they will yield until the response arrives. NOTE: those _sync
-- variants only work from inside an http.go() coroutine — calling them
-- from arbitrary main-thread code will error.

require('socket');
local socket = require('socket');

local http_client = {};

-- =====================================================================
-- END-USER CONFIG: edit HOST/PORT here to match your deployment.
-- =====================================================================
-- These have to agree with the server's CONFIG_HTTP_BIND_ADDR /
-- CONFIG_HTTP_PORT in settings/singleplayer.lua — same port on both
-- sides, and HOST is an IP the server is actually bound on AND that
-- this client machine can reach.
--
-- HOST: the IP/hostname where the map server is reachable from THIS
-- machine (the client's machine).
--   - Same machine as server         → '127.0.0.1'
--   - Win10 VM on the Linux host
--     - VirtualBox/QEMU NAT (default) → '10.0.2.2'
--     - VirtualBox bridged adapter   → the host's LAN IP (`route print 0.0.0.0` in cmd)
--     - VMware NAT                   → '192.168.x.1' (varies)
--   - Different physical machine     → the server's LAN IP
-- If unsure, the rule of thumb: use the same address you use in your
-- FFXI client to connect to the map server, or run `route print 0.0.0.0`
-- in the VM cmd and take the Gateway column.
--
-- PORT: must match settings/singleplayer.lua CONFIG_HTTP_PORT.
--
-- Curl sanity check from inside the client machine:
--   curl http://<HOST>:<PORT>/healthz   # should return "ok"
-- =====================================================================
http_client.HOST = '192.168.40.92';
http_client.PORT = 51220;

-- Per-step deadline (seconds since start). A request that doesn't complete
-- by this much wall-clock time gets killed with err = 'timeout'. Counts
-- across yields, so this is end-to-end not per-poll.
local REQUEST_TIMEOUT_S = 10;

-- =====================================================================
-- Coroutine scheduler.
-- =====================================================================
-- Each in-flight HTTP request is a coroutine. tick() walks the pending
-- list and resumes each coroutine once per frame; the coroutine yields
-- when its socket would block. Finished / errored coroutines are removed.
local pending = {};

local function schedule(co)
    table.insert(pending, co);
end

local function tick_scheduler()
    local i = 1;
    while i <= #pending do
        local co = pending[i];
        local ok, err = coroutine.resume(co);
        if not ok then
            -- Coroutine itself errored — log and drop.
            print(string.format('[http_client] coroutine error: %s', tostring(err)));
            table.remove(pending, i);
        elseif coroutine.status(co) == 'dead' then
            table.remove(pending, i);
        else
            i = i + 1;
        end
    end
end

-- Auto-registration of the frame tick was REMOVED because multiple
-- ashita.register_event('render', fn) calls in the same Lua state collide -
-- depending on require order, either the addon's UI render handler or this
-- scheduler tick gets clobbered, and the addon either has no UI or has no
-- working HTTP scheduler.
--
-- New contract: every addon that uses http_client must call http_client.tick()
-- ONCE per frame from its own existing render hook. The cost is one extra
-- line in the addon's render callback, in exchange for not stomping on the
-- addon's UI registration.
--
-- Example:
--   ashita.register_event('render', function()
--       http_client.tick();        -- advance pending HTTP coroutines
--       ... existing UI render ...
--   end);
http_client.tick = tick_scheduler;

-- =====================================================================
-- Non-blocking HTTP request primitive.
-- =====================================================================
-- Drives the full lifecycle of one request: connect → send → receive →
-- parse. Each socket call uses settimeout(0) (non-blocking), and on a
-- 'timeout' result we coroutine.yield() so the main thread keeps moving.
-- Must be called from a coroutine (i.e. via schedule/go).
--
-- Returns: code, body, headers   on HTTP response
--          nil,  nil,  nil, err  on connection-level failure
local function do_request(method, path, opts)
    opts = opts or {};
    local body_out = opts.body or '';
    local started_at = os.clock();
    -- Per-call host/port override so the conntest command (and any future
    -- diagnostic tool) can target a bad address without mutating the
    -- global default. Falls through to the configured HOST/PORT otherwise.
    local host = opts.host or http_client.HOST;
    local port = opts.port or http_client.PORT;

    local function deadline_hit()
        return (os.clock() - started_at) > REQUEST_TIMEOUT_S;
    end

    -- ----- connect -----
    local sock = socket.tcp();
    if sock == nil then
        return nil, nil, nil, 'tcp create failed';
    end
    sock:settimeout(0);

    local connected, err = sock:connect(host, port);
    while not connected do
        if err == 'already connected' then
            break;
        elseif err == 'timeout' or err == 'Operation already in progress' then
            if deadline_hit() then sock:close(); return nil, nil, nil, 'timeout'; end
            coroutine.yield();
            connected, err = sock:connect(host, port);
        else
            sock:close();
            return nil, nil, nil, tostring(err);
        end
    end

    -- ----- build request -----
    local req_lines = {
        string.format('%s %s HTTP/1.1', method, path),
        string.format('Host: %s:%d', host, port),
        'Connection: close',
        'User-Agent: ashita-http_client/1.0',
    };
    if opts.content_type then
        table.insert(req_lines, 'Content-Type: ' .. opts.content_type);
    end
    if opts.if_none_match then
        table.insert(req_lines, 'If-None-Match: ' .. opts.if_none_match);
    end
    if #body_out > 0 or method == 'PUT' or method == 'POST' then
        table.insert(req_lines, 'Content-Length: ' .. tostring(#body_out));
    end
    table.insert(req_lines, '');
    table.insert(req_lines, body_out);
    local request = table.concat(req_lines, '\r\n');

    -- ----- send -----
    local sent_so_far = 0;
    while sent_so_far < #request do
        local sent, send_err, partial = sock:send(request, sent_so_far + 1);
        if sent then
            sent_so_far = sent;
        elseif send_err == 'timeout' then
            if partial then sent_so_far = partial; end
            if deadline_hit() then sock:close(); return nil, nil, nil, 'timeout'; end
            coroutine.yield();
        else
            sock:close();
            return nil, nil, nil, tostring(send_err);
        end
    end

    -- ----- receive (until connection closed; we set Connection: close so
    -- server signals end-of-response by closing the socket) -----
    local chunks = {};
    while true do
        local data, recv_err, partial = sock:receive(8192);
        if data then
            table.insert(chunks, data);
        else
            if partial and partial ~= '' then table.insert(chunks, partial); end
            if recv_err == 'closed' then
                break;
            elseif recv_err == 'timeout' then
                if deadline_hit() then sock:close(); return nil, nil, nil, 'timeout'; end
                coroutine.yield();
            else
                sock:close();
                return nil, nil, nil, tostring(recv_err);
            end
        end
    end
    sock:close();

    local raw = table.concat(chunks);

    -- ----- parse response -----
    local status_end = raw:find('\r\n');
    if status_end == nil then
        return nil, nil, nil, 'malformed response (no status line)';
    end
    local status_line = raw:sub(1, status_end - 1);
    local code_str = status_line:match('^HTTP/[%d%.]+ (%d+)');
    local code = tonumber(code_str);
    if code == nil then
        return nil, nil, nil, 'malformed response (bad status: ' .. status_line .. ')';
    end

    -- Headers
    local headers = {};
    local pos = status_end + 2;
    while true do
        local nl = raw:find('\r\n', pos, true);
        if nl == nil then
            return code, '', headers, nil;
        end
        local line = raw:sub(pos, nl - 1);
        if line == '' then
            -- Blank line — body starts at nl + 2
            local body = raw:sub(nl + 2);
            return code, body, headers, nil;
        end
        local k, v = line:match('^([^:]+):%s*(.*)$');
        if k then
            headers[k:lower()] = v;
        end
        pos = nl + 2;
    end
end

-- =====================================================================
-- Public API: callback-style.
-- =====================================================================

-- Generic dispatch: spawn a coroutine that runs do_request and fires the
-- callback when done. Callback signature: (code, body, headers, err).
local function dispatch(method, path, opts, callback)
    callback = callback or function() end;
    local co = coroutine.create(function()
        local code, body, headers, err = do_request(method, path, opts);
        local ok, cb_err = pcall(callback, code, body, headers, err);
        if not ok then
            print(string.format('[http_client] callback error for %s %s: %s',
                method, path, tostring(cb_err)));
        end
    end);
    schedule(co);
end

function http_client.get(path, callback, opts)
    opts = opts or {};
    dispatch('GET', path, { if_none_match = opts.if_none_match }, callback);
end

function http_client.put(path, body, content_type, callback)
    dispatch('PUT', path, {
        body = body or '',
        content_type = content_type or 'application/octet-stream',
    }, callback);
end

function http_client.post(path, body, content_type, callback)
    dispatch('POST', path, {
        body = body or '',
        content_type = content_type or 'application/octet-stream',
    }, callback);
end

function http_client.delete_(path, callback)
    dispatch('DELETE', path, {}, callback);
end

-- =====================================================================
-- after_ms(ms, fn) — schedule fn() to run after `ms` milliseconds have
-- elapsed on the render-tick clock. Implemented as a no-op coroutine
-- that yields until deadline. Used by await_op below for polling cadence
-- without touching a real timer / thread.
--
-- Callers must be inside an http_client.tick() driven runtime (i.e. the
-- addon's render event is calling tick each frame). Firing outside that
-- context queues the closure but it never runs.
-- =====================================================================
function http_client.after_ms(ms, fn)
    local deadline = os.clock() + (ms / 1000);
    local co = coroutine.create(function()
        while os.clock() < deadline do
            coroutine.yield();
        end
        local ok, err = pcall(fn);
        if not ok then
            print(string.format('[http_client] after_ms callback error: %s', tostring(err)));
        end
    end);
    schedule(co);
end

-- =====================================================================
-- await_op(post_path, body, opts, onDone)
-- =====================================================================
-- Generic async-op driver over the map's op_registry:
--   1. POST body (JSON) to post_path
--   2. Expect 202 Accepted + { opId: "<id>" }
--   3. Poll GET /ops/<opId> every opts.poll_ms (default 500) until the
--      op reports status = 'success' or 'failed' (or opts.timeout_ms is hit)
--   4. Call onDone(result, err) exactly once
--
--   result on success: { status = 'success', kind = <str>, message = <str>, opId = <str> }
--   err on failure:    string reason ('timeout' / 'expired' / server message / etc.)
--
-- Encoding: body must be a Lua table; encoded to JSON with the addon's
-- json module. If you already have a raw string, pass it as-is (we detect
-- string vs table and skip encoding on the string path).
-- =====================================================================
local _json = require('json');

function http_client.await_op(post_path, body, opts, onDone)
    opts   = opts or {};
    onDone = onDone or function() end;
    local poll_ms    = opts.poll_ms    or 500;
    local timeout_ms = opts.timeout_ms or 15000;
    local body_str;
    if type(body) == 'string' then
        body_str = body;
    else
        body_str = _json:encode(body or {});
    end
    http_client.post(post_path, body_str, 'application/json',
        function(code, res_body, _, err)
            if err ~= nil then
                onDone(nil, 'kickoff: ' .. tostring(err));
                return;
            end
            if code ~= 202 then
                onDone(nil, string.format('kickoff: HTTP %d %s', code, tostring(res_body)));
                return;
            end
            local ok, parsed = pcall(function() return _json:decode(res_body); end);
            if not ok or type(parsed) ~= 'table' or parsed.opId == nil then
                onDone(nil, 'kickoff: bad response body');
                return;
            end
            local opId    = tostring(parsed.opId);
            local started = os.clock();
            local function poll()
                http_client.get('/ops/' .. opId, function(gcode, gbody, _, gerr)
                    if gerr ~= nil then
                        onDone(nil, 'poll: ' .. tostring(gerr));
                        return;
                    end
                    if gcode == 404 then
                        onDone(nil, 'op expired or unknown');
                        return;
                    end
                    if gcode ~= 200 then
                        onDone(nil, string.format('poll: HTTP %d', gcode));
                        return;
                    end
                    local ok2, p = pcall(function() return _json:decode(gbody); end);
                    if not ok2 or type(p) ~= 'table' then
                        onDone(nil, 'poll: bad status body');
                        return;
                    end
                    if p.status == 'success' then
                        p.opId = opId;
                        onDone(p, nil);
                        return;
                    end
                    if p.status == 'failed' then
                        onDone(nil, p.message or 'failed');
                        return;
                    end
                    if (os.clock() - started) * 1000 > timeout_ms then
                        onDone(nil, 'timeout');
                        return;
                    end
                    http_client.after_ms(poll_ms, poll);
                end);
            end
            poll();
        end);
end

-- =====================================================================
-- /healthz probe (callback-style).
-- =====================================================================
function http_client.is_up(callback)
    http_client.get('/healthz', function(code)
        callback(code == 200);
    end);
end

-- =====================================================================
-- Explicit-host GET — bypass the global HOST/PORT for one request.
-- Used by /autobots conntest and any future diagnostic that needs to
-- probe a specific address without mutating http_client.HOST.
-- =====================================================================
function http_client.get_at(host, port, path, callback)
    dispatch('GET', path, { host = host, port = port }, callback);
end

-- =====================================================================
-- Low-level: http_client.go(fn) — wrap user code in a coroutine so it
-- can use the *_sync variants below. Useful for multi-step flows.
-- =====================================================================
function http_client.go(fn)
    schedule(coroutine.create(fn));
end

-- These must be called from inside an http_client.go() coroutine. Each
-- one yields until the response arrives, then returns it sync-style.
function http_client.get_sync(path, opts)
    opts = opts or {};
    return do_request('GET', path, { if_none_match = opts.if_none_match });
end

function http_client.put_sync(path, body, content_type)
    return do_request('PUT', path, {
        body = body or '',
        content_type = content_type or 'application/octet-stream',
    });
end

function http_client.delete_sync(path)
    return do_request('DELETE', path, {});
end

return http_client;
