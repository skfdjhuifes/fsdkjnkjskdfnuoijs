--[[
ESP + Triggerbot (L toggle, V hold) + Kill Button + ESP Settings (HTMLColorCodes-style) + Resizable UI

L = Arm/Disarm ESP system
Hold V = Triggerbot (independent of ESP arm)
RightShift = Toggle UI visibility
]]

------------------------------------------------------------------
-- SERVICES
------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera


------------------------------------------------------------------
-- STATE
------------------------------------------------------------------

local Running = true
local Connections = {}

local ESP = {
    Enabled = false,
    Armed = false,
    Pixels = {},
    FillColor = Color3.fromRGB(255, 0, 0),
    OutlineColor = Color3.fromRGB(255, 255, 255)
}

local AimAssist = {
    Enabled = false,
    Strength = 0.5,
    CurrentTarget = nil
}

local TriggerHeld = false
local TriggerState = "DISARMED"
local clicked = false


------------------------------------------------------------------
-- SETTINGS SYSTEM
------------------------------------------------------------------

local Settings = {
    ESPEnabled = false,
    ESPArmed = false,
    FillColor = Color3.fromRGB(255, 0, 0),
    OutlineColor = Color3.fromRGB(255, 255, 255),
    UISizeX = 360,
    UISizeY = 260,
    AimAssistEnabled = false,
    AimAssistStrength = 0.5,
    WalkSpeed = 16,
    JumpPower = 50
}

local function SaveSettings()

    Settings.ESPEnabled = ESP.Enabled
    Settings.ESPArmed = ESP.Armed
    Settings.FillColor = ESP.FillColor
    Settings.OutlineColor = ESP.OutlineColor
    Settings.AimAssistEnabled = AimAssist.Enabled
    Settings.AimAssistStrength = AimAssist.Strength

    if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        Settings.WalkSpeed = LocalPlayer.Character.Humanoid.WalkSpeed
        Settings.JumpPower = LocalPlayer.Character.Humanoid.JumpPower
    end

    if mainFrame then
        Settings.UISizeX = mainFrame.Size.X.Offset
        Settings.UISizeY = mainFrame.Size.Y.Offset
    end

end


local function LoadSettings()

    ESP.Enabled = Settings.ESPEnabled
    ESP.Armed = Settings.ESPArmed
    ESP.FillColor = Settings.FillColor
    ESP.OutlineColor = Settings.OutlineColor
    AimAssist.Enabled = Settings.AimAssistEnabled
    AimAssist.Strength = Settings.AimAssistStrength

end


------------------------------------------------------------------
-- COLOR HELPERS
------------------------------------------------------------------

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
        r, g, b = c, x, 0
    end

    return Color3.new(r + m, g + m, b + m)

end


local function RGBToHSV(color)

    local r = color.R
    local g = color.G
    local b = color.B

    local max = math.max(r, g, b)
    local min = math.min(r, g, b)

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
-- UI
------------------------------------------------------------------

local screenGui
local mainFrame
local resizeHandle

local mainTab
local debugTab
local settingsTab

local mainContent
local debugContent
local settingsContent

local espToggle
local stateLabel
local killButton

local svSquare
local hueBar
local preview

local applyFill
local applyOutline

local svSelector
local hueSelector


------------------------------------------------------------------
-- UI CREATION
------------------------------------------------------------------

