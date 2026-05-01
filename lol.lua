--[[
    ESP + Triggerbot System (Production Quality)
    =============================================
    
    Controls:
    - L: Arm/Disarm ESP system
    - Hold V: Triggerbot (independent of ESP arm state)
    - RightShift: Toggle UI visibility
    
    Features:
    - Mouse cursor-based raycasting (pixel-accurate)
    - Multi-sample raycasting for improved reliability
    - Character part prioritization and filtering
    - Configurable FOV radius and distance limiting
    - Proper debounce logic to prevent rapid triggering
    - Performance optimized with cached references
    - Clean modular architecture
]]

------------------------------------------------------------------
-- SERVICES & CACHED REFERENCES
------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Cache frequently used references for performance
local Workspace = workspace
local GetPlayers = Players.GetPlayers
local GetMouseLocation = UserInputService.GetMouseLocation

------------------------------------------------------------------
-- CONFIGURATION & SETTINGS
------------------------------------------------------------------

local Config = {
    -- Triggerbot settings
    Triggerbot = {
        Enabled = true,
        FOVRadius = 5,              -- Pixel radius around cursor for multi-sampling
        SampleCount = 9,            -- Number of raycast samples (odd number recommended)
        MaxDistance = 1000,         -- Maximum raycast distance in studs
        DebounceTime = 0.1,         -- Seconds between triggers
        FireDelay = 0.01,           -- Delay between mouse press and release
    },
    
    -- ESP settings
    ESP = {
        FillColor = Color3.fromRGB(255, 0, 0),
        OutlineColor = Color3.fromRGB(255, 255, 255),
        FillTransparency = 0.5,
        OutlineTransparency = 0,
    },
    
    -- UI settings
    UI = {
        DefaultWidth = 360,
        DefaultHeight = 260,
    }
}

-- Priority order for character parts (highest priority first)
local CharacterPartPriority = {
    "HumanoidRootPart",
    "Torso",
    "UpperTorso",
    "LowerTorso",
    "Head",
    "Humanoid",
}

------------------------------------------------------------------
-- STATE MANAGEMENT
------------------------------------------------------------------

local State = {
    Running = true,
    Connections = {},
    
    ESP = {
        Enabled = false,
        Armed = false,
        Highlights = {},  -- Renamed from Pixels for clarity
    },
    
    Triggerbot = {
        Held = false,
        State = "DISARMED",  -- DISARMED, ARMED, HOLDING, TARGET
        Clicked = false,
        LastTriggerTime = 0,
    },
    
    UI = {
        Visible = true,
        Dragging = false,
        Resizing = false,
    },
}

-- Settings persistence
local Settings = {
    ESPEnabled = false,
    ESPArmed = false,
    FillColor = Config.ESP.FillColor,
    OutlineColor = Config.ESP.OutlineColor,
    UISizeX = Config.UI.DefaultWidth,
    UISizeY = Config.UI.DefaultHeight,
}

------------------------------------------------------------------
-- UTILITY FUNCTIONS
------------------------------------------------------------------

local function SaveSettings()
    Settings.ESPEnabled = State.ESP.Enabled
    Settings.ESPArmed = State.ESP.Armed
    Settings.FillColor = Config.ESP.FillColor
    Settings.OutlineColor = Config.ESP.OutlineColor
    
    if State.UI.MainFrame then
        Settings.UISizeX = State.UI.MainFrame.Size.X.Offset
        Settings.UISizeY = State.UI.MainFrame.Size.Y.Offset
    end
end

local function LoadSettings()
    State.ESP.Enabled = Settings.ESPEnabled
    State.ESP.Armed = Settings.ESPArmed
    Config.ESP.FillColor = Settings.FillColor
    Config.ESP.OutlineColor = Settings.OutlineColor
end

