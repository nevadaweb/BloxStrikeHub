-- ============================================================
--  BloxStrike Hub v4.2  |  Multi-Executor  |  Xeno / Madium / Synapse
--  Fixes: math.pow→^, Drawing guard, FOV pcall, CleanESP memory leak,
--         WallCheck em todos os modos, SpeedTimer overflow, AntiAFK API,
--         hook nil-guard, noclip event-driven, FlyOn/NoclipOn serializado
--  Features: FlySpeed slider, AimbotLOS (nunca mira em wall), AimbotKey
--            keybind in-game, TriggerDelay configurável, config AimbotKey
-- ============================================================

-- ============================================================
-- §1  ESTADO GLOBAL
-- ============================================================

if not getgenv().BSH then
    getgenv().BSH = {
        AimbotOn    = false,
        AimbotMode  = "Legit",
        FOV         = 120,
        Smoothing   = 0.12,
        JitterSigma = 1.2,
        Prediction  = true,
        LockMs      = 350,
        ADSOnly     = false,
        AimPart     = "Head",
        SilentAim   = false,
        AimbotLOS   = true,
        Triggerbot    = false,
        TriggerDelay  = 80,
        AimbotKey     = Enum.KeyCode.Unknown,
        TeamCheck     = true,
        NoRecoil    = false,
        NoRecoilStr = 0.85,
        WallCheck   = false,
        ESPOn       = false,
        SkeletonOn  = false,
        HealthBarOn = true,
        TracerOn    = false,
        HeadDotOn   = false,
        ChamsOn     = false,
        ESPColor    = Color3.fromRGB(255, 55, 55),
        LockColor   = Color3.fromRGB(255, 230, 0),
        ChamsColor  = Color3.fromRGB(255, 120, 0),
        SpeedOn     = false,
        WalkSpeed   = 60,
        FlyOn       = false,
        FlySpeed    = 65,
        BunnyHop    = false,
        NoclipOn    = false,
        AntiAFK     = false,
        DrawObjs    = {},
        ChamsObjs   = {},
        Conns       = {},
        Running     = true,
        AimState = {
            jx = 0, jy = 0,
            lockedTarget = nil,
            lockedSince  = 0,
            lastPartPos  = nil,
            lastPartTime = 0,
            headVelocity = Vector3.zero,
        },
        SpeedTimer = 0,
        AFKTimer   = 0,
        LastCamCF  = nil,
        FOVCircle  = nil,
    }
end

local G = getgenv().BSH

-- ============================================================
-- §2  SHIMS DE COMPATIBILIDADE
-- ============================================================

-- Executores que não expõem file API ficam com stubs silenciosos
local _isfile    = (type(isfile)    == "function") and isfile    or function() return false end
local _readfile  = (type(readfile)  == "function") and readfile  or function() return ""    end
local _writefile = (type(writefile) == "function") and writefile or function()               end

-- Drawing: Square e Circle são opcionais em builds antigos do Xeno
local _hasSquare = false
local _hasCircle = false
do
    pcall(function()
        local ok1, s = pcall(Drawing.new, "Square")
        if ok1 and s then _hasSquare = true; pcall(function() s:Remove() end) end
        local ok2, c = pcall(Drawing.new, "Circle")
        if ok2 and c then _hasCircle = true; pcall(function() c:Remove() end) end
    end)
end

-- ============================================================
-- §3  SERVIÇOS & REFERÊNCIAS
-- ============================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local HTTP       = game:GetService("HttpService")
local LP         = Players.LocalPlayer
local Mouse      = LP:GetMouse()
local Camera     = workspace.CurrentCamera

-- ============================================================
-- §4  UTILITÁRIOS MATEMÁTICOS
-- ============================================================

local PI2 = math.pi * 2

local function GaussRand(sigma)
    local u1 = math.max(1e-10, math.random())
    local u2 = math.random()
    return sigma * math.sqrt(-2 * math.log(u1)) * math.cos(PI2 * u2)
end

local function FpsAlpha(base, dt)
    local safe_dt   = math.min(dt, 0.1)
    local safe_base = math.min(base, 0.9999)
    return 1 - (math.max(0, 1 - safe_base) ^ (safe_dt * 60))
end

-- ============================================================
-- §5  CONFIG SAVE / LOAD
-- ============================================================

local CFG_FILE = "BSH_v4_config.json"

local SERIAL_KEYS = {
    "AimbotOn","AimbotMode","FOV","Smoothing","JitterSigma","Prediction","LockMs",
    "ADSOnly","AimPart","SilentAim","AimbotLOS","Triggerbot","TriggerDelay","TeamCheck","NoRecoil","NoRecoilStr","WallCheck",
    "ESPOn","SkeletonOn","HealthBarOn","TracerOn","HeadDotOn","ChamsOn",
    "SpeedOn","WalkSpeed","FlyOn","FlySpeed","BunnyHop","NoclipOn","AntiAFK",
}

local function SaveConfig()
    local t = {}
    for _, k in ipairs(SERIAL_KEYS) do t[k] = G[k] end
    t.ESPColor   = { G.ESPColor.R,   G.ESPColor.G,   G.ESPColor.B   }
    t.LockColor  = { G.LockColor.R,  G.LockColor.G,  G.LockColor.B  }
    t.ChamsColor = { G.ChamsColor.R, G.ChamsColor.G, G.ChamsColor.B }
    t.AimbotKey  = G.AimbotKey.Name  -- serialize Enum as string
    return pcall(_writefile, CFG_FILE, HTTP:JSONEncode(t))
end

local function LoadConfig()
    if not _isfile(CFG_FILE) then return end
    local ok, t = pcall(function() return HTTP:JSONDecode(_readfile(CFG_FILE)) end)
    if not ok or type(t) ~= "table" then return end
    for _, k in ipairs(SERIAL_KEYS) do
        if t[k] ~= nil then G[k] = t[k] end
    end
    if t.ESPColor   then G.ESPColor   = Color3.new(t.ESPColor[1],   t.ESPColor[2],   t.ESPColor[3])   end
    if t.LockColor  then G.LockColor  = Color3.new(t.LockColor[1],  t.LockColor[2],  t.LockColor[3])  end
    if t.ChamsColor then G.ChamsColor = Color3.new(t.ChamsColor[1], t.ChamsColor[2], t.ChamsColor[3]) end
    if type(t.AimbotKey) == "string" then
        local kok, kc = pcall(function() return Enum.KeyCode[t.AimbotKey] end)
        if kok and kc then G.AimbotKey = kc end
    end
end