local function createUI()

    LoadSettings()

    local function setDragging(state)
        if mainFrame then
            mainFrame.Draggable = state
        end
    end

    local pg = LocalPlayer:FindFirstChild("PlayerGui")

    if pg then
        local old = pg:FindFirstChild("ESP_UI")

        if old then
            old:Destroy()
        end
    end


    ------------------------------------------------------------------
    -- SCREEN GUI
    ------------------------------------------------------------------

    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ESP_UI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")


    ------------------------------------------------------------------
    -- MAIN FRAME
    ------------------------------------------------------------------

    mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 360, 0, 260)
    mainFrame.Position = UDim2.new(0, 20, 0, 20)
    mainFrame.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = screenGui

    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)


    ------------------------------------------------------------------
    -- RESIZE HANDLE
    ------------------------------------------------------------------

    resizeHandle = Instance.new("Frame")
    resizeHandle.Size = UDim2.new(0, 14, 0, 14)
    resizeHandle.AnchorPoint = Vector2.new(1, 1)
    resizeHandle.Position = UDim2.new(1, 0, 1, 0)
    resizeHandle.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    resizeHandle.BorderSizePixel = 0
    resizeHandle.Parent = mainFrame

    Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 3)


    ------------------------------------------------------------------
    -- TITLE BAR
    ------------------------------------------------------------------

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    title.Text = "ESP + Triggerbot"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.BorderSizePixel = 0
    title.Parent = mainFrame

    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)


    ------------------------------------------------------------------
    -- TAB BAR
    ------------------------------------------------------------------

    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -10, 0, 26)
    tabBar.Position = UDim2.new(0, 5, 0, 32)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = mainFrame


    ------------------------------------------------------------------
    -- MAIN TAB
    ------------------------------------------------------------------

    mainTab = Instance.new("TextButton")
    mainTab.Size = UDim2.new(1/3, -5, 1, 0)
    mainTab.Position = UDim2.new(0, 0, 0, 0)
    mainTab.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    mainTab.TextColor3 = Color3.fromRGB(255, 255, 255)
    mainTab.TextScaled = true
    mainTab.Text = "Main"
    mainTab.BorderSizePixel = 0
    mainTab.Parent = tabBar

    Instance.new("UICorner", mainTab).CornerRadius = UDim.new(0, 6)


    ------------------------------------------------------------------
    -- DEBUG TAB
    ------------------------------------------------------------------

    debugTab = Instance.new("TextButton")
    debugTab.Size = UDim2.new(1/3, -5, 1, 0)
    debugTab.Position = UDim2.new(1/3, 5, 0, 0)
    debugTab.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    debugTab.TextColor3 = Color3.fromRGB(200, 200, 200)
    debugTab.TextScaled = true
    debugTab.Text = "Debug"
    debugTab.BorderSizePixel = 0
    debugTab.Parent = tabBar

    Instance.new("UICorner", debugTab).CornerRadius = UDim.new(0, 6)


    ------------------------------------------------------------------
    -- SETTINGS TAB
    ------------------------------------------------------------------

    settingsTab = Instance.new("TextButton")
    settingsTab.Size = UDim2.new(1/3, -5, 1, 0)
    settingsTab.Position = UDim2.new(2/3, 10, 0, 0)
    settingsTab.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    settingsTab.TextColor3 = Color3.fromRGB(200, 200, 200)
    settingsTab.TextScaled = true
    settingsTab.Text = "ESP Settings"
    settingsTab.BorderSizePixel = 0
    settingsTab.Parent = tabBar

    Instance.new("UICorner", settingsTab).CornerRadius = UDim.new(0, 6)

        ------------------------------------------------------------------
    -- MAIN CONTENT
    ------------------------------------------------------------------

    mainContent = Instance.new("Frame")
    mainContent.Size = UDim2.new(1, -10, 1, -90)
    mainContent.Position = UDim2.new(0, 5, 0, 60)
    mainContent.BackgroundTransparency = 1
    mainContent.Name = "MainContent"
    mainContent.Parent = mainFrame


    espToggle = Instance.new("TextButton")
    espToggle.Size = UDim2.new(0, 260, 0, 36)
    espToggle.Position = UDim2.new(0, 20, 0, 5)
    espToggle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    espToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    espToggle.TextScaled = true
    espToggle.BorderSizePixel = 0
    espToggle.Text = ESP.Enabled and "ESP: ON" or "ESP: OFF"
    espToggle.Parent = mainContent

    Instance.new("UICorner", espToggle).CornerRadius = UDim.new(0, 6)


    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -10, 0, 40)
    info.Position = UDim2.new(0, 5, 0, 45)
    info.BackgroundTransparency = 1
    info.TextColor3 = Color3.fromRGB(180, 180, 180)
    info.TextScaled = true
    info.TextWrapped = true
    info.Text = "L = Arm/Disarm | Hold V = Trigger | RightShift = Hide UI"
    info.Parent = mainContent

    ------------------------------------------------------------------
    -- AIM ASSIST TOGGLE
    ------------------------------------------------------------------

    local aaToggle = Instance.new("TextButton")
    aaToggle.Size = UDim2.new(0, 260, 0, 30)
    aaToggle.Position = UDim2.new(0, 20, 0, 88)
    aaToggle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    aaToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    aaToggle.TextScaled = true
    aaToggle.BorderSizePixel = 0
    aaToggle.Text = AimAssist.Enabled and "Aim Assist: ON" or "Aim Assist: OFF"
    aaToggle.Parent = mainContent
    Instance.new("UICorner", aaToggle).CornerRadius = UDim.new(0, 6)

    aaToggle.MouseButton1Click:Connect(function()
        AimAssist.Enabled = not AimAssist.Enabled
        aaToggle.Text = AimAssist.Enabled and "Aim Assist: ON" or "Aim Assist: OFF"
        SaveSettings()
    end)

    ------------------------------------------------------------------
    -- AIM ASSIST STRENGTH SLIDER
    ------------------------------------------------------------------

    local sliderBg = Instance.new("Frame")
    sliderBg.Size = UDim2.new(0, 260, 0, 20)
    sliderBg.Position = UDim2.new(0, 20, 0, 124)
    sliderBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    sliderBg.BorderSizePixel = 0
    sliderBg.Parent = mainContent
    Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(0, 4)

    local sliderFill = Instance.new("Frame")
    sliderFill.Size = UDim2.new(AimAssist.Strength, 0, 1, 0)
    sliderFill.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
    sliderFill.BorderSizePixel = 0
    sliderFill.Parent = sliderBg
    Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(0, 4)

    local sliderLabel = Instance.new("TextLabel")
    sliderLabel.Size = UDim2.new(1, 0, 1, 0)
    sliderLabel.BackgroundTransparency = 1
    sliderLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    sliderLabel.TextScaled = true
    sliderLabel.Text = "Strength: " .. math.floor(AimAssist.Strength * 100) .. "%"
    sliderLabel.Parent = sliderBg

    do
        local dragging = false
        local function updateSlider()
            local mouse = UserInputService:GetMouseLocation()
            local relX = mouse.X - sliderBg.AbsolutePosition.X
            local t = math.clamp(relX / sliderBg.AbsoluteSize.X, 0, 1)
            AimAssist.Strength = t
            sliderFill.Size = UDim2.new(t, 0, 1, 0)
            sliderLabel.Text = "Strength: " .. math.floor(t * 100) .. "%"
            SaveSettings()
        end

        sliderBg.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                setDragging(false)
                updateSlider()
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
                setDragging(true)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                updateSlider()
            end
        end)
    end

    ------------------------------------------------------------------
    -- WALK SPEED SLIDER
    ------------------------------------------------------------------

    local wsLabel = Instance.new("TextLabel")
    wsLabel.Size = UDim2.new(0, 130, 0, 20)
    wsLabel.Position = UDim2.new(0, 20, 0, 150)
    wsLabel.BackgroundTransparency = 1
    wsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    wsLabel.TextScaled = true
    wsLabel.TextXAlignment = Enum.TextXAlignment.Left
    wsLabel.Text = "WalkSpeed: " .. tostring(Settings.WalkSpeed)
    wsLabel.Parent = mainContent

    local wsSliderBg = Instance.new("Frame")
    wsSliderBg.Size = UDim2.new(0, 260, 0, 16)
    wsSliderBg.Position = UDim2.new(0, 20, 0, 172)
    wsSliderBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    wsSliderBg.BorderSizePixel = 0
    wsSliderBg.Parent = mainContent
    Instance.new("UICorner", wsSliderBg).CornerRadius = UDim.new(0, 4)

    local wsVal = (Settings.WalkSpeed - 1) / 199
    wsVal = math.clamp(wsVal, 0, 1)
    local wsSliderFill = Instance.new("Frame")
    wsSliderFill.Size = UDim2.new(wsVal, 0, 1, 0)
    wsSliderFill.BackgroundColor3 = Color3.fromRGB(60, 180, 60)
    wsSliderFill.BorderSizePixel = 0
    wsSliderFill.Parent = wsSliderBg
    Instance.new("UICorner", wsSliderFill).CornerRadius = UDim.new(0, 4)

    do
        local dragging = false
        local function updateWS()
            local mouse = UserInputService:GetMouseLocation()
            local relX = mouse.X - wsSliderBg.AbsolutePosition.X
            local t = math.clamp(relX / wsSliderBg.AbsoluteSize.X, 0, 1)
            local speed = math.floor(1 + t * 199)
            wsSliderFill.Size = UDim2.new(t, 0, 1, 0)
            wsLabel.Text = "WalkSpeed: " .. tostring(speed)
            Settings.WalkSpeed = speed
            if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.WalkSpeed = speed
            end
            SaveSettings()
        end

        wsSliderBg.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                setDragging(false)
                updateWS()
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
                setDragging(true)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                updateWS()
            end
        end)
    end

    ------------------------------------------------------------------
    -- JUMP POWER SLIDER
    ------------------------------------------------------------------

    local jpLabel = Instance.new("TextLabel")
    jpLabel.Size = UDim2.new(0, 130, 0, 20)
    jpLabel.Position = UDim2.new(0, 20, 0, 194)
    jpLabel.BackgroundTransparency = 1
    jpLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    jpLabel.TextScaled = true
    jpLabel.TextXAlignment = Enum.TextXAlignment.Left
    jpLabel.Text = "JumpPower: " .. tostring(Settings.JumpPower)
    jpLabel.Parent = mainContent

    local jpSliderBg = Instance.new("Frame")
    jpSliderBg.Size = UDim2.new(0, 260, 0, 16)
    jpSliderBg.Position = UDim2.new(0, 20, 0, 216)
    jpSliderBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    jpSliderBg.BorderSizePixel = 0
    jpSliderBg.Parent = mainContent
    Instance.new("UICorner", jpSliderBg).CornerRadius = UDim.new(0, 4)

    local jpVal = (Settings.JumpPower - 1) / 199
    jpVal = math.clamp(jpVal, 0, 1)
    local jpSliderFill = Instance.new("Frame")
    jpSliderFill.Size = UDim2.new(jpVal, 0, 1, 0)
    jpSliderFill.BackgroundColor3 = Color3.fromRGB(180, 120, 60)
    jpSliderFill.BorderSizePixel = 0
    jpSliderFill.Parent = jpSliderBg
    Instance.new("UICorner", jpSliderFill).CornerRadius = UDim.new(0, 4)

    do
        local dragging = false
        local function updateJP()
            local mouse = UserInputService:GetMouseLocation()
            local relX = mouse.X - jpSliderBg.AbsolutePosition.X
            local t = math.clamp(relX / jpSliderBg.AbsoluteSize.X, 0, 1)
            local power = math.floor(1 + t * 199)
            jpSliderFill.Size = UDim2.new(t, 0, 1, 0)
            jpLabel.Text = "JumpPower: " .. tostring(power)
            Settings.JumpPower = power
            if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.JumpPower = power
            end
            SaveSettings()
        end

        jpSliderBg.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                setDragging(false)
                updateJP()
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
                setDragging(true)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                updateJP()
            end
        end)
    end

    killButton = Instance.new("TextButton")
    killButton.Size = UDim2.new(0, 260, 0, 30)
    killButton.Position = UDim2.new(0, 20, 1, -35)
    killButton.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
    killButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    killButton.TextScaled = true
    killButton.Text = "KILL SCRIPT"
    killButton.BorderSizePixel = 0
    killButton.Parent = mainContent

    Instance.new("UICorner", killButton).CornerRadius = UDim.new(0, 6)


    ------------------------------------------------------------------
    -- DEBUG CONTENT
    ------------------------------------------------------------------

    debugContent = Instance.new("Frame")
    debugContent.Size = UDim2.new(1, -10, 1, -90)
    debugContent.Position = UDim2.new(0, 5, 0, 60)
    debugContent.BackgroundTransparency = 1
    debugContent.Name = "DebugContent"
    debugContent.Visible = false
    debugContent.Parent = mainFrame


    stateLabel = Instance.new("TextLabel")
    stateLabel.Size = UDim2.new(1, -10, 0, 30)
    stateLabel.Position = UDim2.new(0, 5, 0, 5)
    stateLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    stateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    stateLabel.TextScaled = true
    stateLabel.BorderSizePixel = 0
    stateLabel.Text = "Trigger state: " .. TriggerState
    stateLabel.Parent = debugContent

    Instance.new("UICorner", stateLabel).CornerRadius = UDim.new(0, 6)


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
        "TARGET: enemy in center"
    debugInfo.Parent = debugContent


    ------------------------------------------------------------------
    -- SETTINGS CONTENT
    ------------------------------------------------------------------

    settingsContent = Instance.new("Frame")
    settingsContent.Size = UDim2.new(1, -10, 1, -90)
    settingsContent.Position = UDim2.new(0, 5, 0, 60)
    settingsContent.BackgroundTransparency = 1
    settingsContent.Name = "SettingsContent"
    settingsContent.Visible = false
    settingsContent.Parent = mainFrame


    local pickerFrame = Instance.new("Frame")
    pickerFrame.Size = UDim2.new(0, 210, 0, 160)
    pickerFrame.Position = UDim2.new(0, 10, 0, 5)
    pickerFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    pickerFrame.BorderSizePixel = 0
    pickerFrame.Parent = settingsContent

    Instance.new("UICorner", pickerFrame).CornerRadius = UDim.new(0, 6)

        ------------------------------------------------------------------
    -- SATURATION / VALUE SQUARE
    ------------------------------------------------------------------

    svSquare = Instance.new("Frame")
    svSquare.Size = UDim2.new(0, 130, 0, 130)
    svSquare.Position = UDim2.new(0, 10, 0, 10)
    svSquare.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    svSquare.BorderSizePixel = 0
    svSquare.Parent = pickerFrame


    svSelector = Instance.new("Frame")
    svSelector.Size = UDim2.new(0, 8, 0, 8)
    svSelector.AnchorPoint = Vector2.new(0.5, 0.5)
    svSelector.BackgroundColor3 = Color3.new(1, 1, 1)
    svSelector.BorderSizePixel = 1
    svSelector.BorderColor3 = Color3.new(0, 0, 0)
    svSelector.Parent = svSquare

    Instance.new("UICorner", svSelector).CornerRadius = UDim.new(1, 0)


    ------------------------------------------------------------------
    -- WHITE OVERLAY GRADIENT
    ------------------------------------------------------------------

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


    ------------------------------------------------------------------
    -- BLACK OVERLAY GRADIENT
    ------------------------------------------------------------------

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


    ------------------------------------------------------------------
    -- HUE BAR
    ------------------------------------------------------------------

    hueBar = Instance.new("Frame")
    hueBar.Size = UDim2.new(0, 20, 0, 130)
    hueBar.Position = UDim2.new(0, 150, 0, 10)
    hueBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    hueBar.BorderSizePixel = 0
    hueBar.Parent = pickerFrame


    hueSelector = Instance.new("Frame")
    hueSelector.AnchorPoint = Vector2.new(0.5, 0.5)
    hueSelector.Size = UDim2.new(1, 0, 0, 4)
    hueSelector.Position = UDim2.new(0.5, 0, 0, 0)
    hueSelector.BackgroundColor3 = Color3.new(1, 1, 1)
    hueSelector.BorderSizePixel = 1
    hueSelector.BorderColor3 = Color3.new(0, 0, 0)
    hueSelector.Parent = hueBar


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


    ------------------------------------------------------------------
    -- COLOR PREVIEW
    ------------------------------------------------------------------

    preview = Instance.new("Frame")
    preview.Size = UDim2.new(0, 40, 0, 40)
    preview.Position = UDim2.new(0, 150, 0, 145)
    preview.BackgroundColor3 = ESP.FillColor
    preview.BorderSizePixel = 0
    preview.Parent = pickerFrame

    Instance.new("UICorner", preview).CornerRadius = UDim.new(0, 4)


    ------------------------------------------------------------------
    -- APPLY BUTTONS
    ------------------------------------------------------------------

    applyFill = Instance.new("TextButton")
    applyFill.Size = UDim2.new(0, 120, 0, 24)
    applyFill.Position = UDim2.new(0, 230, 0, 20)
    applyFill.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
    applyFill.TextColor3 = Color3.fromRGB(255, 255, 255)
    applyFill.TextScaled = true
    applyFill.Text = "Apply to Fill"
    applyFill.BorderSizePixel = 0
    applyFill.Parent = settingsContent

    Instance.new("UICorner", applyFill).CornerRadius = UDim.new(0, 4)


    applyOutline = applyFill:Clone()
    applyOutline.Text = "Apply to Outline"
    applyOutline.Position = UDim2.new(0, 230, 0, 50)
    applyOutline.Parent = settingsContent

        ------------------------------------------------------------------
    -- APPLY BUTTON LOGIC
    ------------------------------------------------------------------

    applyFill.MouseButton1Click:Connect(function()

        ESP.FillColor = preview.BackgroundColor3

        for _, highlight in pairs(ESP.Pixels) do
            highlight.FillColor = ESP.FillColor
        end

        SaveSettings()

    end)


    applyOutline.MouseButton1Click:Connect(function()

        ESP.OutlineColor = preview.BackgroundColor3

        for _, highlight in pairs(ESP.Pixels) do
            highlight.OutlineColor = ESP.OutlineColor
        end

        SaveSettings()

    end)


    ------------------------------------------------------------------
    -- TAB SWITCHING
    ------------------------------------------------------------------

    local function setTab(which)

        mainContent.Visible = (which == "main")
        debugContent.Visible = (which == "debug")
        settingsContent.Visible = (which == "settings")

        mainTab.BackgroundColor3 =
            (which == "main") and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)

        mainTab.TextColor3 =
            (which == "main") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)


        debugTab.BackgroundColor3 =
            (which == "debug") and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)

        debugTab.TextColor3 =
            (which == "debug") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)


        settingsTab.BackgroundColor3 =
            (which == "settings") and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)

        settingsTab.TextColor3 =
            (which == "settings") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)

    end


    mainTab.MouseButton1Click:Connect(function()
        setTab("main")
    end)


    debugTab.MouseButton1Click:Connect(function()
        setTab("debug")
    end)


    settingsTab.MouseButton1Click:Connect(function()
        setTab("settings")
    end)