local function HSVToRGB(h, s, v)
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    
    local r, g, b = 0, 0, 0
    
    if h < 60 then
        r, g, b = c, x, 0
    elseif h < 120 then
        r, g, b = x, c, 0
    elseif h < 180 then
        r, g, b = 0, c, x
    elseif h < 240 then
        r, g, b = 0, x, c
    elseif h < 300 then
        r, g, b = x, 0, c
    else
        r, g, b = c, 0, x
    end
    
    return Color3.new(r + m, g + m, b + m)
end

local function RGBToHSV(color)
    local r, g, b = color.R, color.G, color.B
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local d = max - min
    local h = 0
    
    if d == 0 then
        h = 0
    elseif max == r then
        h = 60 * (((g - b) / d) % 6)
    elseif max == g then
        h = 60 * (((b - r) / d) + 2)
    elseif max == b then
        h = 60 * (((r - g) / d) + 4)
    end
    
    local s = (max == 0) and 0 or (d / max)
    local v = max
    
    return h, s, v
end

------------------------------------------------------------------
-- RAYCASTING SYSTEM (MOUSE CURSOR-BASED)
------------------------------------------------------------------

-- Pre-allocated RaycastParams for performance
local RaycastParams = RaycastParams.new()
RaycastParams.FilterType = Enum.RaycastFilterType.Blacklist
RaycastParams.FilterDescendantsInstances = {LocalPlayer.Character}

-- Multi-sample offset patterns for better accuracy
local SampleOffsets = {
    Vector2.new(0, 0),      -- Center
    Vector2.new(1, 0),      -- Right
    Vector2.new(-1, 0),     -- Left
    Vector2.new(0, 1),      -- Down
    Vector2.new(0, -1),     -- Up
    Vector2.new(2, 0),      -- Far right
    Vector2.new(-2, 0),     -- Far left
    Vector2.new(0, 2),      -- Far down
    Vector2.new(0, -2),     -- Far up
    Vector2.new(1, 1),      -- Diagonal
    Vector2.new(-1, -1),    -- Diagonal
    Vector2.new(1, -1),     -- Diagonal
    Vector2.new(-1, 1),     -- Diagonal
}

--- Check if a part belongs to a priority character part
local function IsPriorityPart(part)
    for _, priorityName in ipairs(CharacterPartPriority) do
        if part.Name == priorityName then
            return true
        end
    end
    return false
end

--- Get the player from a character model, with filtering
local function GetTargetPlayerFromPart(part)
    local model = part:FindFirstAncestorOfClass("Model")
    if not model then return nil end
    
    local player = Players:GetPlayerFromCharacter(model)
    if not player or player == LocalPlayer then return nil end
    
    -- Filter out irrelevant hits
    if part:IsA("Accessory") or part.Name:match("Handle") then
        return nil
    end
    
    return player
end