pcall(LoadConfig)

-- ============================================================
-- §6  RAYFIELD UI  (pcall + CDN de backup)
-- ============================================================

local Rayfield
do
    local urls = {
        "https://sirius.menu/rayfield",
        "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua",
    }
    for _, url in ipairs(urls) do
        local ok, result = pcall(function()
            return loadstring(game:HttpGet(url))()
        end)
        if ok and result then
            Rayfield = result
            break
        end
    end
    -- Fallback mínimo caso Rayfield falhe completamente (sem UI, script continua)
    if not Rayfield then
        local _noop = function() end
        local _tab  = { CreateToggle=_noop, CreateSlider=_noop, CreateDropdown=_noop,
                         CreateColorPicker=_noop, CreateButton=_noop }
        Rayfield = {
            CreateWindow = function() return { CreateTab = function() return _tab end } end,
            Notify       = _noop,
            Destroy      = _noop,
        }
    end
end

local Win = Rayfield:CreateWindow({
    Name                   = "BloxStrike Hub v4.1",
    LoadingTitle           = "BloxStrike Hub",
    LoadingSubtitle        = "Xeno / Madium | Anti-Ban v4",
    Theme                  = "Default",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings   = true,
    ConfigurationSaving    = { Enabled = false },
    KeySystem              = false,
})

-- ── ABA COMBAT ──────────────────────────────────────────────

local TabCombat = Win:CreateTab("Combat", 4483362458)

TabCombat:CreateToggle({
    Name = "Aimbot", CurrentValue = G.AimbotOn, Flag = "abt",
    Callback = function(v)
        G.AimbotOn = v
        G.AimState.lockedTarget = nil; G.AimState.lockedSince = 0
    end,
})

TabCombat:CreateToggle({
    Name = "ADS Only (Hold RMB)", CurrentValue = G.ADSOnly, Flag = "adsonly",
    Callback = function(v) G.ADSOnly = v end,
})

TabCombat:CreateDropdown({
    Name = "Mode", Options = {"Legit","Rage"},
    CurrentOption = { G.AimbotMode }, Flag = "abtmode",
    Callback = function(v) G.AimbotMode = type(v) == "table" and v[1] or v end,
})

TabCombat:CreateDropdown({
    Name = "Aim Part", Options = {"Head","HumanoidRootPart","UpperTorso"},
    CurrentOption = { G.AimPart }, Flag = "aimpart",
    Callback = function(v)
        G.AimPart = type(v) == "table" and v[1] or v
        G.AimState.lockedTarget = nil; G.AimState.lockedSince = 0
    end,
})

TabCombat:CreateSlider({
    Name = "FOV Radius", Range = {10,600}, Increment = 1,
    Suffix = " px", CurrentValue = G.FOV, Flag = "fov",
    Callback = function(v) G.FOV = v end,
})

TabCombat:CreateSlider({
    Name = "Smoothing", Range = {1,100}, Increment = 1,
    Suffix = "%", CurrentValue = math.floor(G.Smoothing*100), Flag = "smooth",
    Callback = function(v) G.Smoothing = v/100 end,
})

TabCombat:CreateSlider({
    Name = "Jitter Sigma", Range = {0,15}, Increment = 1,
    Suffix = " px", CurrentValue = G.JitterSigma, Flag = "jitter",
    Callback = function(v) G.JitterSigma = v end,
})

TabCombat:CreateToggle({
    Name = "Velocity Prediction", CurrentValue = G.Prediction, Flag = "pred",
    Callback = function(v) G.Prediction = v end,
})

TabCombat:CreateSlider({
    Name = "Target Lock (ms)", Range = {100,2000}, Increment = 50,
    Suffix = " ms", CurrentValue = G.LockMs, Flag = "lockms",
    Callback = function(v) G.LockMs = v end,
})

TabCombat:CreateToggle({
    Name = "Team Check", CurrentValue = G.TeamCheck, Flag = "teamchk",
    Callback = function(v) G.TeamCheck = v end,
})

TabCombat:CreateToggle({
    Name = "Wall Check (LOS)", CurrentValue = G.WallCheck, Flag = "wallchk",
    Callback = function(v) G.WallCheck = v end,
})

TabCombat:CreateToggle({
    Name = "No Recoil", CurrentValue = G.NoRecoil, Flag = "norecoil",
    Callback = function(v) G.NoRecoil = v; G.LastCamCF = nil end,
})

TabCombat:CreateSlider({
    Name = "No Recoil Strength", Range = {10,100}, Increment = 5,
    Suffix = "%", CurrentValue = math.floor(G.NoRecoilStr*100), Flag = "nrstr",
    Callback = function(v) G.NoRecoilStr = v/100 end,
})

TabCombat:CreateToggle({
    Name = "Silent Aim", CurrentValue = G.SilentAim, Flag = "silentaim",
    Callback = function(v) G.SilentAim = v end,
})

TabCombat:CreateToggle({
    Name = "LOS Check (nao mira em wall)", CurrentValue = G.AimbotLOS, Flag = "abtlos",
    Callback = function(v)
        G.AimbotLOS = v
        if not v then G.AimState.lockedTarget = nil; G.AimState.lockedSince = 0 end
    end,
})

TabCombat:CreateToggle({
    Name = "Triggerbot", CurrentValue = G.Triggerbot, Flag = "triggerbot",
    Callback = function(v) G.Triggerbot = v end,
})

TabCombat:CreateSlider({
    Name = "Triggerbot Delay", Range = {0,500}, Increment = 10,
    Suffix = " ms", CurrentValue = G.TriggerDelay, Flag = "tbdelay",
    Callback = function(v) G.TriggerDelay = v end,
})

TabCombat:CreateKeybind({
    Name = "Aimbot Toggle Key",
    CurrentKeybind = tostring(G.AimbotKey.Name ~= "Unknown" and G.AimbotKey.Name or "None"),
    HoldToInteract = false, Flag = "abtkey",
    Callback = function(key)
        if key == "Delete" or key == "Backspace" then
            G.AimbotKey = Enum.KeyCode.Unknown
        else
            local ok, kc = pcall(function() return Enum.KeyCode[key] end)
            if ok and kc then G.AimbotKey = kc end
        end
    end,
})

-- ── ABA VISUALS ──────────────────────────────────────────────

local TabVisuals = Win:CreateTab("Visuals", 4483362458)

local function _removeBox(box)
    if not box then return end
    if box._sq then
        pcall(function() box._sq:Remove() end)
    elseif box._lines then
        for _, ln in ipairs(box._lines) do pcall(function() ln:Remove() end) end
    end
