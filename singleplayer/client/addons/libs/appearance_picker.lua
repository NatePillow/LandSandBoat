-- appearance_picker.lua
--
-- Shared primitives for character appearance / identity pickers (race, gender,
-- face, size, nation) plus the race<->gender<->encoded-race mapping.
--
-- Background: FFXI encodes race AND gender into a single 1-8 "race" value
-- (char_look.race). Humans think of those as two separate choices, so the UI
-- exposes a Race group + a Gender toggle and this module folds them back into
-- the 1-8 the server wants. Mithra (7) and Galka (8) are single-gender.
--
-- Lifted from automog/status_tab.lua's Change Look editor so the create-character
-- tab and (later) that editor can share one copy. Kept UI-agnostic: label + cycle
-- helpers only, no imgui calls, so callers own their own widget layout.

local M = {};

-- Encoded 1-8 labels (match char_look.race). Kept for popups / debug.
M.RACE_NAMES = {
    [1] = 'Hume M', [2] = 'Hume F', [3] = 'Elvaan M', [4] = 'Elvaan F',
    [5] = 'Taru M', [6] = 'Taru F', [7] = 'Mithra',   [8] = 'Galka',
};
M.SIZE_NAMES   = { [0] = 'Small', [1] = 'Medium', [2] = 'Large' };
M.NATION_NAMES = { [0] = "San d'Oria", [1] = 'Bastok', [2] = 'Windurst' };

-- Race groups (gender-agnostic) shown in the Race picker.
M.RACE_GROUPS = { [1] = 'Hume', [2] = 'Elvaan', [3] = 'Tarutaru', [4] = 'Mithra', [5] = 'Galka' };
M.GENDER_MALE   = 0;
M.GENDER_FEMALE = 1;
M.GENDER_NAMES  = { [0] = 'Male', [1] = 'Female' };

-- Which genders each race group allows. Mithra is female-only, Galka male-only.
M.GROUP_GENDERS = {
    [1] = { M.GENDER_MALE, M.GENDER_FEMALE }, -- Hume
    [2] = { M.GENDER_MALE, M.GENDER_FEMALE }, -- Elvaan
    [3] = { M.GENDER_MALE, M.GENDER_FEMALE }, -- Tarutaru
    [4] = { M.GENDER_FEMALE },                -- Mithra
    [5] = { M.GENDER_MALE },                  -- Galka
};

-- ---- label helpers ----
function M.race_group_label(g)  return M.RACE_GROUPS[g] or ('?' .. tostring(g)); end
function M.gender_label(g)      return M.GENDER_NAMES[g] or ('?' .. tostring(g)); end
function M.race_label(v)        return M.RACE_NAMES[v] or ('?' .. tostring(v)); end
function M.size_label(v)        return M.SIZE_NAMES[v] or ('?' .. tostring(v)); end
function M.nation_label(v)      return M.NATION_NAMES[v] or ('?' .. tostring(v)); end
function M.face_label(v)
    -- Interleaved: face = (num-1)*2 + variant, even = A, odd = B.
    local num     = math.floor(v / 2) + 1;
    local variant = (v % 2 == 0) and 'A' or 'B';
    return string.format('%d%s', num, variant);
end

-- Wrap-around cycle within [lo, hi]. Matches status_tab.lua's cycle().
function M.cycle(lo, hi, val, dir)
    local span = hi - lo + 1;
    return ((val - lo + dir) % span) + lo;
end

-- Does this race group allow this gender?
function M.group_allows_gender(group, gender)
    for _, g in ipairs(M.GROUP_GENDERS[group] or {}) do
        if g == gender then return true; end
    end
    return false;
end

-- The gender a group defaults/snaps to when the current one is invalid
-- (e.g. switching to Mithra while "Male" is selected -> Female).
function M.first_gender_for_group(group)
    return (M.GROUP_GENDERS[group] or { M.GENDER_MALE })[1];
end

-- Fold (race group 1-5, gender 0/1) -> encoded char_look.race (1-8).
-- Single-gender groups ignore the passed gender.
function M.encode_race(group, gender)
    if group == 4 then return 7; end -- Mithra (female-only)
    if group == 5 then return 8; end -- Galka (male-only)
    -- Hume/Elvaan/Tarutaru: pairs (M, F) at (1,2)(3,4)(5,6).
    local base = (group - 1) * 2 + 1;
    return (gender == M.GENDER_FEMALE) and (base + 1) or base;
end

-- Split an encoded 1-8 race back into (group, gender).
function M.decode_race(encoded)
    if encoded == 7 then return 4, M.GENDER_FEMALE; end -- Mithra
    if encoded == 8 then return 5, M.GENDER_MALE;   end -- Galka
    local group  = math.floor((encoded - 1) / 2) + 1;
    local gender = ((encoded - 1) % 2 == 0) and M.GENDER_MALE or M.GENDER_FEMALE;
    return group, gender;
end

-- Valid ranges (inclusive), for callers building cycle/popup widgets.
M.FACE_LO, M.FACE_HI     = 0, 15;
M.SIZE_LO, M.SIZE_HI     = 0, 2;
M.NATION_LO, M.NATION_HI = 0, 2;
M.GROUP_LO, M.GROUP_HI   = 1, 5;

return M;