--- Perform multi-sample raycasting from mouse cursor position
local function PerformCursorRaycast()
    if not Camera then
        Camera = Workspace.CurrentCamera
        if not Camera then return nil end
    end
    
    -- Get mouse cursor position
    local mousePos = GetMouseLocation(UserInputService)
    local cursorX, cursorY = mousePos.X, mousePos.Y
    
    -- Update filter to include current character
    RaycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    
    -- Determine number of samples to use
    local sampleCount = math.min(Config.Triggerbot.SampleCount, #SampleOffsets)
    
    -- Try each sample point
    for i = 1, sampleCount do
        local offset = SampleOffsets[i]
        local sampleX = cursorX + offset.X
        local sampleY = cursorY + offset.Y
        
        -- Create ray from viewport point
        local ray = Camera:ViewportPointToRay(sampleX, sampleY)
        
        -- Perform raycast
        local result = Workspace:Raycast(
            ray.Origin,
            ray.Direction * Config.Triggerbot.MaxDistance,
            RaycastParams
        )
        
        if result and result.Instance then
            local part = result.Instance
            
            -- Check if this is a valid target
            local targetPlayer = GetTargetPlayerFromPart(part)
            if targetPlayer then
                -- Prioritize important body parts
                if IsPriorityPart(part) then
                    return {
                        Player = targetPlayer,
                        Part = part,
                        Position = result.Position,
                        Distance = result.Distance,
                        IsPriority = true,
                    }
                else
                    -- Store non-priority hit but continue searching
                    if not bestResult then
                        bestResult = {
                            Player = targetPlayer,
                            Part = part,
                            Position = result.Position,
                            Distance = result.Distance,
                            IsPriority = false,
                        }
                    end
                end
            end
        end
    end
    
    -- Return best result (priority if found, otherwise first valid)
    return bestResult
end

------------------------------------------------------------------
-- ESP SYSTEM
------------------------------------------------------------------

local ESPSystem = {}

function ESPSystem:CreateHighlight(character)
    if not character or State.ESP.Highlights[character] then
        return
    end
    
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Highlight"
    highlight.FillColor = Config.ESP.FillColor
    highlight.FillTransparency = Config.ESP.FillTransparency
    highlight.OutlineColor = Config.ESP.OutlineColor
    highlight.OutlineTransparency = Config.ESP.OutlineTransparency
    highlight.Adornee = character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = character
    
    State.ESP.Highlights[character] = highlight
end

function ESPSystem:RemoveHighlight(character)
    if character and State.ESP.Highlights[character] then
        State.ESP.Highlights[character]:Destroy()
        State.ESP.Highlights[character] = nil
    end
end

function ESPSystem:ClearAll()
    for character, highlight in pairs(State.ESP.Highlights) do
        highlight:Destroy()
    end
    State.ESP.Highlights = {}
end

function ESPSystem:Update()
    if not State.ESP.Enabled or not State.ESP.Armed then
        if next(State.ESP.Highlights) ~= nil then
            self:ClearAll()
        end
        return
    end
    
    -- Update existing highlights and create new ones
    for _, player in ipairs(GetPlayers(Players)) do
        if player ~= LocalPlayer then
            local character = player.Character
            if character and character:FindFirstChild("HumanoidRootPart") then
                if not State.ESP.Highlights[character] then
                    self:CreateHighlight(character)
                end
            else
                self:RemoveHighlight(character)
            end
        end
    end
    
    -- Remove highlights for players that no longer exist
    for character, _ in pairs(State.ESP.Highlights) do
        if not character or not character.Parent then
            self:RemoveHighlight(character)
        end
    end
end

------------------------------------------------------------------
-- TRIGGERBOT SYSTEM
------------------------------------------------------------------

local function ProcessTriggerbot()
    if not Config.Triggerbot.Enabled then
        State.Triggerbot.State = "DISARMED"
        return
    end
    
    if not State.Triggerbot.Held then
        if State.Triggerbot.State == "DISARMED" then
            State.Triggerbot.State = "ARMED"
        end
        State.Triggerbot.Clicked = false
        return
    end
    
    State.Triggerbot.State = "HOLDING"
    
    -- Check debounce
    local currentTime = tick()
    if currentTime - State.Triggerbot.LastTriggerTime < Config.Triggerbot.DebounceTime then
        return
    end
    
    -- Perform raycast
    local targetInfo = PerformCursorRaycast()
    
    if targetInfo then
        State.Triggerbot.State = "TARGET"
        
        -- Fire trigger
        mouse1press()
        task.wait(Config.Triggerbot.FireDelay)
        mouse1release()
        
        State.Triggerbot.LastTriggerTime = currentTime
        State.Triggerbot.Clicked = true
    else
        State.Triggerbot.State = "HOLDING"
        State.Triggerbot.Clicked = false
    end
end

------------------------------------------------------------------
-- UI SYSTEM
------------------------------------------------------------------

local UIElements = {}

local function CreateUI()
    LoadSettings()
    
    -- Clean up existing UI
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local existingUI = playerGui:FindFirstChild("ESP_UI")
    if existingUI then
        existingUI:Destroy()
    end
    
    -- ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ESP_UI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui
    UIElements.ScreenGui = screenGui
    
    -- Main Frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, Settings.UISizeX, 0, Settings.UISizeY)
    mainFrame.Position = UDim2.new(0, 20, 0, 20)
    mainFrame.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = screenGui
    UIElements.MainFrame = mainFrame
    
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)
    
    -- Resize Handle
    local resizeHandle = Instance.new("Frame")
    resizeHandle.Size = UDim2.new(0, 14, 0, 14)
    resizeHandle.AnchorPoint = Vector2.new(1, 1)
    resizeHandle.Position = UDim2.new(1, 0, 1, 0)
    resizeHandle.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    resizeHandle.BorderSizePixel = 0
    resizeHandle.Parent = mainFrame
    
    Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 3)
    UIElements.ResizeHandle = resizeHandle
    
    -- Title Bar
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    title.Text = "ESP + Triggerbot"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.BorderSizePixel = 0
    title.Parent = mainFrame
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)
    
    -- Tab Bar
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -10, 0, 26)
    tabBar.Position = UDim2.new(0, 5, 0, 32)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = mainFrame
    
    -- Main Tab
    local mainTab = Instance.new("TextButton")
    mainTab.Size = UDim2.new(1/3, -5, 1, 0)
    mainTab.Position = UDim2.new(0, 0, 0, 0)
    mainTab.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    mainTab.TextColor3 = Color3.fromRGB(255, 255, 255)
    mainTab.TextScaled = true
    mainTab.Text = "Main"
    mainTab.BorderSizePixel = 0
    mainTab.Parent = tabBar
    Instance.new("UICorner", mainTab).CornerRadius = UDim.new(0, 6)
    UIElements.MainTab = mainTab
    
    -- Debug Tab
    local debugTab = Instance.new("TextButton")
    debugTab.Size = UDim2.new(1/3, -5, 1, 0)
    debugTab.Position = UDim2.new(1/3, 5, 0, 0)
    debugTab.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    debugTab.TextColor3 = Color3.fromRGB(200, 200, 200)
    debugTab.TextScaled = true
    debugTab.Text = "Debug"
    debugTab.BorderSizePixel = 0
    debugTab.Parent = tabBar
    Instance.new("UICorner", debugTab).CornerRadius = UDim.new(0, 6)
    UIElements.DebugTab = debugTab
    
    -- Settings Tab
    local settingsTab = Instance.new("TextButton")
    settingsTab.Size = UDim2.new(1/3, -5, 1, 0)
    settingsTab.Position = UDim2.new(2/3, 10, 0, 0)
    settingsTab.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    settingsTab.TextColor3 = Color3.fromRGB(200, 200, 200)
    settingsTab.TextScaled = true
    settingsTab.Text = "ESP Settings"
    settingsTab.BorderSizePixel = 0
    settingsTab.Parent = tabBar
    Instance.new("UICorner", settingsTab).CornerRadius = UDim.new(0, 6)
    UIElements.SettingsTab = settingsTab
    
    -- Main Content
    local mainContent = Instance.new("Frame")
    mainContent.Size = UDim2.new(1, -10, 1, -90)
    mainContent.Position = UDim2.new(0, 5, 0, 60)
    mainContent.BackgroundTransparency = 1
    mainContent.Name = "MainContent"
    mainContent.Parent = mainFrame
    UIElements.MainContent = mainContent
    
    -- ESP Toggle Button
    local espToggle = Instance.new("TextButton")
    espToggle.Size = UDim2.new(0, 260, 0, 36)
    espToggle.Position = UDim2.new(0, 20, 0, 5)
    espToggle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    espToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    espToggle.TextScaled = true
    espToggle.BorderSizePixel = 0
    espToggle.Text = State.ESP.Enabled and "ESP: ON" or "ESP: OFF"
    espToggle.Parent = mainContent
    Instance.new("UICorner", espToggle).CornerRadius = UDim.new(0, 6)
    UIElements.ESPToggle = espToggle
    
    -- Info Label
    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -10, 0, 40)
    info.Position = UDim2.new(0, 5, 0, 45)
    info.BackgroundTransparency = 1
    info.TextColor3 = Color3.fromRGB(180, 180, 180)
    info.TextScaled = true
    info.TextWrapped = true
    info.Text = "L = Arm/Disarm | Hold V = Trigger | RightShift = Hide UI"
    info.Parent = mainContent
    
    -- Kill Button
    local killButton = Instance.new("TextButton")
    killButton.Size = UDim2.new(0, 260, 0, 30)
    killButton.Position = UDim2.new(0, 20, 1, -35)
    killButton.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
    killButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    killButton.TextScaled = true
    killButton.Text = "KILL SCRIPT"
    killButton.BorderSizePixel = 0
    killButton.Parent = mainContent
    Instance.new("UICorner", killButton).CornerRadius = UDim.new(0, 6)
    UIElements.KillButton = killButton
    
    -- Debug Content
    local debugContent = Instance.new("Frame")
    debugContent.Size = UDim2.new(1, -10, 1, -90)
    debugContent.Position = UDim2.new(0, 5, 0, 60)
    debugContent.BackgroundTransparency = 1
    debugContent.Name = "DebugContent"
    debugContent.Visible = false
    debugContent.Parent = mainFrame
    UIElements.DebugContent = debugContent
    
    -- State Label
    local stateLabel = Instance.new("TextLabel")
    stateLabel.Size = UDim2.new(1, -10, 0, 30)
    stateLabel.Position = UDim2.new(0, 5, 0, 5)
    stateLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    stateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    stateLabel.TextScaled = true
    stateLabel.BorderSizePixel = 0
    stateLabel.Text = "Trigger state: " .. State.Triggerbot.State
    stateLabel.Parent = debugContent
    Instance.new("UICorner", stateLabel).CornerRadius = UDim.new(0, 6)
    UIElements.StateLabel = stateLabel
    
    -- Debug Info
    local debugInfo = Instance.new("TextLabel")
    debugInfo.Size = UDim2.new(1, -10, 0, 70)
    debugInfo.Position = UDim2.new(0, 5, 0, 40)
    debugInfo.BackgroundTransparency = 1
    debugInfo.TextColor3 = Color3.fromRGB(200, 200, 200)
    debugInfo.TextScaled = true
    debugInfo.TextWrapped = true
    debugInfo.Text = 
        "DISARMED: V not held\n" ..
        "ARMED: Ready, V can be held\n" ..
        "HOLDING: V held, scanning\n" ..
        "TARGET: enemy in cursor"
    debugInfo.Parent = debugContent
    
    -- Settings Content
    local settingsContent = Instance.new("Frame")
    settingsContent.Size = UDim2.new(1, -10, 1, -90)
    settingsContent.Position = UDim2.new(0, 5, 0, 60)
    settingsContent.BackgroundTransparency = 1
    settingsContent.Name = "SettingsContent"
    settingsContent.Visible = false
    settingsContent.Parent = mainFrame
    UIElements.SettingsContent = settingsContent
    
    -- Color Picker Frame
    local pickerFrame = Instance.new("Frame")
    pickerFrame.Size = UDim2.new(0, 210, 0, 160)
    pickerFrame.Position = UDim2.new(0, 10, 0, 5)
    pickerFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    pickerFrame.BorderSizePixel = 0
    pickerFrame.Parent = settingsContent
    Instance.new("UICorner", pickerFrame).CornerRadius = UDim.new(0, 6)
    
    -- Saturation/Value Square
    local svSquare = Instance.new("Frame")
    svSquare.Size = UDim2.new(0, 130, 0, 130)
    svSquare.Position = UDim2.new(0, 10, 0, 10)
    svSquare.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    svSquare.BorderSizePixel = 0
    svSquare.Parent = pickerFrame
    UIElements.SVSquare = svSquare
    
    local svSelector = Instance.new("Frame")
    svSelector.Size = UDim2.new(0, 8, 0, 8)
    svSelector.AnchorPoint = Vector2.new(0.5, 0.5)
    svSelector.BackgroundColor3 = Color3.new(1, 1, 1)
    svSelector.BorderSizePixel = 1
    svSelector.BorderColor3 = Color3.new(0, 0, 0)
    svSelector.Parent = svSquare
    Instance.new("UICorner", svSelector).CornerRadius = UDim.new(1, 0)
    UIElements.SVSelector = svSelector
    
    -- White Overlay
    local whiteOverlay = Instance.new("Frame")
    whiteOverlay.Size = UDim2.new(1, 0, 1, 0)
    whiteOverlay.BackgroundTransparency = 1
    whiteOverlay.BorderSizePixel = 0
    whiteOverlay.Parent = svSquare
    
    local whiteGrad = Instance.new("UIGradient")
    whiteGrad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
    }
    whiteGrad.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1)
    }
    whiteGrad.Rotation = 90
    whiteGrad.Parent = whiteOverlay
    
    -- Black Overlay
    local blackOverlay = Instance.new("Frame")
    blackOverlay.Size = UDim2.new(1, 0, 1, 0)
    blackOverlay.BackgroundTransparency = 1
    blackOverlay.BorderSizePixel = 0
    blackOverlay.Parent = svSquare
    
    local blackGrad = Instance.new("UIGradient")
    blackGrad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
    }
    blackGrad.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0)
    }
    blackGrad.Rotation = 0
    blackGrad.Parent = blackOverlay
    
    -- Hue Bar
    local hueBar = Instance.new("Frame")
    hueBar.Size = UDim2.new(0, 20, 0, 130)
    hueBar.Position = UDim2.new(0, 150, 0, 10)
    hueBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    hueBar.BorderSizePixel = 0
    hueBar.Parent = pickerFrame
    UIElements.HueBar = hueBar
    
    local hueSelector = Instance.new("Frame")
    hueSelector.AnchorPoint = Vector2.new(0.5, 0.5)
    hueSelector.Size = UDim2.new(1, 0, 0, 4)
    hueSelector.Position = UDim2.new(0.5, 0, 0, 0)
    hueSelector.BackgroundColor3 = Color3.new(1, 1, 1)
    hueSelector.BorderSizePixel = 1
    hueSelector.BorderColor3 = Color3.new(0, 0, 0)
    hueSelector.Parent = hueBar
    Instance.new("UICorner", hueSelector).CornerRadius = UDim.new(1, 0)
    UIElements.HueSelector = hueSelector
    
    local hueGrad = Instance.new("UIGradient")
    hueGrad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 0, 255)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 0, 255)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0))
    }
    hueGrad.Transparency = NumberSequence.new(0)
    hueGrad.Rotation = 90
    hueGrad.Parent = hueBar
    
    -- Color Preview
    local preview = Instance.new("Frame")
    preview.Size = UDim2.new(0, 40, 0, 40)
    preview.Position = UDim2.new(0, 150, 0, 145)
    preview.BackgroundColor3 = Config.ESP.FillColor
    preview.BorderSizePixel = 0
    preview.Parent = pickerFrame
    Instance.new("UICorner", preview).CornerRadius = UDim.new(0, 4)
    UIElements.Preview = preview
    
    -- Apply Buttons
    local applyFill = Instance.new("TextButton")
    applyFill.Size = UDim2.new(0, 120, 0, 24)
    applyFill.Position = UDim2.new(0, 230, 0, 20)
    applyFill.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
    applyFill.TextColor3 = Color3.fromRGB(255, 255, 255)
    applyFill.TextScaled = true
    applyFill.Text = "Apply to Fill"
    applyFill.BorderSizePixel = 0
    applyFill.Parent = settingsContent
    Instance.new("UICorner", applyFill).CornerRadius = UDim.new(0, 4)
    UIElements.ApplyFill = applyFill
    
    local applyOutline = applyFill:Clone()
    applyOutline.Text = "Apply to Outline"
    applyOutline.Position = UDim2.new(0, 230, 0, 50)
    applyOutline.Parent = settingsContent
    Instance.new("UICorner", applyOutline).CornerRadius = UDim.new(0, 4)
    UIElements.ApplyOutline = applyOutline
    
    -- Tab switching function
    local function setTab(which)
        mainContent.Visible = (which == "main")
        debugContent.Visible = (which == "debug")
        settingsContent.Visible = (which == "settings")
        
        mainTab.BackgroundColor3 = (which == "main") and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)
        mainTab.TextColor3 = (which == "main") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
        
        debugTab.BackgroundColor3 = (which == "debug") and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)
        debugTab.TextColor3 = (which == "debug") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
        
        settingsTab.BackgroundColor3 = (which == "settings") and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)
        settingsTab.TextColor3 = (which == "settings") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
    end
    
    -- Tab click handlers
    mainTab.MouseButton1Click:Connect(function() setTab("main") end)
    debugTab.MouseButton1Click:Connect(function() setTab("debug") end)
    settingsTab.MouseButton1Click:Connect(function() setTab("settings") end)
    
    -- ESP Toggle handler
    espToggle.MouseButton1Click:Connect(function()
        State.ESP.Enabled = not State.ESP.Enabled
        espToggle.Text = State.ESP.Enabled and "ESP: ON" or "ESP: OFF"
        
        if not State.ESP.Enabled then
            ESPSystem:ClearAll()
        end
        
        SaveSettings()
    end)
    
    -- Kill button handler
    killButton.MouseButton1Click:Connect(function()
        State.Running = false
        ESPSystem:ClearAll()
        
        if screenGui then
            screenGui:Destroy()
        end
        
        for _, conn in ipairs(State.Connections) do
            pcall(function() conn:Disconnect() end)
        end
    end)
    
    -- Apply button handlers
    applyFill.MouseButton1Click:Connect(function()
        Config.ESP.FillColor = preview.BackgroundColor3
        
        for _, highlight in pairs(State.ESP.Highlights) do
            highlight.FillColor = Config.ESP.FillColor
        end
        
        SaveSettings()
    end)
    
    applyOutline.MouseButton1Click:Connect(function()
        Config.ESP.OutlineColor = preview.BackgroundColor3
        
        for _, highlight in pairs(State.ESP.Highlights) do
            highlight.OutlineColor = Config.ESP.OutlineColor
        end
        
        SaveSettings()
    end)