end


createUI()


------------------------------------------------------------------
-- CHARACTER RESPAWN HANDLER
------------------------------------------------------------------

local function ApplySpeedSettings()

    if not LocalPlayer then return end
    local char = LocalPlayer.Character
    if not char then return end

    local humanoid = char:FindFirstChild("Humanoid")
    if not humanoid then return end

    humanoid.WalkSpeed = Settings.WalkSpeed
    humanoid.JumpPower = Settings.JumpPower

end

local function OnCharacterAdded(newChar)

    local humanoid = newChar:WaitForChild("Humanoid")

    ApplySpeedSettings()

end

LocalPlayer.CharacterAdded:Connect(OnCharacterAdded)

-- Initial application
ApplySpeedSettings()


local function setDragging(state)

    if mainFrame then
        mainFrame.Draggable = state
    end

end

------------------------------------------------------------------
-- RESIZABLE UI (LOCK DRAG ONLY WHILE RESIZING)
------------------------------------------------------------------

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

                if oldDraggable ~= nil then
                    mainFrame.Draggable = oldDraggable
                else
                    mainFrame.Draggable = true
                end

            end

        end

    end)


    UserInputService.InputChanged:Connect(function(input)

        if not resizing then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end


        local currentPos = UserInputService:GetMouseLocation()

        local dx = currentPos.X - startMousePos.X
        local dy = currentPos.Y - startMousePos.Y


        local newW = math.max(300, startSize.X.Offset + dx)
        local newH = math.max(220, startSize.Y.Offset + dy)


        mainFrame.Size = UDim2.new(0, newW, 0, newH)

        SaveSettings()

    end)

