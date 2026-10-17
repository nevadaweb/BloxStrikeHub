-- ============================================================
--  BloxStrike Hub v4.0  |  Madium Executor  |  Level 7/8
--  Aimbot: OU jitter, fps-independent smoothing, target lock,
--          velocity prediction (AssemblyLinearVelocity), ADS-only,
--          silent aim, wall check (LOS), no-recoil
--  ESP: Square boxes + outline, health bar + text, skeleton,
--       tracers/snaplines, head dot, locked target highlight
--  Combat: triggerbot (modern Raycast API), team check
--  Movement: speed hack, fly, bunny hop, noclip, safe teleport
--  Misc: anti-AFK, anti-kick, config persistence
-- ============================================================

-- ============================================================
-- §1  ESTADO GLOBAL
-- ============================================================

if not getgenv().BSH then
    getgenv().BSH = {
        -- Combat
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
        Triggerbot  = false,
        TeamCheck   = true,
        NoRecoil    = false,
        NoRecoilStr = 0.85,    -- 0..1, força da compensação de recuo
        WallCheck   = false,   -- modo legit: só mira em alvos visíveis

        -- Visuals
        ESPOn       = false,
        SkeletonOn  = false,
        HealthBarOn = true,
        TracerOn    = false,
        HeadDotOn   = false,
        ChamsOn     = false,
        ESPColor    = Color3.fromRGB(255, 55, 55),
        LockColor   = Color3.fromRGB(255, 230, 0),   -- cor do alvo lockado
        ChamsColor  = Color3.fromRGB(255, 120, 0),

        -- Movement
        SpeedOn     = false,
        WalkSpeed   = 60,
        FlyOn       = false,
        BunnyHop    = false,
        NoclipOn    = false,
        AntiAFK     = false,

        -- Internos
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
        SpeedPhase = math.random() * math.pi * 2,
        AFKTimer   = 0,

        -- Camera anterior para no-recoil
        LastCamCF  = nil,
    }
end

local G = getgenv().BSH

-- ============================================================
-- §2  SERVIÇOS & REFERÊNCIAS
-- ============================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local HTTP       = game:GetService("HttpService")
local Camera     = workspace.CurrentCamera
local LP         = Players.LocalPlayer
local Mouse      = LP:GetMouse()

-- ============================================================
-- §3  UTILITÁRIOS MATEMÁTICOS
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
    return 1 - math.pow(math.max(0, 1 - safe_base), safe_dt * 60)
end

-- ============================================================
-- §4  CONFIG SAVE / LOAD
-- ============================================================

local CFG_FILE = "BSH_v4_config.json"

local SERIAL_KEYS = {
    "AimbotOn","AimbotMode","FOV","Smoothing","JitterSigma","Prediction","LockMs",
    "ADSOnly","AimPart","SilentAim","Triggerbot","TeamCheck","NoRecoil","NoRecoilStr","WallCheck",
    "ESPOn","SkeletonOn","HealthBarOn","TracerOn","HeadDotOn","ChamsOn",
    "SpeedOn","WalkSpeed","BunnyHop","AntiAFK",
}

local function SaveConfig()
    local t = {}
    for _, k in ipairs(SERIAL_KEYS) do t[k] = G[k] end
    t.ESPColor   = { G.ESPColor.R,   G.ESPColor.G,   G.ESPColor.B   }
    t.LockColor  = { G.LockColor.R,  G.LockColor.G,  G.LockColor.B  }
    t.ChamsColor = { G.ChamsColor.R, G.ChamsColor.G, G.ChamsColor.B }
    return pcall(writefile, CFG_FILE, HTTP:JSONEncode(t))
end

local function LoadConfig()
    if not isfile(CFG_FILE) then return end
    local ok, t = pcall(function() return HTTP:JSONDecode(readfile(CFG_FILE)) end)
    if not ok or type(t) ~= "table" then return end
    for _, k in ipairs(SERIAL_KEYS) do
        if t[k] ~= nil then G[k] = t[k] end
    end
    if t.ESPColor   then G.ESPColor   = Color3.new(t.ESPColor[1],   t.ESPColor[2],   t.ESPColor[3])   end
    if t.LockColor  then G.LockColor  = Color3.new(t.LockColor[1],  t.LockColor[2],  t.LockColor[3])  end
    if t.ChamsColor then G.ChamsColor = Color3.new(t.ChamsColor[1], t.ChamsColor[2], t.ChamsColor[3]) end