end

local function CleanESPPlayer(p)
    local o = G.DrawObjs[p]
    if not o then return end
    _removeBox(o.Box); _removeBox(o.Outline)
    for _, key in ipairs({"Name","Dist","Health","HealthBg","HPText","Tracer","HeadDot"}) do
        if o[key] then pcall(function() o[key]:Remove() end) end
    end
    for _, ln in ipairs(o.Skel or {}) do pcall(function() ln:Remove() end) end
    G.DrawObjs[p] = nil
end

TabVisuals:CreateToggle({
    Name = "ESP Boxes + Info", CurrentValue = G.ESPOn, Flag = "esp",
    Callback = function(v)
        G.ESPOn = v
        if not v then
            for p in pairs(G.DrawObjs) do CleanESPPlayer(p) end
        end
    end,
})

TabVisuals:CreateToggle({
    Name = "Skeleton ESP", CurrentValue = G.SkeletonOn, Flag = "skel",
    Callback = function(v)
        G.SkeletonOn = v
        if not v then
            for _, o in pairs(G.DrawObjs) do
                if o and o.Skel then
                    for _, ln in ipairs(o.Skel) do ln.Visible = false end
                end
            end
        end
    end,
})

TabVisuals:CreateToggle({
    Name = "Health Bars", CurrentValue = G.HealthBarOn, Flag = "hpbar",
    Callback = function(v)
        G.HealthBarOn = v
        if not v then
            for _, o in pairs(G.DrawObjs) do
                if o then
                    if o.Health   then o.Health.Visible   = false end
                    if o.HealthBg then o.HealthBg.Visible = false end
                    if o.HPText   then o.HPText.Visible   = false end
                end
            end
        end
    end,
})

TabVisuals:CreateToggle({
    Name = "Tracers (Snaplines)", CurrentValue = G.TracerOn, Flag = "tracer",
    Callback = function(v)
        G.TracerOn = v
        if not v then
            for _, o in pairs(G.DrawObjs) do
                if o and o.Tracer then o.Tracer.Visible = false end
            end
        end
    end,
})

TabVisuals:CreateToggle({
    Name = "Head Dot", CurrentValue = G.HeadDotOn, Flag = "headdot",
    Callback = function(v)
        G.HeadDotOn = v
        if not v then
            for _, o in pairs(G.DrawObjs) do
                if o and o.HeadDot then o.HeadDot.Visible = false end
            end
        end
    end,
})

TabVisuals:CreateColorPicker({
    Name = "ESP Color", Color = G.ESPColor, Flag = "espcol",
    Callback = function(v) G.ESPColor = v end,
})

TabVisuals:CreateColorPicker({
    Name = "Lock Highlight Color", Color = G.LockColor, Flag = "lockcol",
    Callback = function(v) G.LockColor = v end,
})

TabVisuals:CreateToggle({
    Name = "Chams (Wallhack)", CurrentValue = G.ChamsOn, Flag = "chams",
    Callback = function(v)
        G.ChamsOn = v
        if not v then
            for _, h in pairs(G.ChamsObjs) do pcall(function() h:Destroy() end) end
            G.ChamsObjs = {}
        end
    end,
})

TabVisuals:CreateColorPicker({
    Name = "Chams Color", Color = G.ChamsColor, Flag = "chamscol",
    Callback = function(v)
        G.ChamsColor = v
        for _, h in pairs(G.ChamsObjs) do
            if h and h.Parent then h.FillColor = v; h.OutlineColor = v end
        end
    end,
})

-- ── ABA MOVEMENT ─────────────────────────────────────────────

-- noclip helpers (early declaration — toggle callback below needs them)
local _noclipConns = {}

local function _disablePart(obj)
    if obj:IsA("BasePart") then obj.CanCollide = false end
end

local function _setupNoclipChar(char)
    for _, conn in ipairs(_noclipConns) do pcall(function() conn:Disconnect() end) end
    _noclipConns = {}
    for _, p in ipairs(char:GetDescendants()) do _disablePart(p) end
    table.insert(_noclipConns, char.DescendantAdded:Connect(_disablePart))
end

local TabMove = Win:CreateTab("Movement", 4483362458)

TabMove:CreateToggle({
    Name = "Speed Hack", CurrentValue = G.SpeedOn, Flag = "spd",
    Callback = function(v)
        G.SpeedOn = v
        if not v then
            local c = LP.Character
            if c then
                local h = c:FindFirstChildOfClass("Humanoid")
                if h then h.WalkSpeed = 16 end
            end
        end
    end,
})

TabMove:CreateSlider({
    Name = "WalkSpeed", Range = {16,500}, Increment = 1,
    Suffix = " st/s", CurrentValue = G.WalkSpeed, Flag = "ws",
    Callback = function(v) G.WalkSpeed = v end,
})

TabMove:CreateToggle({
    Name = "Fly (WASD + Space/Ctrl)", CurrentValue = G.FlyOn, Flag = "fly",
    Callback = function(v)
        G.FlyOn = v
        if not v then
            local c = LP.Character
            if c then
                local hum = c:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false end
                for _, n in ipairs({"_BSH_LV","_BSH_AV","_BSH_AG","_BSH_ATT"}) do
                    local obj = c:FindFirstChild(n, true)
                    if obj then pcall(function() obj:Destroy() end) end
                end
            end
        end
    end,
})

TabMove:CreateSlider({
    Name = "Fly Speed", Range = {10, 300}, Increment = 5,
    Suffix = " studs/s", CurrentValue = G.FlySpeed, Flag = "flyspd",
    Callback = function(v) G.FlySpeed = v end,
})

TabMove:CreateToggle({
    Name = "Bunny Hop", CurrentValue = G.BunnyHop, Flag = "bhop",
    Callback = function(v) G.BunnyHop = v end,
})

TabMove:CreateToggle({
    Name = "Noclip", CurrentValue = G.NoclipOn, Flag = "noclip",
    Callback = function(v)
        G.NoclipOn = v
        local c = LP.Character
        if v then
            if c then _setupNoclipChar(c) end
        else
            for _, conn in ipairs(_noclipConns) do pcall(function() conn:Disconnect() end) end
            _noclipConns = {}
            if c then
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = true end
                end
            end
        end
    end,
})

TabMove:CreateToggle({
    Name = "Anti-AFK", CurrentValue = G.AntiAFK, Flag = "antiafk",
    Callback = function(v) G.AntiAFK = v; G.AFKTimer = 0 end,
})

-- ── ABA CONFIG ───────────────────────────────────────────────

