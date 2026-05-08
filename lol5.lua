--[[
ESP + Triggerbot (L toggle, V hold) + Kill Button + ESP Settings + Resizable UI

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
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera


------------------------------------------------------------------
-- STATE
------------------------------------------------------------------

local Running = true
local Connections = {}

-- ESP Settings (Matrix Hub style)
local ESP = {
    Enabled = false,
    Armed = false,
    
    -- Visual elements
    Boxes = true,
    Names = true,
    Health = true,
    Distance = true,
    Tracers = false,
    Skeleton = false,
    
    -- Colors
    BoxColor = Color3.fromRGB(255, 0, 0),
    NameColor = Color3.fromRGB(255, 255, 255),
    HealthColor = Color3.fromRGB(0, 255, 0),
    TracerColor = Color3.fromRGB(255, 0, 0),
    
    -- Transparency
    BoxTransparency = 0.5,
    FillTransparency = 0.7,
    
    -- Storage
    BoxesTable = {},
    NameTags = {},
    TracersTable = {},
    HealthBars = {},
    
    -- Range
    MaxDistance = 500,
    
    -- Display Name preference
    UseDisplayNames = true
}

local AimAssist = {
    Enabled = false,
    Strength = 0.5,
    CurrentTarget = nil
}

local TriggerHeld = false
local TriggerState = "DISARMED"


------------------------------------------------------------------
-- SETTINGS SYSTEM
------------------------------------------------------------------

local Settings = {
    ESPEnabled = false,
    ESPArmed = false,
    Boxes = true,
    Names = true,
    Health = true,
    Distance = true,
    Tracers = false,
    Skeleton = false,
    BoxColor = Color3.fromRGB(255, 0, 0),
    NameColor = Color3.fromRGB(255, 255, 255),
    HealthColor = Color3.fromRGB(0, 255, 0),
    TracerColor = Color3.fromRGB(255, 0, 0),
    BoxTransparency = 0.5,
    FillTransparency = 0.7,
    MaxDistance = 500,
    UseDisplayNames = true,
    AimAssistEnabled = false,
    AimAssistStrength = 0.5,
    WalkSpeed = 16,
    JumpPower = 50,
    UISizeX = 420,
    UISizeY = 500
}

local function SaveSettings()
    Settings.ESPEnabled = ESP.Enabled
    Settings.ESPArmed = ESP.Armed
    Settings.Boxes = ESP.Boxes
    Settings.Names = ESP.Names
    Settings.Health = ESP.Health
    Settings.Distance = ESP.Distance
    Settings.Tracers = ESP.Tracers
    Settings.Skeleton = ESP.Skeleton
    Settings.BoxColor = ESP.BoxColor
    Settings.NameColor = ESP.NameColor
    Settings.HealthColor = ESP.HealthColor
    Settings.TracerColor = ESP.TracerColor
    Settings.BoxTransparency = ESP.BoxTransparency
    Settings.FillTransparency = ESP.FillTransparency
    Settings.MaxDistance = ESP.MaxDistance
    Settings.UseDisplayNames = ESP.UseDisplayNames
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
    ESP.Boxes = Settings.Boxes
    ESP.Names = Settings.Names
    ESP.Health = Settings.Health
    ESP.Distance = Settings.Distance
    ESP.Tracers = Settings.Tracers
    ESP.Skeleton = Settings.Skeleton
    ESP.BoxColor = Settings.BoxColor
    ESP.NameColor = Settings.NameColor
    ESP.HealthColor = Settings.HealthColor
    ESP.TracerColor = Settings.TracerColor
    ESP.BoxTransparency = Settings.BoxTransparency
    ESP.FillTransparency = Settings.FillTransparency
    ESP.MaxDistance = Settings.MaxDistance
    ESP.UseDisplayNames = Settings.UseDisplayNames
    AimAssist.Enabled = Settings.AimAssistEnabled
    AimAssist.Strength = Settings.AimAssistStrength
end


------------------------------------------------------------------
-- UTILITY FUNCTIONS
------------------------------------------------------------------

local function GetPlayerName(player)
    if ESP.UseDisplayNames then
        return player.DisplayName or player.Name
    end
    return player.Name
end

local function GetCharacterSize(character)
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return 3, 5 end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return 2, 4 end
    
    -- Calculate approximate size based on humanoid
    local width = 2
    local height = 5
    
    local head = character:FindFirstChild("Head")
    if head then
        height = (rootPart.Position.Y - head.Position.Y) + 2
    end
    
    return width, math.abs(height)
end

local function WorldToScreen(position)
    if not Camera then return nil end
    local vector, onScreen = Camera:WorldToViewportPoint(position)
    if onScreen and vector.Z > 0 then
        return Vector2.new(vector.X, vector.Y), vector.Z
    end
    return nil, nil
end


------------------------------------------------------------------
-- DRAWING FUNCTIONS
------------------------------------------------------------------

-- Create a box ESP
local function CreateBox(character, player)
    local box = Instance.new("BoxHandleAdornment")
    box.Name = "ESP_Box_" .. player.Name
    box.Adornee = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
    box.Size = Vector3.new(2.5, 5, 2.5)
    box.Color3 = ESP.BoxColor
    box.Transparency = ESP.BoxTransparency
    box.ZIndex = 0
    box.AlwaysOnTop = true
    box.Visible = true
    box.Parent = screenGui
    return box
end

-- Create a tracer line from bottom of screen to player
local function CreateTracer(character, player)
    local tracer = Instance.new("LineHandleAdornment")
    tracer.Name = "ESP_Tracer_" .. player.Name
    tracer.Adornee = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
    tracer.Color3 = ESP.TracerColor
    tracer.Thickness = 1
    tracer.Transparency = 0.3
    tracer.ZIndex = 0
    tracer.AlwaysOnTop = true
    tracer.Visible = true
    tracer.Parent = screenGui
    return tracer
end

-- Create a BillboardGui name tag
local function CreateNameTag(character, player)
    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
    if not rootPart then return nil end
    
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_NameTag_" .. player.Name
    billboard.Adornee = rootPart
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.ResetOnSpawn = false
    billboard.Parent = screenGui
    
    -- Name label
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0.4, 0)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = ESP.NameColor
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextStrokeTransparency = 0.2
    nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.Text = GetPlayerName(player)
    nameLabel.Parent = billboard
    
    -- Health bar background
    local healthBg = Instance.new("Frame")
    healthBg.Name = "HealthBg"
    healthBg.Size = UDim2.new(0.8, 0, 0.15, 0)
    healthBg.Position = UDim2.new(0.1, 0, 0.45, 0)
    healthBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    healthBg.BorderSizePixel = 0
    healthBg.Parent = billboard
    
    -- Health bar fill
    local healthFill = Instance.new("Frame")
    healthFill.Name = "HealthFill"
    healthFill.Size = UDim2.new(1, 0, 1, 0)
    healthFill.BackgroundColor3 = ESP.HealthColor
    healthFill.BorderSizePixel = 0
    healthFill.Parent = healthBg
    
    -- Distance label
    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "DistanceLabel"
    distLabel.Size = UDim2.new(1, 0, 0.3, 0)
    distLabel.Position = UDim2.new(0, 0, 0.65, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    distLabel.TextScaled = true
    distLabel.Font = Enum.Font.Gotham
    distLabel.TextStrokeTransparency = 0.3
    distLabel.Text = "0m"
    distLabel.Parent = billboard
    
    return billboard
end

-- Update health bar
local function UpdateHealthBar(billboard, health, maxHealth)
    if billboard and billboard:FindFirstChild("HealthBg") then
        local healthBg = billboard.HealthBg
        local healthFill = healthBg:FindFirstChild("HealthFill")
        if healthFill then
            local percent = math.clamp(health / maxHealth, 0, 1)
            healthFill.Size = UDim2.new(percent, 0, 1, 0)
            
            -- Change color based on health percentage
            if percent > 0.7 then
                healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
            elseif percent > 0.3 then
                healthFill.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
            else
                healthFill.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
            end
        end
    end
end

-- Update distance text
local function UpdateDistanceText(billboard, distance)
    if billboard and billboard:FindFirstChild("DistanceLabel") then
        local distLabel = billboard.DistanceLabel
        local rounded = math.floor(distance + 0.5)
        distLabel.Text = tostring(rounded) .. "m"
    end
end

-- Update box size based on character
local function UpdateBoxSize(box, character)
    if not box or not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    
    if rootPart and head then
        local height = math.abs(rootPart.Position.Y - head.Position.Y) + 1.5
        local width = 1.5
        box.Size = Vector3.new(width, height, width)
        box.CFrame = rootPart.CFrame * CFrame.new(0, -height/2 + 0.5, 0)
    end
end

-- Update tracer end point
local function UpdateTracer(tracer, character)
    if not tracer or not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart then
        local screenPos, onScreen = WorldToScreen(rootPart.Position)
        if onScreen and screenPos then
            local screenSize = Camera.ViewportSize
            local startPoint = Vector2.new(screenSize.X / 2, screenSize.Y)
            tracer.From = startPoint
            tracer.To = screenPos
        end
    end
end

-- Remove ESP for a character
local function RemoveESPForCharacter(character)
    if ESP.BoxesTable[character] then
        pcall(function() ESP.BoxesTable[character]:Destroy() end)
        ESP.BoxesTable[character] = nil
    end
    if ESP.NameTags[character] then
        pcall(function() ESP.NameTags[character]:Destroy() end)
        ESP.NameTags[character] = nil
    end
    if ESP.TracersTable[character] then
        pcall(function() ESP.TracersTable[character]:Destroy() end)
        ESP.TracersTable[character] = nil
    end
end

-- Clear all ESP
local function ClearAllESP()
    for _, box in pairs(ESP.BoxesTable) do
        pcall(function() box:Destroy() end)
    end
    for _, tag in pairs(ESP.NameTags) do
        pcall(function() tag:Destroy() end)
    end
    for _, tracer in pairs(ESP.TracersTable) do
        pcall(function() tracer:Destroy() end)
    end
    ESP.BoxesTable = {}
    ESP.NameTags = {}
    ESP.TracersTable = {}
    ESP.HealthBars = {}
end


------------------------------------------------------------------
-- MAIN ESP UPDATE
------------------------------------------------------------------

local function UpdateESP()
    if not ESP.Enabled or not ESP.Armed then
        if next(ESP.BoxesTable) ~= nil or next(ESP.NameTags) ~= nil then
            ClearAllESP()
        end
        return
    end
    
    local cameraPos = Camera and Camera.CFrame.Position or Vector3.new()
    local screenSize = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character
            local humanoid = character and character:FindFirstChild("Humanoid")
            
            if character and humanoid and humanoid.Health > 0 then
                local rootPart = character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local distance = (rootPart.Position - cameraPos).Magnitude
                    
                    -- Check distance limit
                    if distance <= ESP.MaxDistance then
                        -- Create Box
                        if ESP.Boxes and not ESP.BoxesTable[character] then
                            local box = CreateBox(character, player)
                            ESP.BoxesTable[character] = box
                        elseif ESP.Boxes and ESP.BoxesTable[character] then
                            UpdateBoxSize(ESP.BoxesTable[character], character)
                        elseif not ESP.Boxes and ESP.BoxesTable[character] then
                            RemoveESPForCharacter(character)
                        end
                        
                        -- Create Name Tag
                        if (ESP.Names or ESP.Health or ESP.Distance) and not ESP.NameTags[character] then
                            local nameTag = CreateNameTag(character, player)
                            if nameTag then
                                ESP.NameTags[character] = nameTag
                                
                                -- Set initial health
                                if ESP.Health then
                                    UpdateHealthBar(nameTag, humanoid.Health, humanoid.MaxHealth)
                                end
                            end
                        elseif ESP.NameTags[character] then
                            local nameTag = ESP.NameTags[character]
                            
                            -- Update name text
                            if ESP.Names and nameTag:FindFirstChild("NameLabel") then
                                local nameLabel = nameTag.NameLabel
                                nameLabel.Visible = ESP.Names
                                if nameLabel.Text ~= GetPlayerName(player) then
                                    nameLabel.Text = GetPlayerName(player)
                                end
                            elseif not ESP.Names and nameTag:FindFirstChild("NameLabel") then
                                nameTag.NameLabel.Visible = false
                            end
                            
                            -- Update health bar
                            if ESP.Health then
                                UpdateHealthBar(nameTag, humanoid.Health, humanoid.MaxHealth)
                                if nameTag:FindFirstChild("HealthBg") then
                                    nameTag.HealthBg.Visible = true
                                end
                            elseif nameTag:FindFirstChild("HealthBg") then
                                nameTag.HealthBg.Visible = false
                            end
                            
                            -- Update distance
                            if ESP.Distance then
                                UpdateDistanceText(nameTag, distance)
                                if nameTag:FindFirstChild("DistanceLabel") then
                                    nameTag.DistanceLabel.Visible = true
                                end
                            elseif nameTag:FindFirstChild("DistanceLabel") then
                                nameTag.DistanceLabel.Visible = false
                            end
                        end
                        
                        -- Create Tracer
                        if ESP.Tracers and not ESP.TracersTable[character] then
                            local tracer = CreateTracer(character, player)
                            ESP.TracersTable[character] = tracer
                        elseif ESP.Tracers and ESP.TracersTable[character] then
                            UpdateTracer(ESP.TracersTable[character], character)
                        elseif not ESP.Tracers and ESP.TracersTable[character] then
                            pcall(function() ESP.TracersTable[character]:Destroy() end)
                            ESP.TracersTable[character] = nil
                        end
                    else
                        -- Out of range, remove ESP
                        RemoveESPForCharacter(character)
                    end
                end
            else
                RemoveESPForCharacter(character)
            end
        end
    end
end


------------------------------------------------------------------
-- UI CREATION (ORGANIZED TABS)
------------------------------------------------------------------

local screenGui
local mainFrame
local resizeHandle

local currentTab = "visual"

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
    
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ESP_UI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    
    mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, Settings.UISizeX, 0, Settings.UISizeY)
    mainFrame.Position = UDim2.new(0, 20, 0, 20)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = screenGui
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)
    
    -- Title Bar
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 35)
    title.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    title.Text = "MATRIX HUB ESP"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.BorderSizePixel = 0
    title.Parent = mainFrame
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)
    
    -- Resize Handle
    resizeHandle = Instance.new("Frame")
    resizeHandle.Size = UDim2.new(0, 14, 0, 14)
    resizeHandle.AnchorPoint = Vector2.new(1, 1)
    resizeHandle.Position = UDim2.new(1, 0, 1, 0)
    resizeHandle.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    resizeHandle.BorderSizePixel = 0
    resizeHandle.Parent = mainFrame
    Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 3)
    
    -- Tab Buttons
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, 0, 0, 35)
    tabBar.Position = UDim2.new(0, 0, 0, 35)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = mainFrame
    
    local tabs = {"VISUAL", "COLORS", "PLAYER", "AIM"}
    local tabButtons = {}
    local tabContents = {}
    
    for i, tabName in ipairs(tabs) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.25, -5, 1, -5)
        btn.Position = UDim2.new((i-1) * 0.25, 2 + ((i-1) * 3), 0, 2)
        btn.BackgroundColor3 = (i == 1) and Color3.fromRGB(60, 120, 200) or Color3.fromRGB(45, 45, 55)
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextScaled = true
        btn.Font = Enum.Font.GothamBold
        btn.Text = tabName
        btn.BorderSizePixel = 0
        btn.Parent = tabBar
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
        
        tabButtons[tabName] = btn
        
        -- Tab Content
        local content = Instance.new("ScrollingFrame")
        content.Size = UDim2.new(1, -10, 1, -85)
        content.Position = UDim2.new(0, 5, 0, 75)
        content.BackgroundTransparency = 1
        content.BorderSizePixel = 0
        content.ScrollBarThickness = 6
        content.Visible = (i == 1)
        content.Parent = mainFrame
        
        tabContents[tabName] = content
    end
    
    -- VISUAL TAB CONTENT
    local visualContent = tabContents["VISUAL"]
    
    local function AddSection(parent, title, yPos)
        local section = Instance.new("Frame")
        section.Size = UDim2.new(1, -10, 0, 60)
        section.Position = UDim2.new(0, 5, 0, yPos)
        section.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        section.BorderSizePixel = 0
        section.Parent = parent
        Instance.new("UICorner", section).CornerRadius = UDim.new(0, 6)
        
        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, 0, 0, 25)
        titleLabel.BackgroundTransparency = 1
        titleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        titleLabel.Text = title
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.TextSize = 14
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.Parent = section
        
        return section
    end
    
    local function AddToggle(parent, labelText, getValue, setValue, yPos)
        local toggle = Instance.new("TextButton")
        toggle.Size = UDim2.new(0.48, 0, 0, 28)
        toggle.Position = UDim2.new(0.02, 0, 0, yPos)
        toggle.BackgroundColor3 = getValue() and Color3.fromRGB(60, 120, 200) or Color3.fromRGB(45, 45, 55)
        toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
        toggle.Text = labelText .. ": " .. (getValue() and "ON" or "OFF")
        toggle.TextScaled = true
        toggle.Font = Enum.Font.Gotham
        toggle.BorderSizePixel = 0
        toggle.Parent = parent
        Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 4)
        
        toggle.MouseButton1Click:Connect(function()
            setValue(not getValue())
            toggle.BackgroundColor3 = getValue() and Color3.fromRGB(60, 120, 200) or Color3.fromRGB(45, 45, 55)
            toggle.Text = labelText .. ": " .. (getValue() and "ON" or "OFF")
            SaveSettings()
        end)
        
        return toggle
    end
    
    local function AddSlider(parent, labelText, getValue, setValue, minVal, maxVal, yPos)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(0.96, 0, 0, 50)
        container.Position = UDim2.new(0.02, 0, 0, yPos)
        container.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        container.BorderSizePixel = 0
        container.Parent = parent
        Instance.new("UICorner", container).CornerRadius = UDim.new(0, 6)
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 20)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(200, 200, 200)
        label.Text = labelText .. ": " .. math.floor(getValue() * 100) .. "%"
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextSize = 12
        label.Font = Enum.Font.Gotham
        label.Parent = container
        
        local sliderBg = Instance.new("Frame")
        sliderBg.Size = UDim2.new(1, -10, 0, 8)
        sliderBg.Position = UDim2.new(0, 5, 0, 25)
        sliderBg.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        sliderBg.BorderSizePixel = 0
        sliderBg.Parent = container
        Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(1, 0)
        
        local sliderFill = Instance.new("Frame")
        sliderFill.Size = UDim2.new(getValue(), 0, 1, 0)
        sliderFill.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
        sliderFill.BorderSizePixel = 0
        sliderFill.Parent = sliderBg
        Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(1, 0)
        
        local dragging = false
        local function updateSlider()
            local mouse = UserInputService:GetMouseLocation()
            local relX = mouse.X - sliderBg.AbsolutePosition.X
            local t = math.clamp(relX / sliderBg.AbsoluteSize.X, 0, 1)
            local newVal = minVal + (maxVal - minVal) * t
            setValue(newVal)
            sliderFill.Size = UDim2.new(t, 0, 1, 0)
            label.Text = labelText .. ": " .. math.floor(newVal * 100) .. "%"
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
        
        return container
    end
    
    -- Visual Tab Items
    local visualSection = AddSection(visualContent, "VISUAL ELEMENTS", 5)
    
    AddToggle(visualSection, "ESP System", function() return ESP.Enabled end, function(v) ESP.Enabled = v end, 28)
    AddToggle(visualSection, "ESP Armed (L)", function() return ESP.Armed end, function(v) ESP.Armed = v end, 60)
    
    local elementsSection = AddSection(visualContent, "ESP ELEMENTS", 75)
    
    AddToggle(elementsSection, "Boxes", function() return ESP.Boxes end, function(v) ESP.Boxes = v end, 28)
    AddToggle(elementsSection, "Names", function() return ESP.Names end, function(v) ESP.Names = v end, 60)
    AddToggle(elementsSection, "Health Bars", function() return ESP.Health end, function(v) ESP.Health = v end, 92)
    AddToggle(elementsSection, "Distance", function() return ESP.Distance end, function(v) ESP.Distance = v end, 124)
    AddToggle(elementsSection, "Tracers", function() return ESP.Tracers end, function(v) ESP.Tracers = v end, 156)
    
    local rangeSection = AddSection(visualContent, "RANGE SETTINGS", 230)
    
    AddSlider(rangeSection, "Max Distance", function() return ESP.MaxDistance / 500 end, function(v) ESP.MaxDistance = v * 500 end, 0, 500, 28)
    
    -- COLORS TAB CONTENT
    local colorsContent = tabContents["COLORS"]
    
    local boxColorSection = AddSection(colorsContent, "BOX COLOR", 5)
    local nameColorSection = AddSection(colorsContent, "NAME COLOR", 75)
    local healthColorSection = AddSection(colorsContent, "HEALTH COLOR", 145)
    local tracerColorSection = AddSection(colorsContent, "TRACER COLOR", 215)
    
    local function AddColorButton(parent, labelText, getColor, setColor, yPos)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(0.96, 0, 0, 36)
        container.Position = UDim2.new(0.02, 0, 0, yPos)
        container.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        container.BorderSizePixel = 0
        container.Parent = parent
        Instance.new("UICorner", container).CornerRadius = UDim.new(0, 6)
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.5, 0, 1, 0)
        label.Position = UDim2.new(0.05, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(200, 200, 200)
        label.Text = labelText
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextSize = 12
        label.Font = Enum.Font.Gotham
        label.Parent = container
        
        local colorPreview = Instance.new("Frame")
        colorPreview.Size = UDim2.new(0, 40, 0, 28)
        colorPreview.Position = UDim2.new(0.75, 0, 0.11, 0)
        colorPreview.BackgroundColor3 = getColor()
        colorPreview.BorderSizePixel = 1
        colorPreview.BorderColor3 = Color3.fromRGB(100, 100, 100)
        colorPreview.Parent = container
        Instance.new("UICorner", colorPreview).CornerRadius = UDim.new(0, 4)
        
        -- Simple color presets
        local presets = {
            {Color3.fromRGB(255, 0, 0), "Red"},
            {Color3.fromRGB(0, 255, 0), "Green"},
            {Color3.fromRGB(0, 0, 255), "Blue"},
            {Color3.fromRGB(255, 255, 0), "Yellow"},
            {Color3.fromRGB(255, 0, 255), "Purple"},
            {Color3.fromRGB(0, 255, 255), "Cyan"}
        }
        
        for i, preset in ipairs(presets) do
            local presetBtn = Instance.new("TextButton")
            presetBtn.Size = UDim2.new(0, 30, 0, 20)
            presetBtn.Position = UDim2.new(0, 5 + ((i-1) * 35), 0, 50)
            presetBtn.BackgroundColor3 = preset[1]
            presetBtn.Text = ""
            presetBtn.BorderSizePixel = 1
            presetBtn.BorderColor3 = Color3.fromRGB(100, 100, 100)
            presetBtn.Parent = container
            Instance.new("UICorner", presetBtn).CornerRadius = UDim.new(0, 3)
            
            presetBtn.MouseButton1Click:Connect(function()
                setColor(preset[1])
                colorPreview.BackgroundColor3 = preset[1]
                SaveSettings()
                -- Update existing ESP elements
                if labelText == "Box" then
                    for _, box in pairs(ESP.BoxesTable) do
                        box.Color3 = preset[1]
                    end
                elseif labelText == "Tracer" then
                    for _, tracer in pairs(ESP.TracersTable) do
                        tracer.Color3 = preset[1]
                    end
                elseif labelText == "Name" then
                    for _, tag in pairs(ESP.NameTags) do
                        if tag:FindFirstChild("NameLabel") then
                            tag.NameLabel.TextColor3 = preset[1]
                        end
                    end
                end
            end)
        end
        
        return container
    end
    
    AddColorButton(boxColorSection, "Box", function() return ESP.BoxColor end, function(v) ESP.BoxColor = v end, 28)
    AddColorButton(nameColorSection, "Name", function() return ESP.NameColor end, function(v) ESP.NameColor = v end, 28)
    AddColorButton(healthColorSection, "Health", function() return ESP.HealthColor end, function(v) ESP.HealthColor = v end, 28)
    AddColorButton(tracerColorSection, "Tracer", function() return ESP.TracerColor end, function(v) ESP.TracerColor = v end, 28)
    
    -- Transparency sliders
    local transSection = AddSection(colorsContent, "TRANSPARENCY", 300)
    AddSlider(transSection, "Box Transparency", function() return ESP.BoxTransparency end, function(v) ESP.BoxTransparency = v end, 0, 1, 28)
    AddSlider(transSection, "Fill Transparency", function() return ESP.FillTransparency end, function(v) ESP.FillTransparency = v end, 0, 1, 85)
    
    -- PLAYER TAB CONTENT
    local playerContent = tabContents["PLAYER"]
    
    local walkSpeedSection = AddSection(playerContent, "MOVEMENT", 5)
    AddSlider(walkSpeedSection, "Walk Speed", function() return (Settings.WalkSpeed - 1) / 199 end, 
        function(v) 
            Settings.WalkSpeed = math.floor(1 + v * 199)
            if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.WalkSpeed = Settings.WalkSpeed
            end
            SaveSettings()
        end, 0, 1, 28)
    
    AddSlider(walkSpeedSection, "Jump Power", function() return (Settings.JumpPower - 1) / 199 end,
        function(v)
            Settings.JumpPower = math.floor(1 + v * 199)
            if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.JumpPower = Settings.JumpPower
            end
            SaveSettings()
        end, 0, 1, 85)
    
    local namePrefSection = AddSection(playerContent, "NAME PREFERENCES", 155)
    AddToggle(namePrefSection, "Use Display Names", function() return ESP.UseDisplayNames end, function(v) ESP.UseDisplayNames = v; SaveSettings() end, 28)
    
    -- Kill Script button
    local killBtn = Instance.new("TextButton")
    killBtn.Size = UDim2.new(0.96, 0, 0, 40)
    killBtn.Position = UDim2.new(0.02, 0, 1, -50)
    killBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
    killBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    killBtn.Text = "KILL SCRIPT"
    killBtn.TextScaled = true
    killBtn.Font = Enum.Font.GothamBold
    killBtn.BorderSizePixel = 0
    killBtn.Parent = playerContent
    Instance.new("UICorner", killBtn).CornerRadius = UDim.new(0, 6)
    
    killBtn.MouseButton1Click:Connect(function()
        Running = false
        ClearAllESP()
        if screenGui then
            screenGui:Destroy()
        end
        for _, conn in ipairs(Connections) do
            pcall(function() conn:Disconnect() end)
        end
    end)
    
    -- AIM TAB CONTENT
    local aimContent = tabContents["AIM"]
    
    local aimSection = AddSection(aimContent, "AIM ASSIST", 5)
    AddToggle(aimSection, "Aim Assist", function() return AimAssist.Enabled end, function(v) AimAssist.Enabled = v; SaveSettings() end, 28)
    AddSlider(aimSection, "Smoothness", function() return AimAssist.Strength end, function(v) AimAssist.Strength = v; SaveSettings() end, 0, 1, 75)
    
    local triggerSection = AddSection(aimContent, "TRIGGERBOT", 145)
    
    local triggerInfo = Instance.new("TextLabel")
    triggerInfo.Size = UDim2.new(0.96, 0, 0, 40)
    triggerInfo.Position = UDim2.new(0.02, 0, 0, 30)
    triggerInfo.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    triggerInfo.TextColor3 = Color3.fromRGB(200, 200, 200)
    triggerInfo.Text = "Hold V to activate\nInstant fire when aiming at enemy"
    triggerInfo.TextScaled = true
    triggerInfo.Font = Enum.Font.Gotham
    triggerInfo.Parent = triggerSection
    Instance.new("UICorner", triggerInfo).CornerRadius = UDim.new(0, 6)
    
    -- Tab switching
    for tabName, btn in pairs(tabButtons) do
        btn.MouseButton1Click:Connect(function()
            currentTab = tabName:lower()
            for name, content in pairs(tabContents) do
                content.Visible = (name == tabName)
            end
            for _, button in pairs(tabButtons) do
                button.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
            end
            btn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
        end)
    end
end

createUI()


------------------------------------------------------------------
-- RESIZABLE UI
------------------------------------------------------------------

do
    local resizing = false
    local startMousePos
    local startSize
    local oldDraggable
    
    local function setDragging(state)
        if mainFrame then
            mainFrame.Draggable = state
        end
    end
    
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
                mainFrame.Draggable = oldDraggable
            end
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if not resizing then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        
        local currentPos = UserInputService:GetMouseLocation()
        local dx = currentPos.X - startMousePos.X
        local dy = currentPos.Y - startMousePos.Y
        local newW = math.max(380, startSize.X.Offset + dx)
        local newH = math.max(400, startSize.Y.Offset + dy)
        mainFrame.Size = UDim2.new(0, newW, 0, newH)
        SaveSettings()
    end)