end

LoadConfig()

-- ============================================================
-- §5  RAYFIELD UI
-- ============================================================

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Win = Rayfield:CreateWindow({
    Name                   = "BloxStrike Hub v4",
    LoadingTitle           = "BloxStrike Hub",
    LoadingSubtitle        = "Madium | L8 | Anti-Ban v4",
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
        local S = G.AimState
        S.lockedTarget = nil; S.lockedSince = 0
    end,
})

TabCombat:CreateToggle({
    Name = "ADS Only (Hold RMB)", CurrentValue = G.ADSOnly, Flag = "adsonly",
    Callback = function(v) G.ADSOnly = v end,
})

TabCombat:CreateDropdown({
    Name = "Mode", Options = {"Legit", "Rage"},
    CurrentOption = { G.AimbotMode }, Flag = "abtmode",
    Callback = function(v) G.AimbotMode = v[1] end,
})

TabCombat:CreateDropdown({
    Name = "Aim Part", Options = {"Head", "HumanoidRootPart", "UpperTorso"},
    CurrentOption = { G.AimPart }, Flag = "aimpart",
    Callback = function(v)
        G.AimPart = v[1]
        local S = G.AimState
        S.lockedTarget = nil; S.lockedSince = 0
    end,
})

TabCombat:CreateSlider({
    Name = "FOV Radius", Range = {10, 600}, Increment = 1,
    Suffix = " px", CurrentValue = G.FOV, Flag = "fov",
    Callback = function(v) G.FOV = v end,
})

TabCombat:CreateSlider({
    Name = "Smoothing", Range = {1, 100}, Increment = 1,
    Suffix = "%", CurrentValue = math.floor(G.Smoothing * 100), Flag = "smooth",
    Callback = function(v) G.Smoothing = v / 100 end,
})

TabCombat:CreateSlider({
    Name = "Jitter Sigma", Range = {0, 15}, Increment = 1,
    Suffix = " px", CurrentValue = G.JitterSigma, Flag = "jitter",
    Callback = function(v) G.JitterSigma = v end,
})

TabCombat:CreateToggle({
    Name = "Velocity Prediction", CurrentValue = G.Prediction, Flag = "pred",
    Callback = function(v) G.Prediction = v end,
})

TabCombat:CreateSlider({
    Name = "Target Lock (ms)", Range = {100, 2000}, Increment = 50,
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
    Name = "No Recoil Strength", Range = {10, 100}, Increment = 5,
    Suffix = "%", CurrentValue = math.floor(G.NoRecoilStr * 100), Flag = "nrstr",
    Callback = function(v) G.NoRecoilStr = v / 100 end,
})

TabCombat:CreateToggle({
    Name = "Silent Aim", CurrentValue = G.SilentAim, Flag = "silentaim",
    Callback = function(v) G.SilentAim = v end,
})

TabCombat:CreateToggle({
    Name = "Triggerbot", CurrentValue = G.Triggerbot, Flag = "triggerbot",
    Callback = function(v) G.Triggerbot = v end,
})

-- ── ABA VISUALS ──────────────────────────────────────────────

local TabVisuals = Win:CreateTab("Visuals", 4483362458)

TabVisuals:CreateToggle({
    Name = "ESP Boxes + Info", CurrentValue = G.ESPOn, Flag = "esp",
    Callback = function(v)
        G.ESPOn = v
        if not v then
            for p, _ in pairs(G.DrawObjs) do
                -- limpeza lazy: UpdateESP vai lidar no próximo frame
                if G.DrawObjs[p] then
                    local o = G.DrawObjs[p]
                    pcall(function() o.Box:Remove()      end)
                    pcall(function() o.Outline:Remove()  end)
                    pcall(function() o.Name:Remove()     end)
                    pcall(function() o.Dist:Remove()     end)
                    pcall(function() o.Health:Remove()   end)
                    pcall(function() o.HealthBg:Remove() end)
                    pcall(function() o.HPText:Remove()   end)
                    pcall(function() o.Tracer:Remove()   end)
                    pcall(function() o.HeadDot:Remove()  end)
                    if o.Skel then
                        for _, ln in ipairs(o.Skel) do pcall(function() ln:Remove() end) end
                    end
                    G.DrawObjs[p] = nil
                end
            end
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
            if h and h.Parent then
                h.FillColor    = v
                h.OutlineColor = v
            end
        end
    end,
})

