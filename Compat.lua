local _, W = ...
local C = {}
W.Compat = C
C.interface = select(4, GetBuildInfo()) or 0
C.forever = C.interface >= 16000 and C.interface < 17000
C.era = C.interface >= 11500 and C.interface < 11600
function C:Combat() return InCombatLockdown and InCombatLockdown() end
-- Never compare, concatenate, or branch on a secret return value.
function C:Read(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    if issecretvalue and (issecretvalue(a) or issecretvalue(b) or issecretvalue(c)) then return nil end
    return a, b, c
end
function C:Realm(realm)
    realm = realm or self:Read(GetNormalizedRealmName) or self:Read(GetRealmName) or ''
    return string.lower((realm:gsub('[%s%-%\']', '')))
end
function C:Snapshot(unit)
    if not self:Read(UnitExists, unit) then return nil end
    local name, realm = self:Read(UnitName, unit)
    local guid = self:Read(UnitGUID, unit)
    local player = self:Read(UnitIsPlayer, unit)
    if type(name) ~= 'string' or name == '' or type(guid) ~= 'string' or player == nil then return nil end
    return { name = name, realm = self:Realm(realm ~= '' and realm or nil), guid = guid,
        kind = player and 'player' or 'npc', hostile = self:Read(UnitCanAttack, 'player', unit),
        dead = self:Read(UnitIsDeadOrGhost, unit), unit = unit }
end
function C:SpellName(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = self:Read(C_Spell.GetSpellInfo, name)
        if info and not (issecretvalue and issecretvalue(info.name)) then return info.name end
    end
    return self:Read(GetSpellInfo, name)
end
function C:Register(event)
    -- Unsupported events differ by client; do not register invalid events blindly.
    local ok = pcall(W.events.RegisterEvent, W.events, event)
    return ok
end
function C:Plates()
    if C_NamePlate and C_NamePlate.GetNamePlates then return self:Read(C_NamePlate.GetNamePlates) or {} end
    return {}
end

function C:MacroLimits()
    local limits = Constants and Constants.MacroConsts
    return (limits and limits.MAX_ACCOUNT_MACROS) or MAX_ACCOUNT_MACROS or 120,
        (limits and limits.MAX_CHARACTER_MACROS) or MAX_CHARACTER_MACROS or 18
end
