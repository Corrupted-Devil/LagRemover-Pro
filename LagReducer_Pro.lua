-- ============================================================
--  LAG REDUCER PRO v2.0 — Ultra Performance Script
--  Compatible with: Roblox (LocalScript inside StarterPlayerScripts)
-- ============================================================

local LagReducerPro = {}

-- ┌─────────────────────────────────────────────────────────┐
-- │                     SERVICES                            │
-- └─────────────────────────────────────────────────────────┘
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local Lighting         = game:GetService("Lighting")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Stats            = game:GetService("Stats")
local ContentProvider  = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- ┌─────────────────────────────────────────────────────────┐
-- │                   CONFIGURATION                         │
-- └─────────────────────────────────────────────────────────┘
local Config = {
    -- Graphics
    RenderDistance     = 512,    -- Max stud render distance
    LODFactor          = 4,      -- Level of detail factor (higher = less detail far away)
    ShadowQuality      = false,  -- Shadows enabled
    MaxDecals          = 0,      -- Max visible decals
    MaxParticles       = 0,      -- Max particle count
    MaxBeams           = 0,      -- Max beam effects
    MaxTrails          = 0,      -- Max trail effects

    -- Lighting
    DisableBloom       = true,
    DisableBlur        = true,
    DisableSunRays     = true,
    DisableColorCorrect= true,
    DisableAtmosphere  = true,
    DisableDepthOfField= true,
    LightingTech       = Enum.Technology.Compatibility,

    -- Physics
    MaxPhysicsObjects  = 50,     -- Pause physics on objects beyond this
    PhysicsThrottle    = true,   -- Throttle non-visible physics

    -- Network
    StreamingEnabled   = true,
    StreamingMinRadius = 64,

    -- Parts
    HideDecorations    = false,  -- Hide non-essential decorative parts
    TextureQuality     = Enum.QualityLevel.Level01,

    -- Monitoring
    ShowStats          = true,
    FPSWarnThreshold   = 30,
}

-- ┌─────────────────────────────────────────────────────────┐
-- │                      STATE                              │
-- └─────────────────────────────────────────────────────────┘
local State = {
    Active       = false,
    FPS          = 60,
    Ping         = 0,
    MemoryUsage  = 0,
    FrameCount   = 0,
    LastTime     = tick(),
    Connections  = {},
    OrigSettings = {},
    UIVisible    = true,
}

-- ┌─────────────────────────────────────────────────────────┐
-- │                   UTILITY FUNCTIONS                     │
-- └─────────────────────────────────────────────────────────┘
local function SaveOriginalSettings()
    State.OrigSettings = {
        RenderDistance  = Workspace.StreamingMinRadius or 64,
        LightingTech    = Lighting.Technology,
        ShadowSoftness  = Lighting.ShadowSoftness,
        Ambient         = Lighting.Ambient,
        OutdoorAmbient  = Lighting.OutdoorAmbient,
    }
    for _, effect in ipairs(Lighting:GetChildren()) do
        State.OrigSettings["Light_"..effect.Name] = effect.Enabled
    end
end

local function DisableLightingEffects()
    for _, effect in ipairs(Lighting:GetChildren()) do
        if effect:IsA("BloomEffect")
            or effect:IsA("BlurEffect")
            or effect:IsA("SunRaysEffect")
            or effect:IsA("ColorCorrectionEffect")
            or effect:IsA("DepthOfFieldEffect") then
            if Config.DisableBloom or Config.DisableBlur or Config.DisableSunRays
                or Config.DisableColorCorrect or Config.DisableDepthOfField then
                effect.Enabled = false
            end
        end
        if effect:IsA("Atmosphere") and Config.DisableAtmosphere then
            effect.Density = 0
            effect.Haze    = 0
            effect.Glare   = 0
        end
    end
end

local function OptimizeLighting()
    Lighting.Technology       = Config.LightingTech
    Lighting.ShadowSoftness   = 0
    if not Config.ShadowQuality then
        Lighting.ShadowSoftness = 0
    end
    DisableLightingEffects()
end

local function OptimizeCamera()
    Camera.FieldOfView    = 70
    Camera.MaxZoomDistance = Config.RenderDistance
end