local TabCfg = Win:CreateTab("Config", 4483362458)

TabCfg:CreateButton({
    Name = "Save Config",
    Callback = function()
        local ok = SaveConfig()
        Rayfield:Notify({ Title = ok and "Saved" or "Save Error",
                          Content = ok and CFG_FILE or "Sem permissao de escrita",
                          Duration = 3 })
    end,
})

TabCfg:CreateButton({
    Name = "Load Config",
    Callback = function()
        LoadConfig()
        Rayfield:Notify({ Title = "Loaded", Content = "Config aplicada.", Duration = 3 })
    end,
})

TabCfg:CreateButton({
    Name = "Unload Script",
    Callback = function()
        G.Running = false
        for _, c in pairs(G.Conns) do pcall(function() c:Disconnect() end) end
        for p in pairs(G.DrawObjs) do CleanESPPlayer(p) end
        for _, h in pairs(G.ChamsObjs) do pcall(function() h:Destroy() end) end
        if G.FOVCircle then pcall(function() G.FOVCircle:Remove() end) end
        -- cleanup fly
        pcall(function()
            local char = LP.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false end
                for _, n in ipairs({"_BSH_LV","_BSH_AV","_BSH_AG","_BSH_ATT"}) do
                    local obj = char:FindFirstChild(n, true)
                    if obj then obj:Destroy() end
                end
            end
        end)
        Rayfield:Destroy()
    end,
})

-- ============================================================
-- §7  DRAWING ABSTRACTION (Square/Circle fallback)
-- ============================================================

-- Box: usa Drawing.Square se disponível, senão 4 Lines
local function NewBox(col, thick)
    local t = thick or 1.5
    local c = col or Color3.fromRGB(255, 55, 55)
    if _hasSquare then
        local sq      = Drawing.new("Square")
        sq.Thickness  = t; sq.Filled = false
        sq.Color      = c; sq.Visible = false
        return { _sq = sq }
    else
        local lines = {}
        for i = 1, 4 do
            local ln = Drawing.new("Line")
            ln.Thickness = t; ln.Color = c; ln.Visible = false
            lines[i] = ln
        end
        return { _lines = lines }
    end
end

local function SetBox(box, pos, size, col, visible)
    if box._sq then
        local sq = box._sq
        sq.Position = pos; sq.Size = size
        if col then sq.Color = col end
        sq.Visible = visible
    elseif box._lines then
        local x, y = pos.X, pos.Y
        local w, h = size.X, size.Y
        local pts = {
            { Vector2.new(x,   y),   Vector2.new(x+w, y)   },  -- top
            { Vector2.new(x,   y+h), Vector2.new(x+w, y+h) },  -- bottom
            { Vector2.new(x,   y),   Vector2.new(x,   y+h) },  -- left
            { Vector2.new(x+w, y),   Vector2.new(x+w, y+h) },  -- right
        }
        for i, ln in ipairs(box._lines) do
            ln.From = pts[i][1]; ln.To = pts[i][2]
            if col then ln.Color = col end
            ln.Visible = visible
        end
    end
end

local function HideBox(box)
    if box._sq then
        box._sq.Visible = false
    elseif box._lines then
        for _, ln in ipairs(box._lines) do ln.Visible = false end
    end
end

local function RemoveBox(box)
    if box._sq then
        pcall(function() box._sq:Remove() end)
    elseif box._lines then
        for _, ln in ipairs(box._lines) do pcall(function() ln:Remove() end) end
    end
end

-- Circle: usa Drawing.Circle se disponível, senão Line curto (dot)
local function NewCircle(col, thick, filled, radius, numsides)
    local c = col or Color3.fromRGB(255,255,255)
    if _hasCircle then
        local ci        = Drawing.new("Circle")
        ci.Thickness    = thick   or 1.5
        ci.Color        = c
        ci.Filled       = filled  or false
        ci.NumSides     = numsides or 16
        ci.Radius       = radius  or 5
        ci.Visible      = false
        return ci
    else
        -- Fallback: ponto (Line de 1px)
        local ln        = Drawing.new("Line")
        ln.Thickness    = (radius or 5) * 2
        ln.Color        = c
        ln.Visible      = false
        ln._circleFb    = true
        return ln
    end
end

local function SetCircle(obj, pos, col, visible)
    if obj._circleFb then
        obj.From    = pos; obj.To = pos + Vector2.new(1,0)
        if col      then obj.Color = col end
        obj.Visible = visible
    else
        obj.Position = pos
        if col       then obj.Color = col end
        obj.Visible  = visible
    end
end

-- ============================================================
-- §8  FOV CIRCLE
-- ============================================================

pcall(function()
    G.FOVCircle = NewCircle(Color3.fromRGB(255,255,255), 1.5, false, 120, 72)
    G.FOVCircle.Transparency = G.FOVCircle._circleFb and 0 or 0.8
end)

-- ============================================================
-- §9  UTILITÁRIOS DE JOGO
-- ============================================================

local R15_BONES = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"LowerTorso","LeftUpperLeg"},{"LowerTorso","RightUpperLeg"},
    {"LeftUpperLeg","LeftLowerLeg"},{"RightUpperLeg","RightLowerLeg"},
    {"LeftLowerLeg","LeftFoot"},{"RightLowerLeg","RightFoot"},
    {"UpperTorso","LeftUpperArm"},{"UpperTorso","RightUpperArm"},
    {"LeftUpperArm","LeftLowerArm"},{"RightUpperArm","RightLowerArm"},
    {"LeftLowerArm","LeftHand"},{"RightLowerArm","RightHand"},
}

local R6_BONES = {
    {"Head","Torso"},
    {"Torso","Left Arm"},{"Torso","Right Arm"},
    {"Torso","Left Leg"},{"Torso","Right Leg"},
}

local _rcParams = nil
local function GetRayParams()
    if not _rcParams then
        _rcParams = RaycastParams.new()
        _rcParams.FilterType = Enum.RaycastFilterType.Exclude
        _rcParams.FilterDescendantsInstances = { LP.Character or Instance.new("Folder") }
    end
    return _rcParams
end

LP.CharacterAdded:Connect(function() _rcParams = nil end)

local function IsValid(player)
    if player == LP then return false end
    local c = player.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    if not c:FindFirstChild("HumanoidRootPart") then return false end
    if G.TeamCheck then
        local lpTeam = LP.Team
        if lpTeam ~= nil and player.Team == lpTeam then return false end
    end
    return true
end

