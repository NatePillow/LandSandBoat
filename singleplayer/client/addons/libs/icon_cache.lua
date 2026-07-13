-- icon_cache: shared D3D-texture loader for FFXI status / spell / ability /
-- item icons that addons want to render via imgui.Image.
--
-- Why this exists: ADKv3's AshitaCore:GetResourceManager():GetStatusIconById
-- returns a struct with raw .Bitmap bytes and no Lua-callable path to turn
-- those into a IDirect3DTexture8* (which imgui.Image expects). The native
-- v3 path that DOES work — ashita.d3dx.CreateTextureFromFileA(path) — needs
-- the icon as a file on disk. So addons bundle pre-extracted PNGs and
-- load through this helper.
--
-- Source for the PNG files: extract from FFXI's status DAT via NoeSis or an
-- equivalent tool, or pull from an existing icon pack. Drop into the
-- addon's icon dir (e.g. addons/autobots/icons/<effectId>.png). Whatever
-- IDs aren't bundled gracefully fall through to the caller's fallback
-- (typically the name text from GetString("statusnames", id, 2)).
--
-- Usage:
--   local icon_cache = require('icon_cache');
--   local store = icon_cache.new(_addon.path .. 'icons/');
--   local tex = store:get(effectId);
--   if tex ~= nil then
--       imgui.Image(tex, 24, 24);
--   else
--       imgui.Text(name_for(effectId));
--   end
--
-- Lazy-loads textures on first request, caches forever. d3d8 textures are
-- released by Ashita on addon unload (no explicit Release call needed —
-- matching yield's pattern).

require 'd3d8';

local icon_cache = {};
icon_cache.__index = icon_cache;

-- Create a store rooted at base_dir. base_dir should end in a trailing slash
-- and contain files named "<id>.png" (or ".bmp" / ".jpg" / ".dds" — D3DX
-- handles them all).
function icon_cache.new(base_dir)
    local self = setmetatable({}, icon_cache);
    self.base_dir = base_dir or '';
    self.cache    = {};       -- [id] = texture | false (false = tried and failed)
    return self;
end

-- Probe the same id with each plausible extension. PNG is the convention
-- but BMP is what FFXI's icon DAT exports look like before conversion, so
-- we tolerate both — and DDS in case someone bundles pre-compressed icons.
local EXTENSIONS = { '.png', '.bmp', '.dds', '.jpg' };

local function try_load(base_dir, id)
    if ashita == nil or ashita.d3dx == nil or ashita.d3dx.CreateTextureFromFileA == nil then
        return nil;
    end
    for _, ext in ipairs(EXTENSIONS) do
        local path = string.format('%s%d%s', base_dir, id, ext);
        local ok, hres, tex = pcall(function()
            return ashita.d3dx.CreateTextureFromFileA(path);
        end);
        if ok and tex ~= nil then
            return tex;
        end
    end
    return nil;
end

-- Returns the ImTextureID void* suitable for imgui.Image(), or nil if no
-- bundled icon exists for this id. Result is cached; repeat calls are
-- O(1) hash lookups.
function icon_cache:get(id)
    if id == nil then return nil; end
    local cached = self.cache[id];
    if cached ~= nil then
        -- false (= negative cache) bubbles up as nil; an actual texture
        -- returns its underlying ImTextureID via :Get().
        if cached == false then return nil; end
        return cached:Get();
    end
    local tex = try_load(self.base_dir, id);
    if tex == nil then
        self.cache[id] = false;
        return nil;
    end
    self.cache[id] = tex;
    return tex:Get();
end

-- Force-evict an id from the cache. Useful if PNGs are added to the dir
-- at runtime and the addon wants to re-probe.
function icon_cache:evict(id)
    self.cache[id] = nil;
end

-- Drop everything. Doesn't explicitly release textures — Ashita cleans
-- them up on addon unload; calling this just lets Lua GC drop the wrappers.
function icon_cache:reset()
    self.cache = {};
end

return icon_cache;
