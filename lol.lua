--[[
    ESP + Triggerbot System (Production Quality v2)
    ================================================
    
    Controls:
    - L: Arm/Disarm ESP system
    - Hold V: Triggerbot (independent of ESP arm state)
    - RightShift: Toggle UI visibility
    
    Features:
    - Mouse cursor-based raycasting (pixel-accurate)
    - Multi-sample raycasting for improved reliability
    - Character part prioritization and filtering
    - Live UI configuration (no restart needed)
    - Enhanced modern UI with sliders and toggles
    - Proper debounce logic to prevent rapid triggering
    - Performance optimized with cached references
]]

------------------------------------------------------------------
-- SERVICES & CACHED REFERENCES
------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TweenInfo = TweenInfo.new

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Cache frequently used references
local Workspace = workspace
local GetPlayers = Players.GetPlayers
local GetMouseLocation = UserInputService.GetMouseLocation

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
    UI = {
        Theme = "Dark",
        AccentColor = Color3.fromRGB(0, 120, 215),
    }
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
RaycastParamsObj.FilterDescendantsInstances = {LocalPlayer.Character}

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
    if not Camera then
        Camera = Workspace.CurrentCamera
        if not Camera then return nil end
    end
    
    local mousePos = GetMouseLocation(UserInputService)
    RaycastParamsObj.FilterDescendantsInstances = {LocalPlayer.Character}
    
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
-- ENHANCED UI SYSTEM
------------------------------------------------------------------

local UI = {}

-- Modern color scheme
local Colors = {
    Background = Color3.fromRGB(20, 20, 25),
    Surface = Color3.fromRGB(30, 30, 38),
    SurfaceHover = Color3.fromRGB(40, 40, 50),
    Primary = Config.UI.AccentColor,
    Text = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(180, 180, 190),
    Success = Color3.fromRGB(72, 199, 142),
    Danger = Color3.fromRGB(245, 70, 70),
    Warning = Color3.fromRGB(255, 180, 0),
}

local function CreateRoundCorner(radius)
    radius = radius or 4
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    return corner
end

local function CreateLabel(text, parent, size, position, textColor, textSize)
    local label = Instance.new("TextLabel")
    label.Size = size or UDim2.new(1, 0, 0, 20)
    label.Position = position or UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text or ""
    label.TextColor3 = textColor or Colors.Text
    label.TextScaled = textSize == nil and true or textSize
    label.Font = Enum.Font.Gotham
    label.Parent = parent
    return label
end

local function CreateButton(text, parent, size, position, backgroundColor, textColor)
    local button = Instance.new("TextButton")
    button.Size = size or UDim2.new(1, 0, 0, 30)
    button.Position = position or UDim2.new(0, 0, 0, 0)
    button.BackgroundColor3 = backgroundColor or Colors.Surface
    button.Text = text or ""
    button.TextColor3 = textColor or Colors.Text
    button.TextScaled = true
    button.Font = Enum.Font.GothamMedium
    button.BorderSizePixel = 0
    button.Parent = parent
    CreateRoundCorner(6, button)
    
    -- Hover effect
    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = Colors.SurfaceHover
    end)
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = Colors.Surface
    end)
    
    return button
end

local function CreateToggle(parent, text, default, callback)
    local toggleFrame = Instance.new("Frame")
    toggleFrame.Size = UDim2.new(1, -10, 0, 36)
    toggleFrame.BackgroundTransparency = 1
    toggleFrame.Parent = parent
    
    local label = CreateLabel(text, toggleFrame, UDim2.new(1, -50, 1, 0), UDim2.new(0, 0, 0, 0), Colors.Text, true)
    
    local toggleBg = Instance.new("Frame")
    toggleBg.Size = UDim2.new(0, 44, 0, 24)
    toggleBg.Position = UDim2.new(1, -44, 0.5, -12)
    toggleBg.BackgroundColor3 = Colors.Surface
    toggleBg.Parent = toggleFrame
    CreateRoundCorner(12, toggleBg)
    
    local toggleCircle = Instance.new("Frame")
    toggleCircle.Size = UDim2.new(0, 18, 0, 18)
    toggleCircle.Position = default and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    toggleCircle.BackgroundColor3 = default and Colors.Success or Colors.TextSecondary
    toggleCircle.Parent = toggleBg
    CreateRoundCorner(9, toggleCircle)
    
    local isOn = default
    local function updateToggle()
        toggleCircle.Position = isOn and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        toggleCircle.BackgroundColor3 = isOn and Colors.Success or Colors.TextSecondary
        toggleBg.BackgroundColor3 = isOn and Color3.fromRGB(30, 60, 45) or Colors.Surface
    end
    
    toggleBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            isOn = not isOn
            updateToggle()
            if callback then callback(isOn) end
        end
    end)
    
    return {
        Frame = toggleFrame,
        GetValue = function() return isOn end,
        SetValue = function(val) isOn = val; updateToggle() end,
    }