local function GetBounds(char)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local p    = hrp.Position
    local topV = Camera:WorldToViewportPoint(p + Vector3.new(0,  3.1, 0))
    local botV = Camera:WorldToViewportPoint(p + Vector3.new(0, -2.9, 0))
    if topV.Z <= 0 then return nil end
    local h = math.abs(botV.Y - topV.Y)
    if h < 2 then return nil end
    local w = h * 0.55
    return Vector2.new(topV.X - w*0.5, topV.Y), w, h
end

local function GetHP(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return 100, 100 end
    return math.floor(hum.Health), math.floor(hum.MaxHealth)
end

local function HasLOS(fromPos, toPos, targetChar)
    local result = workspace:Raycast(fromPos, toPos - fromPos, GetRayParams())
    if not result then return true end
    return result.Instance:IsDescendantOf(targetChar)
end

-- ============================================================
-- §10  AIMBOT — JITTER (Ornstein-Uhlenbeck)
-- ============================================================

local OU_THETA = 9.0

local function StepOUJitter(dt)
    local S      = G.AimState
    local sigma  = G.JitterSigma
    local sqrtDt = math.sqrt(math.min(dt, 0.033))
    S.jx = S.jx + (-OU_THETA * S.jx * dt) + (sigma * sqrtDt * GaussRand(1))
    S.jy = S.jy + (-OU_THETA * S.jy * dt) + (sigma * sqrtDt * GaussRand(1))
end

-- ============================================================
-- §11  AIMBOT — SELEÇÃO DE ALVO  (sem goto)
-- ============================================================

local function GetAimPart(char)
    return char:FindFirstChild(G.AimPart) or char:FindFirstChild("HumanoidRootPart")
end

local function GetTarget()
    local S   = G.AimState
    local now = tick()
    local mp  = Vector2.new(Mouse.X, Mouse.Y)

    -- Verificar lock existente
    if S.lockedTarget then
        local locked  = S.lockedTarget
        local elapsed = (now - S.lockedSince) * 1000
        local keepLock = false

        if IsValid(locked) then
            local part = locked.Character and GetAimPart(locked.Character)
            if part then
                local sp = Camera:WorldToViewportPoint(part.Position)
                if sp.Z > 0 then
                    local d = (mp - Vector2.new(sp.X, sp.Y)).Magnitude
                    if d <= G.FOV * 1.3 and elapsed < G.LockMs then
                        local losOk = true
                        if G.WallCheck or G.AimbotLOS then
                            losOk = HasLOS(Camera.CFrame.Position, part.Position, locked.Character)
                        end
                        if losOk then keepLock = true end
                    end
                end
            end
        end

        if keepLock then return locked end
        S.lockedTarget = nil; S.lockedSince = 0
    end

    -- Varrer jogadores
    local best    = nil
    local minDist = G.FOV
    for _, p in ipairs(Players:GetPlayers()) do
        if not IsValid(p) then continue end
        local part = GetAimPart(p.Character)
        if not part then continue end
        local sp = Camera:WorldToViewportPoint(part.Position)
        if sp.Z <= 0 then continue end
        if G.WallCheck or G.AimbotLOS then
            if not HasLOS(Camera.CFrame.Position, part.Position, p.Character) then continue end
        end
        local d = (mp - Vector2.new(sp.X, sp.Y)).Magnitude
        if d < minDist then minDist = d; best = p end
    end

    if best then
        S.lockedTarget = best
        S.lockedSince  = now
        S.lastPartPos  = nil
        S.headVelocity = Vector3.zero
    end

    return best
end

-- ============================================================
-- §12  AIMBOT — PREDIÇÃO DE VELOCIDADE
-- ============================================================

local function GetPartVelocity(part)
    local vel
    pcall(function() vel = part.AssemblyLinearVelocity end)
    if vel and vel.Magnitude > 0.1 then return vel end
    pcall(function() vel = part.Velocity end)
    return vel or Vector3.zero
end

local function UpdateVelocity(part)
    local S   = G.AimState
    local now = tick()
    if S.lastPartPos and S.lastPartTime > 0 then
        local dt_v = now - S.lastPartTime
        if dt_v > 0.001 and dt_v < 0.15 then
            local rawVel = (part.Position - S.lastPartPos) / dt_v
            S.headVelocity = S.headVelocity:Lerp(rawVel, 0.35)
        end
    end
    S.lastPartPos  = part.Position
    S.lastPartTime = now
end

local function PredictedPos(part)
    if not G.Prediction then return part.Position end
    local S     = G.AimState
    local pingS = 0.065
    pcall(function()
        pingS = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
    end)
    local physVel = GetPartVelocity(part)
    local vel     = physVel.Magnitude > 0.5 and physVel or S.headVelocity
    return part.Position + vel * math.min(pingS * 0.65, 0.15)
end

-- ============================================================
-- §13  AIMBOT — HUMANIZAÇÃO
-- ============================================================

local AimOffset   = Vector3.zero
local AimOffTimer = 0
local AimOffNext  = 0.09
local HITBOX_R    = 0.45

local function GetHumanizedAimPoint(pos, dt)
    AimOffTimer = AimOffTimer + dt
    if AimOffTimer >= AimOffNext then
        AimOffTimer = 0
        AimOffNext  = math.random(80, 150) / 1000
        local ox, oy, oz
        for _ = 1, 8 do
            ox = GaussRand(HITBOX_R * 0.45)
            oy = GaussRand(HITBOX_R * 0.40)
            oz = GaussRand(HITBOX_R * 0.25)
            if ox*ox + oy*oy + oz*oz <= HITBOX_R * HITBOX_R then break end
        end
        AimOffset = Vector3.new(ox, oy, oz)
    end
    return pos + AimOffset
end

local function AdaptiveAlpha(screenDistPx, baseAlpha, dt)
    local scale
    if     screenDistPx > 120 then scale = 1.6
    elseif screenDistPx < 20  then scale = 0.55
    else   scale = 1.6 - (1.6 - 0.55) * ((120 - screenDistPx) / 100)
    end
    return FpsAlpha(math.min(1, baseAlpha * scale), dt)
end

-- ============================================================
-- §14  ESP — DRAWING OBJECTS
-- ============================================================

local function MakeLine(col, thick)
    local ln = Drawing.new("Line")
    ln.Thickness = thick or 1
    ln.Color     = col or Color3.fromRGB(255, 255, 0)
    ln.Visible   = false
    return ln
end

local function CreateESP(player)
    if G.DrawObjs[player] then return end

    local box     = NewBox(G.ESPColor, 1.5)
    local outline = NewBox(Color3.fromRGB(0,0,0), 3)

    local nm              = Drawing.new("Text")
    nm.Size               = 13; nm.Color = Color3.fromRGB(255,255,255)
    nm.Outline            = true; nm.OutlineColor = Color3.fromRGB(0,0,0)
    nm.Center             = true; nm.Visible = false

    local dist            = Drawing.new("Text")
    dist.Size             = 11; dist.Color = Color3.fromRGB(195,195,195)
    dist.Outline          = true; dist.OutlineColor = Color3.fromRGB(0,0,0)
    dist.Center           = true; dist.Visible = false

    local hpBg   = MakeLine(Color3.fromRGB(30,30,30), 3)
    local hp     = Drawing.new("Line")
    hp.Thickness = 3; hp.Visible = false

    local hpText            = Drawing.new("Text")
    hpText.Size             = 9; hpText.Color = Color3.fromRGB(220,220,220)
    hpText.Outline          = true; hpText.OutlineColor = Color3.fromRGB(0,0,0)
    hpText.Center           = true; hpText.Visible = false

    local tracer = MakeLine(G.ESPColor, 1)
    local headDot = NewCircle(Color3.fromRGB(255,255,255), 1.5, true, 3, 12)

    G.DrawObjs[player] = {
        Box = box, Outline = outline,
        Name = nm, Dist = dist,
        Health = hp, HealthBg = hpBg, HPText = hpText,
        Tracer = tracer, HeadDot = headDot,
        Skel = {},
    }
end

local function RemoveESP(player)
    local o = G.DrawObjs[player]
    if not o then return end
    pcall(function() RemoveBox(o.Box)     end)
    pcall(function() RemoveBox(o.Outline) end)
    for _, key in ipairs({"Name","Dist","Health","HealthBg","HPText","Tracer"}) do
        if o[key] then pcall(function() o[key]:Remove() end) end
    end
    if o.HeadDot then pcall(function() o.HeadDot:Remove() end) end
    for _, ln in ipairs(o.Skel) do pcall(function() ln:Remove() end) end
    G.DrawObjs[player] = nil
end

local function HideESPAll(o)
    HideBox(o.Box); HideBox(o.Outline)
    o.Name.Visible     = false; o.Dist.Visible     = false
    o.Health.Visible   = false; o.HealthBg.Visible = false
    o.HPText.Visible   = false; o.Tracer.Visible   = false
    if o.HeadDot then SetCircle(o.HeadDot, Vector2.zero, nil, false) end
    for _, ln in ipairs(o.Skel) do ln.Visible = false end
end

local function UpdateESP(player)
    local o = G.DrawObjs[player]
    if not o then return end
    if not G.ESPOn or not IsValid(player) then HideESPAll(o); return end

    local char          = player.Character
    local origin, w, h  = GetBounds(char)
    if not origin then HideESPAll(o); return end

    local x, y     = origin.X, origin.Y
    local isLocked = (G.AimState.lockedTarget == player)
    local boxCol   = isLocked and G.LockColor or G.ESPColor
    local pos2     = Vector2.new(x, y)
    local sz2      = Vector2.new(w, h)

    SetBox(o.Outline, Vector2.new(x-1, y-1), Vector2.new(w+2, h+2), Color3.fromRGB(0,0,0), true)
    SetBox(o.Box,     pos2,                  sz2,                   boxCol,                 true)

    local hrp  = char:FindFirstChild("HumanoidRootPart")
    local dist = hrp and math.floor((Camera.CFrame.Position - hrp.Position).Magnitude) or 0

    o.Name.Position = Vector2.new(x + w*0.5, y - 16)
    o.Name.Text     = player.Name .. (isLocked and " [LOCK]" or "")
    o.Name.Color    = isLocked and G.LockColor or Color3.fromRGB(255,255,255)
    o.Name.Visible  = true

    o.Dist.Position = Vector2.new(x + w*0.5, y + h + 2)
    o.Dist.Text     = dist .. " st"
    o.Dist.Visible  = true

    -- Health bar
    if G.HealthBarOn then
        local hpVal, hpMax = GetHP(char)
        local hpRatio      = hpMax > 0 and (hpVal/hpMax) or 1
        local barX         = x - 6
        local barBot       = y + h
        o.HealthBg.From    = Vector2.new(barX, y)
        o.HealthBg.To      = Vector2.new(barX, barBot)
        o.HealthBg.Visible = true
        o.Health.From      = Vector2.new(barX, barBot)
        o.Health.To        = Vector2.new(barX, barBot - h*hpRatio)
        o.Health.Color     = Color3.fromHSV(hpRatio * 0.33, 1, 1)
        o.Health.Visible   = true
        o.HPText.Position  = Vector2.new(barX, y - 10)
        o.HPText.Text      = tostring(hpVal)
        o.HPText.Visible   = true
    else
        o.Health.Visible = false; o.HealthBg.Visible = false; o.HPText.Visible = false
    end

    -- Tracer
    if G.TracerOn and hrp then
        local feetSP = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 2.9, 0))
        if feetSP.Z > 0 then
            local sv = Camera.ViewportSize
            o.Tracer.From    = Vector2.new(sv.X*0.5, sv.Y)
            o.Tracer.To      = Vector2.new(feetSP.X, feetSP.Y)
            o.Tracer.Color   = boxCol
            o.Tracer.Visible = true
        else
            o.Tracer.Visible = false
        end
    else
        o.Tracer.Visible = false
    end

    -- Head dot
    if G.HeadDotOn then
        local head   = char:FindFirstChild("Head")
        local headSP = head and Camera:WorldToViewportPoint(head.Position)
        if headSP and headSP.Z > 0 then
            SetCircle(o.HeadDot, Vector2.new(headSP.X, headSP.Y), boxCol, true)
        else
            SetCircle(o.HeadDot, Vector2.zero, nil, false)
        end
    else
        if o.HeadDot then o.HeadDot.Visible = false end
    end

    -- Skeleton
    if G.SkeletonOn then
        local isR15 = char:FindFirstChild("UpperTorso") ~= nil
        local bones = isR15 and R15_BONES or R6_BONES
        local nB    = #bones
        for i = #o.Skel + 1, nB do o.Skel[i] = MakeLine(boxCol, 1) end
        for i, pair in ipairs(bones) do
            local pA = char:FindFirstChild(pair[1])
            local pB = char:FindFirstChild(pair[2])
            local ln = o.Skel[i]
            if pA and pB then
                local sA = Camera:WorldToViewportPoint(pA.Position)
                local sB = Camera:WorldToViewportPoint(pB.Position)
                if sA.Z > 0 and sB.Z > 0 then
                    ln.From = Vector2.new(sA.X, sA.Y)
                    ln.To   = Vector2.new(sB.X, sB.Y)
                    ln.Color   = boxCol
                    ln.Visible = true
                else
                    ln.Visible = false
                end
            else
                ln.Visible = false
            end
        end
        for i = nB+1, #o.Skel do o.Skel[i].Visible = false end
    else
        for _, ln in ipairs(o.Skel) do ln.Visible = false end
    end
