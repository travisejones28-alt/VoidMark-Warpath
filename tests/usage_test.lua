-- Tests the shared addon Usage.lua with mocked WoW APIs (Lua 5.1).
--   lua5.1 tests/usage_test.lua [path/to/Usage.lua]   (default: addon-shared/Usage.lua)
local path = arg[1] or "addon-shared/Usage.lua"
local src = assert(io.open(path)):read("*a")

local function newWorld(addonName)
    local W = { now = 1763300000, clock = 100, timers = {}, frames = {} }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.time = function() return W.now end
    env.GetTime = function() return W.clock end
    env.SlashCmdList = {}
    env.C_Timer = { After = function(s, fn) W.timers[#W.timers + 1] = fn end }
    env.C_AddOns = { GetAddOnMetadata = function(name, field) if field == "Version" then return "9.9.9" end end }
    env.hooksecurefunc = function(t, k, hook)
        local orig = t[k]
        t[k] = function(...) local r = orig(...); hook(...); return r end
    end
    local function frame(name)
        local f = { scripts = {}, hooks = {} }
        function f:RegisterEvent(e) self.event = e end
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:HookScript(k, fn) self.hooks[k] = self.hooks[k] or {}; table.insert(self.hooks[k], fn) end
        function f:Fire(k) for _, fn in ipairs(self.hooks[k] or {}) do fn(self) end end
        if name then env[name] = f end
        W.frames[#W.frames + 1] = f
        return f
    end
    env.CreateFrame = function(_, name) return frame(name) end
    W.frame, W.env = frame, env
    local chunk = assert(loadstring(src, "Usage.lua"))
    setfenv(chunk, env)
    chunk(addonName, {})
    W.events = W.frames[1]
    W.login = function() W.events.scripts.OnEvent(W.events, "PLAYER_LOGIN") end
    return W
end

local passed = 0
local function test(name, fn) fn(); passed = passed + 1; print("  ok    " .. name) end

test("login stamps init and version only; nothing counts as use yet", function()
    local W = newWorld("VoidMarkMarket")
    W.login()
    local u = W.env.VoidMarkMarketUsage
    assert(u.init == 1763300000 and u.version == "9.9.9" and u.v == 1)
    assert(u.active == nil, "login is not use")
    local keys = 0; for _ in pairs(u) do keys = keys + 1 end
    assert(keys == 3, "only v, init, version")
end)

test("saved data from earlier sessions is kept and updated", function()
    local W = newWorld("VoidMarkMarket")
    W.env.VoidMarkMarketUsage = { v = 1, init = 1, active = 5 }
    W.login()
    assert(W.env.VoidMarkMarketUsage.init == 1763300000)
    assert(W.env.VoidMarkMarketUsage.active == 5)
end)

test("slash command marks active use and still runs the addon's command", function()
    local W = newWorld("VoidMarkNexus")
    local ran = 0
    W.env.SlashCmdList.VOIDMARKNEXUS = function() ran = ran + 1 end
    W.login()
    W.now = W.now + 60
    W.env.SlashCmdList.VOIDMARKNEXUS("routes")
    assert(ran == 1, "original command ran")
    assert(W.env.VoidMarkNexusUsage.active == 1763300060)
end)

test("window shown right after login is ignored; later shows count", function()
    local W = newWorld("VoidMarkMarket")
    local win = W.frame("VoidMarkMarketWindow")
    W.login()
    win:Fire("OnShow")
    assert(W.env.VoidMarkMarketUsage.active == nil, "auto-show at login ignored")
    W.clock = W.clock + 30; W.now = W.now + 30
    win:Fire("OnShow")
    assert(W.env.VoidMarkMarketUsage.active == 1763300030)
end)

test("windows created later are watched after first use or the delayed retry", function()
    local W = newWorld("VoidMarkDebug")
    W.env.SlashCmdList.VOIDMARKDEBUG = function() if not W.env.VoidMarkDebugWindow then W.frame("VoidMarkDebugWindow") end end
    W.login()
    W.env.SlashCmdList.VOIDMARKDEBUG("")
    assert(W.env.VoidMarkDebugWindow.hooks.OnShow, "hooked after the command made it")
    local W2 = newWorld("VoidMarkDebug")
    W2.login()
    W2.frame("VoidMarkDebugProblem")
    for _, fn in ipairs(W2.timers) do fn() end
    assert(W2.env.VoidMarkDebugProblem.hooks.OnShow, "hooked by the retry")
end)

test("minimap button click marks use", function()
    local W = newWorld("VoidMarkForever")
    local b = W.frame("VoidMarkMinimapButton")
    W.login()
    b:Fire("OnClick")
    assert(W.env.VoidMarkForeverUsage.active == 1763300000)
end)

test("hooks are added once, and other addons' commands are not watched", function()
    local W = newWorld("VoidMarkJourney")
    local n = 0
    W.env.SlashCmdList.VOIDMARKJOURNEY = function() n = n + 1 end
    W.env.SlashCmdList.VOIDMARKMINIMAP = function() end
    W.login(); W.login()
    for _, fn in ipairs(W.timers) do fn() end
    W.env.SlashCmdList.VOIDMARKJOURNEY("")
    assert(n == 1, "wrapped once")
    W.env.SlashCmdList.VOIDMARKMINIMAP("")
    assert(W.env.VoidMarkJourneyUsage.active ~= nil)
end)

test("broken APIs never raise errors", function()
    local W = newWorld("VoidMarkMiniMap")
    W.env.time = function() error("secret value") end
    W.env.GetTime = function() error("nope") end
    W.env.C_AddOns = nil
    W.env.hooksecurefunc = function() error("blocked") end
    W.env.SlashCmdList.VOIDMARKHERB = function() end
    W.login()
    W.env.SlashCmdList.VOIDMARKHERB("")
end)

test("an unknown addon only records loading", function()
    local W = newWorld("SomethingElse")
    W.login()
    assert(W.env.SomethingElseUsage.init == 1763300000)
end)

print(passed .. " passed")