end

local function CreateSlider(parent, text, min, max, default, callback, suffix)
    suffix = suffix or ""
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(1, -10, 0, 50)
    sliderFrame.BackgroundTransparency = 1
    sliderFrame.Parent = parent
    
    local labelRow = Instance.new("Frame")
    labelRow.Size = UDim2.new(1, 0, 0, 20)
    labelRow.BackgroundTransparency = 1
    labelRow.Parent = sliderFrame
    
    CreateLabel(text, labelRow, UDim2.new(0.5, 0, 1, 0), UDim2.new(0, 0, 0, 0), Colors.Text, true)
    
    local valueLabel = CreateLabel(tostring(math.floor(default)) .. suffix, labelRow, 
        UDim2.new(0.5, 0, 1, 0), UDim2.new(0.5, 0, 0, 0), Colors.TextSecondary, true)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    
    -- Slider track
    local trackBg = Instance.new("Frame")
    trackBg.Size = UDim2.new(1, -20, 0, 6)
    trackBg.Position = UDim2.new(0, 10, 0, 28)
    trackBg.BackgroundColor3 = Colors.Surface
    trackBg.Parent = sliderFrame
    CreateRoundCorner(3, trackBg)
    
    local trackFill = Instance.new("Frame")
    trackFill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    trackFill.BackgroundColor3 = Colors.Primary
    trackFill.Parent = trackBg
    CreateRoundCorner(3, trackFill)
    
    local thumb = Instance.new("Frame")
    thumb.Size = UDim2.new(0, 16, 0, 16)
    thumb.Position = UDim2.new((default - min) / (max - min), -8, 0.5, -8)
    thumb.BackgroundColor3 = Colors.Text
    thumb.Parent = trackBg
    CreateRoundCorner(8, thumb)
    
    local currentValue = default
    local dragging = false
    
    local function updateSlider(newValue)
        currentValue = math.clamp(newValue, min, max)
        local t = (currentValue - min) / (max - min)
        trackFill.Size = UDim2.new(t, 0, 1, 0)
        thumb.Position = UDim2.new(t, -8, 0.5, -8)
        valueLabel.Text = tostring(math.floor(currentValue)) .. suffix
        if callback then callback(currentValue) end
    end
    
    local function onInput(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or 
           input.UserInputType == Enum.UserInputType.MouseButton1 then
            if dragging then
                local mouse = UserInputService:GetMouseLocation()
                local relX = mouse.X - trackBg.AbsolutePosition.X
                local t = math.clamp(relX / trackBg.AbsoluteSize.X, 0, 1)
                updateSlider(min + t * (max - min))
            end
        end
    end
    
    trackBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            onInput(input)
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(onInput)
    
    return {
        Frame = sliderFrame,
        GetValue = function() return currentValue end,
        SetValue = function(val) updateSlider(val) end,
    }
end

local function CreateColorPicker(parent, text, defaultColor, callback)
    local pickerFrame = Instance.new("Frame")
    pickerFrame.Size = UDim2.new(1, -10, 0, 70)
    pickerFrame.BackgroundTransparency = 1
    pickerFrame.Parent = parent
    
    CreateLabel(text, pickerFrame, UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 0), Colors.Text, true)
    
    local preview = Instance.new("Frame")
    preview.Size = UDim2.new(0, 40, 0, 30)
    preview.Position = UDim2.new(0, 0, 0, 28)
    preview.BackgroundColor3 = defaultColor
    preview.Parent = pickerFrame
    CreateRoundCorner(6, preview)
    
    -- Simple HSV picker
    local svSquare = Instance.new("Frame")
    svSquare.Size = UDim2.new(0, 100, 0, 60)
    svSquare.Position = UDim2.new(0, 50, 0, 28)
    svSquare.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    svSquare.Parent = pickerFrame
    CreateRoundCorner(4, svSquare)
    
    local whiteGrad = Instance.new("UIGradient")
    whiteGrad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255,255,255))
    }
    whiteGrad.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1)
    }
    whiteGrad.Rotation = 90
    whiteGrad.Parent = svSquare
    
    local blackGrad = Instance.new("UIGradient")
    blackGrad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0,0,0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(0,0,0))
    }
    blackGrad.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0)
    }
    blackGrad.Parent = svSquare
    
    local hueBar = Instance.new("Frame")
    hueBar.Size = UDim2.new(0, 15, 0, 60)
    hueBar.Position = UDim2.new(0, 155, 0, 28)
    hueBar.BackgroundColor3 = Color3.fromRGB(255,255,255)
    hueBar.Parent = pickerFrame
    CreateRoundCorner(4, hueBar)
    
    local hueGrad = Instance.new("UIGradient")
    hueGrad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255,0,0)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255,0,255)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0,0,255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0,255,255)),
        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0,255,0)),
        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255,255,0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255,0,0)),
    }
    hueGrad.Rotation = 90
    hueGrad.Parent = hueBar
    
    local currentHue, currentS, currentV = 0, 1, 1
    
    local function updatePicker()
        local color = Color3.fromHSV(currentHue / 360, currentS, currentV)
        preview.BackgroundColor3 = color
        svSquare.BackgroundColor3 = Color3.fromHSV(currentHue / 360, 1, 1)
        if callback then callback(color) end
    end
    
    -- SV Square interaction
    svSquare.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local moveConn, endConn
            moveConn = UserInputService.InputChanged:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseMovement then
                    local mouse = UserInputService:GetMouseLocation()
                    local relX = mouse.X - svSquare.AbsolutePosition.X
                    local relY = mouse.Y - svSquare.AbsolutePosition.Y
                    currentS = math.clamp(relX / svSquare.AbsoluteSize.X, 0, 1)
                    currentV = 1 - math.clamp(relY / svSquare.AbsoluteSize.Y, 0, 1)
                    updatePicker()
                end
            end)
            endConn = UserInputService.InputEnded:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 then
                    moveConn:Disconnect()
                    endConn:Disconnect()
                end
            end)
        end
    end)
    
    -- Hue bar interaction
    hueBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local moveConn, endConn
            moveConn = UserInputService.InputChanged:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseMovement then
                    local mouse = UserInputService:GetMouseLocation()
                    local relY = mouse.Y - hueBar.AbsolutePosition.Y
                    currentHue = (1 - math.clamp(relY / hueBar.AbsoluteSize.Y, 0, 1)) * 360
                    updatePicker()
                end
            end)
            endConn = UserInputService.InputEnded:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 then
                    moveConn:Disconnect()
                    endConn:Disconnect()
                end
            end)
        end
    end)
    
    updatePicker()
    
    return pickerFrame