end

-- ============================================================
-- §15  CHAMS
-- ============================================================

local function UpdateChams(player)
    if not G.ChamsOn or not IsValid(player) then
        local h = G.ChamsObjs[player]
        if h then pcall(function() h:Destroy() end); G.ChamsObjs[player] = nil end
        return
    end
    local c = player.Character
    local h = G.ChamsObjs[player]
    if h then
        if not pcall(function() local _ = h.Parent end) or h.Parent ~= c then
            pcall(function() h:Destroy() end); G.ChamsObjs[player] = nil; h = nil
        end
    end
    if not h then
        local nh               = Instance.new("Highlight")
        nh.FillColor           = G.ChamsColor
        nh.OutlineColor        = G.ChamsColor
        nh.FillTransparency    = 0.5
        nh.OutlineTransparency = 0
        nh.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
        nh.Parent              = c
        G.ChamsObjs[player]    = nh
    end
end

-- ============================================================
-- §16  SPEED HACK
-- ============================================================

local _SPEED_PERIOD = (2 * math.pi) / 2.73  -- evita overflow de float em sessões longas

local function ApplySpeed(dt)
    local c = LP.Character; if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return end
    G.SpeedTimer = (G.SpeedTimer + dt) % _SPEED_PERIOD
    hum.WalkSpeed = math.max(16, G.WalkSpeed + math.sin(G.SpeedTimer * 2.73) * 2.2 + GaussRand(0.5))
