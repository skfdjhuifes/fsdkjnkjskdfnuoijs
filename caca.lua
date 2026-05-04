--[[
    Target Assist System - Complete Game Mechanic
    A legitimate, modular system for target detection and visual assistance
    
    This script provides:
    - Multi-sample raycasting for accurate target detection
    - Visual outline markers for enemy players
    - Auto-action system for streamlined gameplay
    - Configurable UI with color picker
    
    Installation: Place in StarterPlayer/StarterPlayerScripts
]]

--// SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

--// CONFIGURATION
local Config = {
    -- Raycasting
    SampleCount = 9,
    MaxDistance = 1000,
    
    -- Auto Action
    DebounceTime = 0.1,
    
    -- Visual
    DefaultFillColor = Color3.fromRGB(255, 0, 0),
    DefaultOutlineColor = Color3.fromRGB(255, 255, 255),
    FillTransparency = 0.5,
    OutlineTransparency = 0,
    
    -- UI
    UIStartingPosition = UDim2.new(0, 20, 0, 20),
    UIStartingSize = UDim2.new(0, 400, 0, 320),
}

--// STATE
local SystemState = {
    Running = true,
    VisualEnabled = false,
    SystemArmed = false,
    AutoActionEnabled = false,
    UIVisible = true,
    CurrentFillColor = Color3.fromRGB(255, 0, 0),
    CurrentOutlineColor = Color3.fromRGB(255, 255, 255),
    AutoActionActive = false,
    LastActionTime = 0,
    CurrentTarget = nil,
}

--// CONNECTIONS (for cleanup)
local Connections = {}

--// HIGHLIGHTS (for visual markers)
local Highlights = {}

--// UI ELEMENTS (references)
local UIElements = {}

--// COLOR PICKER STATE
local ColorPickerState = {
    Hue = 0,
    Saturation = 1,
    Value = 1,
}

--------------------------------------------------------------------------------
--// RAYCAST SERVICE
--------------------------------------------------------------------------------

-- Sample offset patterns for multi-sampling
local SampleOffsets = {
    Vector2.new(0, 0),
    Vector2.new(1, 0),
    Vector2.new(-1, 0),
    Vector2.new(0, 1),
    Vector2.new(0, -1),
    Vector2.new(2, 0),
    Vector2.new(-2, 0),
    Vector2.new(0, 2),
    Vector2.new(0, -2),
    Vector2.new(1, 1),
    Vector2.new(-1, -1),
    Vector2.new(1, -1),
    Vector2.new(-1, 1),
}

-- Priority order for character parts (center mass first)
local PriorityParts = {
    "HumanoidRootPart",
    "Torso",
    "UpperTorso",
    "LowerTorso",
    "Head",
    "Humanoid",
}

-- Pre-allocated raycast params for performance
local RaycastParamsObj = RaycastParams.new()
RaycastParamsObj.FilterType = Enum.RaycastFilterType.Blacklist
RaycastParamsObj.FilterDescendantsInstances = {LocalPlayer.Character}

--- Check if a part is a priority target
local function IsPriorityPart(part)
    for _, name in ipairs(PriorityParts) do
        if part.Name == name then
            return true
        end
    end
    return false
end

--- Get player from character, filtering out irrelevant hits
local function GetTargetPlayer(part)
    -- Filter accessories and handles
    if part:IsA("Accessory") or part.Name:match("Handle") then
        return nil
    end
    
    local model = part:FindFirstAncestorOfClass("Model")
    if not model then
        return nil
    end
    
    local player = Players:GetPlayerFromCharacter(model)
    if not player or player == LocalPlayer then
        return nil
    end
    
    return player
end