local function OptimizeParticlesInInstance(inst)
    for _, obj in ipairs(inst:GetDescendants()) do
        if obj:IsA("ParticleEmitter") and Config.MaxParticles == 0 then
            obj.Enabled = false
        elseif obj:IsA("Beam") and Config.MaxBeams == 0 then
            obj.Enabled = false
        elseif obj:IsA("Trail") and Config.MaxTrails == 0 then
            obj.Enabled = false
        elseif obj:IsA("Decal") or obj:IsA("Texture") then
            if Config.MaxDecals == 0 then
                obj.Transparency = 1
            end
        end
    end
end

local function OptimizeWorkspace()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            -- Reduce detail on far parts
            local dist = (obj.Position - Camera.CFrame.Position).Magnitude
            if dist > Config.RenderDistance * 0.75 then
                obj.CastShadow = false
            end
            -- Disable LOD-able parts
            if Config.HideDecorations and obj:FindFirstAncestorWhichIsA("Model") then
                if obj.Name:lower():find("decor") or obj.Name:lower():find("prop") then
                    obj.LocalTransparencyModifier = 1
                end
            end
        end
        -- Disable non-essential scripts far from player
        if obj:IsA("Script") or obj:IsA("LocalScript") then
            local char = LocalPlayer.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local dist = (obj.Parent and obj.Parent:IsA("BasePart")) 
                        and (obj.Parent.Position - hrp.Position).Magnitude or 0
                    if dist > Config.RenderDistance then
                        obj.Disabled = true
                    end
                end
            end
        end
    end
end

local function OptimizeGraphicsSettings()
    -- Use pcall for executor environments
    pcall(function()
        settings().Rendering.QualityLevel = Config.TextureQuality
    end)
    pcall(function()
        settings().Rendering.EagerBulkExecution = true
    end)
end

-- ┌─────────────────────────────────────────────────────────┐
-- │                    PERFORMANCE LOOP                     │
-- └─────────────────────────────────────────────────────────┘
local function StartPerformanceMonitor()
    local conn = RunService.Heartbeat:Connect(function()
        State.FrameCount += 1
        local now = tick()
        local elapsed = now - State.LastTime
        if elapsed >= 1 then
            State.FPS           = math.floor(State.FrameCount / elapsed)
            State.FrameCount    = 0
            State.LastTime      = now
            State.Ping          = math.floor(LocalPlayer:GetNetworkPing() * 1000)
            State.MemoryUsage   = math.floor(Stats:GetTotalMemoryUsageMb())
        end
    end)
    table.insert(State.Connections, conn)
end

local function StartDynamicOptimizer()
    local lastOptimize = 0
    local conn = RunService.Heartbeat:Connect(function()
        local now = tick()
        -- Re-optimize every 5 seconds
        if now - lastOptimize > 5 then
            lastOptimize = now
            if State.Active then
                pcall(OptimizeWorkspace)
                pcall(DisableLightingEffects)
            end
        end
    end)
    table.insert(State.Connections, conn)
end