-- ── ABA MOVEMENT ─────────────────────────────────────────────

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
    Name = "WalkSpeed", Range = {16, 500}, Increment = 1,
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
                if c:FindFirstChild("_BSH_BV") then c._BSH_BV:Destroy() end
                if c:FindFirstChild("_BSH_BG") then c._BSH_BG:Destroy() end
            end
        end
    end,
})

TabMove:CreateToggle({
    Name = "Bunny Hop", CurrentValue = G.BunnyHop, Flag = "bhop",
    Callback = function(v) G.BunnyHop = v end,
})

TabMove:CreateToggle({
    Name = "Noclip", CurrentValue = G.NoclipOn, Flag = "noclip",
    Callback = function(v)
        G.NoclipOn = v
        if not v then
            local c = LP.Character
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
        Rayfield:Notify({
            Title    = ok and "Saved" or "Save Error",
            Content  = ok and CFG_FILE or "Verifique permissoes do executor",
            Duration = 3,
        })
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
        for _, o in pairs(G.DrawObjs) do
            if o then
                pcall(function() o.Box:Remove()      end)
                pcall(function() o.Outline:Remove()  end)
                pcall(function() o.Name:Remove()     end)
                pcall(function() o.Dist:Remove()     end)
                pcall(function() o.Health:Remove()   end)
                pcall(function() o.HealthBg:Remove() end)
                pcall(function() o.HPText:Remove()   end)
                pcall(function() o.Tracer:Remove()   end)
                pcall(function() o.HeadDot:Remove()  end)
                if o.Skel then
                    for _, ln in ipairs(o.Skel) do pcall(function() ln:Remove() end) end
                end
            end
        end
        for _, h in pairs(G.ChamsObjs) do pcall(function() h:Destroy() end) end
        if G.FOVCircle then pcall(function() G.FOVCircle:Remove() end) end
        Rayfield:Destroy()
    end,
})

-- ============================================================
-- §6  FOV CIRCLE
-- ============================================================

G.FOVCircle = Drawing.new("Circle")
G.FOVCircle.Thickness    = 1.5
G.FOVCircle.Color        = Color3.fromRGB(255, 255, 255)
G.FOVCircle.Transparency = 0.8
G.FOVCircle.Filled       = false
G.FOVCircle.NumSides     = 72
G.FOVCircle.Visible      = false

-- ============================================================
-- §7  UTILITÁRIOS DE JOGO
-- ============================================================

