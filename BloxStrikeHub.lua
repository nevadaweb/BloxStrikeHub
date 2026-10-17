-- ============================================================
--  BloxStrike Hub v2.0  |  Madium Executor  |  Level 7/8
--  Anti-Ban: Gaussian jitter (OU process), fps-independent
--  smoothing, target lock, velocity prediction, aim humanization
-- ============================================================

-- ============================================================
-- §1  ESTADO GLOBAL — getgenv() persiste entre re-execuções
-- ============================================================

if not getgenv().BSH then
    getgenv().BSH = {
        -- Combat
        AimbotOn    = false,
        AimbotMode  = "Legit",   -- "Legit" | "Rage"
        FOV         = 120,
        Smoothing   = 0.12,      -- 0..1 (base, 60fps-normalizado)
        JitterSigma = 1.2,       -- desvio padrão do jitter em pixels de tela (OU sigma)
        Prediction  = true,      -- lead velocity prediction
        LockMs      = 350,       -- ms mínimos no mesmo alvo antes de trocar (sweet spot humano)

        -- Visuals
        ESPOn       = false,
        ChamsOn     = false,
        ESPColor    = Color3.fromRGB(255, 55, 55),
        ChamsColor  = Color3.fromRGB(255, 120, 0),

        -- Movement
        SpeedOn     = false,
        WalkSpeed   = 60,
        FlyOn       = false,

        -- Internos (não serializar no config)
        DrawObjs    = {},   -- [player] = { Box={Line×4}, Name, Dist }
        ChamsObjs   = {},   -- [player] = Highlight
        Conns       = {},
        Running     = true,

        -- Estado do aimbot (não serializar)
        AimState = {
            -- Ornstein-Uhlenbeck jitter state (processo discreto)
            jx = 0, jy = 0,
            -- Target lock  (usa tick() — wall clock, não CPU time)
            lockedTarget = nil,
            lockedSince  = 0,
            -- Velocity prediction buffer (EMA manual)
            lastHeadPos  = nil,
            lastHeadTime = 0,
            headVelocity = Vector3.zero,
        },

        -- Estado do speed hack
        SpeedTimer  = 0,
        SpeedPhase  = math.random() * math.pi * 2,   -- fase inicial aleatória por sessão
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

-- Box-Muller: gera amostra gaussiana com desvio padrão sigma
local PI2 = math.pi * 2
local function GaussRand(sigma)
    local u1 = math.max(1e-10, math.random())   -- evita log(0)
    local u2 = math.random()
    return sigma * math.sqrt(-2 * math.log(u1)) * math.cos(PI2 * u2)
end

-- Converte alpha "por-frame a 60fps" para alpha frame-rate independente
-- Garante comportamento idêntico a 30, 60, 144, 240 fps
local function FpsAlpha(base, dt)
    local safe_dt   = math.min(dt, 0.1)          -- cap em 100ms (evita snap em hitch)
    local safe_base = math.min(base, 0.9999)      -- evita NaN: 0^0 quando base=1, dt→0
    return 1 - math.pow(math.max(0, 1 - safe_base), safe_dt * 60)
end

-- ============================================================
-- §4  CONFIG SAVE / LOAD  (writefile / readfile)
-- ============================================================

local CFG_FILE = "BSH_v2_config.json"

local SERIAL_KEYS = {
    "AimbotOn","AimbotMode","FOV","Smoothing","JitterSigma",
    "Prediction","LockMs","ESPOn","ChamsOn","SpeedOn","WalkSpeed",
}

local function SaveConfig()
    local t = {}
    for _, k in ipairs(SERIAL_KEYS) do t[k] = G[k] end
    t.ESPColor   = { G.ESPColor.R,   G.ESPColor.G,   G.ESPColor.B   }
    t.ChamsColor = { G.ChamsColor.R, G.ChamsColor.G, G.ChamsColor.B }
    local ok, err = pcall(writefile, CFG_FILE, HTTP:JSONEncode(t))
    return ok
end

local function LoadConfig()
    if not isfile(CFG_FILE) then return end
    local ok, t = pcall(function() return HTTP:JSONDecode(readfile(CFG_FILE)) end)
    if not ok or type(t) ~= "table" then return end
    for _, k in ipairs(SERIAL_KEYS) do
        if t[k] ~= nil then G[k] = t[k] end
    end
    if t.ESPColor   then G.ESPColor   = Color3.new(t.ESPColor[1],   t.ESPColor[2],   t.ESPColor[3])   end
    if t.ChamsColor then G.ChamsColor = Color3.new(t.ChamsColor[1], t.ChamsColor[2], t.ChamsColor[3]) end
end

LoadConfig()

-- ============================================================
-- §5  RAYFIELD UI
-- ============================================================

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Win = Rayfield:CreateWindow({
    Name                   = "BloxStrike Hub v2",
    LoadingTitle           = "BloxStrike Hub",
    LoadingSubtitle        = "Madium | L8 | Anti-Ban",
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
        -- Reset lock ao ligar/desligar para não herdar alvo fantasma
        local S = G.AimState
        S.lockedTarget = nil
        S.lockedSince  = 0
    end,
})

TabCombat:CreateDropdown({
    Name = "Mode", Options = {"Legit", "Rage"},
    CurrentOption = { G.AimbotMode }, Flag = "abtmode",
    Callback = function(v) G.AimbotMode = v[1] end,
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

-- ── ABA VISUALS ──────────────────────────────────────────────

local TabVisuals = Win:CreateTab("Visuals", 4483362458)

TabVisuals:CreateToggle({
    Name = "ESP Boxes + Info", CurrentValue = G.ESPOn, Flag = "esp",
    Callback = function(v)
        G.ESPOn = v
        if not v then
            for _, o in pairs(G.DrawObjs) do
                for _, ln in pairs(o.Box) do pcall(function() ln:Remove() end) end
                pcall(function() o.Name:Remove() end)
                pcall(function() o.Dist:Remove() end)
            end
            G.DrawObjs = {}
        end
    end,
})

TabVisuals:CreateColorPicker({
    Name = "ESP Color", Color = G.ESPColor, Flag = "espcol",
    Callback = function(v) G.ESPColor = v end,
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

-- ── ABA CONFIG ───────────────────────────────────────────────

local TabCfg = Win:CreateTab("Config", 4483362458)

TabCfg:CreateButton({
    Name = "Save Config",
    Callback = function()
        local ok = SaveConfig()
        Rayfield:Notify({
            Title   = ok and "Saved" or "Save Error",
            Content = ok and CFG_FILE or "Verifique permissoes do executor",
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
            for _, ln in pairs(o.Box) do pcall(function() ln:Remove() end) end
            pcall(function() o.Name:Remove() end)
            pcall(function() o.Dist:Remove() end)
        end
        for _, h in pairs(G.ChamsObjs) do pcall(function() h:Destroy() end) end
        if G.FOVCircle then pcall(function() G.FOVCircle:Remove() end) end
        Rayfield:Destroy()
    end,
})

-- ============================================================
-- §6  FOV CIRCLE  (Drawing — segue o mouse)
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

local function IsValid(player)
    if player == LP then return false end
    local c = player.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    return c:FindFirstChild("HumanoidRootPart") ~= nil
end

-- Bounding box 2D para ESP  →  (origin:Vector2, w:number, h:number) | nil
local function GetBounds(char)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local p    = hrp.Position
    local topV = Camera:WorldToViewportPoint(p + Vector3.new(0,  3.1, 0))
    local botV = Camera:WorldToViewportPoint(p + Vector3.new(0, -2.9, 0))
    if topV.Z <= 0 then return nil end   -- behind camera
    local h = math.abs(botV.Y - topV.Y)
    if h < 2 then return nil end          -- too small / very far
    local w = h * 0.55
    return Vector2.new(topV.X - w * 0.5, topV.Y), w, h
end

-- ============================================================
-- §8  AIMBOT — JITTER GAUSSIANO (Ornstein-Uhlenbeck discreto)
-- ============================================================
-- Fórmula discreta exata: dX = -θ·X·dt + σ·√dt·N(0,1)
-- Propriedades garantidas:
--   • Correlação temporal (tremor de mão, não white noise)
--   • Média zero (não deriva — reversão automática)
--   • Amplitude σ em pixels de tela, independente de distância ao alvo
--   • Cada frame é único — nunca se repete (seed do GaussRand)

local OU_THETA = 9.0   -- velocidade de reversão à média (8~12 = fisiologicamente humano)

local function StepOUJitter(dt)
    local S      = G.AimState
    local sigma  = G.JitterSigma
    -- Cap no sqrt(dt) equivalente a ~30fps para evitar explosão em framedrops
    local sqrtDt = math.sqrt(math.min(dt, 0.033))
    -- Processo OU discreto: independente em X e Y
    S.jx = S.jx + (-OU_THETA * S.jx * dt) + (sigma * sqrtDt * GaussRand(1))
    S.jy = S.jy + (-OU_THETA * S.jy * dt) + (sigma * sqrtDt * GaussRand(1))
end

-- ============================================================
-- §9  AIMBOT — SELEÇÃO DE ALVO COM TARGET LOCK
-- ============================================================

local function GetTarget(dt)
    local S   = G.AimState
    -- tick() = wall clock (correto para medir latência real)
    -- os.clock() = CPU time (não usar para lock timers)
    local now = tick()
    local mp  = Vector2.new(Mouse.X, Mouse.Y)

    -- Se tem alvo locado, verifica se ainda é válido
    if S.lockedTarget then
        local locked  = S.lockedTarget
        local elapsed = (now - S.lockedSince) * 1000   -- ms
        if IsValid(locked) then
            local head = locked.Character and locked.Character:FindFirstChild("Head")
            if head then
                local sp = Camera:WorldToViewportPoint(head.Position)
                if sp.Z > 0 then
                    local d = (mp - Vector2.new(sp.X, sp.Y)).Magnitude
                    -- Mantém lock se dentro do FOV expandido (1.3x evita flicker na borda)
                    if d <= G.FOV * 1.3 and elapsed < G.LockMs then
                        return locked
                    end
                end
            end
        end
        S.lockedTarget = nil
        S.lockedSince  = 0
    end

    -- Busca novo melhor alvo (menor distância ao mouse dentro do FOV)
    local best    = nil
    local minDist = G.FOV
    for _, p in ipairs(Players:GetPlayers()) do
        if not IsValid(p) then continue end
        local head = p.Character:FindFirstChild("Head")
        if not head then continue end
        local sp = Camera:WorldToViewportPoint(head.Position)
        if sp.Z <= 0 then continue end
        local d = (mp - Vector2.new(sp.X, sp.Y)).Magnitude
        if d < minDist then minDist = d; best = p end
    end

    if best then
        S.lockedTarget = best
        S.lockedSince  = now
        S.lastHeadPos  = nil
        S.headVelocity = Vector3.zero
    end

    return best
end

-- ============================================================
-- §10  AIMBOT — PREDIÇÃO DE VELOCIDADE
-- ============================================================

local function UpdateVelocity(head)
    local S   = G.AimState
    local now = tick()   -- wall clock consistente com GetTarget
    if S.lastHeadPos and S.lastHeadTime > 0 then
        local dt_v = now - S.lastHeadTime
        -- Ignora gaps > 150ms (lagspike descarta amostra ruidosa)
        if dt_v > 0.001 and dt_v < 0.15 then
            local rawVel = (head.Position - S.lastHeadPos) / dt_v
            -- EMA alpha=0.35: responsivo mas não caótico
            S.headVelocity = S.headVelocity:Lerp(rawVel, 0.35)
        end
    end
    S.lastHeadPos  = head.Position
    S.lastHeadTime = now
end

local function PredictedPos(head)
    if not G.Prediction then return head.Position end
    local S    = G.AimState
    -- Obtém ping real via Stats (fallback 65ms)
    local pingS = 0.065
    pcall(function()
        pingS = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
    end)
    -- Lead 65% do ping: o servidor já processou parte do movimento
    -- Cap em 150ms para não over-predict em lag spike
    local lead = math.min(pingS * 0.65, 0.15)
    return head.Position + S.headVelocity * lead
end

-- ============================================================
-- §11  AIMBOT — HUMANIZAÇÃO DO PONTO DE MIRA
-- ============================================================
-- Em vez de apontar sempre para o centro exato do Head,
-- aplica um offset gaussiano dentro da hitbox sphere (~0.5 studs raio).
-- O offset persiste por N frames para simular micro-ajuste humano.

local AimOffset    = Vector3.zero
local AimOffTimer  = 0
local AimOffNext   = 0.09   -- próxima troca (randomizado)
local HITBOX_R     = 0.45   -- raio do Head hitbox em studs

local function GetHumanizedAimPoint(headPos, dt)
    AimOffTimer = AimOffTimer + dt
    if AimOffTimer >= AimOffNext then
        AimOffTimer = 0
        -- Intervalo randomizado 80-150ms → imita sacada micro-saccade humana
        AimOffNext  = math.random(80, 150) / 1000

        -- Rejection sampling: gera offset dentro da esfera do hitbox
        local ox, oy, oz
        local maxTries = 8
        for _ = 1, maxTries do
            ox = GaussRand(HITBOX_R * 0.45)
            oy = GaussRand(HITBOX_R * 0.40)
            oz = GaussRand(HITBOX_R * 0.25)
            if ox*ox + oy*oy + oz*oz <= HITBOX_R * HITBOX_R then break end
        end
        AimOffset = Vector3.new(ox, oy, oz)
    end
    return headPos + AimOffset
end

-- ============================================================
-- §12  AIMBOT — SMOOTHING ADAPTIVO
-- ============================================================
-- Longe do alvo: smoothing mais rápido (aquisição)
-- Perto do alvo: smoothing mais lento (precisão final)
-- Sem dead zone agressiva — imita como humano para o mouse naturalmente

local function AdaptiveAlpha(screenDistPx, baseAlpha, dt)
    local scale
    if screenDistPx > 120 then
        scale = 1.6   -- acelera aquisição
    elseif screenDistPx < 20 then
        scale = 0.55  -- desacelera para precisão
    else
        -- Interpolação suave entre os extremos
        scale = 1.6 - (1.6 - 0.55) * ((120 - screenDistPx) / 100)
    end
    return FpsAlpha(math.min(1, baseAlpha * scale), dt)
end

-- ============================================================
-- §13  ESP — DRAWING OBJECTS
-- ============================================================

local function CreateESP(player)
    if G.DrawObjs[player] then return end
    local box = {}
    for i = 1, 4 do
        local ln      = Drawing.new("Line")
        ln.Thickness  = 1.5
        ln.Color      = G.ESPColor
        ln.Visible    = false
        box[i]        = ln
    end
    local nm = Drawing.new("Text")
    nm.Size = 13; nm.Color = Color3.fromRGB(255,255,255)
    nm.Outline = true; nm.OutlineColor = Color3.fromRGB(0,0,0)
    nm.Center = true; nm.Visible = false
    local dt = Drawing.new("Text")
    dt.Size = 11; dt.Color = Color3.fromRGB(195,195,195)
    dt.Outline = true; dt.OutlineColor = Color3.fromRGB(0,0,0)
    dt.Center = true; dt.Visible = false
    G.DrawObjs[player] = { Box = box, Name = nm, Dist = dt }
end

local function RemoveESP(player)
    local o = G.DrawObjs[player]
    if not o then return end
    for _, ln in pairs(o.Box) do pcall(function() ln:Remove() end) end
    pcall(function() o.Name:Remove() end)
    pcall(function() o.Dist:Remove() end)
    G.DrawObjs[player] = nil
end

local function UpdateESP(player)
    local o = G.DrawObjs[player]
    if not o then return end
    if not G.ESPOn or not IsValid(player) then
        for _, ln in pairs(o.Box) do ln.Visible = false end
        o.Name.Visible = false; o.Dist.Visible = false
        return
    end
    local origin, w, h = GetBounds(player.Character)
    if not origin then
        for _, ln in pairs(o.Box) do ln.Visible = false end
        o.Name.Visible = false; o.Dist.Visible = false
        return
    end
    local x, y, col = origin.X, origin.Y, G.ESPColor
    -- Top
    o.Box[1].From = Vector2.new(x,   y);     o.Box[1].To = Vector2.new(x+w, y)
    -- Bottom
    o.Box[2].From = Vector2.new(x,   y+h);   o.Box[2].To = Vector2.new(x+w, y+h)
    -- Left
    o.Box[3].From = Vector2.new(x,   y);     o.Box[3].To = Vector2.new(x,   y+h)
    -- Right
    o.Box[4].From = Vector2.new(x+w, y);     o.Box[4].To = Vector2.new(x+w, y+h)
    for _, ln in pairs(o.Box) do ln.Color = col; ln.Visible = true end
    -- Label
    local hrp  = player.Character:FindFirstChild("HumanoidRootPart")
    local dist = hrp and math.floor((Camera.CFrame.Position - hrp.Position).Magnitude) or 0
    o.Name.Position = Vector2.new(x + w*0.5, y - 16)
    o.Name.Text     = player.Name
    o.Name.Visible  = true
    o.Dist.Position = Vector2.new(x + w*0.5, y - 5)
    o.Dist.Text     = dist .. " st"
    o.Dist.Visible  = true
end

-- ============================================================
-- §14  CHAMS — HIGHLIGHT  (com fix de orphan pós-respawn)
-- ============================================================

local function CreateChams(player)
    local c = player.Character
    if not c then return end
    -- Garante destruição de qualquer highlight orphan antes de criar
    if G.ChamsObjs[player] then
        pcall(function() G.ChamsObjs[player]:Destroy() end)
        G.ChamsObjs[player] = nil
    end
    local h = Instance.new("Highlight")
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
    if not G.ChamsOn or not IsValid(player) then
        RemoveChams(player)
        return
    end
    local c = player.Character
    local h = G.ChamsObjs[player]

    -- Se o highlight existe mas não está mais no char correto (respawn),
    -- ou já foi destruído, recria do zero
    if h then
        local ok = pcall(function()
            local _ = h.Parent   -- lança erro se h está destroyed
        end)
        if not ok or h.Parent ~= c then
            -- orphan detectado: recriar
            pcall(function() h:Destroy() end)
            G.ChamsObjs[player] = nil
            h = nil
        end
    end

    if not h then
        CreateChams(player)
    end
end

-- ============================================================
-- §15  SPEED HACK — onda senoidal + ruído gaussiano
-- ============================================================
-- Combinação de seno (variação periódica natural) + gaussian noise
-- para que a velocidade nunca seja uma constante detectável.

local function ApplySpeed(dt)
    local c = LP.Character
    if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    G.SpeedTimer = G.SpeedTimer + dt
    -- Seno com período ~2.3s + fase diferente a cada sessão
    local sineVar  = math.sin(G.SpeedTimer * (math.pi / 1.15)) * 2.2
    -- Gaussian noise ±0.8 studs/s (pequeno mas não zero)
    local noiseVar = GaussRand(0.5)

    hum.WalkSpeed = math.max(16, G.WalkSpeed + sineVar + noiseVar)
end

-- ============================================================
-- §16  FLY HACK — BodyVelocity + BodyGyro
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
        bv.Name     = "_BSH_BV"
        bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        bv.Velocity = Vector3.zero
        bv.Parent   = hrp
        local bg = Instance.new("BodyGyro")
        bg.Name      = "_BSH_BG"
        bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
        bg.P         = 1e4
        bg.Parent    = hrp
    end
    return c:FindFirstChild("_BSH_BV"), c:FindFirstChild("_BSH_BG")
end

local function UpdateFly()
    local bv, bg = EnsureFlyParts()
    if not bv or not bg then return end
    local dir   = Vector3.zero
    local speed = 65
    if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + Camera.CFrame.LookVector  end
    if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - Camera.CFrame.LookVector  end
    if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - Camera.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + Camera.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.Space)       then dir = dir + Vector3.new(0,  1, 0) end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir + Vector3.new(0, -1, 0) end
    bv.Velocity = dir.Magnitude > 0 and dir.Unit * speed or Vector3.zero
    bg.CFrame   = Camera.CFrame
end

-- ============================================================
-- §17  TELEPORTE INTERPOLADO — Anti-Teleport Bypass
-- ============================================================
-- Micro-passos de ≤4 studs a cada frame para nunca ultrapassar
-- o threshold de teleporte do servidor num único tick.

local function SafeTeleport(target)
    local c = LP.Character
    if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local origin = hrp.Position
    local dist   = (target - origin).Magnitude
    local steps  = math.max(8, math.ceil(dist / 4))
    for i = 1, steps do
        if not G.Running then return end
        local alpha = i / steps
        -- Ease-in-out para o movimento ser mais natural
        local t  = alpha * alpha * (3 - 2 * alpha)
        hrp.CFrame = CFrame.new(origin:Lerp(target, t))
        task.wait()
    end
end

-- ============================================================
-- §18  EVENTOS DE PLAYER
-- ============================================================

local function HookPlayer(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.8)
        if G.ESPOn   then CreateESP(player)   end
        if G.ChamsOn then CreateChams(player) end
    end)
end

-- Inicializa players já presentes quando o script carrega
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LP then
        HookPlayer(p)
        if G.ESPOn   then CreateESP(p)   end
        if G.ChamsOn then CreateChams(p) end
    end
end

Players.PlayerAdded:Connect(function(p)
    HookPlayer(p)
end)

Players.PlayerRemoving:Connect(function(p)
    RemoveESP(p)
    RemoveChams(p)
    -- Limpa state de aimbot se o alvo saiu do jogo
    if G.AimState.lockedTarget == p then
        G.AimState.lockedTarget = nil
        G.AimState.lockedSince  = 0
    end
end)

-- ============================================================
-- §19  LOOP PRINCIPAL — Heartbeat (sincronizado com motor)
-- ============================================================

local hbConn = RunService.Heartbeat:Connect(function(dt)
    if not G.Running then return end

    -- FOV Circle
    G.FOVCircle.Position = Vector2.new(Mouse.X, Mouse.Y)
    G.FOVCircle.Radius   = G.FOV
    G.FOVCircle.Visible  = G.AimbotOn

    -- Speed Hack
    if G.SpeedOn then ApplySpeed(dt) end

    -- Fly
    if G.FlyOn then UpdateFly() end

    -- Jitter OU (avança o processo independente do aimbot estar ativo ou não,
    -- para que quando ativar, o estado já esteja "aquecido" e não parta do zero)
    StepOUJitter(dt)

    -- ESP + Chams por player
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
-- §20  AIMBOT — RenderStepped (pré-frame, acesso à Camera)
-- ============================================================

local rsConn = RunService.RenderStepped:Connect(function(dt)
    if not G.Running or not G.AimbotOn then return end

    local target = GetTarget(dt)
    if not target then return end

    local char = target.Character
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end

    -- Atualiza estimativa de velocidade do alvo
    UpdateVelocity(head)

    -- Ponto de mira base: posição predita + humanização
    local baseAimPos = PredictedPos(head)
    local aimPos     = GetHumanizedAimPoint(baseAimPos, dt)

    -- Distância do aim atual ao alvo em pixels (para smoothing adaptivo)
    local sp        = Camera:WorldToViewportPoint(aimPos)
    local screenDist = (Vector2.new(sp.X, sp.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude

    if G.AimbotMode == "Legit" then
        -- Aplica jitter gaussiano OU em coordenadas de tela
        -- Converte offset de pixels para perturbação de CFrame
        local S          = G.AimState
        local camPos     = Camera.CFrame.Position
        local toTarget   = (aimPos - camPos)
        local dist3D     = toTarget.Magnitude
        local pixPerUnit = (Camera.ViewportSize.Y * 0.5) / math.tan(math.rad(Camera.FieldOfView * 0.5))
        local unitsPerPx = dist3D / pixPerUnit

        local jitteredAim = aimPos
            + Camera.CFrame.RightVector * (S.jx * unitsPerPx)
            + Camera.CFrame.UpVector    * (S.jy * unitsPerPx)

        local alpha    = AdaptiveAlpha(screenDist, G.Smoothing, dt)
        local targetCF = CFrame.new(camPos, jitteredAim)
        Camera.CFrame  = Camera.CFrame:Lerp(targetCF, alpha)

    elseif G.AimbotMode == "Rage" then
        -- Snap direto ao ponto humanizado (sem jitter no Rage)
        Camera.CFrame = CFrame.new(Camera.CFrame.Position, aimPos)
    end
end)

table.insert(G.Conns, rsConn)

-- ============================================================
-- §21  BOOT NOTIFICATION
-- ============================================================

Rayfield:Notify({
    Title    = "BloxStrike Hub v2",
    Content  = "Loaded  |  Madium L8  |  Anti-Ban",
    Duration = 5,
})