end

------------------------------------------------------------------
-- COLOR PICKER LOGIC (FIXED)
------------------------------------------------------------------

local currentHue = 0
local currentS = 1
local currentV = 1


local function updateFromHSV()

    local color = Color3.fromHSV(currentHue / 360, currentS, currentV)

    preview.BackgroundColor3 = color

    svSquare.BackgroundColor3 = Color3.fromHSV(currentHue / 360, 1, 1)
    svSquare.BackgroundTransparency = 0


    if svSelector then
        svSelector.Position = UDim2.new(currentS, 0, 1 - currentV, 0)
    end

    if hueSelector then
        hueSelector.Position = UDim2.new(0.5, 0, 1 - (currentHue / 360), 0)
    end

end


updateFromHSV()

svSelector.Position = UDim2.new(currentS, 0, 1 - currentV, 0)


------------------------------------------------------------------
-- SV SQUARE INPUT
------------------------------------------------------------------

svSquare.InputBegan:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.MouseButton1 then

        setDragging(false)

        local moveConn
        local endConn


        moveConn = UserInputService.InputChanged:Connect(function(i)

            if i.UserInputType == Enum.UserInputType.MouseMovement then

                local mouse = UserInputService:GetMouseLocation()

                local relX = mouse.X - svSquare.AbsolutePosition.X
                local relY = mouse.Y - svSquare.AbsolutePosition.Y

                local sx = math.clamp(relX / svSquare.AbsoluteSize.X, 0, 1)
                local sy = math.clamp(relY / svSquare.AbsoluteSize.Y, 0, 1)

                currentS = sx
                currentV = 1 - sy

                updateFromHSV()

            end

        end)


        endConn = UserInputService.InputEnded:Connect(function(i2)

            if i2.UserInputType == Enum.UserInputType.MouseButton1 then

                if moveConn then
                    moveConn:Disconnect()
                end

                if endConn then
                    endConn:Disconnect()
                end

                setDragging(true)

            end

        end)

    end