end

------------------------------------------------------------------
-- COLOR PICKER LOGIC
------------------------------------------------------------------

local ColorPickerState = {
    Hue = 0,
    Saturation = 1,
    Value = 1,
}

local function UpdateColorPickerFromHSV()
    local color = Color3.fromHSV(ColorPickerState.Hue / 360, ColorPickerState.Saturation, ColorPickerState.Value)
    
    UIElements.Preview.BackgroundColor3 = color
    UIElements.SVSquare.BackgroundColor3 = Color3.fromHSV(ColorPickerState.Hue / 360, 1, 1)
    UIElements.SVSquare.BackgroundTransparency = 0
    
    UIElements.SVSelector.Position = UDim2.new(ColorPickerState.Saturation, 0, 1 - ColorPickerState.Value, 0)
    UIElements.HueSelector.Position = UDim2.new(0.5, 0, 1 - (ColorPickerState.Hue / 360), 0)
end

local function SetUIDragging(enabled)
    if UIElements.MainFrame then
        UIElements.MainFrame.Draggable = enabled
    end
end

-- SV Square input handling
UIElements.SVSquare.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        SetUIDragging(false)
        
        local moveConn, endConn
        
        moveConn = UserInputService.InputChanged:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseMovement then
                local mouse = UserInputService:GetMouseLocation()
                local relX = mouse.X - UIElements.SVSquare.AbsolutePosition.X
                local relY = mouse.Y - UIElements.SVSquare.AbsolutePosition.Y
                
                local sx = math.clamp(relX / UIElements.SVSquare.AbsoluteSize.X, 0, 1)
                local sy = math.clamp(relY / UIElements.SVSquare.AbsoluteSize.Y, 0, 1)
                
                ColorPickerState.Saturation = sx
                ColorPickerState.Value = 1 - sy
                
                UpdateColorPickerFromHSV()
            end
        end)
        
        endConn = UserInputService.InputEnded:Connect(function(i2)
            if i2.UserInputType == Enum.UserInputType.MouseButton1 then
                moveConn:Disconnect()
                endConn:Disconnect()
                SetUIDragging(true)
            end
        end)
    end