end

-- Status indicator
local function CreateStatusIndicator(parent)
    local statusFrame = Instance.new("Frame")
    statusFrame.Size = UDim2.new(1, -10, 0, 24)
    statusFrame.Position = UDim2.new(0, 5, 1, -30)
    statusFrame.BackgroundTransparency = 1
    statusFrame.Parent = parent
    
    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 8, 0, 8)
    dot.Position = UDim2.new(0, 0, 0.5, -4)
    dot.BackgroundColor3 = Colors.TextSecondary
    dot.Parent = statusFrame
    CreateRoundCorner(4, dot)
    
    local statusText = CreateLabel("DISARMED", statusFrame, UDim2.new(1, -12, 1, 0), UDim2.new(0, 12, 0, 0), Colors.TextSecondary, true)
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    
    local function updateStatus(state)
        statusText.Text = state
        if state == "TARGET" then
            dot.BackgroundColor3 = Colors.Danger
            statusText.TextColor3 = Colors.Danger
        elseif state == "HOLDING" then
            dot.BackgroundColor3 = Colors.Warning
            statusText.TextColor3 = Colors.Warning
        elseif state == "ARMED" then
            dot.BackgroundColor3 = Colors.Success
            statusText.TextColor3 = Colors.Success
        else
            dot.BackgroundColor3 = Colors.TextSecondary
            statusText.TextColor3 = Colors.TextSecondary
        end
    end
    
    return {
        Frame = statusFrame,
        Update = updateStatus,
    }