local R15_BONES = {
    {"Head",          "UpperTorso"},
    {"UpperTorso",    "LowerTorso"},
    {"LowerTorso",    "LeftUpperLeg"},
    {"LowerTorso",    "RightUpperLeg"},
    {"LeftUpperLeg",  "LeftLowerLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"LeftLowerLeg",  "LeftFoot"},
    {"RightLowerLeg", "RightFoot"},
    {"UpperTorso",    "LeftUpperArm"},
    {"UpperTorso",    "RightUpperArm"},
    {"LeftUpperArm",  "LeftLowerArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"LeftLowerArm",  "LeftHand"},
    {"RightLowerArm", "RightHand"},
}

local R6_BONES = {
    {"Head",   "Torso"},
    {"Torso",  "Left Arm"},
    {"Torso",  "Right Arm"},
    {"Torso",  "Left Leg"},
    {"Torso",  "Right Leg"},
}

-- RaycastParams reutilizável (recriado quando character muda)
local _rcParams = nil
local function GetRayParams()
    if not _rcParams then
        _rcParams = RaycastParams.new()
        _rcParams.FilterType = Enum.RaycastFilterType.Exclude
        _rcParams.FilterDescendantsInstances = { LP.Character or Instance.new("Folder") }
    end
    return _rcParams
end

LP.CharacterAdded:Connect(function(char)
    _rcParams = nil   -- força recriar com novo character na exclusão
end)

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

-- Bounding box 2D
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
    return Vector2.new(topV.X - w * 0.5, topV.Y), w, h
end

local function GetHPRatio(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.MaxHealth <= 0 then return 1 end
    return math.clamp(hum.Health / hum.MaxHealth, 0, 1)
end

local function GetHP(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return 100, 100 end
    return math.floor(hum.Health), math.floor(hum.MaxHealth)
end

-- Line-of-sight check via workspace:Raycast() (API moderna)
local function HasLOS(fromPos, toPos, targetChar)
    local dir    = toPos - fromPos
    local params = GetRayParams()
    -- Adiciona char do alvo na exclusão temporariamente não é possível de forma simples,
    -- então verificamos se o hit é dentro do char do alvo
    local result = workspace:Raycast(fromPos, dir, params)
    if not result then return true end  -- sem colisão = visível
    -- Verifica se o que colidiu é parte do character alvo
    local hitInst = result.Instance
    return hitInst:IsDescendantOf(targetChar)
end

-- ============================================================
-- §8  AIMBOT — JITTER GAUSSIANO (Ornstein-Uhlenbeck)
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
-- §9  AIMBOT — SELEÇÃO DE ALVO
-- ============================================================

local function GetAimPart(char)
    return char:FindFirstChild(G.AimPart) or char:FindFirstChild("HumanoidRootPart")
end

local function GetTarget(dt)
    local S   = G.AimState
    local now = tick()
    local mp  = Vector2.new(Mouse.X, Mouse.Y)

    if S.lockedTarget then
        local locked  = S.lockedTarget
        local elapsed = (now - S.lockedSince) * 1000
        if IsValid(locked) then
            local part = locked.Character and GetAimPart(locked.Character)
            if part then
                local sp = Camera:WorldToViewportPoint(part.Position)
                if sp.Z > 0 then
                    local d = (mp - Vector2.new(sp.X, sp.Y)).Magnitude
                    if d <= G.FOV * 1.3 and elapsed < G.LockMs then
                        -- Wall check no alvo lockado (modo legit)
                        if G.WallCheck and G.AimbotMode == "Legit" then
                            if not HasLOS(Camera.CFrame.Position, part.Position, locked.Character) then
                                S.lockedTarget = nil; S.lockedSince = 0
                                goto scan
                            end
                        end
                        return locked
                    end
                end
            end
        end
        S.lockedTarget = nil; S.lockedSince = 0
    end

    ::scan::
    local best    = nil
    local minDist = G.FOV
    for _, p in ipairs(Players:GetPlayers()) do
        if not IsValid(p) then continue end
        local part = GetAimPart(p.Character)
        if not part then continue end
        local sp = Camera:WorldToViewportPoint(part.Position)
        if sp.Z <= 0 then continue end
        -- Wall check na seleção (modo legit)
        if G.WallCheck and G.AimbotMode == "Legit" then
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
-- §10  AIMBOT — PREDIÇÃO DE VELOCIDADE
-- ============================================================

local function GetPartVelocity(part)
    local vel = nil
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
    local lead    = math.min(pingS * 0.65, 0.15)
    return part.Position + vel * lead
end

-- ============================================================
-- §11  AIMBOT — HUMANIZAÇÃO
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

-- ============================================================
-- §12  AIMBOT — SMOOTHING ADAPTIVO
-- ============================================================

local function AdaptiveAlpha(screenDistPx, baseAlpha, dt)
    local scale
    if screenDistPx > 120 then
        scale = 1.6
    elseif screenDistPx < 20 then
        scale = 0.55
    else
        scale = 1.6 - (1.6 - 0.55) * ((120 - screenDistPx) / 100)
    end
    return FpsAlpha(math.min(1, baseAlpha * scale), dt)
end

-- ============================================================
-- §13  ESP — DRAWING OBJECTS
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

    local box             = Drawing.new("Square")
    box.Thickness         = 1.5; box.Filled = false; box.Visible = false

    local outline         = Drawing.new("Square")
    outline.Thickness     = 3; outline.Filled = false
    outline.Color         = Color3.fromRGB(0,0,0); outline.Visible = false

    local nm              = Drawing.new("Text")
    nm.Size               = 13; nm.Color = Color3.fromRGB(255,255,255)
    nm.Outline            = true; nm.OutlineColor = Color3.fromRGB(0,0,0)
    nm.Center             = true; nm.Visible = false

    local dist            = Drawing.new("Text")
    dist.Size             = 11; dist.Color = Color3.fromRGB(195,195,195)
    dist.Outline          = true; dist.OutlineColor = Color3.fromRGB(0,0,0)
    dist.Center           = true; dist.Visible = false

    local hpBg            = MakeLine(Color3.fromRGB(30,30,30), 3)
    local hp              = Drawing.new("Line")
    hp.Thickness          = 3; hp.Visible = false

    local hpText          = Drawing.new("Text")
    hpText.Size           = 9; hpText.Color = Color3.fromRGB(220,220,220)
    hpText.Outline        = true; hpText.OutlineColor = Color3.fromRGB(0,0,0)
    hpText.Center         = true; hpText.Visible = false

    -- Tracer: linha do centro-baixo da tela até os pés do player
    local tracer          = MakeLine(G.ESPColor, 1)

    -- Head dot: círculo sobre a cabeça
    local headDot         = Drawing.new("Circle")
    headDot.Thickness     = 1.5
    headDot.Filled        = true
    headDot.Color         = Color3.fromRGB(255, 255, 255)
    headDot.NumSides      = 16
    headDot.Radius        = 3
    headDot.Visible       = false

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
    pcall(function() o.Box:Remove()      end)
    pcall(function() o.Outline:Remove()  end)
    pcall(function() o.Name:Remove()     end)
    pcall(function() o.Dist:Remove()     end)
    pcall(function() o.Health:Remove()   end)
    pcall(function() o.HealthBg:Remove() end)
    pcall(function() o.HPText:Remove()   end)
    pcall(function() o.Tracer:Remove()   end)
    pcall(function() o.HeadDot:Remove()  end)
    for _, ln in ipairs(o.Skel) do pcall(function() ln:Remove() end) end
    G.DrawObjs[player] = nil
end

local function UpdateESP(player)
    local o = G.DrawObjs[player]
    if not o then return end

    local function hideAll()
        o.Box.Visible      = false; o.Outline.Visible  = false
        o.Name.Visible     = false; o.Dist.Visible     = false
        o.Health.Visible   = false; o.HealthBg.Visible = false
        o.HPText.Visible   = false; o.Tracer.Visible   = false
        o.HeadDot.Visible  = false
        for _, ln in ipairs(o.Skel) do ln.Visible = false end
    end

    if not G.ESPOn or not IsValid(player) then hideAll(); return end

    local char           = player.Character
    local origin, w, h  = GetBounds(char)
    if not origin then hideAll(); return end

    local x, y       = origin.X, origin.Y
    local isLocked   = (G.AimState.lockedTarget == player)
    local boxCol     = isLocked and G.LockColor or G.ESPColor
    local outlineCol = isLocked and Color3.fromRGB(0,0,0) or Color3.fromRGB(0,0,0)

    -- Outline
    o.Outline.Position = Vector2.new(x - 1, y - 1)
    o.Outline.Size     = Vector2.new(w + 2, h + 2)
    o.Outline.Color    = outlineCol
    o.Outline.Visible  = true

    -- Box
    o.Box.Position = Vector2.new(x, y)
    o.Box.Size     = Vector2.new(w, h)
    o.Box.Color    = boxCol
    o.Box.Visible  = true

    -- Name
    local hrp  = char:FindFirstChild("HumanoidRootPart")
    local dist = hrp and math.floor((Camera.CFrame.Position - hrp.Position).Magnitude) or 0
    o.Name.Position = Vector2.new(x + w * 0.5, y - 16)
    o.Name.Text     = player.Name .. (isLocked and " [LOCK]" or "")
    o.Name.Color    = isLocked and G.LockColor or Color3.fromRGB(255,255,255)
    o.Name.Visible  = true

    -- Distance
    o.Dist.Position = Vector2.new(x + w * 0.5, y + h + 2)
    o.Dist.Text     = dist .. " st"
    o.Dist.Visible  = true

    -- Health bar + HP text
    if G.HealthBarOn then
        local hpVal, hpMax = GetHP(char)
        local hpRatio      = hpMax > 0 and (hpVal / hpMax) or 1
        local barX         = x - 6
        local barBot       = y + h
        local barFill      = barBot - (h * hpRatio)

        o.HealthBg.From    = Vector2.new(barX, y)
        o.HealthBg.To      = Vector2.new(barX, barBot)
        o.HealthBg.Visible = true

        o.Health.From    = Vector2.new(barX, barBot)
        o.Health.To      = Vector2.new(barX, barFill)
        o.Health.Color   = Color3.fromHSV(hpRatio * 0.33, 1, 1)
        o.Health.Visible = true

        -- HP number no topo da barra
        o.HPText.Position = Vector2.new(barX, y - 10)
        o.HPText.Text     = tostring(hpVal)
        o.HPText.Visible  = true
    else
        o.Health.Visible   = false
        o.HealthBg.Visible = false
        o.HPText.Visible   = false
    end

    -- Tracer (snapline do centro-baixo da tela até os pés)
    if G.TracerOn and hrp then
        local feetSP = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 2.9, 0))
        if feetSP.Z > 0 then
            local screenBot = Camera.ViewportSize
            o.Tracer.From    = Vector2.new(screenBot.X * 0.5, screenBot.Y)
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
            o.HeadDot.Position = Vector2.new(headSP.X, headSP.Y)
            o.HeadDot.Color    = boxCol
            o.HeadDot.Visible  = true
        else
            o.HeadDot.Visible  = false
        end
    else
        o.HeadDot.Visible = false
    end

    -- Skeleton
    if G.SkeletonOn then
        local isR15 = char:FindFirstChild("UpperTorso") ~= nil
        local bones = isR15 and R15_BONES or R6_BONES
        local nBones = #bones

        for i = #o.Skel + 1, nBones do
            o.Skel[i] = MakeLine(boxCol, 1)
        end

        for i, pair in ipairs(bones) do
            local partA = char:FindFirstChild(pair[1])
            local partB = char:FindFirstChild(pair[2])
            local ln    = o.Skel[i]
            if partA and partB then
                local spA = Camera:WorldToViewportPoint(partA.Position)
                local spB = Camera:WorldToViewportPoint(partB.Position)
                if spA.Z > 0 and spB.Z > 0 then
                    ln.From    = Vector2.new(spA.X, spA.Y)
                    ln.To      = Vector2.new(spB.X, spB.Y)
                    ln.Color   = boxCol
                    ln.Visible = true
                else
                    ln.Visible = false
                end
            else
                ln.Visible = false
            end
        end

        for i = nBones + 1, #o.Skel do o.Skel[i].Visible = false end
    else
        for _, ln in ipairs(o.Skel) do ln.Visible = false end
    end
end

-- ============================================================
-- §14  CHAMS
-- ============================================================

local function CreateChams(player)
    local c = player.Character
    if not c then return end
    if G.ChamsObjs[player] then
        pcall(function() G.ChamsObjs[player]:Destroy() end)
        G.ChamsObjs[player] = nil
    end
    local h               = Instance.new("Highlight")
    h.FillColor           = G.ChamsColor
    h.OutlineColor        = G.ChamsColor
    h.FillTransparency    = 0.5
    h.OutlineTransparency = 0
    h.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent              = c
    G.ChamsObjs[player]   = h
end

local function RemoveChams(player)
    local h = G.ChamsObjs[player]
    if h then pcall(function() h:Destroy() end) end
    G.ChamsObjs[player] = nil
end

local function UpdateChams(player)
    if not G.ChamsOn or not IsValid(player) then RemoveChams(player); return end
    local c = player.Character
    local h = G.ChamsObjs[player]
    if h then
        local ok = pcall(function() local _ = h.Parent end)
        if not ok or h.Parent ~= c then
            pcall(function() h:Destroy() end)
            G.ChamsObjs[player] = nil; h = nil
        end
    end
    if not h then CreateChams(player) end
end

-- ============================================================
-- §15  SPEED HACK
-- ============================================================

local function ApplySpeed(dt)
    local c = LP.Character
    if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    G.SpeedTimer = G.SpeedTimer + dt
    local sineVar  = math.sin(G.SpeedTimer * (math.pi / 1.15)) * 2.2
    local noiseVar = GaussRand(0.5)
    hum.WalkSpeed  = math.max(16, G.WalkSpeed + sineVar + noiseVar)
end

-- ============================================================
-- §16  FLY HACK
-- ============================================================

local function EnsureFlyParts()
    local c = LP.Character
    if not c then return nil, nil end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then return nil, nil end
    if not c:FindFirstChild("_BSH_BV") then
        hum.PlatformStand = true
        local bv = Instance.new("BodyVelocity")
        bv.Name     = "_BSH_BV"; bv.MaxForce = Vector3.new(1e5,1e5,1e5)
        bv.Velocity = Vector3.zero; bv.Parent = hrp
        local bg = Instance.new("BodyGyro")
        bg.Name      = "_BSH_BG"; bg.MaxTorque = Vector3.new(1e5,1e5,1e5)
        bg.P         = 1e4; bg.Parent = hrp
    end
    return c:FindFirstChild("_BSH_BV"), c:FindFirstChild("_BSH_BG")
end

local function UpdateFly()
    local bv, bg = EnsureFlyParts()
    if not bv or not bg then return end
    local dir   = Vector3.zero
    local speed = 65
    if UIS:IsKeyDown(Enum.KeyCode.W)           then dir = dir + Camera.CFrame.LookVector  end
    if UIS:IsKeyDown(Enum.KeyCode.S)           then dir = dir - Camera.CFrame.LookVector  end
    if UIS:IsKeyDown(Enum.KeyCode.A)           then dir = dir - Camera.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.D)           then dir = dir + Camera.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.Space)       then dir = dir + Vector3.new(0,  1, 0)     end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir + Vector3.new(0, -1, 0)     end
    bv.Velocity = dir.Magnitude > 0 and dir.Unit * speed or Vector3.zero
    bg.CFrame   = Camera.CFrame