end

-- ============================================================
-- §17  FLY
-- ============================================================

local function UpdateFly()
    local c = LP.Character; if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return end
    if not c:FindFirstChild("_BSH_LV") then
        hum.PlatformStand = true
        -- LinearVelocity (novo API) com fallback para BodyVelocity (legado)
        local useLV = pcall(function()
            local att = Instance.new("Attachment")
            att.Name = "_BSH_ATT"; att.Parent = hrp
            local lv = Instance.new("LinearVelocity")
            lv.Name = "_BSH_LV"; lv.Attachment0 = att
            lv.MaxForce = math.huge; lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
            lv.VectorVelocity = Vector3.zero; lv.Parent = hrp
            local av = Instance.new("AngularVelocity")
            av.Name = "_BSH_AV"; av.Attachment0 = att
            av.MaxTorque = math.huge; av.AngularVelocity = Vector3.zero; av.Parent = hrp
        end)
        if not useLV then
            -- fallback deprecated mas ainda funciona
            local bv = Instance.new("BodyVelocity")
            bv.Name = "_BSH_LV"; bv.MaxForce = Vector3.new(1e5,1e5,1e5)
            bv.Velocity = Vector3.zero; bv.Parent = hrp
            local bg = Instance.new("BodyGyro")
            bg.Name = "_BSH_AG"; bg.MaxTorque = Vector3.new(1e5,1e5,1e5)
            bg.P = 1e4; bg.Parent = hrp
        end
    end
    local lv = c:FindFirstChild("_BSH_LV")
    if not lv then return end
    local dir = Vector3.zero; local spd = G.FlySpeed
    if UIS:IsKeyDown(Enum.KeyCode.W)           then dir = dir + Camera.CFrame.LookVector  end
    if UIS:IsKeyDown(Enum.KeyCode.S)           then dir = dir - Camera.CFrame.LookVector  end
    if UIS:IsKeyDown(Enum.KeyCode.A)           then dir = dir - Camera.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.D)           then dir = dir + Camera.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.Space)       then dir = dir + Vector3.new(0,1,0)        end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir + Vector3.new(0,-1,0)       end
    local vel = dir.Magnitude > 0 and dir.Unit * spd or Vector3.zero
    if lv:IsA("LinearVelocity") then
        lv.VectorVelocity = vel
        local av = c:FindFirstChild("_BSH_AV")
        if av then av.AngularVelocity = Vector3.zero end
    else
        lv.Velocity = vel
        local bg = c:FindFirstChild("_BSH_AG")
        if bg then bg.CFrame = Camera.CFrame end
    end
end

-- ============================================================
-- §18  BUNNY HOP
-- ============================================================

local function UpdateBunnyHop()
    if not G.BunnyHop then return end
    if not UIS:IsKeyDown(Enum.KeyCode.Space) then return end
    local c   = LP.Character; if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local st  = hum:GetState()
    if st == Enum.HumanoidStateType.Landed or st == Enum.HumanoidStateType.Running then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- ============================================================
-- §19  NOCLIP
-- ============================================================

LP.CharacterAdded:Connect(function(char)
    if G.NoclipOn then _setupNoclipChar(char) end
end)

local function UpdateNoclip()
    if not G.NoclipOn then return end
    local c = LP.Character; if not c then return end
    -- event-driven: just keep any parts that got re-enabled back off
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if hrp and hrp.CanCollide then hrp.CanCollide = false end
end

-- ============================================================
-- §20  ANTI-AFK
-- ============================================================

local function UpdateAntiAFK(dt)
    if not G.AntiAFK then return end
    G.AFKTimer = G.AFKTimer + dt
    if G.AFKTimer < 180 then return end
    G.AFKTimer = 0
    local c = LP.Character; if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local ok = pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
    if not ok then
        hum.Jump = true
        task.delay(0.15, function() if hum and hum.Parent then hum.Jump = false end end)
    end
end

-- ============================================================
-- §21  HOOKS — Silent Aim + Anti-Kick
-- ============================================================

local _siHooked, _akHooked = false, false

local function InstallHooks()
    if not (hookmetamethod and getrawmetatable and setreadonly and newcclosure) then return end
    local mt = getrawmetatable(game)
    if not pcall(setreadonly, mt, false) then return end

    if not _siHooked then
        local oldIndex = mt.__index
        mt.__index = newcclosure(function(self, key)
            if G.SilentAim and key == "Hit" and rawequal(self, Mouse) then
                local locked = G.AimState.lockedTarget
                if locked and IsValid(locked) then
                    local part = GetAimPart(locked.Character)
                    if part then return CFrame.new(part.Position) end
                end
            end
            if oldIndex then return oldIndex(self, key) end
            return rawget(self, key)
        end)
        _siHooked = true
    end

    if not _akHooked then
        local oldNc = mt.__namecall
        mt.__namecall = newcclosure(function(self, ...)
            if getnamecallmethod() == "Kick" and rawequal(self, LP) then return end
            if oldNc then return oldNc(self, ...) end
        end)
        _akHooked = true
    end

    pcall(setreadonly, mt, true)