end


------------------------------------------------------------------
-- INPUT HANDLERS
------------------------------------------------------------------

table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    
    if input.KeyCode == Enum.KeyCode.RightShift then
        if mainFrame then
            mainFrame.Visible = not mainFrame.Visible
        end
    end
    
    if input.KeyCode == Enum.KeyCode.L then
        ESP.Armed = not ESP.Armed
    end
    
    if input.KeyCode == Enum.KeyCode.C then
        AimAssist.Enabled = not AimAssist.Enabled
        SaveSettings()
    end
    
    if input.KeyCode == Enum.KeyCode.V then
        TriggerHeld = true
        TriggerState = "HOLDING"
    end
end))


table.insert(Connections, UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.V then
        TriggerHeld = false
        if TriggerState ~= "DISARMED" then
            TriggerState = "ARMED"
        end
    end
end))


------------------------------------------------------------------
-- TRIGGERBOT
------------------------------------------------------------------

local function DetectCenterTarget()
    if not TriggerHeld then
        if TriggerState == "DISARMED" then
            TriggerState = "ARMED"
        end
        return
    end
    
    TriggerState = "HOLDING"
    
    if not Camera then
        Camera = workspace.CurrentCamera
        if not Camera then return end
    end
    
    local mousePos = UserInputService:GetMouseLocation()
    local ray = Camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    
    local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
    
    if result and result.Instance then
        local model = result.Instance:FindFirstAncestorOfClass("Model")
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
end