end

-- ============================================================
-- §17  BUNNY HOP
-- ============================================================

local function UpdateBunnyHop()
    if not G.BunnyHop then return end
    local c = LP.Character
    if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if not UIS:IsKeyDown(Enum.KeyCode.Space) then return end
    -- Pula automaticamente ao tocar o chão enquanto Space está pressionado
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Landed
    or state == Enum.HumanoidStateType.Running then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- ============================================================
-- §18  NOCLIP
-- ============================================================

local function UpdateNoclip()
    if not G.NoclipOn then return end
    local c = LP.Character
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
end

-- ============================================================
-- §19  SAFE TELEPORT
-- ============================================================

local function SafeTeleport(target)
    local c = LP.Character
    if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local origin = hrp.Position
    local steps  = math.max(8, math.ceil((target - origin).Magnitude / 4))
    for i = 1, steps do
        if not G.Running then return end
        local alpha = i / steps
        local t     = alpha * alpha * (3 - 2 * alpha)
        hrp.CFrame  = CFrame.new(origin:Lerp(target, t))
        task.wait()
    end
end

-- ============================================================
-- §20  ANTI-AFK
-- ============================================================

local function UpdateAntiAFK(dt)
    if not G.AntiAFK then return end
    G.AFKTimer = G.AFKTimer + dt
    if G.AFKTimer < 180 then return end   -- a cada 3 minutos
    G.AFKTimer = 0
    local c = LP.Character
    if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.Jump = true
        task.delay(0.15, function() if hum and hum.Parent then hum.Jump = false end end)
    end
