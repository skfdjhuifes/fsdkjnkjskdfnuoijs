-- dljdsafd.lua
-- ESP + Triggerbot + Aim Assist with Linoria UI

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
-- COLOR HELPERS (kept for logic, not used by UI directly)
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
        r, g, b = c, 0, x
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
-- LINORIA UI
------------------------------------------------------------------

LoadSettings()

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/SaveManager.lua"))()

local Window = Library:CreateWindow({
    Title = "ESP + Triggerbot",
    Center = true,
    AutoShow = true,
})

-- Tabs
local ESPTab = Window:AddTab("ESP")
local CamTab = Window:AddTab("Cam")
local MiscTab = Window:AddTab("Misc")

-- Sections
local ESPSection = ESPTab:AddSection("ESP Settings")
local CamSection = CamTab:AddSection("Aim Assist Settings")
local MiscSection = MiscTab:AddSection("Misc Settings")

-- ESP Tab Content
ESPTab:AddLabel("L = Arm/Disarm | Hold V = Trigger | F7 = Kill Script")

ESPTab:AddToggle("ESPEnabledToggle", {
    Text = "ESP Enabled",
    Default = ESP.Enabled,
    Callback = function(value)
        ESP.Enabled = value
        if not value then
            ESP:ClearAll()
        end
        SaveSettings()
    end
})

ESPTab:AddToggle("ESPArmedToggle", {
    Text = "ESP Armed (L key also toggles)",
    Default = ESP.Armed,
    Callback = function(value)
        ESP.Armed = value
        SaveSettings()
    end
})

ESPTab:AddColorPicker("ESPFillColorPicker", {
    Text = "ESP Fill Color",
    Default = ESP.FillColor,
    Callback = function(color)
        ESP.FillColor = color
        for _, highlight in pairs(ESP.Pixels) do
            highlight.FillColor = ESP.FillColor
        end
        SaveSettings()
    end
})

ESPTab:AddColorPicker("ESPOutlineColorPicker", {
    Text = "ESP Outline Color",
    Default = ESP.OutlineColor,
    Callback = function(color)
        ESP.OutlineColor = color
        for _, highlight in pairs(ESP.Pixels) do
            highlight.OutlineColor = ESP.OutlineColor
        end
        SaveSettings()
    end
})

-- Cam Tab Content
CamSection:AddToggle("AimAssistToggle", {
    Text = "Aim Assist Enabled (C key also toggles)",
    Default = AimAssist.Enabled,
    Callback = function(value)
        AimAssist.Enabled = value
        SaveSettings()
    end
})

CamSection:AddSlider("AimAssistStrengthSlider", {
    Text = "Aim Assist Strength",
    Default = math.floor(AimAssist.Strength * 100),
    Min = 0,
    Max = 100,
    Rounding = 0,
    Compact = false,
    Callback = function(value)
        AimAssist.Strength = value / 100
        SaveSettings()
    end
})

-- Misc Tab Content
MiscSection:AddSlider("WalkSpeedSlider", {
    Text = "WalkSpeed",
    Default = Settings.WalkSpeed,
    Min = 1,
    Max = 200,
    Rounding = 0,
    Compact = false,
    Callback = function(value)
        Settings.WalkSpeed = value
        if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.WalkSpeed = value
        end
        SaveSettings()
    end
})

MiscSection:AddSlider("JumpPowerSlider", {
    Text = "JumpPower",
    Default = Settings.JumpPower,
    Min = 1,
    Max = 200,
    Rounding = 0,
    Compact = false,
    Callback = function(value)
        Settings.JumpPower = value
        if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.JumpPower = value
        end
        SaveSettings()
    end
})

MiscSection:AddButton("KillScriptButton", {
    Text = "KILL SCRIPT (F7)",
    Func = function()
        Running = false
        ESP:ClearAll()
        if Library and Library.Unload then
            Library:Unload()
        end
        for _, conn in ipairs(Connections) do
            pcall(function()
                conn:Disconnect()
            end)
        end
    end
})

-- Theme / Config Tabs
local ThemeTab = Window:AddTab("Theme")
local ConfigTab = Window:AddTab("Config")

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

ThemeManager:ApplyToTab(ThemeTab)
SaveManager:BuildConfigSection(ConfigTab)

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
ApplySpeedSettings()

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
-- KILL SCRIPT (F7 HANDLER)
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
        pcall(function()
            conn:Disconnect()
        end)
    end

    if Library and Library.Unload then
        pcall(function()
            Library:Unload()
        end)
    end
end

------------------------------------------------------------------
-- INPUT: L (ARM ESP), V (TRIGGERBOT), C (AIM ASSIST), F7 (KILL)
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
            SaveSettings()
        end

        if input.KeyCode == Enum.KeyCode.C then
            if not Running then return end
            AimAssist.Enabled = not AimAssist.Enabled
            SaveSettings()
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
-- TRIGGERBOT
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

    local offsets = {
        Vector2.new(0, 0),
        Vector2.new(1, 0),
        Vector2.new(-1, 0),
        Vector2.new(0, 1),
        Vector2.new(0, -1),
        Vector2.new(2, 0),
        Vector2.new(-2, 0),
        Vector2.new(0, 2),
        Vector2.new(0, -2)
    }

    local result

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { LocalPlayer.Character }

    for _, offset in ipairs(offsets) do
        local ray =
            Camera:ViewportPointToRay(
                mousePos.X + offset.X,
                mousePos.Y + offset.Y
            )

        local origin = ray.Origin

        result =
            workspace:Raycast(
                origin,
                ray.Direction * 1000,
                params
            )

        if result then
            break
        end
    end

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
-- AIM ASSIST
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

    return true
end

local function GetTargetHeadCFrame(targetChar)
    if not targetChar then
        return nil
    end

    local head = targetChar:FindFirstChild("Head")

    if head then
        return head.Position
    end

    local rootPart = targetChar:FindFirstChild("HumanoidRootPart")

    if rootPart then
        return rootPart.Position + Vector3.new(0, 1.5, 0)
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

    if self.CurrentTarget then
        local char = self.CurrentTarget.Character

        if self:IsTargetValid(char) == false then
            self.CurrentTarget = nil
            return
        end

        local targetPos = GetTargetHeadCFrame(char)

        if targetPos then
            local screenPos = Camera:WorldToViewportPoint(targetPos)
            local screenCenter = Camera.ViewportSize / 2
            local dx = screenPos.X - screenCenter.X
            local dy = screenPos.Y - screenCenter.Y
            local distFromCenter = Vector2.new(dx, dy).Magnitude

            if distFromCenter > AAFOV * 2 then
                self.CurrentTarget = nil
            else
                local smoothness = self.Strength
                local currentCFrame = Camera.CFrame
                local cameraPos = currentCFrame.Position
                local targetCFrame = CFrame.lookAt(cameraPos, targetPos)

                local factor = 1 - smoothness
                local dtFactor = 1 - (1 - factor) ^ (deltaTime * 60)
                dtFactor = math.clamp(dtFactor, 0, 1)

                local newCFrame = currentCFrame:Lerp(targetCFrame, dtFactor)

                Camera.CFrame = newCFrame
                return
            end
        end
    end

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
    end)
)
