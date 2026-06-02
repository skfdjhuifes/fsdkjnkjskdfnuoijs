--// SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--// STATE
local TriggerHeld = false
local TriggerState = "DISARMED"
local clicked = false

--// SAFE GETTERS
local function GetLocalCharacter()
    if not LocalPlayer then return nil end
    return LocalPlayer.Character
end

local function EnsureCamera()
    if not Camera or Camera ~= workspace.CurrentCamera then
        Camera = workspace.CurrentCamera
    end
    return Camera
end

--// INPUT HANDLING
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end

    if input.KeyCode == Enum.KeyCode.V then
        TriggerHeld = true
        TriggerState = "HOLDING"
        clicked = false
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.V then
        TriggerHeld = false
        if TriggerState ~= "DISARMED" then
            TriggerState = "ARMED"
        end
        clicked = false
    end
end)

--// CORE DETECTION
local function DetectCenterTarget()
    -- If not holding, reset state and exit
    if not TriggerHeld then
        if TriggerState == "DISARMED" then
            TriggerState = "ARMED"
        end
        clicked = false
        return
    end

    TriggerState = "HOLDING"

    local cam = EnsureCamera()
    if not cam then return end

    local char = GetLocalCharacter()
    if not char then return end

    local mousePos = UserInputService:GetMouseLocation()

    -- Slight multi‑ray sampling around center
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

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { char }

    local result

    for _, offset in ipairs(offsets) do
        local ray = cam:ViewportPointToRay(
            mousePos.X + offset.X,
            mousePos.Y + offset.Y
        )

        result = workspace:Raycast(
            ray.Origin,
            ray.Direction * 1000,
            params
        )

        if result then break end
    end

    if not result or not result.Instance then
        TriggerState = "HOLDING"
        clicked = false
        return
    end

    local part = result.Instance
    local model = part:FindFirstAncestorOfClass("Model")
    if not model then
        TriggerState = "HOLDING"
        clicked = false
        return
    end

    local playerHit = Players:GetPlayerFromCharacter(model)
    if not playerHit or playerHit == LocalPlayer then
        TriggerState = "HOLDING"
        clicked = false
        return
    end

    -- Valid enemy in center
    TriggerState = "TARGET"

    -- Simple debounce: only click once per detection cycle
    if not clicked then
        clicked = true
        mouse1press()
        mouse1release()
    end
end

--// MAIN LOOP
RunService.RenderStepped:Connect(function()
    DetectCenterTarget()
end)