end

-- ============================================================
-- §21  HOOKS — Silent Aim + Anti-Kick
-- ============================================================

local _siHooked = false
local _akHooked = false

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
            return oldIndex(self, key)
        end)
        _siHooked = true
    end

    if not _akHooked then
        local oldNc = mt.__namecall
        mt.__namecall = newcclosure(function(self, ...)
            if getnamecallmethod() == "Kick" and rawequal(self, LP) then return end
            return oldNc(self, ...)
        end)
        _akHooked = true
    end

    pcall(setreadonly, mt, true)
end

InstallHooks()

-- ============================================================
-- §22  TRIGGERBOT (workspace:Raycast — API moderna)
-- ============================================================

local _tbCooldown = 0

local function RunTriggerbot()
    if not G.Triggerbot then return end
    local now = tick()
    if now - _tbCooldown < 0.08 then return end

    local center  = Camera.ViewportSize / 2
    local unitRay = Camera:ScreenPointToRay(center.X, center.Y)
    local params  = GetRayParams()
    local result  = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)
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
-- Detecta aumento súbito de pitch da câmera (recuo move pra cima)
-- e cancela parcialmente via compensação inversa.
-- Threshold: 0.012 rad/frame ≈ 0.7° — abaixo disso é movimento normal.

local NR_THRESHOLD = 0.012