end

------------------------------------------------------------------
-- MAIN UI CREATION
------------------------------------------------------------------

local function CreateMainWindow()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("ESP_UI_v2")
    if existing then existing:Destroy() end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ESP_UI_v2"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui
    State.UIElements.ScreenGui = screenGui
    
    -- Main window
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 320, 0, 480)
    mainFrame.Position = UDim2.new(0, 100, 0, 100)
    mainFrame.BackgroundColor3 = Colors.Background
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = screenGui
    CreateRoundCorner(12, mainFrame)
    State.UIElements.MainFrame = mainFrame
    
    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundColor3 = Colors.Surface
    titleBar.Parent = mainFrame
    CreateRoundCorner(12, titleBar)
    
    -- Remove bottom corners from title bar
    local titleCorner = titleBar:FindFirstChild("UICorner")
    if titleCorner then
        titleCorner.CornerRadius = UDim.new(0, 12)
    end
    
    local title = CreateLabel("⚡ ESP + Triggerbot", titleBar, UDim2.new(1, -40, 1, 0), UDim2.new(0, 12, 0, 0), Colors.Text, false)
    title.TextSize = 16
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    
    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0.5, -15)
    closeBtn.BackgroundColor3 = Colors.Danger
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Colors.Text
    closeBtn.TextScaled = true
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = titleBar
    CreateRoundCorner(15, closeBtn)
    
    closeBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
    end)
    
    -- Scroll frame for content
    local scrollFrame = Instance.new("Frame")
    scrollFrame.Size = UDim2.new(1, -10, 1, -50)
    scrollFrame.Position = UDim2.new(0, 5, 0, 45)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.Parent = mainFrame
    
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.Parent = scrollFrame
    
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 5)
    padding.PaddingRight = UDim.new(0, 5)
    padding.Parent = scrollFrame
    
    -- Section: Triggerbot Settings
    local function createSection(title, parent)
        local section = Instance.new("Frame")
        section.Size = UDim2.new(1, 0, 0, 200)
        section.BackgroundColor3 = Colors.Surface
        section.Parent = parent
        CreateRoundCorner(8, section)
        
        local sectionTitle = CreateLabel(title, section, UDim2.new(1, -10, 0, 30), UDim2.new(0, 5, 0, 0), Colors.Primary, false)
        sectionTitle.TextSize = 14
        sectionTitle.Font = Enum.Font.GothamBold
        sectionTitle.TextXAlignment = Enum.TextXAlignment.Left
        
        local content = Instance.new("Frame")
        content.Size = UDim2.new(1, -10, 1, -35)
        content.Position = UDim2.new(0, 5, 0, 35)
        content.BackgroundTransparency = 1
        content.Parent = section
        
        local contentLayout = Instance.new("UIListLayout")
        contentLayout.Padding = UDim.new(0, 6)
        contentLayout.Parent = content
        
        return content
    end
    
    -- Triggerbot Section
    local triggerSection = createSection("🎯 Triggerbot", scrollFrame)
    
    local triggerEnabled = CreateToggle(triggerSection, "Enabled", Config.Triggerbot.Enabled, function(val)
        Config.Triggerbot.Enabled = val
    end)
    
    local sampleCount = CreateSlider(triggerSection, "Sample Count", 1, 13, Config.Triggerbot.SampleCount, function(val)
        Config.Triggerbot.SampleCount = math.floor(val)
    end)
    
    local maxDist = CreateSlider(triggerSection, "Max Distance", 100, 2000, Config.Triggerbot.MaxDistance, function(val)
        Config.Triggerbot.MaxDistance = math.floor(val)
    end, " studs")
    
    local debounce = CreateSlider(triggerSection, "Debounce", 10, 500, Config.Triggerbot.DebounceTime * 1000, function(val)
        Config.Triggerbot.DebounceTime = val / 1000
    end, " ms")
    
    -- ESP Section
    local espSection = createSection("👁 ESP", scrollFrame)
    
    local espEnabled = CreateToggle(espSection, "ESP Enabled", State.ESP.Enabled, function(val)
        State.ESP.Enabled = val
        if not val then ESPSystem:ClearAll() end
    end)
    
    local espArmed = CreateToggle(espSection, "ESP Armed", State.ESP.Armed, function(val)
        State.ESP.Armed = val
    end)
    
    CreateColorPicker(espSection, "Fill Color", Config.ESP.FillColor, function(color)
        Config.ESP.FillColor = color
        for _, highlight in pairs(State.ESP.Highlights) do
            highlight.FillColor = color
        end
    end)
    
    CreateColorPicker(espSection, "Outline Color", Config.ESP.OutlineColor, function(color)
        Config.ESP.OutlineColor = color
        for _, highlight in pairs(State.ESP.Highlights) do
            highlight.OutlineColor = color
        end
    end)
    
    -- Status indicator
    local statusIndicator = CreateStatusIndicator(scrollFrame)
    State.UIElements.StatusIndicator = statusIndicator
    
    -- Footer with controls info
    local footer = Instance.new("Frame")
    footer.Size = UDim2.new(1, -10, 0, 50)
    footer.BackgroundColor3 = Colors.Surface
    footer.Parent = scrollFrame
    CreateRoundCorner(8, footer)
    
    local controlsLabel = CreateLabel("Controls:", footer, UDim2.new(1, -10, 0, 18), UDim2.new(0, 5, 0, 0), Colors.Primary, false)
    controlsLabel.TextSize = 12
    controlsLabel.Font = Enum.Font.GothamBold
    
    local controlsInfo = CreateLabel("L = Arm/Disarm ESP\nHold V = Triggerbot\nRightShift = Toggle UI", 
        footer, UDim2.new(1, -10, 1, -22), UDim2.new(0, 5, 0, 20), Colors.TextSecondary, true)
    controlsInfo.TextYAlignment = Enum.TextYAlignment.Top
    controlsInfo.TextXAlignment = Enum.TextXAlignment.Left
    controlsInfo.TextWrapped = true
    
    -- Resize handle
    local resizeHandle = Instance.new("Frame")
    resizeHandle.Size = UDim2.new(0, 16, 0, 16)
    resizeHandle.AnchorPoint = Vector2.new(1, 1)
    resizeHandle.Position = UDim2.new(1, -2, 1, -2)
    resizeHandle.BackgroundColor3 = Colors.Primary
    resizeHandle.BackgroundTransparency = 0.5
    resizeHandle.Parent = mainFrame
    CreateRoundCorner(4, resizeHandle)
    
    -- Resize logic
    local resizing = false
    local startMouse, startSize
    
    resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = true
            startMouse = UserInputService:GetMouseLocation()
            startSize = mainFrame.Size
            mainFrame.Draggable = false
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and resizing then
            resizing = false
            mainFrame.Draggable = true
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if not resizing then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        
        local current = UserInputService:GetMouseLocation()
        local dx = current.X - startMouse.X
        local dy = current.Y - startMouse.Y
        
        mainFrame.Size = UDim2.new(0, math.max(280, startSize.X.Offset + dx), 0, math.max(400, startSize.Y.Offset + dy))
    end)
    
    -- Update status periodically
    State.UIElements.UpdateStatus = function()
        statusIndicator.Update(State.Triggerbot.State)
    end
    
    return mainFrame
end

------------------------------------------------------------------
-- INPUT HANDLING
------------------------------------------------------------------

table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    
    if input.KeyCode == Enum.KeyCode.RightShift then
        if State.UIElements.MainFrame then
            State.UIElements.MainFrame.Visible = not State.UIElements.MainFrame.Visible
        end
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
        State.Triggerbot.State = State.Triggerbot.State ~= "DISARMED" and "ARMED" or "DISARMED"
        State.Triggerbot.Clicked = false
    end
end))

------------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------------

table.insert(State.Connections, RunService.RenderStepped:Connect(function()
    if not State.Running then return end
    
    ESPSystem:Update()
    ProcessTriggerbot()
    
    if State.UIElements.UpdateStatus then
        State.UIElements.UpdateStatus()
    end
end))

------------------------------------------------------------------
-- INITIALIZATION
------------------------------------------------------------------

CreateMainWindow()