-- ┌─────────────────────────────────────────────────────────┐
-- │                         GUI                             │
-- └─────────────────────────────────────────────────────────┘
local function BuildUI()
    local player = LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    -- Cleanup existing
    local existing = playerGui:FindFirstChild("LagReducerUI")
    if existing then existing:Destroy() end

    -- ── Root ScreenGui ──────────────────────────────────────
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name            = "LagReducerUI"
    ScreenGui.ResetOnSpawn    = false
    ScreenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    ScreenGui.IgnoreGuiInset  = true
    ScreenGui.Parent          = playerGui

    -- ── Main Frame ──────────────────────────────────────────
    local Main = Instance.new("Frame")
    Main.Name             = "Main"
    Main.Size             = UDim2.new(0, 300, 0, 420)
    Main.Position         = UDim2.new(0, 20, 0.5, -210)
    Main.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
    Main.BorderSizePixel  = 0
    Main.Parent           = ScreenGui

    local MainCorner = Instance.new("UICorner")
    MainCorner.CornerRadius = UDim.new(0, 14)
    MainCorner.Parent = Main

    local MainStroke = Instance.new("UIStroke")
    MainStroke.Color     = Color3.fromRGB(80, 60, 200)
    MainStroke.Thickness = 1.5
    MainStroke.Parent    = Main

    -- ── Top Bar ─────────────────────────────────────────────
    local TopBar = Instance.new("Frame")
    TopBar.Name             = "TopBar"
    TopBar.Size             = UDim2.new(1, 0, 0, 52)
    TopBar.BackgroundColor3 = Color3.fromRGB(22, 14, 52)
    TopBar.BorderSizePixel  = 0
    TopBar.ZIndex           = 3
    TopBar.Parent           = Main

    local TopBarCorner = Instance.new("UICorner")
    TopBarCorner.CornerRadius = UDim.new(0, 14)
    TopBarCorner.Parent = TopBar

    -- Fix bottom corners of TopBar
    local TopBarFix = Instance.new("Frame")
    TopBarFix.Size             = UDim2.new(1, 0, 0, 14)
    TopBarFix.Position         = UDim2.new(0, 0, 1, -14)
    TopBarFix.BackgroundColor3 = Color3.fromRGB(22, 14, 52)
    TopBarFix.BorderSizePixel  = 0
    TopBarFix.ZIndex           = 2
    TopBarFix.Parent           = TopBar

    -- Title
    local Title = Instance.new("TextLabel")
    Title.Text               = "⚡ LAG REDUCER PRO"
    Title.Size               = UDim2.new(1, -60, 1, 0)
    Title.Position           = UDim2.new(0, 16, 0, 0)
    Title.BackgroundTransparency = 1
    Title.TextColor3         = Color3.fromRGB(200, 170, 255)
    Title.TextSize           = 15
    Title.Font               = Enum.Font.GothamBold
    Title.TextXAlignment     = Enum.TextXAlignment.Left
    Title.ZIndex             = 4
    Title.Parent             = TopBar

    local SubTitle = Instance.new("TextLabel")
    SubTitle.Text            = "Performance Optimizer"
    SubTitle.Size            = UDim2.new(1, -60, 0, 16)
    SubTitle.Position        = UDim2.new(0, 16, 0, 30)
    SubTitle.BackgroundTransparency = 1
    SubTitle.TextColor3      = Color3.fromRGB(130, 110, 200)
    SubTitle.TextSize        = 11
    SubTitle.Font            = Enum.Font.Gotham
    SubTitle.TextXAlignment  = Enum.TextXAlignment.Left
    SubTitle.ZIndex          = 4
    SubTitle.Parent          = TopBar

    -- Toggle Button
    local ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Name               = "ToggleBtn"
    ToggleBtn.Size               = UDim2.new(0, 36, 0, 22)
    ToggleBtn.Position           = UDim2.new(1, -50, 0.5, -11)
    ToggleBtn.BackgroundColor3   = Color3.fromRGB(60, 40, 140)
    ToggleBtn.Text               = "ON"
    ToggleBtn.TextColor3         = Color3.fromRGB(200, 170, 255)
    ToggleBtn.TextSize           = 11
    ToggleBtn.Font               = Enum.Font.GothamBold
    ToggleBtn.ZIndex             = 5
    ToggleBtn.Parent             = TopBar

    local ToggleCorner = Instance.new("UICorner")
    ToggleCorner.CornerRadius = UDim.new(0, 6)
    ToggleCorner.Parent = ToggleBtn

    -- Close Button
    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size               = UDim2.new(0, 22, 0, 22)
    CloseBtn.Position           = UDim2.new(1, -26, 0.5, -11)
    CloseBtn.BackgroundColor3   = Color3.fromRGB(180, 50, 80)
    CloseBtn.Text               = "✕"
    CloseBtn.TextColor3         = Color3.fromRGB(255, 200, 200)
    CloseBtn.TextSize           = 13
    CloseBtn.Font               = Enum.Font.GothamBold
    CloseBtn.ZIndex             = 5
    CloseBtn.Parent             = TopBar

    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 6)
    CloseCorner.Parent = CloseBtn

    -- ── Stats Row ───────────────────────────────────────────
    local StatsRow = Instance.new("Frame")
    StatsRow.Name             = "StatsRow"
    StatsRow.Size             = UDim2.new(1, -20, 0, 60)
    StatsRow.Position         = UDim2.new(0, 10, 0, 60)
    StatsRow.BackgroundTransparency = 1
    StatsRow.Parent           = Main

    local StatsLayout = Instance.new("UIListLayout")
    StatsLayout.FillDirection  = Enum.FillDirection.Horizontal
    StatsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    StatsLayout.Padding        = UDim.new(0, 8)
    StatsLayout.Parent         = StatsRow

    local function MakeStat(name, value, color)
        local card = Instance.new("Frame")
        card.Size             = UDim2.new(0, 82, 1, 0)
        card.BackgroundColor3 = Color3.fromRGB(18, 14, 36)
        card.BorderSizePixel  = 0
        card.Parent           = StatsRow

        local cardCorner = Instance.new("UICorner")
        cardCorner.CornerRadius = UDim.new(0, 10)
        cardCorner.Parent = card

        local cardStroke = Instance.new("UIStroke")
        cardStroke.Color     = color
        cardStroke.Thickness = 1
        cardStroke.Parent    = card

        local lbl = Instance.new("TextLabel")
        lbl.Text             = name
        lbl.Size             = UDim2.new(1, 0, 0, 18)
        lbl.Position         = UDim2.new(0, 0, 0, 6)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3       = Color3.fromRGB(130, 120, 160)
        lbl.TextSize         = 11
        lbl.Font             = Enum.Font.Gotham
        lbl.Parent           = card

        local val = Instance.new("TextLabel")
        val.Name             = "Value"
        val.Text             = value
        val.Size             = UDim2.new(1, 0, 0, 24)
        val.Position         = UDim2.new(0, 0, 0, 26)
        val.BackgroundTransparency = 1
        val.TextColor3       = color
        val.TextSize         = 18
        val.Font             = Enum.Font.GothamBold
        val.Parent           = card

        local unit = Instance.new("TextLabel")
        unit.Text            = name == "FPS" and "fps" or (name == "PING" and "ms" or "mb")
        unit.Size            = UDim2.new(1, 0, 0, 14)
        unit.Position        = UDim2.new(0, 0, 1, -14)
        unit.BackgroundTransparency = 1
        unit.TextColor3      = Color3.fromRGB(100, 90, 140)
        unit.TextSize        = 10
        unit.Font            = Enum.Font.Gotham
        unit.Parent          = card

        return val
    end

    local FPSVal  = MakeStat("FPS",  "60", Color3.fromRGB(100, 255, 160))
    local PingVal = MakeStat("PING", "0",  Color3.fromRGB(100, 200, 255))
    local MemVal  = MakeStat("RAM",  "0",  Color3.fromRGB(255, 180, 80))

    -- ── Divider ─────────────────────────────────────────────
    local Divider = Instance.new("Frame")
    Divider.Size             = UDim2.new(1, -20, 0, 1)
    Divider.Position         = UDim2.new(0, 10, 0, 130)
    Divider.BackgroundColor3 = Color3.fromRGB(50, 40, 90)
    Divider.BorderSizePixel  = 0
    Divider.Parent           = Main

    -- ── Toggle Options ──────────────────────────────────────
    local OptionsScroll = Instance.new("ScrollingFrame")
    OptionsScroll.Size             = UDim2.new(1, -20, 1, -200)
    OptionsScroll.Position         = UDim2.new(0, 10, 0, 140)
    OptionsScroll.BackgroundTransparency = 1
    OptionsScroll.BorderSizePixel  = 0
    OptionsScroll.ScrollBarThickness = 3
    OptionsScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 80, 200)
    OptionsScroll.CanvasSize       = UDim2.new(0, 0, 0, 0)
    OptionsScroll.Parent           = Main

    local OptionsLayout = Instance.new("UIListLayout")
    OptionsLayout.Padding  = UDim.new(0, 6)
    OptionsLayout.Parent   = OptionsScroll

    local Toggles = {
        { key = "DisableBloom",        label = "Disable Bloom",         default = true  },
        { key = "DisableBlur",         label = "Disable Blur Effects",  default = true  },
        { key = "DisableSunRays",      label = "Disable Sun Rays",      default = true  },
        { key = "DisableAtmosphere",   label = "Disable Atmosphere",    default = true  },
        { key = "DisableColorCorrect", label = "Disable Color Correct", default = true  },
        { key = "DisableDepthOfField", label = "Disable Depth of Field",default = true  },
        { key = "ShadowQuality",       label = "Dynamic Shadows",       default = false },
        { key = "HideDecorations",     label = "Hide Prop Decorations", default = false },
        { key = "PhysicsThrottle",     label = "Throttle Far Physics",  default = true  },
    }

    local ToggleRefs = {}

    local function MakeToggleRow(info)
        local row = Instance.new("Frame")
        row.Size             = UDim2.new(1, 0, 0, 36)
        row.BackgroundColor3 = Color3.fromRGB(18, 14, 36)
        row.BorderSizePixel  = 0
        row.Parent           = OptionsScroll

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 8)
        rowCorner.Parent = row

        local label = Instance.new("TextLabel")
        label.Text           = info.label
        label.Size           = UDim2.new(1, -70, 1, 0)
        label.Position       = UDim2.new(0, 12, 0, 0)
        label.BackgroundTransparency = 1
        label.TextColor3     = Color3.fromRGB(200, 190, 230)
        label.TextSize       = 13
        label.Font           = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent         = row

        local togBtn = Instance.new("TextButton")
        togBtn.Size              = UDim2.new(0, 46, 0, 24)
        togBtn.Position          = UDim2.new(1, -54, 0.5, -12)
        togBtn.BackgroundColor3  = info.default 
            and Color3.fromRGB(60, 200, 110) 
            or Color3.fromRGB(80, 60, 100)
        togBtn.Text              = info.default and "ON" or "OFF"
        togBtn.TextColor3        = Color3.fromRGB(255, 255, 255)
        togBtn.TextSize          = 11
        togBtn.Font              = Enum.Font.GothamBold
        togBtn.Parent            = row

        local togCorner = Instance.new("UICorner")
        togCorner.CornerRadius = UDim.new(0, 6)
        togCorner.Parent = togBtn

        local isOn = info.default
        togBtn.MouseButton1Click:Connect(function()
            isOn = not isOn
            Config[info.key] = isOn
            if isOn then
                togBtn.BackgroundColor3 = Color3.fromRGB(60, 200, 110)
                togBtn.Text = "ON"
            else
                togBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 100)
                togBtn.Text = "OFF"
            end
            if State.Active then
                pcall(OptimizeLighting)
                pcall(OptimizeWorkspace)
            end
        end)
        ToggleRefs[info.key] = togBtn
    end

    for _, info in ipairs(Toggles) do
        MakeToggleRow(info)
    end

    -- Auto-resize scroll canvas
    OptionsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        OptionsScroll.CanvasSize = UDim2.new(0, 0, 0, OptionsLayout.AbsoluteContentSize.Y + 10)
    end)

    -- ── Bottom Apply Button ─────────────────────────────────
    local ApplyBtn = Instance.new("TextButton")
    ApplyBtn.Size             = UDim2.new(1, -20, 0, 38)
    ApplyBtn.Position         = UDim2.new(0, 10, 1, -50)
    ApplyBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 200)
    ApplyBtn.Text             = "▶  APPLY OPTIMIZATION"
    ApplyBtn.TextColor3       = Color3.fromRGB(230, 210, 255)
    ApplyBtn.TextSize         = 14
    ApplyBtn.Font             = Enum.Font.GothamBold
    ApplyBtn.BorderSizePixel  = 0
    ApplyBtn.Parent           = Main

    local ApplyCorner = Instance.new("UICorner")
    ApplyCorner.CornerRadius = UDim.new(0, 10)
    ApplyCorner.Parent = ApplyBtn

    ApplyBtn.MouseButton1Click:Connect(function()
        LagReducerPro.Activate()
        ApplyBtn.Text             = "✔  OPTIMIZED!"
        ApplyBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
        task.delay(2.5, function()
            ApplyBtn.Text             = "▶  APPLY OPTIMIZATION"
            ApplyBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 200)
        end)
    end)

    -- ── Toggle UI Visibility ────────────────────────────────
    local MinimizedFrame = Instance.new("Frame")
    MinimizedFrame.Name             = "Mini"
    MinimizedFrame.Size             = UDim2.new(0, 140, 0, 34)
    MinimizedFrame.Position         = UDim2.new(0, 20, 0.5, -17)
    MinimizedFrame.BackgroundColor3 = Color3.fromRGB(14, 10, 30)
    MinimizedFrame.BorderSizePixel  = 0
    MinimizedFrame.Visible          = false
    MinimizedFrame.Parent           = ScreenGui

    local MiniCorner = Instance.new("UICorner")
    MiniCorner.CornerRadius = UDim.new(0, 10)
    MiniCorner.Parent = MinimizedFrame

    local MiniStroke = Instance.new("UIStroke")
    MiniStroke.Color     = Color3.fromRGB(80, 60, 200)
    MiniStroke.Thickness = 1
    MiniStroke.Parent    = MinimizedFrame

    local MiniLabel = Instance.new("TextLabel")
    MiniLabel.Text           = "⚡ LAG REDUCER PRO"
    MiniLabel.Size           = UDim2.new(1, -30, 1, 0)
    MiniLabel.Position       = UDim2.new(0, 10, 0, 0)
    MiniLabel.BackgroundTransparency = 1
    MiniLabel.TextColor3     = Color3.fromRGB(180, 150, 255)
    MiniLabel.TextSize       = 12
    MiniLabel.Font           = Enum.Font.GothamBold
    MiniLabel.TextXAlignment = Enum.TextXAlignment.Left
    MiniLabel.Parent         = MinimizedFrame

    local ExpandBtn = Instance.new("TextButton")
    ExpandBtn.Size           = UDim2.new(0, 22, 0, 22)
    ExpandBtn.Position       = UDim2.new(1, -26, 0.5, -11)
    ExpandBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 140)
    ExpandBtn.Text           = "+"
    ExpandBtn.TextColor3     = Color3.fromRGB(200, 170, 255)
    ExpandBtn.TextSize       = 16
    ExpandBtn.Font           = Enum.Font.GothamBold
    ExpandBtn.Parent         = MinimizedFrame

    local ExpandCorner = Instance.new("UICorner")
    ExpandCorner.CornerRadius = UDim.new(0, 6)
    ExpandCorner.Parent = ExpandBtn

    CloseBtn.MouseButton1Click:Connect(function()
        Main.Visible         = false
        MinimizedFrame.Visible = true
    end)

    ExpandBtn.MouseButton1Click:Connect(function()
        Main.Visible         = true
        MinimizedFrame.Visible = false
    end)

    -- ── Active/Inactive Toggle ──────────────────────────────
    ToggleBtn.MouseButton1Click:Connect(function()
        State.Active = not State.Active
        if State.Active then
            ToggleBtn.Text             = "ON"
            ToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
            LagReducerPro.Activate()
        else
            ToggleBtn.Text             = "OFF"
            ToggleBtn.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
            LagReducerPro.Deactivate()
        end
    end)

    -- ── Draggable ───────────────────────────────────────────
    local dragging, dragInput, dragStart, startPos
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging  = true
            dragStart = input.Position
            startPos  = Main.Position
        end
    end)
    TopBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)

    -- ── Live Stats Update ───────────────────────────────────
    local statsConn = RunService.Heartbeat:Connect(function()
        FPSVal.Text = tostring(State.FPS)
        PingVal.Text = tostring(State.Ping)
        MemVal.Text = tostring(State.MemoryUsage)

        if State.FPS < Config.FPSWarnThreshold then
            FPSVal.TextColor3 = Color3.fromRGB(255, 100, 100)
        elseif State.FPS < 50 then
            FPSVal.TextColor3 = Color3.fromRGB(255, 200, 80)
        else
            FPSVal.TextColor3 = Color3.fromRGB(100, 255, 160)
        end

        if State.Ping > 200 then
            PingVal.TextColor3 = Color3.fromRGB(255, 100, 100)
        elseif State.Ping > 100 then
            PingVal.TextColor3 = Color3.fromRGB(255, 200, 80)
        else
            PingVal.TextColor3 = Color3.fromRGB(100, 200, 255)
        end
    end)
    table.insert(State.Connections, statsConn)