local function ApplyNoRecoil()
    if not G.NoRecoil then
        G.LastCamCF = Camera.CFrame
        return
    end

    local curr = Camera.CFrame
    if not G.LastCamCF then
        G.LastCamCF = curr
        return
    end

    -- Delta de pitch entre frames (eixo X local da câmera)
    local lastX = select(1, G.LastCamCF:ToEulerAnglesYXZ())
    local currX = select(1, curr:ToEulerAnglesYXZ())
    local delta = currX - lastX

    -- Se o pitch subiu mais que o threshold = recuo
    if delta > NR_THRESHOLD then
        Camera.CFrame = curr * CFrame.Angles(-delta * G.NoRecoilStr, 0, 0)
    end

    G.LastCamCF = Camera.CFrame
end

-- ============================================================
-- §24  EVENTOS DE PLAYER
-- ============================================================

local function HookPlayer(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.8)
        if G.ESPOn   then CreateESP(player)   end
        if G.ChamsOn then CreateChams(player) end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LP then
        HookPlayer(p)
        if G.ESPOn   then CreateESP(p)   end
        if G.ChamsOn then CreateChams(p) end
    end
end

Players.PlayerAdded:Connect(function(p) HookPlayer(p) end)

Players.PlayerRemoving:Connect(function(p)
    RemoveESP(p); RemoveChams(p)
    if G.AimState.lockedTarget == p then
        G.AimState.lockedTarget = nil; G.AimState.lockedSince = 0
    end
end)

