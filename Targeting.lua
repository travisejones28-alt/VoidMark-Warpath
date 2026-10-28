local _, W = ...
W.Targeting = {}
function W.Targeting:AddCurrent()
    local s = W.Compat:Snapshot('target')
    if not s then return nil, 'Select a player whose identity is exposed by the client.' end
    if s.kind ~= 'player' then return nil, 'Add Target accepts players; use /warpath npc Name for NPCs.' end
    local name, realm = W.Compat:Read(UnitName, 'target')
    return W.DB:Add(name .. ((realm and realm ~= '') and '-' .. realm or ''))
end
function W.Targeting:SetMode(mode, spell)
    local settings = W.DB.data.settings
    if mode == 'spell' then
        local valid, err = W.Macros:ValidateSpell(spell)
        if not valid then return nil, err end
        settings.spell = valid
    end
    settings.mode = mode == 'spell' and 'spell' or 'target'
    W:Changed()
    return true
end