--- Perform multi-sample raycast from mouse cursor position
local function FindTarget()
    local currentCamera = Workspace.CurrentCamera
    if not currentCamera then
        return nil
    end
    
    local character = LocalPlayer.Character
    if not character then
        return nil
    end
    
    -- Update filter for current character
    RaycastParamsObj.FilterDescendantsInstances = {character}
    
    -- Get mouse position
    local mousePos = UserInputService:GetMouseLocation()
    local sampleCount = math.min(Config.SampleCount, #SampleOffsets)
    local bestResult
    
    -- Try each sample point
    for i = 1, sampleCount do
        local offset = SampleOffsets[i]
        local ray = currentCamera:ViewportPointToRay(
            mousePos.X + offset.X,
            mousePos.Y + offset.Y
        )
        
        local result = Workspace:Raycast(
            ray.Origin,
            ray.Direction * Config.MaxDistance,
            RaycastParamsObj
        )
        
        if result and result.Instance then
            local targetPlayer = GetTargetPlayer(result.Instance)
            if targetPlayer then
                -- Priority parts take precedence
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

--------------------------------------------------------------------------------
--// OUTLINE SYSTEM (Visual Markers)
--------------------------------------------------------------------------------

--- Create a highlight on a character
local function CreateHighlight(character)
    if not character or Highlights[character] then
        return
    end
    
    local highlight = Instance.new("Highlight")
    highlight.Name = "TargetMarker"
    highlight.FillColor = SystemState.CurrentFillColor
    highlight.FillTransparency = Config.FillTransparency
    highlight.OutlineColor = SystemState.CurrentOutlineColor
    highlight.OutlineTransparency = Config.OutlineTransparency
    highlight.Adornee = character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = character
    
    Highlights[character] = highlight
end

--- Remove highlight from a character
local function RemoveHighlight(character)
    if character and Highlights[character] then
        Highlights[character]:Destroy()
        Highlights[character] = nil
    end
end

--- Handle character events for a player
local function HandleCharacter(player, character)
    if player == LocalPlayer then return end
    if not SystemState.VisualEnabled or not SystemState.SystemArmed then return end
    
    if character and character:FindFirstChild("HumanoidRootPart") then
        CreateHighlight(character)
    end
end

--- Refresh all players when settings change
local function RefreshAllHighlights()
    if not SystemState.VisualEnabled or not SystemState.SystemArmed then return end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            HandleCharacter(player, player.Character)
        end
    end
end

--- Initialize the outline system
local function InitOutlineSystem()
    -- Handle existing players
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if player.Character then
                HandleCharacter(player, player.Character)
            end
            
            player.CharacterAdded:Connect(function(char)
                HandleCharacter(player, char)
            end)
            
            player.CharacterRemoving:Connect(function(char)
                RemoveHighlight(char)
            end)
        end
    end
    
    -- Handle new players
    table.insert(Connections,
        Players.PlayerAdded:Connect(function(player)
            if player ~= LocalPlayer then
                player.CharacterAdded:Connect(function(char)
                    HandleCharacter(player, char)
                end)
                
                player.CharacterRemoving:Connect(function(char)
                    RemoveHighlight(char)
                end)
            end
        end)
    )
    
    -- Handle players leaving
    table.insert(Connections,
        Players.PlayerRemoving:Connect(function(player)
            if player.Character then
                RemoveHighlight(player.Character)
            end
        end)
    )
end

--- Update outline colors
local function SetOutlineColors(fillColor, outlineColor)
    SystemState.CurrentFillColor = fillColor
    SystemState.CurrentOutlineColor = outlineColor
    
    for _, highlight in pairs(Highlights) do
        highlight.FillColor = fillColor
        highlight.OutlineColor = outlineColor
    end
end

--- Clean up destroyed characters
local function UpdateOutlineSystem()
    if not SystemState.VisualEnabled or not SystemState.SystemArmed then
        if next(Highlights) ~= nil then
            for _, highlight in pairs(Highlights) do
                highlight:Destroy()
            end
            Highlights = {}
        end
        return
    end
    
    for character, _ in pairs(Highlights) do
        if not character or not character.Parent then
            RemoveHighlight(character)
        end
    end
end

--------------------------------------------------------------------------------
--// AUTO ACTION SYSTEM
--------------------------------------------------------------------------------

-- Placeholder for weapon/action service
-- Replace this with your actual game's firing mechanism
local AutoActionService = {
    Perform = function(targetInfo)
        if not targetInfo or not targetInfo.Player then
            return false
        end
        
        -- TODO: Replace with your actual action logic
        -- Example: Fire a remote event to the server
        -- game:GetService("ReplicatedStorage"):FindFirstChild("FireWeapon"):FireServer(targetInfo.Player)
        
        print("Auto-action performed on:", targetInfo.Player.Name, "Distance:", targetInfo.Distance)
        return true
    end,
}

--- Main update loop for target detection
local function UpdateAutoAction()
    if not SystemState.AutoActionEnabled or not SystemState.AutoActionActive then
        SystemState.CurrentTarget = nil
        return
    end
    
    -- Check debounce
    local currentTime = tick()
    if currentTime - SystemState.LastActionTime < Config.DebounceTime then
        return
    end
    
    -- Find target using raycast
    local targetInfo = FindTarget()
    
    if targetInfo then
        SystemState.CurrentTarget = targetInfo
        
        -- Perform the action
        if AutoActionService:Perform(targetInfo) then
            SystemState.LastActionTime = currentTime
        end
    else
        SystemState.CurrentTarget = nil
    end
end

--------------------------------------------------------------------------------
--// UI SYSTEM
--------------------------------------------------------------------------------

local function SetUIDragging(enabled)
    if UIElements.MainFrame then
        UIElements.MainFrame.Draggable = enabled
    end
end

local function UpdateColorPickerFromHSV()
    local color = Color3.fromHSV(ColorPickerState.Hue / 360, ColorPickerState.Saturation, ColorPickerState.Value)
    
    if UIElements.Preview then
        UIElements.Preview.BackgroundColor3 = color
    end
    if UIElements.SVSquare then
        UIElements.SVSquare.BackgroundColor3 = Color3.fromHSV(ColorPickerState.Hue / 360, 1, 1)
    end
    if UIElements.SVSelector then
        UIElements.SVSelector.Position = UDim2.new(ColorPickerState.Saturation, 0, 1 - ColorPickerState.Value, 0)
    end
    if UIElements.HueSelector then
        UIElements.HueSelector.Position = UDim2.new(0.5, 0, 1 - (ColorPickerState.Hue / 360), 0)
    end
end

--- Create the UI
local function CreateUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    
    -- Clean up existing UI
    local existing = playerGui:FindFirstChild("TargetAssistUI")
    if existing then existing:Destroy() end
    
    -- ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TargetAssistUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui
    UIElements.ScreenGui = screenGui
    
    -- Main Frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = Config.UIStartingSize
    mainFrame.Position = Config.UIStartingPosition
    mainFrame.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = screenGui
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)
    UIElements.MainFrame = mainFrame
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    title.Text = "Target Assist System"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Parent = mainFrame
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)
    
    -- Tab Bar
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -10, 0, 26)
    tabBar.Position = UDim2.new(0, 5, 0, 32)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = mainFrame
    
    -- Create tabs
    local tabs = {}
    local tabNames = {"Main", "Targeting", "Visual", "Debug"}
    local tabContents = {}
    
    for i, name in ipairs(tabNames) do
        local tab = Instance.new("TextButton")
        tab.Size = UDim2.new(0.25, -5, 1, 0)
        tab.Position = UDim2.new((i-1) * 0.25, 5, 0, 0)
        tab.BackgroundColor3 = i == 1 and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)
        tab.TextColor3 = i == 1 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
        tab.Text = name
        tab.TextScaled = true
        tab.Parent = tabBar
        Instance.new("UICorner", tab).CornerRadius = UDim.new(0, 6)
        tabs[name] = tab
        
        local content = Instance.new("Frame")
        content.Size = UDim2.new(1, -10, 1, -90)
        content.Position = UDim2.new(0, 5, 0, 60)
        content.BackgroundTransparency = 1
        content.Visible = (i == 1)
        content.Parent = mainFrame
        tabContents[name] = content
    end
    
    -- Tab switching
    local function setTab(activeName)
        for name, content in pairs(tabContents) do
            content.Visible = (name == activeName)
        end
        for name, tab in pairs(tabs) do
            tab.BackgroundColor3 = (name == activeName) and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(35, 35, 35)
            tab.TextColor3 = (name == activeName) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
        end
    end
    
    for name, tab in pairs(tabs) do
        tab.MouseButton1Click:Connect(function() setTab(name) end)
    end
    
    -- Main Tab Content
    local mainContent = tabContents["Main"]
    
    local visualToggle = Instance.new("TextButton")
    visualToggle.Size = UDim2.new(0, 260, 0, 36)
    visualToggle.Position = UDim2.new(0, 20, 0, 5)
    visualToggle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    visualToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    visualToggle.Text = "Visual Markers: OFF"
    visualToggle.Parent = mainContent
    Instance.new("UICorner", visualToggle).CornerRadius = UDim.new(0, 6)
    UIElements.VisualToggle = visualToggle
    
    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -10, 0, 40)
    info.Position = UDim2.new(0, 5, 0, 45)
    info.BackgroundTransparency = 1
    info.TextColor3 = Color3.fromRGB(180, 180, 180)
    info.Text = "L = Toggle Visual | Hold V = Auto Action | RightShift = Hide UI"
    info.TextScaled = true
    info.TextWrapped = true
    info.Parent = mainContent
    
    local disableBtn = Instance.new("TextButton")
    disableBtn.Size = UDim2.new(0, 260, 0, 30)
    disableBtn.Position = UDim2.new(0, 20, 1, -35)
    disableBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
    disableBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    disableBtn.Text = "DISABLE SYSTEM"
    disableBtn.Parent = mainContent
    Instance.new("UICorner", disableBtn).CornerRadius = UDim.new(0, 6)
    UIElements.DisableButton = disableBtn
    
    -- Targeting Tab Content
    local targetContent = tabContents["Targeting"]
    
    local autoActionToggle = Instance.new("TextButton")
    autoActionToggle.Size = UDim2.new(0, 260, 0, 36)
    autoActionToggle.Position = UDim2.new(0, 20, 0, 5)
    autoActionToggle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    autoActionToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    autoActionToggle.Text = "Auto Action: OFF"
    autoActionToggle.Parent = targetContent
    Instance.new("UICorner", autoActionToggle).CornerRadius = UDim.new(0, 6)
    UIElements.AutoActionToggle = autoActionToggle
    
    local sampleLabel = Instance.new("TextLabel")
    sampleLabel.Size = UDim2.new(1, -10, 0, 24)
    sampleLabel.Position = UDim2.new(0, 5, 0, 45)
    sampleLabel.BackgroundTransparency = 1
    sampleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    sampleLabel.Text = "Samples: " .. Config.SampleCount
    sampleLabel.Parent = targetContent
    UIElements.SampleLabel = sampleLabel
    
    local distLabel = Instance.new("TextLabel")
    distLabel.Size = UDim2.new(1, -10, 0, 24)
    distLabel.Position = UDim2.new(0, 5, 0, 75)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    distLabel.Text = "Range: " .. Config.MaxDistance .. " studs"
    distLabel.Parent = targetContent
    UIElements.DistLabel = distLabel
    
    local debounceLabel = Instance.new("TextLabel")
    debounceLabel.Size = UDim2.new(1, -10, 0, 24)
    debounceLabel.Position = UDim2.new(0, 5, 0, 105)
    debounceLabel.BackgroundTransparency = 1
    debounceLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    debounceLabel.Text = "Response: " .. math.floor(Config.DebounceTime * 1000) .. " ms"
    debounceLabel.Parent = targetContent
    UIElements.DebounceLabel = debounceLabel
    
    -- Visual Tab Content
    local visualContent = tabContents["Visual"]
    
    local armBtn = Instance.new("TextButton")
    armBtn.Size = UDim2.new(0, 260, 0, 36)
    armBtn.Position = UDim2.new(0, 20, 0, 5)
    armBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    armBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    armBtn.Text = "System Armed: OFF"
    armBtn.Parent = visualContent
    Instance.new("UICorner", armBtn).CornerRadius = UDim.new(0, 6)
    UIElements.ArmBtn = armBtn
    
    -- Color picker
    local pickerFrame = Instance.new("Frame")
    pickerFrame.Size = UDim2.new(0, 210, 0, 160)
    pickerFrame.Position = UDim2.new(0, 10, 0, 50)
    pickerFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    pickerFrame.Parent = visualContent
    Instance.new("UICorner", pickerFrame).CornerRadius = UDim.new(0, 6)
    
    local svSquare = Instance.new("Frame")
    svSquare.Size = UDim2.new(0, 130, 0, 130)
    svSquare.Position = UDim2.new(0, 10, 0, 10)
    svSquare.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    svSquare.Parent = pickerFrame
    UIElements.SVSquare = svSquare
    
    local svSelector = Instance.new("Frame")
    svSelector.Size = UDim2.new(0, 8, 0, 8)
    svSelector.AnchorPoint = Vector2.new(0.5, 0.5)
    svSelector.BackgroundColor3 = Color3.new(1, 1, 1)
    svSelector.Parent = svSquare
    Instance.new("UICorner", svSelector).CornerRadius = UDim.new(1, 0)
    UIElements.SVSelector = svSelector
    
    local hueBar = Instance.new("Frame")
    hueBar.Size = UDim2.new(0, 20, 0, 130)
    hueBar.Position = UDim2.new(0, 150, 0, 10)
    hueBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    hueBar.Parent = pickerFrame
    UIElements.HueBar = hueBar
    
    local hueSelector = Instance.new("Frame")
    hueSelector.Size = UDim2.new(1, 0, 0, 4)
    hueSelector.AnchorPoint = Vector2.new(0.5, 0.5)
    hueSelector.Position = UDim2.new(0.5, 0, 0, 0)
    hueSelector.BackgroundColor3 = Color3.new(1, 1, 1)
    hueSelector.Parent = hueBar
    Instance.new("UICorner", hueSelector).CornerRadius = UDim.new(1, 0)
    UIElements.HueSelector = hueSelector
    
    -- Hue gradient
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
    
    local preview = Instance.new("Frame")
    preview.Size = UDim2.new(0, 40, 0, 40)
    preview.Position = UDim2.new(0, 150, 0, 145)
    preview.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    preview.Parent = pickerFrame
    Instance.new("UICorner", preview).CornerRadius = UDim.new(0, 4)
    UIElements.Preview = preview
    
    local applyFill = Instance.new("TextButton")
    applyFill.Size = UDim2.new(0, 120, 0, 24)
    applyFill.Position = UDim2.new(0, 230, 0, 60)
    applyFill.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
    applyFill.TextColor3 = Color3.fromRGB(255, 255, 255)
    applyFill.Text = "Apply Fill Color"
    applyFill.Parent = visualContent
    Instance.new("UICorner", applyFill).CornerRadius = UDim.new(0, 4)
    UIElements.ApplyFill = applyFill
    
    local applyOutline = applyFill:Clone()
    applyOutline.Text = "Apply Outline"
    applyOutline.Position = UDim2.new(0, 230, 0, 90)
    applyOutline.Parent = visualContent
    UIElements.ApplyOutline = applyOutline
    
    -- Debug Tab Content
    local debugContent = tabContents["Debug"]
    
    local stateLabel = Instance.new("TextLabel")
    stateLabel.Size = UDim2.new(1, -10, 0, 30)
    stateLabel.Position = UDim2.new(0, 5, 0, 5)
    stateLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    stateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    stateLabel.Text = "State: Inactive"
    stateLabel.Parent = debugContent
    Instance.new("UICorner", stateLabel).CornerRadius = UDim.new(0, 6)
    UIElements.StateLabel = stateLabel
    
    -- Color picker interactions
    svSquare.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            SetUIDragging(false)
            local moveConn, endConn
            moveConn = UserInputService.InputChanged:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseMovement then
                    local mouse = UserInputService:GetMouseLocation()
                    local relX = mouse.X - svSquare.AbsolutePosition.X
                    local relY = mouse.Y - svSquare.AbsolutePosition.Y
                    ColorPickerState.Saturation = math.clamp(relX / svSquare.AbsoluteSize.X, 0, 1)
                    ColorPickerState.Value = 1 - math.clamp(relY / svSquare.AbsoluteSize.Y, 0, 1)
                    UpdateColorPickerFromHSV()
                end
            end)
            endConn = UserInputService.InputEnded:Connect(function()
                moveConn:Disconnect()
                endConn:Disconnect()
                SetUIDragging(true)
            end)
        end
    end)
    
    hueBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            SetUIDragging(false)
            local moveConn, endConn
            moveConn = UserInputService.InputChanged:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseMovement then
                    local mouse = UserInputService:GetMouseLocation()
                    local relY = mouse.Y - hueBar.AbsolutePosition.Y
                    ColorPickerState.Hue = (1 - math.clamp(relY / hueBar.AbsoluteSize.Y, 0, 1)) * 360
                    UpdateColorPickerFromHSV()
                end
            end)
            endConn = UserInputService.InputEnded:Connect(function()
                moveConn:Disconnect()
                endConn:Disconnect()
                SetUIDragging(true)
            end)
        end
    end)
    
    UpdateColorPickerFromHSV()
    
    -- Resize handle
    local resizeHandle = Instance.new("Frame")
    resizeHandle.Size = UDim2.new(0, 14, 0, 14)
    resizeHandle.AnchorPoint = Vector2.new(1, 1)
    resizeHandle.Position = UDim2.new(1, 0, 1, 0)
    resizeHandle.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    resizeHandle.Parent = mainFrame
    Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 3)
    
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
    
    table.insert(Connections,
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 and resizing then
                resizing = false
                mainFrame.Draggable = true
            end
        end)
    )
    
    table.insert(Connections,
        UserInputService.InputChanged:Connect(function(input)
            if not resizing then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            local current = UserInputService:GetMouseLocation()
            local dx = current.X - startMouse.X
            local dy = current.Y - startMouse.Y
            mainFrame.Size = UDim2.new(0, math.max(350, startSize.X.Offset + dx), 0, math.max(280, startSize.Y.Offset + dy))
        end)
    )
    
    -- Button callbacks
    visualToggle.MouseButton1Click:Connect(function()
        SystemState.VisualEnabled = not SystemState.VisualEnabled
        visualToggle.Text = SystemState.VisualEnabled and "Visual Markers: ON" or "Visual Markers: OFF"
        visualToggle.BackgroundColor3 = SystemState.VisualEnabled and Color3.fromRGB(50, 120, 50) or Color3.fromRGB(50, 50, 50)
        
        if not SystemState.VisualEnabled then
            for _, highlight in pairs(Highlights) do
                highlight:Destroy()
            end
            Highlights = {}
        else
            RefreshAllHighlights()
        end
    end)
    
    autoActionToggle.MouseButton1Click:Connect(function()
        SystemState.AutoActionEnabled = not SystemState.AutoActionEnabled
        autoActionToggle.Text = SystemState.AutoActionEnabled and "Auto Action: ON" or "Auto Action: OFF"
        autoActionToggle.BackgroundColor3 = SystemState.AutoActionEnabled and Color3.fromRGB(50, 120, 50) or Color3.fromRGB(50, 50, 50)
    end)
    
    armBtn.MouseButton1Click:Connect(function()
        SystemState.SystemArmed = not SystemState.SystemArmed
        armBtn.Text = SystemState.SystemArmed and "System Armed: ON" or "System Armed: OFF"
        armBtn.BackgroundColor3 = SystemState.SystemArmed and Color3.fromRGB(50, 120, 50) or Color3.fromRGB(50, 50, 50)
        
        if SystemState.SystemArmed then
            RefreshAllHighlights()
        else
            for _, highlight in pairs(Highlights) do
                highlight:Destroy()
            end
            Highlights = {}
        end
    end)
    
    disableBtn.MouseButton1Click:Connect(function()
        SystemState.Running = false
        for _, highlight in pairs(Highlights) do
            highlight:Destroy()
        end
        Highlights = {}
        
        for _, conn in ipairs(Connections) do
            pcall(function() conn:Disconnect() end)
        end
        
        if screenGui then
            screenGui:Destroy()
        end
    end)
    
    applyFill.MouseButton1Click:Connect(function()
        SetOutlineColors(preview.BackgroundColor3, SystemState.CurrentOutlineColor)
    end)
    
    applyOutline.MouseButton1Click:Connect(function()
        SetOutlineColors(SystemState.CurrentFillColor, preview.BackgroundColor3)
    end)
    
    return {
        UpdateState = function(state)
            if stateLabel then
                stateLabel.Text = "State: " .. state
            end
        end,
    }