end)


------------------------------------------------------------------
-- HUE BAR INPUT
------------------------------------------------------------------

hueBar.InputBegan:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.MouseButton1 then

        setDragging(false)

        local moveConn
        local endConn


        moveConn = UserInputService.InputChanged:Connect(function(i)

            if i.UserInputType == Enum.UserInputType.MouseMovement then

                local mouse = UserInputService:GetMouseLocation()

                local relY = mouse.Y - hueBar.AbsolutePosition.Y

                local t = math.clamp(relY / hueBar.AbsoluteSize.Y, 0, 1)

                currentHue = (1 - t) * 360

                updateFromHSV()

            end

        end)


        endConn = UserInputService.InputEnded:Connect(function(i2)

            if i2.UserInputType == Enum.UserInputType.MouseButton1 then

                if moveConn then
                    moveConn:Disconnect()
                end

                if endConn then
                    endConn:Disconnect()
                end

                setDragging(true)

            end

        end)

    end

end)

------------------------------------------------------------------
-- ESP FUNCTIONS
------------------------------------------------------------------

function ESP:CreatePixel(character)

    if not character or self.Pixels[character] then
        return
    end

    local highlight = Instance.new("Highlight")

    highlight.Name = "ESP_Highlight"
    highlight.FillColor = self.FillColor
    highlight.FillTransparency = 0.5
    highlight.OutlineColor = self.OutlineColor
    highlight.OutlineTransparency = 0
    highlight.Adornee = character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = character

    self.Pixels[character] = highlight