end)

-- Hue Bar input handling
UIElements.HueBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        SetUIDragging(false)
        
        local moveConn, endConn
        
        moveConn = UserInputService.InputChanged:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseMovement then
                local mouse = UserInputService:GetMouseLocation()
                local relY = mouse.Y - UIElements.HueBar.AbsolutePosition.Y
                
                local t = math.clamp(relY / UIElements.HueBar.AbsoluteSize.Y, 0, 1)
                ColorPickerState.Hue = (1 - t) * 360
                
                UpdateColorPickerFromHSV()
            end
        end)
        
        endConn = UserInputService.InputEnded:Connect(function(i2)
            if i2.UserInputType == Enum.UserInputType.MouseButton1 then
                moveConn:Disconnect()
                endConn:Disconnect()
                SetUIDragging(true)
            end
        end)
    end
end)

-- Initialize color picker
UpdateColorPickerFromHSV()

------------------------------------------------------------------
-- UI RESIZING
------------------------------------------------------------------

do
    local resizing = false
    local startMousePos
    local startSize
    local oldDraggable
    
    UIElements.ResizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = true
            startMousePos = UserInputService:GetMouseLocation()
            startSize = UIElements.MainFrame.Size
            
            oldDraggable = UIElements.MainFrame.Draggable
            UIElements.MainFrame.Draggable = false
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if resizing then
                resizing = false
                UIElements.MainFrame.Draggable = oldDraggable ~= nil and oldDraggable or true
            end
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if not resizing then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        
        local currentPos = UserInputService:GetMouseLocation()
        local dx = currentPos.X - startMousePos.X
        local dy = currentPos.Y - startMousePos.Y
        
        local newW = math.max(300, startSize.X.Offset + dx)
        local newH = math.max(220, startSize.Y.Offset + dy)
        
        UIElements.MainFrame.Size = UDim2.new(0, newW, 0, newH)
        SaveSettings()
    end)