------------------------------------------------------------------
-- AIM ASSIST
------------------------------------------------------------------

local AAFOV = 400

local function IsCharacterValid(char)
    if not char then return false end
    local humanoid = char:FindFirstChild("Humanoid")
    if not humanoid then return false end
    if humanoid.Health <= 0 then return false end
    return true
end

local function GetTargetPosition(char)
    if not char then return nil end
    local head = char:FindFirstChild("Head")
    if head then return head.Position end
    local root = char:FindFirstChild("HumanoidRootPart")
    if root then return root.Position + Vector3.new(0, 1.5, 0) end
    return nil
end

function AimAssist:Update(deltaTime)
    if not self.Enabled then
        self.CurrentTarget = nil
        return
    end
    
    if not Camera then return end
    
    local screenCenter = Camera.ViewportSize / 2
    local bestTarget = nil
    local bestDistance = math.huge
    local bestTargetPos = nil
    
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            if IsCharacterValid(char) then
                local targetPos = GetTargetPosition(char)
                if targetPos then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPos)
                    if onScreen then
                        local dx = screenPos.X - screenCenter.X
                        local dy = screenPos.Y - screenCenter.Y
                        local dist = math.sqrt(dx*dx + dy*dy)
                        
                        if dist < bestDistance and dist <= AAFOV then
                            bestDistance = dist
                            bestTarget = plr
                            bestTargetPos = targetPos
                        end
                    end
                end
            end
        end
    end
    
    self.CurrentTarget = bestTarget
    
    if bestTargetPos then
        local currentCFrame = Camera.CFrame
        local targetCFrame = CFrame.lookAt(currentCFrame.Position, bestTargetPos)
        
        local smoothness = self.Strength
        local factor = 1 - smoothness
        local dtFactor = 1 - (1 - factor) ^ (deltaTime * 60)
        dtFactor = math.clamp(dtFactor, 0, 1)
        
        Camera.CFrame = currentCFrame:Lerp(targetCFrame, dtFactor)
    end
end


------------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------------

table.insert(Connections, RunService.RenderStepped:Connect(function(dt)
    if not Running then return end
    
    UpdateESP()
    DetectCenterTarget()
    AimAssist:Update(dt)
end))
