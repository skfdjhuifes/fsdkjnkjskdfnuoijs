--[[  
ESP + Triggerbot (L toggle, V hold)  
L = Arm/Disarm ESP  
Hold V = Triggerbot  
C = Toggle Aim Assist
F7 = Kill Script
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

local Settings = {
    WalkSpeed = 16,
    JumpPower = 50
}

local TriggerHeld = false
local TriggerState = "DISARMED"
local clicked = false

------------------------------------------------------------------  
-- LINORIA UI  
------------------------------------------------------------------  

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/SaveManager.lua"))()

local Window = Library:CreateWindow({
    Title = "ESP + Triggerbot",
    Center = true,
    AutoShow = true,
})

local ESPTab = Window:AddTab("ESP")
local CamTab = Window:AddTab("Cam")
local MiscTab = Window:AddTab("Misc")
local ThemeTab = Window:AddTab("Theme")
local ConfigTab = Window:AddTab("Config")

-- ESP TAB
local ESPGroup = ESPTab:AddLeftGroupbox("ESP Settings")
ESPGroup:AddToggle("ESPEnabled", {
    Text = "ESP Enabled",
    Default = false,
    Tooltip = "Toggle ESP visibility"
})
ESPGroup:AddToggle("ESPArmed", {
    Text = "ESP Armed",
    Default = false,
    Tooltip = "Arm ESP system (can also be toggled with L key)"
})
ESPGroup:AddColorPicker("FillColor", {
    Text = "Fill Color",
    Default = Color3.fromRGB(255, 0, 0),
    Tooltip = "ESP fill color"
})
ESPGroup:AddColorPicker("OutlineColor", {
    Text = "Outline Color",
    Default = Color3.fromRGB(255, 255, 255),
    Tooltip = "ESP outline color"
})

local InfoGroup = ESPTab:AddRightGroupbox("Keybinds")
InfoGroup:AddLabel("L - Toggle ESP Armed")
InfoGroup:AddLabel("V (Hold) - Triggerbot")
InfoGroup:AddLabel("C - Toggle Aim Assist")
InfoGroup:AddLabel("F7 - Kill Script")

-- CAM TAB
local CamGroup = CamTab:AddLeftGroupbox("Aim Assist Settings")
CamGroup:AddToggle("AimAssistEnabled", {
    Text = "Aim Assist Enabled",
    Default = false,
    Tooltip = "Toggle aim assist (can also be toggled with C key)"
})
CamGroup:AddSlider("AimAssistStrength", {
    Text = "Aim Assist Strength",
    Default = 0.5,
    Min = 0,
    Max = 1,
    Decimals = 2,
    Tooltip = "How strong the aim assist pulls toward targets"
})

-- MISC TAB
local MiscGroup = MiscTab:AddLeftGroupbox("Movement Settings")
MiscGroup:AddSlider("WalkSpeed", {
    Text = "Walk Speed",
    Default = 16,
    Min = 1,
    Max = 200,
    Decimals = 0,
    Tooltip = "Player walk speed"
})
MiscGroup:AddSlider("JumpPower", {
    Text = "Jump Power",
    Default = 50,
    Min = 1,
    Max = 200,
    Decimals = 0,
    Tooltip = "Player jump power"
})

local KillGroup = MiscTab:AddRightGroupbox("Script Control")
KillGroup:AddButton("Kill Script", function()
    KillScript()
end)

-- THEME & CONFIG
ThemeManager:SetLibrary(Library)
ThemeManager:ApplyToTab(ThemeTab)
SaveManager:SetLibrary(Library)
SaveManager:BuildConfigSection(ConfigTab)

-- Bind UI elements to variables
Library:OnToggle("ESPEnabled", function(value)
    ESP.Enabled = value
end)
Library:OnToggle("ESPArmed", function(value)
    ESP.Armed = value
end)
Library:OnColorPicker("FillColor", function(value)
    ESP.FillColor = value
    for _, highlight in pairs(ESP.Pixels) do
        highlight.FillColor = ESP.FillColor
    end
end)
Library:OnColorPicker("OutlineColor", function(value)
    ESP.OutlineColor = value
    for _, highlight in pairs(ESP.Pixels) do
        highlight.OutlineColor = ESP.OutlineColor
    end
end)
Library:OnToggle("AimAssistEnabled", function(value)
    AimAssist.Enabled = value
    if not value then
        AimAssist.CurrentTarget = nil
    end
end)
Library:OnSlider("AimAssistStrength", function(value)
    AimAssist.Strength = value
end)
Library:OnSlider("WalkSpeed", function(value)
    Settings.WalkSpeed = value
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        LocalPlayer.Character.Humanoid.WalkSpeed = Settings.WalkSpeed
    end
end)
Library:OnSlider("JumpPower", function(value)
    Settings.JumpPower = value
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        LocalPlayer.Character.Humanoid.JumpPower = Settings.JumpPower
    end
end)

-- Set initial UI values
Library:SetValue("ESPEnabled", ESP.Enabled)
Library:SetValue("ESPArmed", ESP.Armed)
Library:SetValue("FillColor", ESP.FillColor)
Library:SetValue("OutlineColor", ESP.OutlineColor)
Library:SetValue("AimAssistEnabled", AimAssist.Enabled)
Library:SetValue("AimAssistStrength", AimAssist.Strength)
Library:SetValue("WalkSpeed", Settings.WalkSpeed)
Library:SetValue("JumpPower", Settings.JumpPower)

------------------------------------------------------------------  
-- CHARACTER RESPAWN  
------------------------------------------------------------------  

local function ApplySpeedSettings()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    hum.WalkSpeed = Settings.WalkSpeed
    hum.JumpPower = Settings.JumpPower
end

LocalPlayer.CharacterAdded:Connect(function()
    ApplySpeedSettings()
end)

ApplySpeedSettings()

------------------------------------------------------------------  
-- ESP FUNCTIONS  
------------------------------------------------------------------  

function ESP:CreatePixel(character)
    if not character or self.Pixels[character] then return end
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
    for _, h in pairs(self.Pixels) do h:Destroy() end
    self.Pixels = {}
end

function ESP:Update()
    if not self.Enabled or not self.Armed then
        if next(self.Pixels) then self:ClearAll() end
        return
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                if not self.Pixels[char] then self:CreatePixel(char) end
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
    if not Running then return end
    Running = false

    AimAssist.Enabled = false
    AimAssist.CurrentTarget = nil
    TriggerHeld = false
    TriggerState = "DISARMED"
    clicked = false

    ESP:ClearAll()

    for _, conn in ipairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    Connections = {}

    if Window and Window.Destroy then
        pcall(function() Window:Destroy() end)
    end
    
    if Library and Library.Unload then
        pcall(function() Library:Unload() end)
    end
end

------------------------------------------------------------------  
-- INPUT  
------------------------------------------------------------------  

table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gp)
    if input.KeyCode == Enum.KeyCode.F7 then 
        KillScript() 
        return 
    end
    if gp then return end

    if input.KeyCode == Enum.KeyCode.L then 
        ESP.Armed = not ESP.Armed
        Library:SetValue("ESPArmed", ESP.Armed)
    end
    if input.KeyCode == Enum.KeyCode.C then 
        AimAssist.Enabled = not AimAssist.Enabled
        Library:SetValue("AimAssistEnabled", AimAssist.Enabled)
        if not AimAssist.Enabled then
            AimAssist.CurrentTarget = nil
        end
    end
    if input.KeyCode == Enum.KeyCode.V then 
        TriggerHeld = true 
        TriggerState = "HOLDING" 
    end
end))

