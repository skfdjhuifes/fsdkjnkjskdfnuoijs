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
local Running = true

------------------------------------------------------------------
-- KILL SCRIPT
------------------------------------------------------------------

local function KillScript()
    Running = false

    if screenGui then
        screenGui:Destroy()
    end

    for _, conn in ipairs(Connections or {}) do
        pcall(function()
            conn:Disconnect()
        end)
    end
end

------------------------------------------------------------------
-- INPUT: V (HOLD FOR TRIGGERBOT)
------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end

    if input.KeyCode == Enum.KeyCode.F7 then
        KillScript()
        return
    end

    if input.KeyCode == Enum.KeyCode.V then
        TriggerHeld = true
        TriggerState = "HOLDING"
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

------------------------------------------------------------------
-- TRIGGERBOT (WITH WALLCHECK)
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
-- MAIN LOOP
------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
    if not Running then return end
    DetectCenterTarget()
end)
