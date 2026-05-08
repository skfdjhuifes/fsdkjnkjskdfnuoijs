--[[
    Jayden's Script Hub
    Controls: L = Arm/Disarm ESP, V = Triggerbot (Hold), RightShift = Hide UI
]]

-- Load LinoriaLib (You must have the library installed in your executor)
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- State
local Running = true
local TriggerHeld = false
local TriggerState = "DISARMED"

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

-- Apply speed settings
local function ApplySpeedSettings()
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChild("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = PlayerSettings.WalkSpeed
        humanoid.JumpPower = PlayerSettings.JumpPower
    end
end

-- Character added handler
LocalPlayer.CharacterAdded:Connect(function(char)
    char:WaitForChild("Humanoid")
    ApplySpeedSettings()
end)

-- Utility functions
local function GetPlayerName(player)
    return ESP.UseDisplayNames and (player.DisplayName or player.Name) or player.Name
end

local function WorldToScreen(position)
    if not Camera then return nil end
    local vector, onScreen = Camera:WorldToViewportPoint(position)
    if onScreen and vector.Z > 0 then
        return Vector2.new(vector.X, vector.Y), vector.Z
    end
    return nil, nil
end

-- ESP Drawing Functions
local function CreateBox(character, player)
    local box = Instance.new("BoxHandleAdornment")
    box.Name = "ESP_Box_" .. player.Name
    box.Adornee = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
    box.Size = Vector3.new(2.5, 5, 2.5)
    box.Color3 = ESP.BoxColor
    box.Transparency = ESP.BoxTransparency
    box.AlwaysOnTop = true
    box.Visible = true
    box.Parent = game:GetService("CoreGui")
    return box
end

local function CreateTracer(character, player)
    local tracer = Instance.new("LineHandleAdornment")
    tracer.Name = "ESP_Tracer_" .. player.Name
    tracer.Adornee = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
    tracer.Color3 = ESP.TracerColor
    tracer.Thickness = 1
    tracer.Transparency = 0.3
    tracer.AlwaysOnTop = true
    tracer.Visible = true
    tracer.Parent = game:GetService("CoreGui")
    return tracer
end

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
    billboard.Parent = game:GetService("CoreGui")
    
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0.4, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = ESP.NameColor
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextStrokeTransparency = 0.2
    nameLabel.Text = GetPlayerName(player)
    nameLabel.Parent = billboard
    
    local healthBg = Instance.new("Frame")
    healthBg.Name = "HealthBg"
    healthBg.Size = UDim2.new(0.8, 0, 0.15, 0)
    healthBg.Position = UDim2.new(0.1, 0, 0.45, 0)
    healthBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    healthBg.BorderSizePixel = 0
    healthBg.Visible = ESP.Health
    healthBg.Parent = billboard
    
    local healthFill = Instance.new("Frame")
    healthFill.Name = "HealthFill"
    healthFill.Size = UDim2.new(1, 0, 1, 0)
    healthFill.BackgroundColor3 = ESP.HealthColor
    healthFill.BorderSizePixel = 0
    healthFill.Parent = healthBg
    
    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "DistanceLabel"
    distLabel.Size = UDim2.new(1, 0, 0.3, 0)
    distLabel.Position = UDim2.new(0, 0, 0.65, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    distLabel.TextScaled = true
    distLabel.Font = Enum.Font.Gotham
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
        end
    end
end

local function UpdateDistanceText(billboard, distance)
    if billboard and billboard:FindFirstChild("DistanceLabel") then
        billboard.DistanceLabel.Text = math.floor(distance + 0.5) .. "m"
    end
end

local function RemoveESPForCharacter(character)
    if ESP.BoxesTable[character] then
        ESP.BoxesTable[character]:Destroy()
        ESP.BoxesTable[character] = nil
    end
    if ESP.NameTags[character] then
        ESP.NameTags[character]:Destroy()
        ESP.NameTags[character] = nil
    end
    if ESP.TracersTable[character] then
        ESP.TracersTable[character]:Destroy()
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

-- Main ESP Update
local function UpdateESP()
    if not ESP.Enabled or not ESP.Armed then
        if next(ESP.BoxesTable) ~= nil then
            ClearAllESP()
        end
        return
    end
    
    local cameraPos = Camera and Camera.CFrame.Position or Vector3.new()
    
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
                        if ESP.Boxes and not ESP.BoxesTable[character] then
                            ESP.BoxesTable[character] = CreateBox(character, player)
                        elseif not ESP.Boxes and ESP.BoxesTable[character] then
                            RemoveESPForCharacter(character)
                        end
                        
                        -- Name Tags
                        if (ESP.Names or ESP.Health or ESP.Distance) and not ESP.NameTags[character] then
                            ESP.NameTags[character] = CreateNameTag(character, player)
                        elseif ESP.NameTags[character] then
                            local tag = ESP.NameTags[character]
                            if tag:FindFirstChild("NameLabel") then
                                tag.NameLabel.Text = GetPlayerName(player)
                            end
                            if ESP.Health and tag:FindFirstChild("HealthBg") then
                                tag.HealthBg.Visible = true
                                UpdateHealthBar(tag, humanoid.Health, humanoid.MaxHealth)
                            elseif tag:FindFirstChild("HealthBg") then
                                tag.HealthBg.Visible = false
                            end
                            if ESP.Distance and tag:FindFirstChild("DistanceLabel") then
                                tag.DistanceLabel.Visible = true
                                UpdateDistanceText(tag, distance)
                            elseif tag:FindFirstChild("DistanceLabel") then
                                tag.DistanceLabel.Visible = false
                            end
                        end
                        
                        -- Tracers
                        if ESP.Tracers and not ESP.TracersTable[character] then
                            ESP.TracersTable[character] = CreateTracer(character, player)
                        elseif ESP.Tracers and ESP.TracersTable[character] then
                            local tracer = ESP.TracersTable[character]
                            local root = character:FindFirstChild("HumanoidRootPart")
                            if root then
                                local screenPos = WorldToScreen(root.Position)
                                if screenPos then
                                    local screenSize = Camera.ViewportSize
                                    tracer.From = Vector2.new(screenSize.X / 2, screenSize.Y)
                                    tracer.To = screenPos
                                end
                            end
                        elseif not ESP.Tracers and ESP.TracersTable[character] then
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

-- Triggerbot
local function DetectCenterTarget()
    if not TriggerHeld then
        TriggerState = "ARMED"
        return
    end
    
    TriggerState = "HOLDING"
    
    if not Camera then return end
    
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

-- Aim Assist
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
    return root and (root.Position + Vector3.new(0, 1.5, 0)) or nil
end

function AimAssist:Update(deltaTime)
    if not self.Enabled or not Camera then
        self.CurrentTarget = nil
        return
    end
    
    local screenCenter = Camera.ViewportSize / 2
    local bestDist = math.huge
    local bestTarget = nil
    local bestPos = nil
    
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
                            bestTarget = targetPos
                        end
                    end
                end
            end
        end
    end
    
    if bestTarget then
        local targetCF = CFrame.lookAt(Camera.CFrame.Position, bestTarget)
        local smooth = self.Strength
        local factor = 1 - (1 - (1 - smooth)) ^ (deltaTime * 60)
        Camera.CFrame = Camera.CFrame:Lerp(targetCF, math.clamp(factor, 0, 1))
    end
end

-- ========== LINORIALIB UI ==========
local Window = Library:CreateWindow("Jayden's Script Hub", { Resizable = true })
Window:SetSize(Vector2.new(450, 500))

-- ESP Tab
local ESPTab = Window:AddTab("ESP")
local VisualGroup = ESPTab:AddLeftGroupbox("Visual Elements")
local ColorGroup = ESPTab:AddRightGroupbox("Colors")
local RangeGroup = ESPTab:AddLeftGroupbox("Range")
local ToggleGroup = ESPTab:AddRightGroupbox("Toggles")

VisualGroup:AddToggle("ESPEnabled", { Text = "ESP System", Default = ESP.Enabled }):OnChanged(function(v)
    ESP.Enabled = v
    if not v then ClearAllESP() end
end)

VisualGroup:AddToggle("ESPArmed", { Text = "ESP Armed (L key)", Default = ESP.Armed }):OnChanged(function(v)
    ESP.Armed = v
end)

VisualGroup:AddToggle("ESPBoxes", { Text = "Boxes", Default = ESP.Boxes }):OnChanged(function(v)
    ESP.Boxes = v
    if not v then
        for _, box in pairs(ESP.BoxesTable) do box:Destroy() end
        ESP.BoxesTable = {}
    end
end)

VisualGroup:AddToggle("ESPNames", { Text = "Names", Default = ESP.Names }):OnChanged(function(v)
    ESP.Names = v
end)

VisualGroup:AddToggle("ESPHealth", { Text = "Health Bars", Default = ESP.Health }):OnChanged(function(v)
    ESP.Health = v
end)

VisualGroup:AddToggle("ESPDistance", { Text = "Distance", Default = ESP.Distance }):OnChanged(function(v)
    ESP.Distance = v
end)

VisualGroup:AddToggle("ESPTracers", { Text = "Tracers", Default = ESP.Tracers }):OnChanged(function(v)
    ESP.Tracers = v
    if not v then
        for _, tracer in pairs(ESP.TracersTable) do tracer:Destroy() end
        ESP.TracersTable = {}
    end
end)

RangeGroup:AddSlider("ESPRange", { Text = "Max Distance", Default = ESP.MaxDistance, Min = 50, Max = 1000, Rounding = 0 }):OnChanged(function(v)
    ESP.MaxDistance = v
end)

RangeGroup:AddSlider("BoxTrans", { Text = "Box Transparency", Default = ESP.BoxTransparency * 100, Min = 0, Max = 100, Rounding = 0 }):OnChanged(function(v)
    ESP.BoxTransparency = v / 100
    for _, box in pairs(ESP.BoxesTable) do
        box.Transparency = ESP.BoxTransparency
    end
end)

ToggleGroup:AddToggle("UseDisplayNames", { Text = "Use Display Names", Default = ESP.UseDisplayNames }):OnChanged(function(v)
    ESP.UseDisplayNames = v
end)

-- Color pickers
ColorGroup:AddColorPicker("BoxColor", { Text = "Box Color", Default = ESP.BoxColor }):OnChanged(function(v)
    ESP.BoxColor = v
    for _, box in pairs(ESP.BoxesTable) do
        box.Color3 = v
    end
end)

ColorGroup:AddColorPicker("NameColor", { Text = "Name Color", Default = ESP.NameColor }):OnChanged(function(v)
    ESP.NameColor = v
    for _, tag in pairs(ESP.NameTags) do
        if tag:FindFirstChild("NameLabel") then
            tag.NameLabel.TextColor3 = v
        end
    end
end)

ColorGroup:AddColorPicker("TracerColor", { Text = "Tracer Color", Default = ESP.TracerColor }):OnChanged(function(v)
    ESP.TracerColor = v
    for _, tracer in pairs(ESP.TracersTable) do
        tracer.Color3 = v
    end
end)

-- Aim Tab
local AimTab = Window:AddTab("Aim")
local AimGroup = AimTab:AddLeftGroupbox("Aim Assist")
local TriggerGroup = AimTab:AddRightGroupbox("Triggerbot")

AimGroup:AddToggle("AimEnabled", { Text = "Enable Aim Assist", Default = AimAssist.Enabled }):OnChanged(function(v)
    AimAssist.Enabled = v
end)

AimGroup:AddSlider("AimSmooth", { Text = "Smoothness", Default = AimAssist.Strength * 100, Min = 0, Max = 100, Rounding = 0 }):OnChanged(function(v)
    AimAssist.Strength = v / 100
end)

TriggerGroup:AddLabel("Hold V to activate"):AddDivider()
TriggerGroup:AddLabel("Instant fire when aiming at enemies")

-- Player Tab
local PlayerTab = Window:AddTab("Player")
local MoveGroup = PlayerTab:AddLeftGroupbox("Movement")
local MiscGroup = PlayerTab:AddRightGroupbox("Miscellaneous")

MoveGroup:AddSlider("WalkSpeed", { Text = "Walk Speed", Default = PlayerSettings.WalkSpeed, Min = 10, Max = 250, Rounding = 0 }):OnChanged(function(v)
    PlayerSettings.WalkSpeed = v
    ApplySpeedSettings()
end)

MoveGroup:AddSlider("JumpPower", { Text = "Jump Power", Default = PlayerSettings.JumpPower, Min = 10, Max = 250, Rounding = 0 }):OnChanged(function(v)
    PlayerSettings.JumpPower = v
    ApplySpeedSettings()
end)

MiscGroup:AddButton("Kill Script", function()
    Running = false
    ClearAllESP()
    Library:Unload()
    for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
end)

-- Keybinds Tab
local KeybindTab = Window:AddTab("Keybinds")
local KeybindGroup = KeybindTab:AddLeftGroupbox("Keybinds")

KeybindGroup:AddKeybind("ToggleUI", { Text = "Toggle UI", Default = "RightShift" }):OnChanged(function(v)
    if v then
        Window:Toggle()
    end
end)

KeybindGroup:AddKeybind("ArmESP", { Text = "Arm ESP (L)", Default = "L" }):OnChanged(function(v)
    if v == Enum.KeyCode.L then
        ESP.Armed = not ESP.Armed
    end
end)

KeybindGroup:AddKeybind("ToggleAim", { Text = "Toggle Aim Assist (C)", Default = "C" }):OnChanged(function(v)
    if v == Enum.KeyCode.C then
        AimAssist.Enabled = not AimAssist.Enabled
    end
end)

-- Notify
Library:Notify("Jayden's Script Hub Loaded", 3)

-- Connections table
local Connections = {}

-- Input handlers
table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    
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

-- Main Loop
table.insert(Connections, RunService.RenderStepped:Connect(function(dt)
    if not Running then return end
    UpdateESP()
    DetectCenterTarget()
    AimAssist:Update(dt)
end))

-- Apply initial speeds
ApplySpeedSettings()