table.insert(Connections, UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.V then
        TriggerHeld = false
        if TriggerState ~= "DISARMED" then TriggerState = "ARMED" end
        clicked = false
    end
end))

------------------------------------------------------------------  
-- TRIGGERBOT  
------------------------------------------------------------------  

local function DetectCenterTarget()
    if not TriggerHeld then
        if TriggerState == "DISARMED" then TriggerState = "ARMED" end
        clicked = false
        return
    end

    TriggerState = "HOLDING"

    if not Camera then Camera = workspace.CurrentCamera if not Camera then return end end

    local mousePos = UserInputService:GetMouseLocation()
    local offsets = {
        Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(-1, 0),
        Vector2.new(0, 1), Vector2.new(0, -1),
        Vector2.new(2, 0), Vector2.new(-2, 0),
        Vector2.new(0, 2), Vector2.new(0, -2)
    }

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { LocalPlayer.Character }

    local result
    for _, offset in ipairs(offsets) do
        local ray = Camera:ViewportPointToRay(mousePos.X + offset.X, mousePos.Y + offset.Y)
        result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
        if result then break end
    end

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
    clicked = false
end

------------------------------------------------------------------  
-- AIM ASSIST  
------------------------------------------------------------------  

local function IsCharacterKnocked(char)
    if not char then return true end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return true end
    if hum.Health <= 0 then return true end
    if hum:GetState() == Enum.HumanoidStateType.Dead then return true end
    return false