-- ============================================================
-- §25  LOOP PRINCIPAL — Heartbeat
-- ============================================================

local hbConn = RunService.Heartbeat:Connect(function(dt)
    if not G.Running then return end

    G.FOVCircle.Position = Vector2.new(Mouse.X, Mouse.Y)
    G.FOVCircle.Radius   = G.FOV
    G.FOVCircle.Visible  = G.AimbotOn

    if G.SpeedOn   then ApplySpeed(dt)     end
    if G.FlyOn     then UpdateFly()        end
    if G.BunnyHop  then UpdateBunnyHop()   end
    if G.NoclipOn  then UpdateNoclip()     end
    if G.AntiAFK   then UpdateAntiAFK(dt)  end

    StepOUJitter(dt)
    RunTriggerbot()

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        if G.ESPOn then
            if not G.DrawObjs[p] then CreateESP(p) end
            UpdateESP(p)
        else
            RemoveESP(p)
        end
        UpdateChams(p)
    end
end)

table.insert(G.Conns, hbConn)

-- ============================================================
-- §26  AIMBOT + NO-RECOIL — RenderStepped
-- ============================================================

local rsConn = RunService.RenderStepped:Connect(function(dt)
    if not G.Running then return end

    -- No-recoil roda sempre (mesmo sem aimbot) quando habilitado
    ApplyNoRecoil()

    if not G.AimbotOn then return end

    if G.ADSOnly and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        return
    end

    local target = GetTarget(dt)
    if not target then return end

    local char = target.Character
    if not char then return end
    local part = GetAimPart(char)
    if not part then return end

    UpdateVelocity(part)

    local baseAimPos = PredictedPos(part)
    local aimPos     = GetHumanizedAimPoint(baseAimPos, dt)

    local sp         = Camera:WorldToViewportPoint(aimPos)
    local screenDist = (Vector2.new(sp.X, sp.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude

    if G.AimbotMode == "Legit" then
        local S          = G.AimState
        local camPos     = Camera.CFrame.Position
        local dist3D     = (aimPos - camPos).Magnitude
        local pixPerUnit = (Camera.ViewportSize.Y * 0.5) / math.tan(math.rad(Camera.FieldOfView * 0.5))
        local unitsPerPx = dist3D / pixPerUnit

        local jitteredAim = aimPos
            + Camera.CFrame.RightVector * (S.jx * unitsPerPx)
            + Camera.CFrame.UpVector    * (S.jy * unitsPerPx)

        local alpha    = AdaptiveAlpha(screenDist, G.Smoothing, dt)
        local targetCF = CFrame.new(camPos, jitteredAim)
        Camera.CFrame  = Camera.CFrame:Lerp(targetCF, alpha)

    elseif G.AimbotMode == "Rage" then
        Camera.CFrame = CFrame.new(Camera.CFrame.Position, aimPos)
    end

    -- Sync LastCamCF após aimbot mover a câmera para não falso-positivo no no-recoil
    G.LastCamCF = Camera.CFrame
end)

table.insert(G.Conns, rsConn)

-- ============================================================
-- §27  BOOT NOTIFICATION
-- ============================================================

Rayfield:Notify({
    Title    = "BloxStrike Hub v4",
    Content  = "Loaded  |  NoRecoil + Tracers + BHop + Noclip",
    Duration = 5,
})