end

------------------------------------------------------------------
-- INPUT HANDLING
------------------------------------------------------------------

-- UI Toggle (RightShift)
table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    
    if input.KeyCode == Enum.KeyCode.RightShift then
        UIElements.MainFrame.Visible = not UIElements.MainFrame.Visible
        State.UI.Visible = UIElements.MainFrame.Visible
    end
end))

-- L key (ESP Arm/Disarm) and V key (Triggerbot hold)
table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    
    if input.KeyCode == Enum.KeyCode.L then
        State.ESP.Armed = not State.ESP.Armed
    end
    
    if input.KeyCode == Enum.KeyCode.V then
        State.Triggerbot.Held = true
        State.Triggerbot.State = "HOLDING"
    end
end))

table.insert(State.Connections, UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.V then
        State.Triggerbot.Held = false
        
        if State.Triggerbot.State ~= "DISARMED" then
            State.Triggerbot.State = "ARMED"
        end
        
        State.Triggerbot.Clicked = false
    end
end))

------------------------------------------------------------------
-- MAIN GAME LOOP
------------------------------------------------------------------

table.insert(State.Connections, RunService.RenderStepped:Connect(function()
    if not State.Running then return end
    
    -- Update ESP system
    ESPSystem:Update()
    
    -- Process triggerbot
    ProcessTriggerbot()
    
    -- Update debug UI
    if UIElements.StateLabel then
        UIElements.StateLabel.Text = "Trigger state: " .. State.Triggerbot.State
    end
end))

------------------------------------------------------------------
-- INITIALIZATION
------------------------------------------------------------------

CreateUI()