end

local AAFOV = 300

function AimAssist:IsTargetValid(character)
    if not character then return false end
    local hum = character:FindFirstChild("Humanoid")
    if not hum then return false end
    if hum.Health <= 0 then return false end
    if hum:GetState() == Enum.HumanoidStateType.Dead then return false end
    return true
end

local function GetTargetHeadCFrame(char)
    if not char then return nil end
    local head = char:FindFirstChild("Head")
    if head then return head.Position end
    local root = char:FindFirstChild("HumanoidRootPart")
    if root then return root.Position + Vector3.new(0, 1.5, 0) end
    return nil
end

function AimAssist:Update(dt)
    if not self.Enabled then 
        self.CurrentTarget = nil 
        return 
    end
    if not Camera then 
        Camera = workspace.CurrentCamera 
        if not Camera then 
            return 
        end 
    end

    if self.CurrentTarget then
        local char = self.CurrentTarget.Character
        if not self:IsTargetValid(char) then 
            self.CurrentTarget = nil 
            return 
        end

        local targetPos = GetTargetHeadCFrame(char)
        if targetPos then
            local screenPos = Camera:WorldToViewportPoint(targetPos)
            local center = Camera.ViewportSize / 2
            local dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude

            if dist > AAFOV * 2 then
                self.CurrentTarget = nil
            else
                local smooth = self.Strength
                local current = Camera.CFrame
                local camPos = current.Position
                local target = CFrame.lookAt(camPos, targetPos)
                local factor = 1 - smooth
                local dtFactor = 1 - (1 - factor) ^ (dt * 60)
                Camera.CFrame = current:Lerp(target, dtFactor)
                return
            end
        end
    end

    local center = Camera.ViewportSize / 2
    local nearest, nearestDist, nearestPos = nil, math.huge, nil

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            if char and not IsCharacterKnocked(char) then
                local pos = GetTargetHeadCFrame(char)
                if pos then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                    if onScreen then
                        local dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                        if dist < nearestDist and dist <= AAFOV then
                            nearestDist = dist
                            nearest = plr
                            nearestPos = pos
                        end
                    end
                end
            end
        end
    end

    self.CurrentTarget = nearest

    if nearestPos then
        local smooth = self.Strength
        local current = Camera.CFrame
        local camPos = current.Position
        local target = CFrame.lookAt(camPos, nearestPos)
        local factor = 1 - smooth
        local dtFactor = 1 - (1 - factor) ^ (dt * 60)
        Camera.CFrame = current:Lerp(target, dtFactor)
    end
end

------------------------------------------------------------------  
-- MAIN LOOP  
------------------------------------------------------------------  

table.insert(Connections, RunService.RenderStepped:Connect(function(dt)
    if not Running then return end
    ESP:Update()
    DetectCenterTarget()
    AimAssist:Update(dt)
end))
