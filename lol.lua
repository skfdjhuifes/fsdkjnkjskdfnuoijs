--[[
    ESP + Triggerbot System (Production Quality - Fixed Initialization)
    ====================================================================
    
    PLACE AS A LOCALSCRIPT IN StarterPlayerScripts OR StarterGui
    
    Controls:
    - L: Arm/Disarm ESP system
    - Hold V: Triggerbot (independent of ESP arm state)
    - RightShift: Toggle UI visibility
    
    Features:
    - Mouse cursor-based raycasting (pixel-accurate)
    - Multi-sample raycasting for improved reliability
    - Character part prioritization and filtering
    - Live UI configuration (no restart needed)
    - Enhanced UI with more settings
    - Proper debounce logic to prevent rapid triggering
    - Performance optimized with cached references
    - Safe initialization with proper waiting
]]

------------------------------------------------------------------
-- SAFE INITIALIZATION - Wait for game to be ready
------------------------------------------------------------------

print("[ESP+Triggerbot] Script started, initializing...")

-- Wait for game to load
repeat task.wait() until game:IsLoaded()
print("[ESP+Triggerbot] Game loaded")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Wait for LocalPlayer
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    print("[ESP+Triggerbot] ERROR: No LocalPlayer, waiting...")
    LocalPlayer = Players.LocalPlayerAdded:Wait()
end
print("[ESP+Triggerbot] LocalPlayer: " .. LocalPlayer.Name)

-- Wait for PlayerGui
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
print("[ESP+Triggerbot] PlayerGui ready")

-- Wait for Character
local function GetCharacter()
    local char = LocalPlayer.Character
    while not char or not char:FindFirstChild("HumanoidRootPart") do
        task.wait(0.1)
        char = LocalPlayer.Character
    end
    return char
end

-- Wait for Camera
local function GetCamera()
    local cam = workspace.CurrentCamera
    while not cam do
        task.wait(0.1)
        cam = workspace.CurrentCamera
    end
    return cam
end

print("[ESP+Triggerbot] Waiting for character...")
local Character = GetCharacter()
print("[ESP+Triggerbot] Character ready: " .. Character.Name)

local Camera = GetCamera()
print("[ESP+Triggerbot] Camera ready")

-- Cache frequently used references
local Workspace = workspace
local GetPlayers = Players.GetPlayers
local GetMouseLocation = UserInputService.GetMouseLocation

print("[ESP+Triggerbot] Services initialized")

------------------------------------------------------------------
-- CONFIGURATION (Live-Editable)
------------------------------------------------------------------

local Config = {
    Triggerbot = {
        Enabled = true,
        SampleCount = 9,
        MaxDistance = 1000,
        DebounceTime = 0.1,
        FireDelay = 0.01,
    },
    ESP = {
        FillColor = Color3.fromRGB(255, 0, 0),
        OutlineColor = Color3.fromRGB(255, 255, 255),
        FillTransparency = 0.5,
        OutlineTransparency = 0,
    },
}

-- Priority order for character parts
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
    UIElements = {},
    
    ESP = {
        Enabled = false,
        Armed = false,
        Highlights = {},
    },
    
    Triggerbot = {
        Held = false,
        State = "DISARMED",
        Clicked = false,
        LastTriggerTime = 0,
    },
}

------------------------------------------------------------------
-- UTILITY FUNCTIONS
------------------------------------------------------------------

local function HSVToRGB(h, s, v)
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b = 0, 0, 0
    
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    
    return Color3.new(r + m, g + m, b + m)
end

------------------------------------------------------------------
-- RAYCASTING SYSTEM (MOUSE CURSOR-BASED)
------------------------------------------------------------------

local RaycastParamsObj = RaycastParams.new()
RaycastParamsObj.FilterType = Enum.RaycastFilterType.Blacklist

local SampleOffsets = {
    Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(-1, 0),
    Vector2.new(0, 1), Vector2.new(0, -1), Vector2.new(2, 0),
    Vector2.new(-2, 0), Vector2.new(0, 2), Vector2.new(0, -2),
    Vector2.new(1, 1), Vector2.new(-1, -1), Vector2.new(1, -1),
    Vector2.new(-1, 1),
}

