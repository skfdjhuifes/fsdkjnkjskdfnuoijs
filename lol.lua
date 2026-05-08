--[[  
ESP + Triggerbot (L toggle, V hold)  
L = Arm/Disarm ESP  
Hold V = Triggerbot  
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
-- SETTINGS  
------------------------------------------------------------------  

local Settings = {
    ESPEnabled = false,
    ESPArmed = false,
    FillColor = Color3.fromRGB(255, 0, 0),
    OutlineColor = Color3.fromRGB(255, 255, 255),
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

    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        Settings.WalkSpeed = LocalPlayer.Character.Humanoid.WalkSpeed
        Settings.JumpPower = LocalPlayer.Character.Humanoid.JumpPower
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
-- LINORIA UI  
------------------------------------------------------------------  

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/SaveManager.lua"))()

LoadSettings()

local Window = Library:CreateWindow({
    Title = "ESP + Triggerbot",
    Center = true,
    AutoShow = true,
})

local ESPTab = Window:AddTab("ESP")
local CamTab = Window:AddTab("Cam")
local MiscTab = Window:AddTab("Misc")

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

local ThemeTab = Window:AddTab("Theme")
local ConfigTab = Window:AddTab("Config")

ThemeManager:ApplyToTab(ThemeTab)
SaveManager:BuildConfigSection(ConfigTab)

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

    ESP:ClearAll()

    for _, conn in ipairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end

    if Window then
        pcall(function() Window:Destroy() end)
        Window = nil
    end
end

------------------------------------------------------------------  
-- INPUT  
------------------------------------------------------------------  

table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gp)
    if input.KeyCode == Enum.KeyCode.F7 then KillScript() return end
    if gp then return end

    if input.KeyCode == Enum.KeyCode.L then ESP.Armed = not ESP.Armed end
    if input.KeyCode == Enum.KeyCode.C then AimAssist.Enabled = not AimAssist.Enabled SaveSettings() end
    if input.KeyCode == Enum.KeyCode.V then TriggerHeld = true TriggerState = "HOLDING" end
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
    if not self.Enabled then self.CurrentTarget = nil return end
    if not Camera then Camera = workspace.CurrentCamera if not Camera then return end end

    if self.CurrentTarget then
        local char = self.CurrentTarget.Character
        if not self:IsTargetValid(char) then self.CurrentTarget = nil return end

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
