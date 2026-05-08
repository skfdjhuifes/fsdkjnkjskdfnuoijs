--[[
    Jayden's Script Hub
    Controls: L = Arm/Disarm ESP, V = Triggerbot (Hold), RightShift = Hide UI
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
local TriggerHeld = false
local TriggerState = "DISARMED"
local UIVisible = true

-- ESP Settings
local ESP = {
    Enabled = false,
    Armed = false,
    -- Visual elements
    Boxes = true,
    Names = true,
    Health = true,
    Distance = true,
    Tracers = false,
    -- Colors
    BoxColor = Color3.fromRGB(255, 0, 0),
    NameColor = Color3.fromRGB(255, 255, 255),
    HealthColor = Color3.fromRGB(0, 255, 0),
    TracerColor = Color3.fromRGB(255, 0, 0),
    -- Transparency
    BoxTransparency = 0.5,
    FillTransparency = 0.7,
    -- Range
    MaxDistance = 500,
    UseDisplayNames = true,
    -- Storage
    BoxesTable = {},
    NameTags = {},
    TracersTable = {},
}

-- Aim Assist Settings
local AimAssist = {
    Enabled = false,
    Strength = 0.5,
    CurrentTarget = nil
}

-- Player Settings
local PlayerSettings = {
    WalkSpeed = 16,
    JumpPower = 50
}


------------------------------------------------------------------
-- UTILITY FUNCTIONS
------------------------------------------------------------------

local function GetPlayerName(player)
    if ESP.UseDisplayNames then
        return player.DisplayName or player.Name
    end
    return player.Name
end

local function WorldToScreen(position)
    if not Camera then return nil end
    local vector, onScreen = Camera:WorldToViewportPoint(position)
    if onScreen and vector.Z > 0 then
        return Vector2.new(vector.X, vector.Y), vector.Z
    end
    return nil, nil
end

local function ApplySpeedSettings()
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChild("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = PlayerSettings.WalkSpeed
        humanoid.JumpPower = PlayerSettings.JumpPower
    end
end

LocalPlayer.CharacterAdded:Connect(function(char)
    char:WaitForChild("Humanoid")
    ApplySpeedSettings()
end)


------------------------------------------------------------------
-- ESP DRAWING FUNCTIONS
------------------------------------------------------------------

local function CreateBox(character, player)
    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
    if not rootPart then return nil end
    
    local box = Instance.new("BoxHandleAdornment")
    box.Name = "ESP_Box_" .. player.Name
    box.Adornee = rootPart
    box.Size = Vector3.new(2.5, 5, 2.5)
    box.Color3 = ESP.BoxColor
    box.Transparency = ESP.BoxTransparency
    box.AlwaysOnTop = true
    box.Visible = true
    box.ZIndex = 0
    box.Parent = game:GetService("CoreGui")
    return box
end

local function CreateTracer(character, player)
    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
    if not rootPart then return nil end
    
    local tracer = Instance.new("LineHandleAdornment")
    tracer.Name = "ESP_Tracer_" .. player.Name
    tracer.Adornee = rootPart
    tracer.Color3 = ESP.TracerColor
    tracer.Thickness = 1
    tracer.Transparency = 0.3
    tracer.AlwaysOnTop = true
    tracer.Visible = true
    tracer.ZIndex = 0
    tracer.Parent = game:GetService("CoreGui")
    return tracer
end

local function CreateNameTag(character, player)
    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
    if not rootPart then return nil end
    
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_NameTag_" .. player.Name
    billboard.Adornee = rootPart
    billboard.Size = UDim2.new(0, 200, 0, 55)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.ResetOnSpawn = false
    billboard.Parent = game:GetService("CoreGui")
    
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
    healthBg.Visible = ESP.Health
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
    distLabel.Visible = ESP.Distance
    distLabel.Text = "0m"
    distLabel.Parent = billboard
    
    return billboard
end

local function UpdateHealthBar(billboard, health, maxHealth)
    if billboard and billboard:FindFirstChild("HealthBg") then
        local healthBg = billboard.HealthBg
        local healthFill = healthBg:FindFirstChild("HealthFill")
        if healthFill then
            local percent = math.clamp(health / maxHealth, 0, 1)
            healthFill.Size = UDim2.new(percent, 0, 1, 0)
            
            -- Color based on health percentage
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

local function UpdateDistanceText(billboard, distance)
    if billboard and billboard:FindFirstChild("DistanceLabel") then
        billboard.DistanceLabel.Text = math.floor(distance + 0.5) .. "m"
    end
end

local function UpdateTracerPosition(tracer, character)
    if not tracer or not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
    if rootPart and Camera then
        local screenPos = WorldToScreen(rootPart.Position)
        if screenPos then
            local screenSize = Camera.ViewportSize
            tracer.From = Vector2.new(screenSize.X / 2, screenSize.Y)
            tracer.To = screenPos
        end
    end
end

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
    
    if not Camera then
        Camera = workspace.CurrentCamera
        return
    end
    
    local cameraPos = Camera.CFrame.Position
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character
            local humanoid = character and character:FindFirstChild("Humanoid")
            
            if character and humanoid and humanoid.Health > 0 then
                local rootPart = character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local distance = (rootPart.Position - cameraPos).Magnitude
                    
                    if distance <= ESP.MaxDistance then
                        -- Boxes
                        if ESP.Boxes then
                            if not ESP.BoxesTable[character] then
                                local box = CreateBox(character, player)
                                if box then
                                    ESP.BoxesTable[character] = box
                                end
                            else
                                UpdateBoxSize(ESP.BoxesTable[character], character)
                            end
                        elseif ESP.BoxesTable[character] then
                            RemoveESPForCharacter(character)
                        end
                        
                        -- Name Tags
                        if ESP.Names or ESP.Health or ESP.Distance then
                            if not ESP.NameTags[character] then
                                local nameTag = CreateNameTag(character, player)
                                if nameTag then
                                    ESP.NameTags[character] = nameTag
                                end
                            elseif ESP.NameTags[character] then
                                local tag = ESP.NameTags[character]
                                
                                if tag:FindFirstChild("NameLabel") then
                                    tag.NameLabel.Text = GetPlayerName(player)
                                    tag.NameLabel.Visible = ESP.Names
                                end
                                
                                if tag:FindFirstChild("HealthBg") then
                                    tag.HealthBg.Visible = ESP.Health
                                    if ESP.Health then
                                        UpdateHealthBar(tag, humanoid.Health, humanoid.MaxHealth)
                                    end
                                end
                                
                                if tag:FindFirstChild("DistanceLabel") then
                                    tag.DistanceLabel.Visible = ESP.Distance
                                    if ESP.Distance then
                                        UpdateDistanceText(tag, distance)
                                    end
                                end
                            end
                        elseif ESP.NameTags[character] then
                            RemoveESPForCharacter(character)
                        end
                        
                        -- Tracers
                        if ESP.Tracers then
                            if not ESP.TracersTable[character] then
                                local tracer = CreateTracer(character, player)
                                if tracer then
                                    ESP.TracersTable[character] = tracer
                                end
                            else
                                UpdateTracerPosition(ESP.TracersTable[character], character)
                            end
                        elseif ESP.TracersTable[character] then
                            RemoveESPForCharacter(character)
                        end
                    else
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
-- TRIGGERBOT
------------------------------------------------------------------

local function DetectCenterTarget()
    if not TriggerHeld then
        TriggerState = "ARMED"
        return
    end
    
    TriggerState = "HOLDING"
    
    if not Camera then
        Camera = workspace.CurrentCamera
        return
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
            end
        end
    end
end


------------------------------------------------------------------
-- AIM ASSIST
------------------------------------------------------------------

local AAFOV = 400

local function IsCharacterValid(char)
    if not char then return false end
    local humanoid = char:FindFirstChild("Humanoid")
    return humanoid and humanoid.Health > 0
end

local function GetTargetPosition(char)
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
    
    if not Camera then
        Camera = workspace.CurrentCamera
        return
    end
    
    local screenCenter = Camera.ViewportSize / 2
    local bestDist = math.huge
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
                        if dist < bestDist and dist <= AAFOV then
                            bestDist = dist
                            bestTargetPos = targetPos
                        end
                    end
                end
            end
        end
    end
    
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
-- UI CREATION (SIMPLE & RELIABLE)
------------------------------------------------------------------

local screenGui
local mainFrame
local currentTab = "main"

local function createUI()
    -- Clean up old UI
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        local old = pg:FindFirstChild("JaydenUI")
        if old then old:Destroy() end
    end
    
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "JaydenUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    
    -- Main Frame
    mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 400, 0, 500)
    mainFrame.Position = UDim2.new(0, 10, 0, 10)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = screenGui
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)
    
    -- Title Bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 35)
    titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -40, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Jayden's Script Hub"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextSize = 18
    title.Font = Enum.Font.GothamBold
    title.Parent = titleBar
    
    -- Close Button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 1, -6)
    closeBtn.Position = UDim2.new(1, -35, 0, 3)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 14
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = titleBar
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)
    
    closeBtn.MouseButton1Click:Connect(function()
        Running = false
        ClearAllESP()
        if screenGui then screenGui:Destroy() end
        for _, conn in ipairs(Connections) do
            pcall(function() conn:Disconnect() end)
        end
    end)
    
    -- Tab Bar
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, 0, 0, 35)
    tabBar.Position = UDim2.new(0, 0, 0, 35)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = mainFrame
    
    local tabs = {"ESP", "AIM", "PLAYER"}
    local tabButtons = {}
    local tabContents = {}
    
    for i, tabName in ipairs(tabs) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.33, -2, 1, -6)
        btn.Position = UDim2.new((i-1) * 0.33, 2 + ((i-1) * 2), 0, 3)
        btn.BackgroundColor3 = (i == 1) and Color3.fromRGB(60, 120, 200) or Color3.fromRGB(45, 45, 55)
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Text = tabName
        btn.TextSize = 14
        btn.Font = Enum.Font.GothamBold
        btn.BorderSizePixel = 0
        btn.Parent = tabBar
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        
        tabButtons[tabName] = btn
        
        -- Content Frame
        local content = Instance.new("ScrollingFrame")
        content.Size = UDim2.new(1, -10, 1, -85)
        content.Position = UDim2.new(0, 5, 0, 75)
        content.BackgroundTransparency = 1
        content.BorderSizePixel = 0
        content.ScrollBarThickness = 6
        content.CanvasSize = UDim2.new(0, 0, 0, 0)
        content.Visible = (i == 1)
        content.Parent = mainFrame
        
        tabContents[tabName] = content
    end
    
    -- Helper function to add sections
    local function AddSection(parent, title, yPos)
        local section = Instance.new("Frame")
        section.Size = UDim2.new(1, -10, 0, 50)
        section.Position = UDim2.new(0, 5, 0, yPos)
        section.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        section.BorderSizePixel = 0
        section.Parent = parent
        Instance.new("UICorner", section).CornerRadius = UDim.new(0, 6)
        
        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, -10, 0, 22)
        titleLabel.Position = UDim2.new(0, 5, 0, 0)
        titleLabel.BackgroundTransparency = 1
        titleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        titleLabel.Text = title
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.TextSize = 13
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.Parent = section
        
        return section, titleLabel
    end
    
    local function AddToggle(parent, labelText, getValue, setValue, yPos)
        local toggle = Instance.new("TextButton")
        toggle.Size = UDim2.new(0.48, 0, 0, 28)
        toggle.Position = UDim2.new(0.02, 0, 0, yPos)
        toggle.BackgroundColor3 = getValue() and Color3.fromRGB(60, 120, 200) or Color3.fromRGB(45, 45, 55)
        toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
        toggle.Text = labelText .. ": " .. (getValue() and "ON" or "OFF")
        toggle.TextSize = 12
        toggle.Font = Enum.Font.Gotham
        toggle.BorderSizePixel = 0
        toggle.Parent = parent
        Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 4)
        
        toggle.MouseButton1Click:Connect(function()
            setValue(not getValue())
            toggle.BackgroundColor3 = getValue() and Color3.fromRGB(60, 120, 200) or Color3.fromRGB(45, 45, 55)
            toggle.Text = labelText .. ": " .. (getValue() and "ON" or "OFF")
        end)
        
        return toggle
    end
    
    local function AddSlider(parent, labelText, getValue, setValue, minVal, maxVal, yPos, isInt)
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
        label.Text = labelText .. ": " .. tostring(getValue())
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextSize = 12
        label.Font = Enum.Font.Gotham
        label.Parent = container
        
        local sliderBg = Instance.new("Frame")
        sliderBg.Size = UDim2.new(1, -10, 0, 6)
        sliderBg.Position = UDim2.new(0, 5, 0, 28)
        sliderBg.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        sliderBg.BorderSizePixel = 0
        sliderBg.Parent = container
        Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(1, 0)
        
        local t = (getValue() - minVal) / (maxVal - minVal)
        local sliderFill = Instance.new("Frame")
        sliderFill.Size = UDim2.new(t, 0, 1, 0)
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
            if isInt then newVal = math.floor(newVal) end
            setValue(newVal)
            sliderFill.Size = UDim2.new(t, 0, 1, 0)
            label.Text = labelText .. ": " .. tostring(getValue())
        end
        
        sliderBg.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                mainFrame.Draggable = false
                updateSlider()
            end
        end)
        
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
                mainFrame.Draggable = true
            end
        end)
        
        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                updateSlider()
            end
        end)
        
        return container
    end
    
    local function AddColorButton(parent, labelText, getColor, setColor, yPos)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(0.96, 0, 0, 40)
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
        colorPreview.Size = UDim2.new(0, 50, 0, 28)
        colorPreview.Position = UDim2.new(0.7, 0, 0.15, 0)
        colorPreview.BackgroundColor3 = getColor()
        colorPreview.BorderSizePixel = 1
        colorPreview.BorderColor3 = Color3.fromRGB(100, 100, 100)
        colorPreview.Parent = container
        Instance.new("UICorner", colorPreview).CornerRadius = UDim.new(0, 4)
        
        -- Color presets
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
            presetBtn.Size = UDim2.new(0, 28, 0, 22)
            presetBtn.Position = UDim2.new(0, 5 + ((i-1) * 33), 0, 52)
            presetBtn.BackgroundColor3 = preset[1]
            presetBtn.Text = ""
            presetBtn.BorderSizePixel = 0
            presetBtn.Parent = container
            Instance.new("UICorner", presetBtn).CornerRadius = UDim.new(0, 3)
            
            presetBtn.MouseButton1Click:Connect(function()
                setColor(preset[1])
                colorPreview.BackgroundColor3 = preset[1]
            end)
        end
        
        return container
    end
    
    -- ========== ESP TAB ==========
    local espContent = tabContents["ESP"]
    local canvasY = 5
    
    local visSection, _ = AddSection(espContent, "VISUAL ELEMENTS", canvasY)
    canvasY = canvasY + 55
    
    AddToggle(visSection, "ESP System", function() return ESP.Enabled end, function(v) ESP.Enabled = v end, 28)
    AddToggle(visSection, "ESP Armed (L)", function() return ESP.Armed end, function(v) ESP.Armed = v end, 60)
    
    local elemSection, _ = AddSection(espContent, "ESP ELEMENTS", canvasY)
    canvasY = canvasY + 55
    
    AddToggle(elemSection, "Boxes", function() return ESP.Boxes end, function(v) ESP.Boxes = v end, 28)
    AddToggle(elemSection, "Names", function() return ESP.Names end, function(v) ESP.Names = v end, 60)
    AddToggle(elemSection, "Health Bars", function() return ESP.Health end, function(v) ESP.Health = v end, 92)
    AddToggle(elemSection, "Distance", function() return ESP.Distance end, function(v) ESP.Distance = v end, 124)
    AddToggle(elemSection, "Tracers", function() return ESP.Tracers end, function(v) ESP.Tracers = v end, 156)
    
    local colorSection, _ = AddSection(espContent, "COLORS", canvasY)
    canvasY = canvasY + 55
    
    AddColorButton(colorSection, "Box Color", function() return ESP.BoxColor end, function(v) 
        ESP.BoxColor = v
        for _, box in pairs(ESP.BoxesTable) do
            pcall(function() box.Color3 = v end)
        end
    end, 28)
    
    AddColorButton(colorSection, "Name Color", function() return ESP.NameColor end, function(v)
        ESP.NameColor = v
        for _, tag in pairs(ESP.NameTags) do
            pcall(function() 
                if tag:FindFirstChild("NameLabel") then
                    tag.NameLabel.TextColor3 = v
                end
            end)
        end
    end, 75)
    
    local rangeSection, _ = AddSection(espContent, "RANGE & TRANSPARENCY", canvasY)
    canvasY = canvasY + 55
    
    AddSlider(rangeSection, "Max Distance", function() return ESP.MaxDistance end, function(v) ESP.MaxDistance = v end, 50, 1000, 28, true)
    AddSlider(rangeSection, "Box Transparency", function() return ESP.BoxTransparency end, function(v) 
        ESP.BoxTransparency = v
        for _, box in pairs(ESP.BoxesTable) do
            pcall(function() box.Transparency = v end)
        end
    end, 0, 1, 85, false)
    
    local miscSection, _ = AddSection(espContent, "MISCELLANEOUS", canvasY)
    canvasY = canvasY + 55
    
    AddToggle(miscSection, "Use Display Names", function() return ESP.UseDisplayNames end, function(v) ESP.UseDisplayNames = v end, 28)
    
    -- Update canvas size
    espContent.CanvasSize = UDim2.new(0, 0, 0, canvasY + 60)
    
    -- ========== AIM TAB ==========
    local aimContent = tabContents["AIM"]
    canvasY = 5
    
    local aimSection, _ = AddSection(aimContent, "AIM ASSIST", canvasY)
    canvasY = canvasY + 55
    
    AddToggle(aimSection, "Aim Assist", function() return AimAssist.Enabled end, function(v) AimAssist.Enabled = v end, 28)
    AddSlider(aimSection, "Smoothness", function() return AimAssist.Strength end, function(v) AimAssist.Strength = v end, 0, 1, 75, false)
    
    local triggerSection, _ = AddSection(aimContent, "TRIGGERBOT", canvasY)
    canvasY = canvasY + 55
    
    local triggerInfo = Instance.new("TextLabel")
    triggerInfo.Size = UDim2.new(0.96, 0, 0, 40)
    triggerInfo.Position = UDim2.new(0.02, 0, 0, 28)
    triggerInfo.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    triggerInfo.TextColor3 = Color3.fromRGB(200, 200, 200)
    triggerInfo.Text = "Hold V to activate\nInstant fire when aiming at enemy"
    triggerInfo.TextSize = 12
    triggerInfo.Font = Enum.Font.Gotham
    triggerInfo.Parent = triggerSection
    Instance.new("UICorner", triggerInfo).CornerRadius = UDim.new(0, 6)
    
    aimContent.CanvasSize = UDim2.new(0, 0, 0, canvasY + 80)
    
    -- ========== PLAYER TAB ==========
    local playerContent = tabContents["PLAYER"]
    canvasY = 5
    
    local moveSection, _ = AddSection(playerContent, "MOVEMENT", canvasY)
    canvasY = canvasY + 55
    
    AddSlider(moveSection, "Walk Speed", function() return PlayerSettings.WalkSpeed end, function(v) 
        PlayerSettings.WalkSpeed = v
        ApplySpeedSettings()
    end, 10, 250, 28, true)
    
    AddSlider(moveSection, "Jump Power", function() return PlayerSettings.JumpPower end, function(v)
        PlayerSettings.JumpPower = v
        ApplySpeedSettings()
    end, 10, 250, 85, true)
    
    playerContent.CanvasSize = UDim2.new(0, 0, 0, canvasY + 100)
    
    -- Tab switching
    for tabName, btn in pairs(tabButtons) do
        btn.MouseButton1Click:Connect(function()
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

-- Create the UI
createUI()


------------------------------------------------------------------
-- INPUT HANDLERS
------------------------------------------------------------------

table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    
    if input.KeyCode == Enum.KeyCode.RightShift then
        if mainFrame then
            UIVisible = not UIVisible
            mainFrame.Visible = UIVisible
        end
    end
    
    if input.KeyCode == Enum.KeyCode.L then
        ESP.Armed = not ESP.Armed
    end
    
    if input.KeyCode == Enum.KeyCode.C then
        AimAssist.Enabled = not AimAssist.Enabled
    end
    
    if input.KeyCode == Enum.KeyCode.V then
        TriggerHeld = true
    end
end))


table.insert(Connections, UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.V then
        TriggerHeld = false
    end
end))


------------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------------

table.insert(Connections, RunService.RenderStepped:Connect(function(dt)
    if not Running then return end
    
    UpdateESP()
    DetectCenterTarget()
    AimAssist:Update(dt)
end))

-- Apply initial settings
ApplySpeedSettings()

-- Print confirmation
print("Jayden's Script Hub Loaded Successfully!")
print("Controls: L = Arm ESP, V = Triggerbot, RightShift = Hide UI")