end

pcall(InstallHooks)

-- ============================================================
-- §22  TRIGGERBOT
-- ============================================================

local _tbCooldown = 0

local function RunTriggerbot()
    if not G.Triggerbot then return end
    local now   = tick()
    local delay = G.TriggerDelay / 1000
    if now - _tbCooldown < delay then return end
    local cam    = Camera
    local center = cam.ViewportSize / 2
    local unitRay = cam:ScreenPointToRay(center.X, center.Y)
    local result  = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, GetRayParams())
    if not result then return end
    local model = result.Instance:FindFirstAncestorOfClass("Model")
    if not model then return end
    local target = Players:GetPlayerFromCharacter(model)
    if not target or not IsValid(target) then return end
    _tbCooldown = now
    if mouse1click then pcall(mouse1click) end
end

-- ============================================================
-- §23  NO RECOIL
-- ============================================================

local NR_THRESHOLD = 0.012

local function ApplyNoRecoil()
    if not G.NoRecoil then G.LastCamCF = Camera.CFrame; return end
    local curr = Camera.CFrame
    if not G.LastCamCF then G.LastCamCF = curr; return end
    local lastX = select(1, G.LastCamCF:ToEulerAnglesYXZ())
    local currX = select(1, curr:ToEulerAnglesYXZ())
    local delta = currX - lastX
    if delta > NR_THRESHOLD then
        Camera.CFrame = curr * CFrame.Angles(-delta * G.NoRecoilStr, 0, 0)
    end
    G.LastCamCF = Camera.CFrame
end

-- ============================================================
-- §24  EVENTOS DE PLAYER
-- ============================================================

local function HookPlayer(p)
    p.CharacterAdded:Connect(function()
        task.wait(0.8)
        if G.ESPOn   then CreateESP(p)   end
        if G.ChamsOn then UpdateChams(p) end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LP then HookPlayer(p) end
end

Players.PlayerAdded:Connect(HookPlayer)

Players.PlayerRemoving:Connect(function(p)
    RemoveESP(p)
    local h = G.ChamsObjs[p]
    if h then pcall(function() h:Destroy() end); G.ChamsObjs[p] = nil end
    if G.AimState.lockedTarget == p then
        G.AimState.lockedTarget = nil; G.AimState.lockedSince = 0
    end
end)

-- ============================================================
-- §25  INPUT — Aimbot keybind toggle
-- ============================================================

UIS.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if G.AimbotKey == Enum.KeyCode.Unknown then return end
    if inp.KeyCode ~= G.AimbotKey then return end
    G.AimbotOn = not G.AimbotOn
    if not G.AimbotOn then
        G.AimState.lockedTarget = nil
        G.AimState.lockedSince  = 0
    end
end)

-- ============================================================
-- §26  LOOP PRINCIPAL — Heartbeat  (pcall por frame)
-- ============================================================

local hbConn = RunService.Heartbeat:Connect(function(dt)
    if not G.Running then return end

    Camera = workspace.CurrentCamera

    -- FOV circle
    pcall(function()
        if G.FOVCircle then
            SetCircle(G.FOVCircle, Vector2.new(Mouse.X, Mouse.Y), nil, G.AimbotOn)
            if not G.FOVCircle._circleFb then
                G.FOVCircle.Radius = G.FOV
            end
        end
    end)

    if G.SpeedOn  then pcall(ApplySpeed,  dt) end
    if G.FlyOn    then pcall(UpdateFly)       end
    if G.BunnyHop then pcall(UpdateBunnyHop)  end
    if G.NoclipOn then pcall(UpdateNoclip)    end
    if G.AntiAFK  then pcall(UpdateAntiAFK, dt) end

    pcall(StepOUJitter, dt)
    pcall(RunTriggerbot)

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        pcall(function()
            if G.ESPOn then
                if not G.DrawObjs[p] then CreateESP(p) end
                UpdateESP(p)
            elseif G.DrawObjs[p] then
                RemoveESP(p)
            end
            UpdateChams(p)
        end)
    end
end)

table.insert(G.Conns, hbConn)

-- ============================================================
-- §27  AIMBOT + NO-RECOIL — RenderStepped  (pcall por frame)
-- ============================================================

local rsConn = RunService.RenderStepped:Connect(function(dt)
    if not G.Running then return end

    pcall(ApplyNoRecoil)

    if not G.AimbotOn then return end
    if G.ADSOnly and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end

    pcall(function()
        local target = GetTarget()
        if not target then return end
        local char = target.Character; if not char then return end
        local part = GetAimPart(char); if not part then return end

        -- AimbotLOS: bloqueia puxada quando inimigo está atrás de parede
        if G.AimbotLOS and not HasLOS(Camera.CFrame.Position, part.Position, char) then return end

        UpdateVelocity(part)
        local aimPos = GetHumanizedAimPoint(PredictedPos(part), dt)
        local sp     = Camera:WorldToViewportPoint(aimPos)
        local dist   = (Vector2.new(sp.X, sp.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude

        if G.AimbotMode == "Legit" then
            local S          = G.AimState
            local camPos     = Camera.CFrame.Position
            local dist3D     = (aimPos - camPos).Magnitude
            local ppx        = (Camera.ViewportSize.Y * 0.5) / math.tan(math.rad(Camera.FieldOfView * 0.5))
            local upp        = dist3D / ppx
            local jittered   = aimPos
                + Camera.CFrame.RightVector * (S.jx * upp)
                + Camera.CFrame.UpVector    * (S.jy * upp)
            local alpha      = AdaptiveAlpha(dist, G.Smoothing, dt)
            Camera.CFrame    = Camera.CFrame:Lerp(CFrame.new(camPos, jittered), alpha)
        else
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, aimPos)
        end

        G.LastCamCF = Camera.CFrame
    end)
end)

table.insert(G.Conns, rsConn)

-- ============================================================
-- §28  BOOT
-- ============================================================

Rayfield:Notify({
    Title    = "BloxStrike Hub v4.2",
    Content  = "Loaded | Aimbot + ESP + Triggerbot + Fly + Noclip",
    Duration = 5,
})