end


function ESP:RemovePixel(character)

    if character and self.Pixels[character] then

        self.Pixels[character]:Destroy()
        self.Pixels[character] = nil

    end

end


function ESP:ClearAll()

    for _, h in pairs(self.Pixels) do
        h:Destroy()
    end

    self.Pixels = {}

end


function ESP:Update()

    if not self.Enabled or not self.Armed then

        if next(self.Pixels) ~= nil then
            self:ClearAll()
        end

        return
    end


    for _, plr in ipairs(Players:GetPlayers()) do

        if plr ~= LocalPlayer then

            local char = plr.Character

            if char and char:FindFirstChild("HumanoidRootPart") then

                if not self.Pixels[char] then
                    self:CreatePixel(char)
                end

            else

                self:RemovePixel(char)

            end

        end

    end

end

------------------------------------------------------------------
-- KILL SCRIPT
------------------------------------------------------------------

local function KillScript()

    Running = false

    ESP:ClearAll()

    if screenGui then
        screenGui:Destroy()
    end


    for _, conn in ipairs(Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end

end


table.insert(
    Connections,
    killButton.MouseButton1Click:Connect(KillScript)
)


------------------------------------------------------------------
-- UI TOGGLE + ESP BUTTON
------------------------------------------------------------------

table.insert(
    Connections,
    UserInputService.InputBegan:Connect(function(input, gp)

        if gp then return end

        if input.KeyCode == Enum.KeyCode.RightShift then

            if mainFrame then
                mainFrame.Visible = not mainFrame.Visible
            end

        end

    end)
)


table.insert(
    Connections,
    espToggle.MouseButton1Click:Connect(function()

        ESP.Enabled = not ESP.Enabled

        espToggle.Text = ESP.Enabled and "ESP: ON" or "ESP: OFF"

        if not ESP.Enabled then
            ESP:ClearAll()
        end

        SaveSettings()

    end)
)


------------------------------------------------------------------
-- INPUT: L (ARM FOR ESP), V (HOLD FOR TRIGGERBOT)
------------------------------------------------------------------

table.insert(
    Connections,
    UserInputService.InputBegan:Connect(function(input, gp)

        if input.KeyCode == Enum.KeyCode.F7 then

            KillScript()
            return

        end

        if gp then return end


        if input.KeyCode == Enum.KeyCode.L then
            ESP.Armed = not ESP.Armed
        end


        if input.KeyCode == Enum.KeyCode.C then

            AimAssist.Enabled = not AimAssist.Enabled
            SaveSettings()

            for _, btn in ipairs(mainContent:GetChildren()) do
                if btn:IsA("TextButton") and (btn.Text:find("Aim Assist") or btn.Text:find("Aim Assist")) then
                    btn.Text = AimAssist.Enabled and "Aim Assist: ON" or "Aim Assist: OFF"
                    break
                end
            end

        end


        if input.KeyCode == Enum.KeyCode.V then

            TriggerHeld = true
            TriggerState = "HOLDING"

        end

    end)
)


table.insert(
    Connections,
    UserInputService.InputEnded:Connect(function(input)

        if input.KeyCode == Enum.KeyCode.V then

            TriggerHeld = false

            if TriggerState ~= "DISARMED" then
                TriggerState = "ARMED"
            end

            clicked = false

        end

    end)
)


------------------------------------------------------------------
-- TRIGGERBOT (NO DELAY)
------------------------------------------------------------------

local function DetectCenterTarget()

    if not TriggerHeld then

        if TriggerState == "DISARMED" then
            TriggerState = "ARMED"
        end

        clicked = false
        return

    end


    TriggerState = "HOLDING"


    if not Camera then
        Camera = workspace.CurrentCamera
        if not Camera then return end
    end


    local mousePos = UserInputService:GetMouseLocation()


    -- Immediate raycast at center pixel, no offsets needed for instant response
    local ray = Camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    local origin = ray.Origin

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { LocalPlayer.Character }

    local result = workspace:Raycast(origin, ray.Direction * 1000, params)

    if result and result.Instance then

        local part = result.Instance
        local model = part:FindFirstAncestorOfClass("Model")

        if model then

            local playerHit = Players:GetPlayerFromCharacter(model)

            if playerHit and playerHit ~= LocalPlayer then

                TriggerState = "TARGET"

                mouse1press()
                mouse1release()

                return

            end

        end

    end


    TriggerState = "HOLDING"
    clicked = false

end


------------------------------------------------------------------
-- AIM ASSIST (Matrix Hub-style: camera CFrame smoothing + FOV)
------------------------------------------------------------------

local function IsCharacterKnocked(char)

    if not char then
        return true
    end

    local humanoid = char:FindFirstChild("Humanoid")

    if not humanoid then
        return true
    end

    if humanoid.Health <= 0 then
        return true
    end

    if humanoid:GetState() == Enum.HumanoidStateType.Dead then
        return true
    end

    return false

end


local function DisableAimAssist()

    AimAssist.Enabled = false
    AimAssist.CurrentTarget = nil

    for _, btn in ipairs(mainContent:GetChildren()) do
        if btn:IsA("TextButton") and (btn.Text:find("Aim Assist") or btn.Text:find("Aim Assist")) then
            btn.Text = "Aim Assist: OFF"
            break
        end
    end

    SaveSettings()

end


local AAFOV = 300 -- max pixels from screen center to lock on


function AimAssist:IsTargetValid(character)

    if not character then
        return false
    end

    local humanoid = character:FindFirstChild("Humanoid")

    if not humanoid then
        return false
    end

    if humanoid.Health <= 0 then
        return false
    end

    if humanoid:GetState() == Enum.HumanoidStateType.Dead then
        return false
    end

    -- Check for common knocked/ragdoll states
    local rootPart = character:FindFirstChild("HumanoidRootPart")

    if rootPart then
        -- If root part velocity is near zero but character is on floor and not moving = likely ragdolled/knocked
        local bodyVelocity = rootPart.Velocity
        if bodyVelocity and bodyVelocity.Magnitude < 0.1 and humanoid:GetState() == Enum.HumanoidStateType.Ragdoll then
            return false
        end
    end

    return true

end


local function GetTargetHeadCFrame(targetChar)

    if not targetChar then
        return nil
    end

    -- Try to get head first, fall back to HumanoidRootPart
    local head = targetChar:FindFirstChild("Head")

    if head then
        return head.Position
    end

    local rootPart = targetChar:FindFirstChild("HumanoidRootPart")

    if rootPart then
        return rootPart.Position + Vector3.new(0, 1.5, 0) -- approximate head height
    end

    return nil

end


function AimAssist:Update(deltaTime)

    if not self.Enabled then
        if self.CurrentTarget then
            self.CurrentTarget = nil
        end
        return
    end

    if not Camera then
        Camera = workspace.CurrentCamera
        if not Camera then return end
    end

    -- Check if current target is still alive
    if self.CurrentTarget then

        local char = self.CurrentTarget.Character

        if self:IsTargetValid(char) == false then
            self.CurrentTarget = nil
            return
        end

        -- Get the target position (head or root)
        local targetPos = GetTargetHeadCFrame(char)

        if targetPos then

            -- Project to viewport to check if still in range
            local screenPos = Camera:WorldToViewportPoint(targetPos)
            local screenCenter = Camera.ViewportSize / 2
            local dx = screenPos.X - screenCenter.X
            local dy = screenPos.Y - screenCenter.Y
            local distFromCenter = Vector2.new(dx, dy).Magnitude

            -- If target moved too far out of FOV, drop lock
            if distFromCenter > AAFOV * 2 then
                self.CurrentTarget = nil
            else
                -- Smooth camera rotation toward target using CFrame lerp
                local smoothness = self.Strength -- 0.0 = instant, 1.0 = max smoothing

                -- compute target camera CFrame looking at the target's head
                local currentCFrame = Camera.CFrame
                local cameraPos = currentCFrame.Position
                local targetCFrame = CFrame.lookAt(cameraPos, targetPos)

                -- interpolation factor: 1 - smoothness
                -- 0 smoothness -> factor 1.0 (instant snap)
                -- 1 smoothness -> factor 0.0 (no movement)
                local factor = 1 - smoothness

                -- Apply deltaTime so behavior is frame-rate independent
                -- factor * (1 - (1/2)^(dt*60)) ensures ~same speed at any framerate
                local dtFactor = 1 - (1 - factor) ^ (deltaTime * 60)
                dtFactor = math.clamp(dtFactor, 0, 1)

                -- Slerp-like approach: lerp the look vector components
                local newCFrame = currentCFrame:Lerp(targetCFrame, dtFactor)

                Camera.CFrame = newCFrame
                return
            end

        end

    end

    -- Find nearest target to screen center within FOV
    local screenCenter = Camera.ViewportSize / 2
    local nearestTargetPlayer = nil
    local nearestDist = math.huge
    local nearestTargetPos = nil

    for _, plr in ipairs(Players:GetPlayers()) do

        if plr ~= LocalPlayer then

            local char = plr.Character

            if char and not IsCharacterKnocked(char) then

                local targetPos = GetTargetHeadCFrame(char)

                if targetPos then

                    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPos)

                    if onScreen then

                        local dx = screenPos.X - screenCenter.X
                        local dy = screenPos.Y - screenCenter.Y
                        local dist = Vector2.new(dx, dy).Magnitude

                        if dist < nearestDist and dist <= AAFOV then
                            nearestDist = dist
                            nearestTargetPos = targetPos
                            nearestTargetPlayer = plr
                        end

                    end

                end

            end

        end

    end

    self.CurrentTarget = nearestTargetPlayer

    if nearestTargetPos then

        local smoothness = self.Strength
        local currentCFrame = Camera.CFrame
        local cameraPos = currentCFrame.Position
        local targetCFrame = CFrame.lookAt(cameraPos, nearestTargetPos)

        local factor = 1 - smoothness
        local dtFactor = 1 - (1 - factor) ^ (deltaTime * 60)
        dtFactor = math.clamp(dtFactor, 0, 1)

        local newCFrame = currentCFrame:Lerp(targetCFrame, dtFactor)
        Camera.CFrame = newCFrame

    end

end


local function DoAimAssist()

    -- DoAimAssist is kept as a wrapper that gets called from the main loop.
    -- Expected to be refactored to pass deltaTime at the call site.
    -- This function will be replaced by the AimAssist:Update() call in the main loop.

end


------------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------------

table.insert(
    Connections,
    RunService.RenderStepped:Connect(function(dt)

        if not Running then
            return
        end

        ESP:Update()

        DetectCenterTarget()

        AimAssist:Update(dt)

        if stateLabel then
            stateLabel.Text = "Trigger state: " .. TriggerState
        end

    end)
)