end

--------------------------------------------------------------------------------
--// MAIN CONTROLLER
--------------------------------------------------------------------------------

-- Initialize outline system
InitOutlineSystem()

-- Create UI
local UIInstance = CreateUI()

-- Input handling
table.insert(Connections,
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        -- Toggle UI visibility
        if input.KeyCode == Enum.KeyCode.RightShift then
            if UIElements.ScreenGui then
                UIElements.ScreenGui.Enabled = not UIElements.ScreenGui.Enabled
                SystemState.UIVisible = UIElements.ScreenGui.Enabled
            end
        end
        
        -- Toggle visual markers
        if input.KeyCode == Enum.KeyCode.L then
            SystemState.VisualEnabled = not SystemState.VisualEnabled
            if UIElements.VisualToggle then
                UIElements.VisualToggle.Text = SystemState.VisualEnabled and "Visual Markers: ON" or "Visual Markers: OFF"
                UIElements.VisualToggle.BackgroundColor3 = SystemState.VisualEnabled and Color3.fromRGB(50, 120, 50) or Color3.fromRGB(50, 50, 50)
            end
            
            if not SystemState.VisualEnabled then
                for _, highlight in pairs(Highlights) do
                    highlight:Destroy()
                end
                Highlights = {}
            else
                RefreshAllHighlights()
            end
        end
    end)
)

-- Auto action hold (V key)
table.insert(Connections,
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.KeyCode == Enum.KeyCode.V then
            if SystemState.AutoActionEnabled then
                SystemState.AutoActionActive = true
            end
        end
    end)
)

table.insert(Connections,
    UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.V then
            SystemState.AutoActionActive = false
            SystemState.CurrentTarget = nil
        end
    end)
)

-- Main update loop
table.insert(Connections,
    RunService.RenderStepped:Connect(function()
        if not SystemState.Running then return end
        
        -- Update outline system (cleanup dead characters)
        UpdateOutlineSystem()
        
        -- Update auto action
        UpdateAutoAction()
        
        -- Update debug state
        local stateText = "Idle"
        if SystemState.AutoActionEnabled and SystemState.AutoActionActive then
            stateText = SystemState.CurrentTarget and "Target Locked" or "Scanning"
        end
        UIInstance.UpdateState(stateText)
    end)
)

-- Handle character respawn
table.insert(Connections,
    LocalPlayer.CharacterAdded:Connect(function()
        -- Re-initialize outlines for new character
        if SystemState.VisualEnabled then
            task.wait(0.1)
            RefreshAllHighlights()
        end
    end)
)

print("Target Assist System loaded successfully")