local function IsPriorityPart(part)
    for _, name in ipairs(CharacterPartPriority) do
        if part.Name == name then return true end
    end
    return false
end

local function GetTargetPlayerFromPart(part)
    if part:IsA("Accessory") or part.Name:match("Handle") then return nil end
    
    local model = part:FindFirstAncestorOfClass("Model")
    if not model then return nil end
    
    local player = Players:GetPlayerFromCharacter(model)
    if not player or player == LocalPlayer then return nil end
    
    return player
end

local function PerformCursorRaycast()
    -- Update camera reference
    Camera = Workspace.CurrentCamera
    if not Camera then return nil end
    
    -- Update character filter
    local char = LocalPlayer.Character
    if not char then return nil end
    
    RaycastParamsObj.FilterDescendantsInstances = {char}
    
    local mousePos = GetMouseLocation(UserInputService)
    local sampleCount = math.min(Config.Triggerbot.SampleCount, #SampleOffsets)
    local bestResult
    
    for i = 1, sampleCount do
        local offset = SampleOffsets[i]
        local ray = Camera:ViewportPointToRay(
            mousePos.X + offset.X,
            mousePos.Y + offset.Y
        )
        
        local result = Workspace:Raycast(
            ray.Origin,
            ray.Direction * Config.Triggerbot.MaxDistance,
            RaycastParamsObj
        )
        
        if result and result.Instance then
            local targetPlayer = GetTargetPlayerFromPart(result.Instance)
            if targetPlayer then
                if IsPriorityPart(result.Instance) then
                    return {
                        Player = targetPlayer,
                        Part = result.Instance,
                        Position = result.Position,
                        Distance = result.Distance,
                        IsPriority = true,
                    }
                elseif not bestResult then
                    bestResult = {
                        Player = targetPlayer,
                        Part = result.Instance,
                        Position = result.Position,
                        Distance = result.Distance,
                        IsPriority = false,
                    }
                end
            end
        end
    end
    
    return bestResult
end

------------------------------------------------------------------
-- ESP SYSTEM
------------------------------------------------------------------

local ESPSystem = {}

function ESPSystem:CreateHighlight(character)
    if not character or State.ESP.Highlights[character] then return end
    
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
    for _, highlight in pairs(State.ESP.Highlights) do
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
        State.Triggerbot.State = State.Triggerbot.State == "DISARMED" and "DISARMED" or "ARMED"
        State.Triggerbot.Clicked = false
        return
    end
    
    State.Triggerbot.State = "HOLDING"
    
    local currentTime = tick()
    if currentTime - State.Triggerbot.LastTriggerTime < Config.Triggerbot.DebounceTime then
        return
    end
    
    local targetInfo = PerformCursorRaycast()
    
    if targetInfo then
        State.Triggerbot.State = "TARGET"
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
local currentHue = 0
local currentS = 1
local currentV = 1

local function SetUIDragging(enabled)
    if UIElements.MainFrame then
        UIElements.MainFrame.Draggable = enabled
    end
end

local function UpdateColorPickerFromHSV()
    local color = Color3.fromHSV(currentHue / 360, currentS, currentV)
    
    if UIElements.Preview then
        UIElements.Preview.BackgroundColor3 = color
    end
    if UIElements.SVSquare then
        UIElements.SVSquare.BackgroundColor3 = Color3.fromHSV(currentHue / 360, 1, 1)
        UIElements.SVSquare.BackgroundTransparency = 0
    end
    
    if UIElements.SVSelector then
        UIElements.SVSelector.Position = UDim2.new(currentS, 0, 1 - currentV, 0)
    end
    if UIElements.HueSelector then
        UIElements.HueSelector.Position = UDim2.new(0.5, 0, 1 - (currentHue / 360), 0)
    end
end

local function CreateUI()
    print("[ESP+Triggerbot] Creating UI...")
    
    -- Clean up existing UI
    local existingUI = PlayerGui:FindFirstChild("ESP_UI")
    if existingUI then
        existingUI:Destroy()
    end
    
    -- ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ESP_UI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = PlayerGui
    UIElements.ScreenGui = screenGui
    print("[ESP+Triggerbot] ScreenGui created and parented to PlayerGui")
    
    -- Main Frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 400, 0, 320)
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
    mainTab.Size = UDim2.new(0.25, -5, 1, 0)
    mainTab.Position = UDim2.new(0, 0, 0, 0)
    mainTab.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    mainTab.TextColor3 = Color3.fromRGB(255, 255, 255)
    mainTab.TextScaled = true
    mainTab.Text = "Main"
    mainTab.BorderSizePixel = 0
    mainTab.Parent = tabBar
    Instance.new("UICorner", mainTab).CornerRadius = UDim.new(0, 6)
    UIElements.MainTab = mainTab
    
    -- Triggerbot Tab
    local triggerTab = Instance.new("TextButton")
    triggerTab.Size = UDim2.new(0.25, -5, 1, 0)
    triggerTab.Position = UDim2.new(0.25, 5, 0, 0)
    triggerTab.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    triggerTab.TextColor3 = Color3.fromRGB(200, 200, 200)
    triggerTab.TextScaled = true
    triggerTab.Text = "Triggerbot"
    triggerTab.BorderSizePixel = 0
    triggerTab.Parent = tabBar
    Instance.new("UICorner", triggerTab).CornerRadius = UDim.new(0, 6)
    UIElements.TriggerTab = triggerTab
    
    -- ESP Tab
    local espTab = Instance.new("TextButton")
    espTab.Size = UDim2.new(0.25, -5, 1, 0)
    espTab.Position = UDim2.new(0.5, 10, 0, 0)
    espTab.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    espTab.TextColor3 = Color3.fromRGB(200, 200, 200)
    espTab.TextScaled = true
    espTab.Text = "ESP"
    espTab.BorderSizePixel = 0
    espTab.Parent = tabBar
    Instance.new("UICorner", espTab).CornerRadius = UDim.new(0, 6)
    UIElements.ESPTab = espTab
    
    -- Debug Tab
    local debugTab = Instance.new("TextButton")
    debugTab.Size = UDim2.new(0.25, -5, 1, 0)
    debugTab.Position = UDim2.new(0.75, 15, 0, 0)
    debugTab.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    debugTab.TextColor3 = Color3.fromRGB(200, 200, 200)
    debugTab.TextScaled = true
    debugTab.Text = "Debug"
    debugTab.BorderSizePixel = 0
    debugTab.Parent = tabBar
    Instance.new("UICorner", debugTab).CornerRadius = UDim.new(0, 6)
    UIElements.DebugTab = debugTab
    
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
    
    -- Triggerbot Content
    local triggerContent = Instance.new("Frame")
    triggerContent.Size = UDim2.new(1, -10, 1, -90)
    triggerContent.Position = UDim2.new(0, 5, 0, 60)
    triggerContent.BackgroundTransparency = 1
    triggerContent.Name = "TriggerContent"
    triggerContent.Visible = false
    triggerContent.Parent = mainFrame
    UIElements.TriggerContent = triggerContent
    
    -- Triggerbot Enabled Toggle
    local triggerEnabledBtn = Instance.new("TextButton")
    triggerEnabledBtn.Size = UDim2.new(0, 260, 0, 36)
    triggerEnabledBtn.Position = UDim2.new(0, 20, 0, 5)
    triggerEnabledBtn.BackgroundColor3 = Config.Triggerbot.Enabled and Color3.fromRGB(50, 120, 50) or Color3.fromRGB(50, 50, 50)
    triggerEnabledBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    triggerEnabledBtn.TextScaled = true
    triggerEnabledBtn.BorderSizePixel = 0
    triggerEnabledBtn.Text = Config.Triggerbot.Enabled and "Triggerbot: ON" or "Triggerbot: OFF"
    triggerEnabledBtn.Parent = triggerContent
    Instance.new("UICorner", triggerEnabledBtn).CornerRadius = UDim.new(0, 6)
    UIElements.TriggerEnabledBtn = triggerEnabledBtn
    
    -- Sample Count Label
    local sampleLabel = Instance.new("TextLabel")
    sampleLabel.Size = UDim2.new(1, -10, 0, 24)
    sampleLabel.Position = UDim2.new(0, 5, 0, 45)
    sampleLabel.BackgroundTransparency = 1
    sampleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    sampleLabel.TextScaled = true
    sampleLabel.Text = "Sample Count: " .. Config.Triggerbot.SampleCount
    sampleLabel.Parent = triggerContent
    UIElements.SampleLabel = sampleLabel
    
    -- Sample Count Slider
    local sampleSlider = Instance.new("Frame")
    sampleSlider.Size = UDim2.new(0, 260, 0, 20)
    sampleSlider.Position = UDim2.new(0, 20, 0, 70)
    sampleSlider.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    sampleSlider.BorderSizePixel = 0
    sampleSlider.Parent = triggerContent
    Instance.new("UICorner", sampleSlider).CornerRadius = UDim.new(0, 4)
    
    local sampleSliderFill = Instance.new("Frame")
    sampleSliderFill.Size = UDim2.new((Config.Triggerbot.SampleCount - 1) / 12, 0, 1, 0)
    sampleSliderFill.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    sampleSliderFill.BorderSizePixel = 0
    sampleSliderFill.Parent = sampleSlider
    Instance.new("UICorner", sampleSliderFill).CornerRadius = UDim.new(0, 4)
    UIElements.SampleSliderFill = sampleSliderFill
    
    -- Max Distance Label
    local distLabel = Instance.new("TextLabel")
    distLabel.Size = UDim2.new(1, -10, 0, 24)
    distLabel.Position = UDim2.new(0, 5, 0, 95)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    distLabel.TextScaled = true
    distLabel.Text = "Max Distance: " .. Config.Triggerbot.MaxDistance .. " studs"
    distLabel.Parent = triggerContent
    UIElements.DistLabel = distLabel
    
    -- Max Distance Slider
    local distSlider = Instance.new("Frame")
    distSlider.Size = UDim2.new(0, 260, 0, 20)
    distSlider.Position = UDim2.new(0, 20, 0, 120)
    distSlider.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    distSlider.BorderSizePixel = 0
    distSlider.Parent = triggerContent
    Instance.new("UICorner", distSlider).CornerRadius = UDim.new(0, 4)
    
    local distSliderFill = Instance.new("Frame")
    distSliderFill.Size = UDim2.new(Config.Triggerbot.MaxDistance / 2000, 0, 1, 0)
    distSliderFill.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    distSliderFill.BorderSizePixel = 0
    distSliderFill.Parent = distSlider
    Instance.new("UICorner", distSliderFill).CornerRadius = UDim.new(0, 4)
    UIElements.DistSliderFill = distSliderFill
    
    -- Debounce Label
    local debounceLabel = Instance.new("TextLabel")
    debounceLabel.Size = UDim2.new(1, -10, 0, 24)
    debounceLabel.Position = UDim2.new(0, 5, 0, 145)
    debounceLabel.BackgroundTransparency = 1
    debounceLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    debounceLabel.TextScaled = true
    debounceLabel.Text = "Debounce: " .. math.floor(Config.Triggerbot.DebounceTime * 1000) .. " ms"
    debounceLabel.Parent = triggerContent
    UIElements.DebounceLabel = debounceLabel
    
    -- Debounce Slider
    local debounceSlider = Instance.new("Frame")
    debounceSlider.Size = UDim2.new(0, 260, 0, 20)
    debounceSlider.Position = UDim2.new(0, 20, 0, 170)
    debounceSlider.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    debounceSlider.BorderSizePixel = 0
    debounceSlider.Parent = triggerContent
    Instance.new("UICorner", debounceSlider).CornerRadius = UDim.new(0, 4)
    
    local debounceSliderFill = Instance.new("Frame")
    debounceSliderFill.Size = UDim2.new(Config.Triggerbot.DebounceTime / 0.5, 0, 1, 0)
    debounceSliderFill.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    debounceSliderFill.BorderSizePixel = 0
    debounceSliderFill.Parent = debounceSlider
    Instance.new("UICorner", debounceSliderFill).CornerRadius = UDim.new(0, 4)
    UIElements.DebounceSliderFill = debounceSliderFill
    
    -- ESP Content
    local espContent = Instance.new("Frame")
    espContent.Size = UDim2.new(1, -10, 1, -90)
    espContent.Position = UDim2.new(0, 5, 0, 60)
    espContent.BackgroundTransparency = 1
    espContent.Name = "ESPContent"
    espContent.Visible = false
    espContent.Parent = mainFrame
    UIElements.ESPContent = espContent
    
    -- ESP Armed Toggle
    local espArmedBtn = Instance.new("TextButton")
    espArmedBtn.Size = UDim2.new(0, 260, 0, 36)
    espArmedBtn.Position = UDim2.new(0, 20, 0, 5)
    espArmedBtn.BackgroundColor3 = State.ESP.Armed and Color3.fromRGB(50, 120, 50) or Color3.fromRGB(50, 50, 50)
    espArmedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    espArmedBtn.TextScaled = true
    espArmedBtn.BorderSizePixel = 0
    espArmedBtn.Text = State.ESP.Armed and "ESP Armed: ON" or "ESP Armed: OFF"
    espArmedBtn.Parent = espContent
    Instance.new("UICorner", espArmedBtn).CornerRadius = UDim.new(0, 6)
    UIElements.ESPArmedBtn = espArmedBtn
    
    -- Color Picker Frame
    local pickerFrame = Instance.new("Frame")
    pickerFrame.Size = UDim2.new(0, 210, 0, 160)
    pickerFrame.Position = UDim2.new(0, 10, 0, 50)
    pickerFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    pickerFrame.BorderSizePixel = 0
    pickerFrame.Parent = espContent
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
    applyFill.Position = UDim2.new(0, 230, 0, 60)
    applyFill.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
    applyFill.TextColor3 = Color3.fromRGB(255, 255, 255)
    applyFill.TextScaled = true
    applyFill.Text = "Apply to Fill"
    applyFill.BorderSizePixel = 0
    applyFill.Parent = espContent
    Instance.new("UICorner", applyFill).CornerRadius = UDim.new(0, 4)
    UIElements.ApplyFill = applyFill
    
    local applyOutline = applyFill:Clone()
    applyOutline.Text = "Apply to Outline"
    applyOutline.Position = UDim2.new(0, 230, 0, 90)
    applyOutline.Parent = espContent
    Instance.new("UICorner", applyOutline).CornerRadius = UDim.new(0, 4)
    UIElements.ApplyOutline = applyOutline
    
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
    
    -- Config Info
    local configInfo = Instance.new("TextLabel")
    configInfo.Size = UDim2.new(1, -10, 0, 80)
    configInfo.Position = UDim2.new(0, 5, 0, 115)
    configInfo.BackgroundTransparency = 1
    configInfo.TextColor3 = Color3.fromRGB(200, 200, 200)
    configInfo.TextScaled = true
    configInfo.TextWrapped = true
    configInfo.Text = 
        "Current Config:\n" ..
        "Sample Count: " .. Config.Triggerbot.SampleCount .. "\n" ..
        "Max Distance: " .. Config.Triggerbot.MaxDistance .. " studs\n" ..
        "Debounce: " .. math.floor(Config.Triggerbot.DebounceTime * 1000) .. " ms"
    configInfo.Parent = debugContent
    UIElements.ConfigInfo = configInfo
    
    -- Tab switching function
    local function setTab(which)
        mainContent.Visible = (which == "main")
        triggerContent.Visible = (which == "trigger")
        espContent.Visible = (which == "esp")
        debugContent.Visible = (which == "debug")
        
        mainTab.BackgroundColor3 = (which == "main") and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)
        mainTab.TextColor3 = (which == "main") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
        
        triggerTab.BackgroundColor3 = (which == "trigger") and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)
        triggerTab.TextColor3 = (which == "trigger") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
        
        espTab.BackgroundColor3 = (which == "esp") and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)
        espTab.TextColor3 = (which == "esp") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
        
        debugTab.BackgroundColor3 = (which == "debug") and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)
        debugTab.TextColor3 = (which == "debug") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
    end
    
    -- Tab click handlers
    mainTab.MouseButton1Click:Connect(function() setTab("main") end)
    triggerTab.MouseButton1Click:Connect(function() setTab("trigger") end)
    espTab.MouseButton1Click:Connect(function() setTab("esp") end)
    debugTab.MouseButton1Click:Connect(function() setTab("debug") end)
    
    -- ESP Toggle handler
    espToggle.MouseButton1Click:Connect(function()
        State.ESP.Enabled = not State.ESP.Enabled
        espToggle.Text = State.ESP.Enabled and "ESP: ON" or "ESP: OFF"
        
        if not State.ESP.Enabled then
            ESPSystem:ClearAll()
        end
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
    
    -- Triggerbot enabled toggle
    triggerEnabledBtn.MouseButton1Click:Connect(function()
        Config.Triggerbot.Enabled = not Config.Triggerbot.Enabled
        triggerEnabledBtn.Text = Config.Triggerbot.Enabled and "Triggerbot: ON" or "Triggerbot: OFF"
        triggerEnabledBtn.BackgroundColor3 = Config.Triggerbot.Enabled and Color3.fromRGB(50, 120, 50) or Color3.fromRGB(50, 50, 50)
    end)
    
    -- ESP Armed toggle
    espArmedBtn.MouseButton1Click:Connect(function()
        State.ESP.Armed = not State.ESP.Armed
        espArmedBtn.Text = State.ESP.Armed and "ESP Armed: ON" or "ESP Armed: OFF"
        espArmedBtn.BackgroundColor3 = State.ESP.Armed and Color3.fromRGB(50, 120, 50) or Color3.fromRGB(50, 50, 50)
    end)
    
    -- Apply button handlers
    applyFill.MouseButton1Click:Connect(function()
        Config.ESP.FillColor = preview.BackgroundColor3
        
        for _, highlight in pairs(State.ESP.Highlights) do
            highlight.FillColor = Config.ESP.FillColor
        end
    end)
    
    applyOutline.MouseButton1Click:Connect(function()
        Config.ESP.OutlineColor = preview.BackgroundColor3
        
        for _, highlight in pairs(State.ESP.Highlights) do
            highlight.OutlineColor = Config.ESP.OutlineColor
        end
    end)
    
    -- Slider interactions
    local function setupSlider(sliderFrame, fill, min, max, callback)
        local dragging = false
        
        sliderFrame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                SetUIDragging(false)
                
                local mouse = UserInputService:GetMouseLocation()
                local relX = mouse.X - sliderFrame.AbsolutePosition.X
                local t = math.clamp(relX / sliderFrame.AbsoluteSize.X, 0, 1)
                local val = min + t * (max - min)
                callback(val, t)
            end
        end)
        
        UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                local mouse = UserInputService:GetMouseLocation()
                local relX = mouse.X - sliderFrame.AbsolutePosition.X
                local t = math.clamp(relX / sliderFrame.AbsoluteSize.X, 0, 1)
                local val = min + t * (max - min)
                callback(val, t)
            end
        end)
        
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                if dragging then
                    dragging = false
                    SetUIDragging(true)
                end
            end
        end)
    end
    
    -- Sample count slider
    setupSlider(sampleSlider, sampleSliderFill, 1, 13, function(val, t)
        Config.Triggerbot.SampleCount = math.floor(val)
        sampleLabel.Text = "Sample Count: " .. Config.Triggerbot.SampleCount
        sampleSliderFill.Size = UDim2.new(t, 0, 1, 0)
    end)
    
    -- Max distance slider
    setupSlider(distSlider, distSliderFill, 100, 2000, function(val, t)
        Config.Triggerbot.MaxDistance = math.floor(val)
        distLabel.Text = "Max Distance: " .. Config.Triggerbot.MaxDistance .. " studs"
        distSliderFill.Size = UDim2.new(t, 0, 1, 0)
    end)
    
    -- Debounce slider
    setupSlider(debounceSlider, debounceSliderFill, 10, 500, function(val, t)
        Config.Triggerbot.DebounceTime = val / 1000
        debounceLabel.Text = "Debounce: " .. math.floor(val) .. " ms"
        debounceSliderFill.Size = UDim2.new(t, 0, 1, 0)
    end)
    
    -- Color Picker Input Handling (INSIDE CreateUI where elements exist)
    svSquare.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            SetUIDragging(false)
            
            local moveConn, endConn
            
            moveConn = UserInputService.InputChanged:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseMovement then
                    local mouse = UserInputService:GetMouseLocation()
                    local relX = mouse.X - svSquare.AbsolutePosition.X
                    local relY = mouse.Y - svSquare.AbsolutePosition.Y
                    
                    local sx = math.clamp(relX / svSquare.AbsoluteSize.X, 0, 1)
                    local sy = math.clamp(relY / svSquare.AbsoluteSize.Y, 0, 1)
                    
                    currentS = sx
                    currentV = 1 - sy
                    
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
    
    hueBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            SetUIDragging(false)
            
            local moveConn, endConn
            
            moveConn = UserInputService.InputChanged:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseMovement then
                    local mouse = UserInputService:GetMouseLocation()
                    local relY = mouse.Y - hueBar.AbsolutePosition.Y
                    
                    local t = math.clamp(relY / hueBar.AbsoluteSize.Y, 0, 1)
                    
                    currentHue = (1 - t) * 360
                    
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
    
    -- UI Resizing
    do
        local resizing = false
        local startMousePos
        local startSize
        local oldDraggable
        
        resizeHandle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                resizing = true
                startMousePos = UserInputService:GetMouseLocation()
                startSize = mainFrame.Size
                
                oldDraggable = mainFrame.Draggable
                mainFrame.Draggable = false
            end
        end)
        
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                if resizing then
                    resizing = false
                    mainFrame.Draggable = oldDraggable ~= nil and oldDraggable or true
                end
            end
        end)
        
        UserInputService.InputChanged:Connect(function(input)
            if not resizing then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            
            local currentPos = UserInputService:GetMouseLocation()
            local dx = currentPos.X - startMousePos.X
            local dy = currentPos.Y - startMousePos.Y
            
            local newW = math.max(350, startSize.X.Offset + dx)
            local newH = math.max(280, startSize.Y.Offset + dy)
            
            mainFrame.Size = UDim2.new(0, newW, 0, newH)
        end)
    end
    
    -- Input Handling
    table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        
        if input.KeyCode == Enum.KeyCode.RightShift then
            mainFrame.Visible = not mainFrame.Visible
        end
        
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
    
    -- Main Game Loop
    table.insert(State.Connections, RunService.RenderStepped:Connect(function()
        if not State.Running then return end
        
        ESPSystem:Update()
        ProcessTriggerbot()
        
        if stateLabel then
            stateLabel.Text = "Trigger state: " .. State.Triggerbot.State
        end
        
        if configInfo then
            configInfo.Text = 
                "Current Config:\n" ..
                "Sample Count: " .. Config.Triggerbot.SampleCount .. "\n" ..
                "Max Distance: " .. Config.Triggerbot.MaxDistance .. " studs\n" ..
                "Debounce: " .. math.floor(Config.Triggerbot.DebounceTime * 1000) .. " ms"
        end
    end))
    
    print("[ESP+Triggerbot] UI created successfully")
    print("[ESP+Triggerbot] Main loop connected")
    print("[ESP+Triggerbot] System ready!")
    
    return mainFrame
end

------------------------------------------------------------------
-- INITIALIZATION
------------------------------------------------------------------

print("[ESP+Triggerbot] Starting UI creation...")
CreateUI()
print("[ESP+Triggerbot] Initialization complete!")