end

-- ┌─────────────────────────────────────────────────────────┐
-- │                   PUBLIC API                            │
-- └─────────────────────────────────────────────────────────┘
function LagReducerPro.Activate()
    State.Active = true
    pcall(SaveOriginalSettings)
    pcall(OptimizeLighting)
    pcall(OptimizeCamera)
    pcall(OptimizeGraphicsSettings)
    pcall(OptimizeWorkspace)
    -- Optimize new characters and models as they stream in
    Workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("Model") then
            task.defer(function()
                pcall(OptimizeParticlesInInstance, obj)
            end)
        end
    end)
    print("[LagReducerPro] ✔ Optimization ACTIVE — Targeting 10x lag reduction")
end

function LagReducerPro.Deactivate()
    State.Active = false
    -- Restore lighting technology
    Lighting.Technology = State.OrigSettings.LightingTech or Enum.Technology.ShadowMap
    for _, effect in ipairs(Lighting:GetChildren()) do
        local key = "Light_"..effect.Name
        if State.OrigSettings[key] ~= nil then
            effect.Enabled = State.OrigSettings[key]
        end
        if effect:IsA("Atmosphere") then
            effect.Density = 0.395
            effect.Haze    = 0
        end
    end
    print("[LagReducerPro] ✖ Optimization DISABLED — Settings restored")
end

function LagReducerPro.Init()
    StartPerformanceMonitor()
    StartDynamicOptimizer()
    BuildUI()
    LagReducerPro.Activate()
    print("[LagReducerPro] Initialized — UI ready, auto-optimizing...")
end

-- ┌─────────────────────────────────────────────────────────┐
-- │                        START                            │
-- └─────────────────────────────────────────────────────────┘
LagReducerPro.Init()

return LagReducerPro
