if getgenv().RepzHubUnload then
    pcall(getgenv().RepzHubUnload)
end

local Ins, C3, U2, V3, UD = Instance.new, Color3.fromRGB, UDim2.new, Vector3.new, UDim.new
local floor, clamp = math.floor, math.clamp

local function toHex(c)
    local r, g, b = floor(c.R * 255), floor(c.G * 255), floor(c.B * 255)
    return string.format("#%02X%02X%02X", r, g, b)
end

local espData = { 
    survivors = {}, killers = {}, generators = {}, batteries = {}, fuses = {}, texts = {}, 
    minions = {}, traps = {}, nameStamConns = {}, pool = {}, genBills = {} 
}
local function getSafeGui()
    local success, res = pcall(function() return game:GetService("CoreGui") end)
    if success and res then return res end
    return LocalPlayer:WaitForChild("PlayerGui", 10)
end
local TargetGUI = getSafeGui()
local nameStamESPEnabled = false
local pendingESP = {}

local _cachedPlayers = nil
local _lastPlayersTick = 0
local function getPlayersFolder()
    local now = tick()
    if not _cachedPlayers or _cachedPlayers.Parent ~= workspace or (now - _lastPlayersTick) > 2 then
        _lastPlayersTick = now
        _cachedPlayers = workspace:FindFirstChild("PLAYERS")
    end
    return _cachedPlayers
end

local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local silentAimEnabled = false
local silentAimPrediction = false
local predictionVelocityScale = 1.0
local predictionProjectileSpeed = 750 
local silentAimTarget = nil
local autoShakeEnabled = false
local isShaking = false

local activeKillerRole = nil
local ennardEHeld = false

local lastTargetTick = 0
local cachedTarget = nil
local lastTargetFrame = 0

local function getSilentAimTarget()
	local now = tick()
	local frame = RunService:IsRenderStep() and 1 or 0
	
    if now - lastTargetTick < 0.03 then return cachedTarget end
    lastTargetTick = tick()
    
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then cachedTarget = nil return nil end
    
    local isKiller = (char.Parent and char.Parent.Name == "KILLER")
    local teamFolder = isKiller and "ALIVE" or "KILLER"
    local pFolder = getPlayersFolder()
    local enemyFolder = pFolder and pFolder:FindFirstChild(teamFolder)
    if not enemyFolder then cachedTarget = nil return nil end
    
    local closest, dist = nil, 1000
    local cam = workspace.CurrentCamera
	if not cam then return nil end
    local fovLimit = 0.5

    for _, v in ipairs(enemyFolder:GetChildren()) do
        local hrp = v:FindFirstChild("HumanoidRootPart")
        if hrp and v ~= char then
            local d = (root.Position - hrp.Position).Magnitude
            if d < dist then
                local screenPos, onScreen = cam:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    dist = d
                    closest = v
                end
            end
        end
    end
    cachedTarget = closest
    return closest
end

local function getPredictedPosition(tPart, origin)
    if not tPart then return nil end
    local pos = tPart.Position
    if not (silentAimEnabled and silentAimPrediction) then return pos end
    
    local vel = tPart.Velocity
    if vel.Magnitude < 0.05 then return pos end
    
    -- Ping compensation
    local ping = (LocalPlayer:GetNetworkPing() or 0) 
    
    -- Distance / Speed = Travel Time
    local travelTime = (pos - origin).Magnitude / math.max(predictionProjectileSpeed, 1)
    
    -- Total time = time for projectile to travel + the time it takes for your 'hit' to reach the server
    local totalTime = travelTime + ping
    
    return pos + (vel * totalTime * predictionVelocityScale)
end

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = Workspace.CurrentCamera
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function getSurvivorColor(char)
    local c = char:GetAttribute("Character") or ""
    if c == "Survivor-Security Guard" then return Color3.fromRGB(0, 80, 255)
    elseif c == "Survivor-Medic" then return Color3.fromRGB(255, 255, 255)
    elseif c == "Survivor-Fighter" then return Color3.fromRGB(128, 0, 128)
    elseif c == "Survivor-Customer" then return Color3.fromRGB(0, 255, 0)
    else return Color3.fromRGB(0, 255, 0) end
end

local function getGenColor(prog)
    if prog >= 100 then return C3(0, 255, 0)
    elseif prog >= 75 then return C3(100, 255, 0)
    elseif prog >= 50 then return C3(255, 255, 0)
    elseif prog >= 25 then return C3(255, 140, 0)
    else return C3(255, 60, 60) end
end

local function getRoleLabel(char)
    local c = char:GetAttribute("Character") or ""
    if c == "" then
        return (char.Parent and char.Parent.Name == "KILLER") and "Killer" or "Survivor"
    end
    
    if c:find("Survivor%-") then
        return c:gsub("Survivor%-", "")
    elseif c:find("Killer%-") then
        return c:gsub("Killer%-", "")
    end
    
    return c
end

getgenv().RepzLoops = getgenv().RepzLoops or {}

local function getActiveKiller()
    local p = getPlayersFolder()
    local killerFolder = p and p:FindFirstChild("KILLER")
    if killerFolder then
        for _, v in ipairs(killerFolder:GetChildren()) do
            if v:FindFirstChild("HumanoidRootPart") and v ~= LocalPlayer.Character then
                return v
            end
        end
    end
    return nil
end

local lastRoundTick = 0
local cachedRoundState = false
local function isRoundActive()
    local now = tick()
    if now - lastRoundTick < 0.2 then return cachedRoundState end
    lastRoundTick = now
    
    local p = getPlayersFolder()
    if not p then cachedRoundState = false return false end
    local k = p:FindFirstChild("KILLER")
    local a = p:FindFirstChild("ALIVE")
    local res = (k and k:FindFirstChildWhichIsA("Model") ~= nil) or (a and a:FindFirstChildWhichIsA("Model") ~= nil)
    cachedRoundState = res
    return res
end

local lastRoleTick = 0
local cachedMyRole = nil
local function getMyRole()
    local char = LocalPlayer.Character
    if not char then cachedMyRole = nil return nil end
    local now = tick()
    if now - lastRoleTick < 0.5 then return cachedMyRole end
    lastRoleTick = now
    local res = getRoleLabel(char)
    cachedMyRole = res
    return res
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.E then ennardEHeld = true end
end)
UserInputService.InputEnded:Connect(function(input, gpe)
    if input.KeyCode == Enum.KeyCode.E then ennardEHeld = false end
end)

task.spawn(function()
    local function checkAndDestroy(obj)
        if obj:IsA("ScreenGui") or obj:IsA("LocalScript") then
            local name = obj.Name:lower()
            if name == "anitcheat" or name == "anticheat" then
                obj:Destroy()
            end
        end
    end
    
    local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
    if playerGui then
        for _, v in ipairs(playerGui:GetDescendants()) do
            checkAndDestroy(v)
        end
        playerGui.DescendantAdded:Connect(checkAndDestroy)
    end
end)


local function shouldRunSilentAim()
    if not silentAimEnabled then return false end
    if getMyRole() == "Ennard" then return ennardEHeld end
    return true
end

local scriptCache = {}
local function isSafeScript(s)
    if not s then return false end
    if scriptCache[s] ~= nil then return scriptCache[s] end
    
    local name = s.Name
    local res = (name == "CameraModule" or name == "PopperCam" or name == "ZoomController" or name == "BaseCamera" or name == "ControlModule" or (s.Parent and s.Parent.Name == "CameraModule"))
    scriptCache[s] = res
    return res
end

local successHook, errHook = pcall(function()
    local gm = getrawmetatable(game)
    local oldNamecall = gm.__namecall
    local oldIndex = gm.__index
    setreadonly(gm, false)
    
    gm.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        
        if not checkcaller() then
            if (method == "Raycast" or method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList") then
                if shouldRunSilentAim() and not isSafeScript(getcallingscript()) then
                    local target = getSilentAimTarget()
                    local tPart = target and (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChildWhichIsA("BasePart"))
                    if tPart then
                        local args = {...}
                        if method == "Raycast" then
                            local origin = args[1]
                            local predictedPos = getPredictedPosition(tPart, origin)
                            args[2] = (predictedPos - origin).Unit * 1000
                            return oldNamecall(self, unpack(args))
                        else
                            local origin = args[1].Origin
                            local predictedPos = getPredictedPosition(tPart, origin)
                            args[1] = Ray.new(origin, (predictedPos - origin).Unit * 1000)
                            return oldNamecall(self, unpack(args))
                        end
                    end
                end
            elseif (method == "FireServer" or method == "InvokeServer") then
                local remoteName = self.Name
                if shouldRunSilentAim() and (remoteName:find("swing") or remoteName:find("throw") or remoteName:find("attack")) then
                    local target = getSilentAimTarget()
                    local tPart = target and (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChildWhichIsA("BasePart"))
                    if tPart then
                        local args = {...}
                        local char = LocalPlayer.Character
                        local origin = char and char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart.Position or Camera.CFrame.Position
                        local predictedPos = getPredictedPosition(tPart, origin)
                        
                        for i = 1, #args do
                            local v = args[i]
                            if typeof(v) == "Vector3" then
                                args[i] = predictedPos
                            elseif typeof(v) == "CFrame" then
                                args[i] = CFrame.new(predictedPos, predictedPos + (predictedPos - origin).Unit)
                            end
                        end
                        return oldNamecall(self, unpack(args))
                    end
                end
            end
        end
        return oldNamecall(self, ...)
    end)
    
    gm.__index = newcclosure(function(self, k)
        if not checkcaller() then
            if (self == Mouse) and (k == "Target" or k == "Hit" or k == "UnitRay") then
                if shouldRunSilentAim() and not isSafeScript(getcallingscript()) then
                    local target = getSilentAimTarget()
                    local tPart = target and (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChildWhichIsA("BasePart"))
                    if tPart then
                        local origin = Camera.CFrame.Position
                        local predictedPos = getPredictedPosition(tPart, origin)
                        if k == "Target" then return tPart end
                        if k == "Hit" then return CFrame.new(predictedPos) end
                        if k == "UnitRay" then return Ray.new(origin, (predictedPos - origin).Unit) end
                    end
                end
            end
        end
        return oldIndex(self, k)
    end)

    setreadonly(gm, true)
end)

local gameIconId = "rbxassetid://68073547" 
local successIcon, productInfo = pcall(function()
    return MarketplaceService:GetProductInfo(game.PlaceId)
end)
if successIcon and productInfo and productInfo.IconImageAssetId then
    gameIconId = "rbxassetid://" .. productInfo.IconImageAssetId
end

local loadScreen = Instance.new("ScreenGui")
loadScreen.Name = "RepzHubBBN"
loadScreen.IgnoreGuiInset = true

local success, err = pcall(function() loadScreen.Parent = CoreGui end)
if not success then loadScreen.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local dimBg = Instance.new("Frame")
dimBg.Size = UDim2.new(1, 0, 1, 0)
dimBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dimBg.BackgroundTransparency = 1 
dimBg.BorderSizePixel = 0
dimBg.Parent = loadScreen

local centerBox = Instance.new("Frame")
centerBox.Size = UDim2.new(0.8, 0, 0, 130) 
centerBox.Position = UDim2.new(0.5, 0, 0.5, 0)
centerBox.AnchorPoint = Vector2.new(0.5, 0.5)
centerBox.BackgroundColor3 = Color3.fromRGB(45, 45, 45) 
centerBox.BackgroundTransparency = 1 
centerBox.BorderSizePixel = 0
centerBox.ClipsDescendants = true
centerBox.Parent = dimBg

local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 10)
boxCorner.Parent = centerBox

local boxConstraint = Instance.new("UISizeConstraint")
boxConstraint.MaxSize = Vector2.new(380, 130) 
boxConstraint.Parent = centerBox

local boxStroke = Instance.new("UIStroke")
boxStroke.Color = Color3.fromRGB(0, 0, 0)
boxStroke.Thickness = 2
boxStroke.Transparency = 1
boxStroke.Parent = centerBox

local topBarContainer = Instance.new("Frame")
topBarContainer.Size = UDim2.new(1, 0, 0, 70)
topBarContainer.Position = UDim2.new(0, 0, 0, 10)
topBarContainer.BackgroundTransparency = 1
topBarContainer.Parent = centerBox

local topBarLayout = Instance.new("UIListLayout")
topBarLayout.FillDirection = Enum.FillDirection.Horizontal
topBarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
topBarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
topBarLayout.Padding = UDim.new(0, 12)
topBarLayout.Parent = topBarContainer

local gameLogo = Instance.new("ImageLabel")
gameLogo.Image = gameIconId
gameLogo.Size = UDim2.new(0, 50, 0, 50)
gameLogo.BackgroundTransparency = 1
gameLogo.ImageTransparency = 1
gameLogo.Parent = topBarContainer

local logoCorner = Instance.new("UICorner")
logoCorner.CornerRadius = UDim.new(0, 8)
logoCorner.Parent = gameLogo

local topBarText = Instance.new("TextLabel")
topBarText.Text = "Bite By Night | Repz hub"
topBarText.Font = Enum.Font.GothamBold
topBarText.TextSize = 24
topBarText.TextColor3 = Color3.fromRGB(255, 255, 255)
topBarText.Size = UDim2.new(0, 240, 0, 50)
topBarText.BackgroundTransparency = 1
topBarText.TextTransparency = 1
topBarText.TextXAlignment = Enum.TextXAlignment.Left
topBarText.Parent = topBarContainer

local barContainer = Instance.new("Frame")
barContainer.Size = UDim2.new(0.85, 0, 0, 16) 
barContainer.Position = UDim2.new(0.075, 0, 0.75, 0) 
barContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
barContainer.BackgroundTransparency = 1
barContainer.BorderSizePixel = 0
barContainer.Parent = centerBox

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 6)
barCorner.Parent = barContainer

local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromRGB(0, 0, 0)
barStroke.Thickness = 1.5
barStroke.Transparency = 1
barStroke.Parent = barContainer

local bar = Instance.new("Frame")
bar.Size = UDim2.new(0, 0, 1, 0)
bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
bar.BorderSizePixel = 0
bar.Parent = barContainer

local barInnerCorner = Instance.new("UICorner")
barInnerCorner.CornerRadius = UDim.new(0, 6)
barInnerCorner.Parent = bar

local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 35)),  
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 139))    
})
grad.Parent = bar

local fadeSpeed = 0.5
TweenService:Create(dimBg, TweenInfo.new(fadeSpeed), {BackgroundTransparency = 0.4}):Play()
TweenService:Create(centerBox, TweenInfo.new(fadeSpeed), {BackgroundTransparency = 0}):Play()
TweenService:Create(boxStroke, TweenInfo.new(fadeSpeed), {Transparency = 0}):Play()
TweenService:Create(gameLogo, TweenInfo.new(fadeSpeed), {ImageTransparency = 0}):Play()
TweenService:Create(topBarText, TweenInfo.new(fadeSpeed), {TextTransparency = 0}):Play()
TweenService:Create(barContainer, TweenInfo.new(fadeSpeed), {BackgroundTransparency = 0}):Play()
TweenService:Create(barStroke, TweenInfo.new(fadeSpeed), {Transparency = 0}):Play()

task.wait(fadeSpeed)

local barTween = TweenService:Create(bar, TweenInfo.new(2.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 1, 0)})
barTween:Play()
barTween.Completed:Wait()

TweenService:Create(dimBg, TweenInfo.new(fadeSpeed), {BackgroundTransparency = 1}):Play()
TweenService:Create(centerBox, TweenInfo.new(fadeSpeed), {BackgroundTransparency = 1}):Play()
TweenService:Create(boxStroke, TweenInfo.new(fadeSpeed), {Transparency = 1}):Play()
TweenService:Create(gameLogo, TweenInfo.new(fadeSpeed), {ImageTransparency = 1}):Play()
TweenService:Create(topBarText, TweenInfo.new(fadeSpeed), {TextTransparency = 1}):Play()
TweenService:Create(barContainer, TweenInfo.new(fadeSpeed), {BackgroundTransparency = 1}):Play()
TweenService:Create(barStroke, TweenInfo.new(fadeSpeed), {Transparency = 1}):Play()
TweenService:Create(bar, TweenInfo.new(fadeSpeed), {BackgroundTransparency = 1}):Play()

task.wait(fadeSpeed)
loadScreen:Destroy()


local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles
local executorName = identifyexecutor and identifyexecutor() or "Unknown Executor"

local function checkCompatibility()
    local requiredFunctions = {
        "getrawmetatable", "setreadonly", "newcclosure", "getnamecallmethod", "checkcaller",
        "hookmetamethod", "identifyexecutor", "getgenv", "getrenv", "getreg", "getgc"
    }
    local supported = 0
    for _, func in ipairs(requiredFunctions) do
        local exists = false
        pcall(function()
            if getfenv()[func] ~= nil or _G[func] ~= nil or (getgenv and getgenv()[func] ~= nil) then
                exists = true
            end
        end)
        if exists then
            supported = supported + 1
        end
    end
    return supported, #requiredFunctions
end

local supportedCount, totalChecks = checkCompatibility()
local isCompatible = supportedCount >= (totalChecks - 2) -- Allow for some missing non-essential ones
local statusText = isCompatible and "your executor seems to support our script." or "your executor might have issues with some features."

local Window = Library:CreateWindow({
    Title = " Repz Hub | BBN ",
    Footer = "https://discord.gg/2j5F3JGubc for more scripts!",
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = true,
})


Library:Notify("Repz hub Loaded Successfully.", 4)

local Tabs = {
    Info = Window:AddTab("Info", "user"),
    Fun = Window:AddTab("Fun", "smile"),
    Tasks = Window:AddTab("Tasks", "list"),
    AutoFarm = Window:AddTab("Auto-Farm", "zap"),
    Local = Window:AddTab("Local", "user"),
    Visuals = Window:AddTab("Visuals", "eye"),
    Combat = Window:AddTab("Combat", "swords"),
    AntiLag = Window:AddTab("Anti-Lag", "zap"),
    Other = Window:AddTab("Other", "folder"),
    UISettings = Window:AddTab("UI Settings", "settings"),
}

local InfoBox = Tabs.Info:AddLeftGroupbox("Information")
InfoBox:AddLabel("Main script: Repz")
InfoBox:AddButton({
    Text = "Status Update",
    Func = function() 
        Library:Notify("Some features/tabs were removed due to anti-cheat.", 3)
    end
})
InfoBox:AddButton({
    Text = "*SIDENOTE*",
    Func = function()
        Library:Notify("Thank you all for supporting me throughout the days and years...", 5)
    end
})
InfoBox:AddLabel("Executor Status:\nExecutor you're using: " .. executorName .. "\nWe have ran " .. supportedCount .. "/" .. totalChecks .. " checks, and " .. statusText, true)

local hookedACFunctions = {}
local acKeywords = {"anticheat", "hacker", "kick", "hackerkick", "ban", "exploit", "crash", "detect"}

local SettingsBox = Tabs.Info:AddRightGroupbox("Bypass Options")
SettingsBox:AddToggle("AC_Bypass", {
    Text = "Anti-Cheat Bypass",
    Default = false,
    Callback = function(Value)
        if Value then
            for _, v in pairs(getgc()) do
                if type(v) == "function" and islclosure(v) then
                    local info = debug.getinfo(v)
                    if info and info.name then
                        local funcName = string.lower(info.name)
                        for _, keyword in ipairs(acKeywords) do
                            if string.find(funcName, keyword) then
                                hookedACFunctions[v] = hookfunction(v, function() return end)
                            end
                        end
                    end
                end
            end
            Library:Notify("Found and neutralized localized AC functions.", 4)
        else
            for orig, hook in pairs(hookedACFunctions) do
                hookfunction(orig, hook)
            end
            table.clear(hookedACFunctions)
            Library:Notify("AC functions restored to original state.", 4)
        end
    end
})

local storedEmotes = {}
local emoteDropdownList = {"Select Emote First"}
local selectedEmoteObj = nil
local activeEmoteTrack = nil
local activeEffects = {}
_G.GameMusicSteppedConnection = nil
_G.CustomOST_Active = false
_G.OriginalLobbyMusic = nil 

local function updateEmoteList()
    table.clear(storedEmotes)
    emoteDropdownList = {"Select Emote First"}
    local repStorage = game:GetService("ReplicatedStorage")
    local modulesFolder = repStorage:FindFirstChild("Modules")
    local emotesFolder = modulesFolder and modulesFolder:FindFirstChild("Emotes")
    if emotesFolder then
        pcall(function()
            for _, obj in ipairs(emotesFolder:GetChildren()) do
                if obj:IsA("ModuleScript") and obj.Name ~= "EmoteClass" then
                    local nameLower = string.lower(obj.Name)
                    if not string.find(nameLower, "ennard") then
                        storedEmotes[obj.Name] = obj
                        table.insert(emoteDropdownList, obj.Name)
                    end
                end
            end
        end)
    end
    if #emoteDropdownList == 1 then table.insert(emoteDropdownList, "No Emotes Found") end
end

updateEmoteList()

local CustomOSTBox = Tabs.Fun:AddLeftGroupbox("Custom OST")
local storedMusic = {}
local musicDropdownList = {"Select Music File"}
local selectedMusicObj = nil

local function updateMusicList()
    table.clear(storedMusic)
    musicDropdownList = {"Select Music File"}
    local soundService = game:GetService("SoundService")
    local workspace = game:GetService("Workspace")

    local function scanFolder(folder)
        for _, obj in ipairs(folder:GetDescendants()) do
            if obj:IsA("Sound") and (obj.Name == "LobbyMusic" or (obj.Parent and obj.Parent.Name == "GAME MAP" and obj.Parent.Parent and obj.Parent.Parent.Name == "MAPS" and obj.Name == "Music") or (obj.Parent and obj.Parent.Name == "Sounds" and obj.Parent.Parent and obj.Parent.Parent.Name == "Assets" and obj.Parent.Parent.Parent and obj.Parent.Parent.Parent.Name == "SnakeGame" and obj.Parent.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent.Name == "Games" and obj.Parent.Parent.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent.Parent.Name == "Modules" and obj.Parent.Parent.Parent.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent.Parent.Parent.Name == "ReplicatedStorage" and obj.Name == "Music") or (obj.Parent and obj.Parent.Name == "ChaseThemes-Killer" and obj.Parent.Parent and obj.Parent.Parent.Name == "KILLER" and obj.Parent.Parent.Parent and obj.Parent.Parent.Parent.Name == "PLAYERS" and obj.Parent.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent.Name == "workspace") or obj.Name:lower():find("lms") or obj.Name:lower():find("map") or obj.Name:lower():find("chase") or obj.Parent.Name:lower():find("chasethemes") or (obj.Parent and obj.Parent.Name == "Phases" and obj.Parent.Parent and obj.Parent.Parent.Name == "KILLER" and obj.Parent.Parent.Parent and obj.Parent.Parent.Parent.Name == "PLAYERS" and obj.Parent.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent.Name == "workspace") or (obj.Parent and obj.Parent.Parent and obj.Parent.Parent.Name == "Emotes" and obj.Parent.Parent.Parent and obj.Parent.Parent.Parent.Name == "Modules" and obj.Parent.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent.Name == "ReplicatedStorage")) then
                storedMusic[obj.Name] = obj
                table.insert(musicDropdownList, obj.Name)
            end
        end
    end

    -- Scan SoundService and Workspace for music
    scanFolder(soundService)
    scanFolder(workspace)

    if #musicDropdownList == 1 then table.insert(musicDropdownList, "No Music Found") end
end

updateMusicList()

CustomOSTBox:AddDropdown("MusicSelect", {
    Values = musicDropdownList,
    Default = 1,
    Multi = false,
    Text = "Select Music",
    Callback = function(Value)
        if storedMusic[Value] then
            selectedMusicObj = storedMusic[Value]
        end
    end,
})

CustomOSTBox:AddInput("MP3Url", {
    Text = "Direct MP3 URL / Asset ID",
    Placeholder = "Enter direct MP3 URL or rbxassetid here",
    Default = "",
    Callback = function(Value)
        _G.CustomOST_MP3Url = Value
    end,
})

CustomOSTBox:AddButton({
    Text = "Scan Music Folders",
    Func = function()
        updateMusicList()
        Options.MusicSelect:SetValues(musicDropdownList)
        Library:Notify("Found " .. tostring(#musicDropdownList - 1) .. " music files!", 3)
    end
})

CustomOSTBox:AddButton({
    Text = "Play Selected / Custom OST",
    Func = function()
        local customSoundId = nil
        if selectedMusicObj then
            customSoundId = selectedMusicObj.SoundId
        elseif _G.CustomOST_MP3Url and string.len(_G.CustomOST_MP3Url) > 0 then
            if _G.CustomOST_MP3Url:match("^rbxassetid://%d+$") then
                customSoundId = _G.CustomOST_MP3Url
            elseif _G.CustomOST_MP3Url:match("^https?://.+\.mp3$") then
                customSoundId = _G.CustomOST_MP3Url
            else
                customSoundId = "rbxassetid://" .. (_G.CustomOST_MP3Url:match("%d+") or "")
            end
        end

        if customSoundId then
            -- Stop existing game music
            for _, sound in ipairs(game:GetService("SoundService"):GetDescendants()) do
                if sound:IsA("Sound") and (sound.Name:lower():find("lms") or sound.Name:lower():find("map") or sound.Name:lower():find("chase")) then
                    sound:Stop()
                end
            end

            -- Replace SoundId of specific game music objects
            local lobbyMusic = game:GetService("SoundService"):FindFirstChild("LobbyMusic")
            local gameMapMusic = workspace:FindFirstChild("MAPS") and workspace.MAPS:FindFirstChild("GAME MAP") and workspace.MAPS["GAME MAP"]:FindFirstChild("Music")
            local snakeGameMusic = game:GetService("ReplicatedStorage"):FindFirstChild("Modules") and game.ReplicatedStorage.Modules:FindFirstChild("Games") and game.ReplicatedStorage.Modules.Games:FindFirstChild("SnakeGame") and game.ReplicatedStorage.Modules.Games.SnakeGame:FindFirstChild("Assets") and game.ReplicatedStorage.Modules.Games.SnakeGame.Assets:FindFirstChild("Sounds") and game.ReplicatedStorage.Modules.Games.SnakeGame.Assets.Sounds:FindFirstChild("Music")
            local killerChaseThemesMusic = workspace:FindFirstChild("PLAYERS") and workspace.PLAYERS:FindFirstChild("KILLER") and workspace.PLAYERS.KILLER:FindFirstChild("ChaseThemes-Killer") and workspace.PLAYERS.KILLER["ChaseThemes-Killer"]:FindFirstChild("Music")
            local killerPhasesMusic = {}
            local killerFolder = workspace:FindFirstChild("PLAYERS") and workspace.PLAYERS:FindFirstChild("KILLER")
            if killerFolder then
                for _, killer in ipairs(killerFolder:GetChildren()) do
                    local phasesFolder = killer:FindFirstChild("Phases")
                    if phasesFolder then
                        for i = 1, 4 do
                            local phaseMusic = phasesFolder:FindFirstChild(tostring(i))
                            if phaseMusic and phaseMusic:IsA("Sound") then
                                table.insert(killerPhasesMusic, phaseMusic)
                            end
                        end
                    end
                end
            end

            _G.CustomOST_Active = true

            -- Stop any previously playing custom OST
            if _G.CustomOST_Sound then
                _G.CustomOST_Sound:Stop()
                _G.CustomOST_Sound:Destroy()
                _G.CustomOST_Sound = nil
            end

            -- Create and play the new custom OST
            _G.CustomOST_Sound = Instance.new("Sound")
            _G.CustomOST_Sound.SoundId = customSoundId
            _G.CustomOST_Sound.Parent = game:GetService("SoundService")
            _G.CustomOST_Sound.Looped = true
            _G.CustomOST_Sound.Volume = 1 -- Ensure custom music is audible
            _G.CustomOST_Sound:Play()

            -- Setup a loop to constantly mute game music while Custom OST is active
            if _G.CustomOST_MuteLoop then _G.CustomOST_MuteLoop:Disconnect() end
            _G.CustomOST_MuteLoop = game:GetService("RunService").Heartbeat:Connect(function()
                if not _G.CustomOST_Active then
                    if _G.CustomOST_MuteLoop then _G.CustomOST_MuteLoop:Disconnect() end
                    return
                end

                local allGameMusicObjects = {}
                local lobbyMusic = game:GetService("SoundService"):FindFirstChild("LobbyMusic")
                local gameMapMusic = workspace:FindFirstChild("MAPS") and workspace.MAPS:FindFirstChild("GAME MAP") and workspace.MAPS["GAME MAP"]:FindFirstChild("Music")
                local snakeGameMusic = game:GetService("ReplicatedStorage"):FindFirstChild("Modules") and game.ReplicatedStorage.Modules:FindFirstChild("Games") and game.ReplicatedStorage.Modules.Games:FindFirstChild("SnakeGame") and game.ReplicatedStorage.Modules.Games.SnakeGame:FindFirstChild("Assets") and game.ReplicatedStorage.Modules.Games.SnakeGame.Assets:FindFirstChild("Sounds") and game.ReplicatedStorage.Modules.Games.SnakeGame.Assets.Sounds:FindFirstChild("Music")
                local killerChaseThemesMusic = workspace:FindFirstChild("PLAYERS") and workspace.PLAYERS:FindFirstChild("KILLER") and workspace.PLAYERS.KILLER:FindFirstChild("ChaseThemes-Killer") and workspace.PLAYERS.KILLER["ChaseThemes-Killer"]:FindFirstChild("Music")
                
                if lobbyMusic then table.insert(allGameMusicObjects, lobbyMusic) end
                if gameMapMusic then table.insert(allGameMusicObjects, gameMapMusic) end
                if snakeGameMusic then table.insert(allGameMusicObjects, snakeGameMusic) end
                if killerChaseThemesMusic then table.insert(allGameMusicObjects, killerChaseThemesMusic) end
                
                local killerFolder = workspace:FindFirstChild("PLAYERS") and workspace.PLAYERS:FindFirstChild("KILLER")
                if killerFolder then
                    for _, killer in ipairs(killerFolder:GetChildren()) do
                        local phasesFolder = killer:FindFirstChild("Phases")
                        if phasesFolder then
                            for i = 1, 4 do
                                local phaseMusic = phasesFolder:FindFirstChild(tostring(i))
                                if phaseMusic and phaseMusic:IsA("Sound") then
                                    table.insert(allGameMusicObjects, phaseMusic)
                                end
                            end
                        end
                    end
                end

                for _, musicObj in ipairs(allGameMusicObjects) do
                    if musicObj.Volume > 0 then
                        musicObj.Volume = 0
                    end
                end
            end)

            Library:Notify("Playing Custom OST! (Game music muted)", 3)
        else
            Library:Notify("Error: Please select a music file or enter an MP3 URL/Asset ID first.", 3)
        end
    end,
})

local EmotesBox = Tabs.Fun:AddLeftGroupbox("Emote Menu")
EmotesBox:AddDropdown("EmoteSelect", {
    Values = emoteDropdownList,
    Default = 1,
    Multi = false,
    Text = "Select Emote",
    Callback = function(Value)
        if storedEmotes[Value] then
            selectedEmoteObj = storedEmotes[Value]
        end
    end,
})

EmotesBox:AddButton({
    Text = "Scan Emotes Folder",
    Func = function()
        updateEmoteList()
        Options.EmoteSelect:SetValues(emoteDropdownList)
        Library:Notify("Found " .. tostring(#emoteDropdownList - 1) .. " Emotes!", 3)
    end
})

EmotesBox:AddToggle("PlayEmoteToggle", {
    Text = "Play Emote",
    Default = false,
    Callback = function(Value)
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        local rootPart = char and char:FindFirstChild("HumanoidRootPart")

        if Value then
            if selectedEmoteObj and animator then
                pcall(function()
                    local anim = selectedEmoteObj:FindFirstChildOfClass("Animation")
                    if anim then
                        activeEmoteTrack = animator:LoadAnimation(anim)
                        activeEmoteTrack.Looped = true
                        activeEmoteTrack:Play()
                    else
                        local emoteData = require(selectedEmoteObj)
                        if type(emoteData) == "table" and emoteData.AnimationId then
                            local tempAnim = Instance.new("Animation")
                            tempAnim.AnimationId = emoteData.AnimationId
                            activeEmoteTrack = animator:LoadAnimation(tempAnim)
                            activeEmoteTrack.Looped = true
                            activeEmoteTrack:Play()
                        end
                    end

                    for _, child in ipairs(selectedEmoteObj:GetDescendants()) do
                        if child:IsA("Sound") then
                            local sfx = child:Clone()
                            sfx.Parent = rootPart or char
                            sfx:Play()
                            table.insert(activeEffects, sfx)
                        elseif child:IsA("ParticleEmitter") or child:IsA("PointLight") then
                            local fx = child:Clone()
                            fx.Parent = rootPart
                            table.insert(activeEffects, fx)
                        elseif child:IsA("MeshPart") or child:IsA("Part") then
                            local prop = child:Clone()
                            prop.Parent = char
                            local weld = Instance.new("WeldConstraint")
                            weld.Part0 = char:FindFirstChild("RightHand") or rootPart
                            weld.Part1 = prop
                            weld.Parent = prop
                            prop.CanCollide = false
                            prop.Massless = true
                            table.insert(activeEffects, prop)
                        end
                    end
                end)
            else
                Library:Notify("Select an emote first!", 2)
                Toggles.PlayEmoteToggle:SetValue(false)
            end
        else
            if activeEmoteTrack then
                activeEmoteTrack:Stop()
                activeEmoteTrack = nil
            end
            for _, effect in ipairs(activeEffects) do
                if effect and effect.Parent then
                    effect:Destroy()
                end
            end
            table.clear(activeEffects)
        end
    end,
})

local SnakeBox = Tabs.Fun:AddLeftGroupbox("Snake Menu")
_G.SnakeGod = false
local function hookSnakeGod()
    for _, t in ipairs(getgc(true)) do
        if type(t) == "table"
            and rawget(t, "ClassName") == "Game"
            and rawget(t, "CheckForDeath")
            and not t._GodHooked
        then
            local original = t.CheckForDeath
            t.CheckForDeath = newcclosure(function(self, ...)
                if _G.SnakeGod then
                    return false
                end
                return original(self, ...)
            end)
            t._GodHooked = true
        end
    end
end

SnakeBox:AddToggle("SnakeGodMode", {
    Text = "Snake God Mode",
    Default = false,
    Callback = function(Value)
        _G.SnakeGod = Value
        if Value then
            hookSnakeGod()
            task.spawn(function()
                while _G.SnakeGod do
                    hookSnakeGod()
                    task.wait(1)
                end
            end)
        end
    end
})



local TasksBox = Tabs.Tasks:AddLeftGroupbox("Automation")
local autoRepairEnabled = false
local autoRepairTask = nil
local repairInterval = 0.5

TasksBox:AddToggle("AutoRepair", {
    Text = "Auto-Repair Generators",
    Default = false,
    Callback = function(Value)
        autoRepairEnabled = Value
        if Value then
            if not autoRepairTask then
                autoRepairTask = task.spawn(function()
                    while autoRepairEnabled do
                        local genUI = LocalPlayer.PlayerGui:FindFirstChild("Gen")
                        if genUI then
                            local main = genUI:FindFirstChild("GeneratorMain")
                            local evt = main and main:FindFirstChild("Event")
                            if evt and evt:IsA("RemoteEvent") then
                                evt:FireServer(true)
                            end
                        end
                        task.wait(repairInterval)
                    end
                    autoRepairTask = nil
                end)
            end
        else
            autoRepairEnabled = false
        end
    end,
})

TasksBox:AddSlider("RepairInterval", {
    Text = "Auto-Repair Interval",
    Default = 0.5,
    Min = 0.1,
    Max = 15,
    Rounding = 1,
    Suffix = "s",
    Callback = function(Value)
        repairInterval = Value
    end,
})

local autoShakeConn = nil
TasksBox:AddToggle("AutoShakeMinion", {
    Text = "Auto-Shake Minions",
    Default = false,
    Callback = function(Value)
        if Value then
            autoShakeConn = RunService.RenderStepped:Connect(function()
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if not root then return end
                
                local attached = false
                for obj, _ in pairs(espData.minions) do
                    if obj and obj.Parent then
                        local pos = (obj:IsA("Model") and obj:GetPivot().Position) or (obj:IsA("BasePart") and obj.Position)
                        if pos and (root.Position - pos).Magnitude < 4.5 then
                            attached = true
                            break
                        end
                    end
                end
                
                if attached then
                    local cam = Workspace.CurrentCamera
                    local rx = math.rad(math.random(-60, 60))
                    local ry = math.rad(math.random(-60, 60))
                    cam.CFrame = cam.CFrame * CFrame.Angles(rx, ry, 0)
                end
            end)
        else
            if autoShakeConn then autoShakeConn:Disconnect() autoShakeConn = nil end
        end
    end,
})

local instantPromptEnabled = false
local instantPromptConn = nil

local function setInstantPrompts(state)
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            if state then
                if obj.HoldDuration ~= 0 then
                    obj:SetAttribute("HoldDurationOld", obj.HoldDuration)
                    obj.HoldDuration = 0
                end
                obj.ClickableDuringHold = true 
            else
                local old = obj:GetAttribute("HoldDurationOld")
                if old and old ~= 0 then obj.HoldDuration = old end
            end
        end
    end
end

TasksBox:AddToggle("InstantPromptToggle", {
    Text = "Instant Prompts",
    Default = false,
    Callback = function(Value)
        instantPromptEnabled = Value
        setInstantPrompts(Value)
        if Value then
            if not instantPromptConn then
                instantPromptConn = true
                task.spawn(function()
                    while instantPromptEnabled do
                        local folders = {workspace:FindFirstChild("MAPS"), workspace:FindFirstChild("INTERACTABLES"), workspace:FindFirstChild("EQUIPMENT")}
                        for _, folder in ipairs(folders) do
                            if folder then
                                for _, obj in ipairs(folder:GetDescendants()) do
                                    if not instantPromptEnabled then break end
                                    if obj:IsA("ProximityPrompt") and obj.HoldDuration ~= 0 then
                                        obj:SetAttribute("HoldDurationOld", obj.HoldDuration)
                                        obj.HoldDuration = 0
                                        obj.ClickableDuringHold = true 
                                    end
                                end
                            end
                        end
                        task.wait(2)
                    end
                    instantPromptConn = nil
                end)
            end
        else
            if instantPromptConn then 
                instantPromptConn = nil 
            end
        end
    end,
})


local dotConn = nil
TasksBox:AddToggle("PerfectBarricade", {
    Text = "Perfect Barricade",
    Default = false,
    Callback = function(Value)
        if Value then
            local playerGui = LocalPlayer:WaitForChild("PlayerGui")
            dotConn = RunService.RenderStepped:Connect(function()
                local dot = playerGui:FindFirstChild("Dot")
                if dot and dot:IsA("ScreenGui") and dot.Enabled then
                    local c = dot:FindFirstChild("Container")
                    local f = c and c:FindFirstChild("Frame")
                    if f then
                        f.AnchorPoint = Vector2.new(0.5, 0.5)
                        f.Position = UDim2.new(0.5, 0, 0.5, 0)
                    end
                end
            end)
        else
            if dotConn then dotConn:Disconnect() dotConn = nil end
        end
    end,
})

local autoKillConn = nil
TasksBox:AddToggle("AutoKill", {
    Text = "Auto-Kill (Killer Only)",
    Default = false,
    Callback = function(Value)
        if Value then
            autoKillConn = RunService.Heartbeat:Connect(function()
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if not root then return end
                local closest, dist = nil, math.huge
                local p = getPlayersFolder()
                local aliveFolder = p and p:FindFirstChild("ALIVE")
                if aliveFolder then
                    for _, v in ipairs(aliveFolder:GetChildren()) do
                        local hrp = v:FindFirstChild("HumanoidRootPart")
                        if hrp and v ~= char then
                            local d = (root.Position - hrp.Position).Magnitude
                            if d < dist then dist = d; closest = v end
                        end
                    end
                end
                if closest and closest:FindFirstChild("HumanoidRootPart") then
                    local targetPos = closest.HumanoidRootPart.Position
                    local dir = (targetPos - root.Position).Unit
                    if dist > 6 then
                        root.CFrame = root.CFrame + (dir * 1.5) 
                    else
                        root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetPos.X, root.Position.Y, targetPos.Z))
                        local tool = char:FindFirstChildOfClass("Tool")
                        if tool then tool:Activate() end
                    end
                end
            end)
        else
            if autoKillConn then autoKillConn:Disconnect() autoKillConn = nil end
        end
    end,
})

local AutoFarmBox = Tabs.AutoFarm:AddLeftGroupbox("Auto-Farm")

local function notify2(title, msg)
    Library:Notify("[" .. title .. "] " .. msg, 3)
end

local autoEscape = false
local autoEscapeConn

AutoFarmBox:AddToggle("AutoEscapeToggle", {
    Text = "Auto Escape",
    Default = false,
    Callback = function(state)
        autoEscape = state
        local player = game.Players.LocalPlayer
        if state then
            notify2("Auto Escape", "Enabled.")
            local teleported = false
            autoEscapeConn = game:GetService("RunService").RenderStepped:Connect(function()
                if teleported or not autoEscape then return end
                local char = player.Character
                if not char then return end
                if not workspace.GAME.CAN_ESCAPE.Value then return end
                local playersFolder = workspace:FindFirstChild("PLAYERS")
                if not playersFolder or char.Parent ~= playersFolder:FindFirstChild("ALIVE") then return end
                local gameMap = workspace.MAPS:FindFirstChild("GAME MAP")
                if not gameMap then return end
                local escapes = gameMap:FindFirstChild("Escapes")
                if not escapes then return end
                for _,part in pairs(escapes:GetChildren()) do
                    if part:IsA("BasePart") and part:GetAttribute("Enabled") then
                        local highlight = part:FindFirstChildOfClass("Highlight")
                        if highlight and highlight.Enabled then
                            local root = char:FindFirstChild("HumanoidRootPart")
                            if root then
                                teleported = true
                                root.Anchored = true
                                char.PrimaryPart.CFrame = part.CFrame
                                task.delay(1.5, function() if root then root.Anchored = false end end)
                                task.delay(10, function() teleported = false end)
                            end
                        end
                    end
                end
            end)
        else
            if autoEscapeConn then autoEscapeConn:Disconnect() end
            notify2("Auto Escape", "Disabled.")
        end
    end,
})

AutoFarmBox:AddToggle("AutoFarmKill", {
    Text = "Auto-Kill All (Killers Only)",
    Default = false,
    Callback = function(Value)
        if Value then
            autoKillConn = RunService.Heartbeat:Connect(function()
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if not root then return end
                local closest, dist = nil, math.huge
                local p = getPlayersFolder()
                local aliveFolder = p and p:FindFirstChild("ALIVE")
                if aliveFolder then
                    for _, v in ipairs(aliveFolder:GetChildren()) do
                        local hrp = v:FindFirstChild("HumanoidRootPart")
                        if hrp and v ~= char then
                            local d = (root.Position - hrp.Position).Magnitude
                            if d < dist then dist = d; closest = v end
                        end
                    end
                end
                if closest and closest:FindFirstChild("HumanoidRootPart") then
                    local targetPos = closest.HumanoidRootPart.Position
                    local dir = (targetPos - root.Position).Unit
                    if dist > 6 then
                        root.CFrame = root.CFrame + (dir * 1.5) 
                    else
                        root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetPos.X, root.Position.Y, targetPos.Z))
                        local tool = char:FindFirstChildOfClass("Tool")
                        if tool then tool:Activate() end
                    end
                end
            end)
        else
            if autoKillConn then autoKillConn:Disconnect() autoKillConn = nil end
        end
    end,
})

local autoGenEnabled = false
local autoGenTask = nil

local function instantCompleteGenerator(genModel)
    local genUI = LocalPlayer.PlayerGui:FindFirstChild("Gen")
    if genUI then
        local main = genUI:FindFirstChild("GeneratorMain")
        local evt = main and main:FindFirstChild("Event")
        if evt and evt:IsA("RemoteEvent") then
            for i = 1, 20 do
                evt:FireServer(true)
            end
        end
    end
    pcall(function()
        if genModel and genModel.Parent then
            genModel:SetAttribute("Progress", 100)
        end
    end)
end

local function findSafeZoneOrExit()
    local maps = workspace:FindFirstChild("MAPS")
    local gameMap = maps and maps:FindFirstChild("GAME MAP")
    if gameMap then
        local escapes = gameMap:FindFirstChild("Escapes")
        if escapes then
            for _, part in pairs(escapes:GetChildren()) do
                if part:IsA("BasePart") then
                    return part.CFrame
                end
            end
        end
        local safeZone = gameMap:FindFirstChild("SafeZone") or gameMap:FindFirstChild("Safe Zone") or gameMap:FindFirstChild("Lobby")
        if safeZone then
            local part = safeZone:FindFirstChildWhichIsA("BasePart")
            if part then return part.CFrame end
        end
    end
    return nil
end

local function getAllGenerators()
    local gens = {}
    local maps = workspace:FindFirstChild("MAPS")
    if maps then
        for _, v in ipairs(maps:GetDescendants()) do
            if v:IsA("Model") and v.Name == "Generator" then
                local prog = v:GetAttribute("Progress") or 0
                local done = v:GetAttribute("Completed") or v:GetAttribute("Repaired") or false
                if not done and prog < 100 then
                    table.insert(gens, v)
                end
            end
        end
    end
    return gens
end

AutoFarmBox:AddToggle("AutoCompleteGens", {
    Text = "Auto-Complete All Generators",
    Default = false,
    Callback = function(Value)
        autoGenEnabled = Value
        if Value then
            notify2("Auto-Complete Gens", "Enabled. Walking to generators...")
            if autoGenTask then task.cancel(autoGenTask) end
            autoGenTask = task.spawn(function()
                while autoGenEnabled do
                    local char = LocalPlayer.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if not root or not hum then task.wait(1) continue end

                    local gens = getAllGenerators()
                    if #gens == 0 then
                        notify2("Auto-Complete Gens", "All generators done! Moving to exit.")
                        local safeCF = findSafeZoneOrExit()
                        if safeCF and root then
                            root.CFrame = safeCF * CFrame.new(0, 0, -2)
                        end
                        task.wait(5)
                        continue
                    end

                    for _, gen in ipairs(gens) do
                        if not autoGenEnabled then break end
                        char = LocalPlayer.Character
                        root = char and char:FindFirstChild("HumanoidRootPart")
                        hum = char and char:FindFirstChildOfClass("Humanoid")
                        if not root or not hum then break end

                        local prog = gen:GetAttribute("Progress") or 0
                        local done = gen:GetAttribute("Completed") or gen:GetAttribute("Repaired") or false
                        if done or prog >= 100 then continue end

                        local genPart = gen.PrimaryPart or gen:FindFirstChildWhichIsA("BasePart")
                        if not genPart then continue end

                        local genPos = genPart.Position
                        local dist = (root.Position - genPos).Magnitude

                        if dist > 5 then
                            local steps = math.ceil(dist / 10)
                            for s = 1, steps do
                                if not autoGenEnabled then break end
                                char = LocalPlayer.Character
                                root = char and char:FindFirstChild("HumanoidRootPart")
                                if not root then break end
                                local currentDist = (root.Position - genPos).Magnitude
                                if currentDist <= 5 then break end
                                local dir = (genPos - root.Position).Unit
                                root.CFrame = CFrame.new(root.Position + dir * math.min(10, currentDist - 4), genPos)
                                task.wait(0.05)
                            end
                        end

                        task.wait(0.1)
                        instantCompleteGenerator(gen)
                        task.wait(0.3)

                        local genUI = LocalPlayer.PlayerGui:FindFirstChild("Gen")
                        if genUI then
                            local main = genUI:FindFirstChild("GeneratorMain")
                            local evt = main and main:FindFirstChild("Event")
                            if evt and evt:IsA("RemoteEvent") then
                                for i = 1, 30 do
                                    evt:FireServer(true)
                                    task.wait(0.05)
                                end
                            end
                        end

                        task.wait(0.2)
                    end

                    if autoGenEnabled then
                        local safeCF = findSafeZoneOrExit()
                        if safeCF then
                            char = LocalPlayer.Character
                            root = char and char:FindFirstChild("HumanoidRootPart")
                            if root then
                                local parts = {}
                                if char then
                                    for _, p in ipairs(char:GetDescendants()) do
                                        if p:IsA("BasePart") then
                                            p.CanCollide = false
                                            table.insert(parts, p)
                                        end
                                    end
                                end
                                root.CFrame = safeCF * CFrame.new(0, 0, -1)
                                task.wait(1)
                                for _, p in ipairs(parts) do
                                    if p and p.Parent then p.CanCollide = true end
                                end
                            end
                        end
                    end

                    task.wait(2)
                end
                autoGenTask = nil
            end)
        else
            autoGenEnabled = false
            if autoGenTask then task.cancel(autoGenTask) autoGenTask = nil end
            notify2("Auto-Complete Gens", "Disabled.")
        end
    end,
})

local LocalBox = Tabs.Local:AddLeftGroupbox("Player Modifications")
local sprintConn = nil
local charAddConn = nil

local customStaminaAmount = math.huge
local stamConn = nil

local function setStamina()
    if stamConn then stamConn:Disconnect(); stamConn = nil; end;
    local char = LocalPlayer.Character;
    if not char then return end;
    stamConn = RunService.Heartbeat:Connect(function()
        local c = LocalPlayer.Character;
        if not c then return end;
        local mx = c:GetAttribute("MaxStamina") or 100;
        if (c:GetAttribute("Stamina") or mx) < mx then
            c:SetAttribute("Stamina", mx);
        end;
    end);
end;

LocalBox:AddToggle("InfStam", {
    Text = "Infinite Stamina",
    Default = false,
    Callback = function(Value)
        if Value then
            setStamina();
            if not charAddConn then
                charAddConn = LocalPlayer.CharacterAdded:Connect(function()
                    task.wait(1);
                    if Toggles.InfStam.Value then
                        setStamina();
                    end
                end);
            end
        else
            if stamConn then stamConn:Disconnect(); stamConn = nil; end;
            if charAddConn then charAddConn:Disconnect(); charAddConn = nil; end;
        end
    end,
})


LocalBox:AddInput("CustomStam", {
    Default = "",
    Text = "Custom stamina amount (Legacy)",
    Placeholder = "Currently unused...",
    Callback = function(Text) end,
})

local noclipTask = nil
local noclipCharAdd = nil
local noclipParts = {}
LocalBox:AddToggle("Noclip", {
    Text = "Noclip",
    Default = false,
    Callback = function(Value)
        if Value then
            local function cacheParts()
                table.clear(noclipParts)
                local char = LocalPlayer.Character
                if not char then return end
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then table.insert(noclipParts, part) end
                end
            end
            cacheParts()
            noclipCharAdd = LocalPlayer.CharacterAdded:Connect(function()
                task.wait(0.5)
                cacheParts()
            end)
            noclipTask = RunService.Stepped:Connect(function()
                for i = 1, #noclipParts do
                    local p = noclipParts[i]
                    if p.Parent then p.CanCollide = false end
                end
            end)
        else
            if noclipTask then noclipTask:Disconnect() noclipTask = nil end
            if noclipCharAdd then noclipCharAdd:Disconnect() noclipCharAdd = nil end
            table.clear(noclipParts)
        end
    end,
})

local pcFlyConn = nil
LocalBox:AddToggle("FlyPC", {
    Text = "Advanced Fly (PC)",
    Default = false,
    Callback = function(Value)
        if Value then
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not root then return end
            char:FindFirstChildOfClass("Humanoid").PlatformStand = true
            root.Anchored = true
            pcFlyConn = RunService.RenderStepped:Connect(function(dt)
                if not root or not root.Parent then return end
                local move = Vector3.zero
                local speed = 100
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += Camera.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= Camera.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= Camera.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += Camera.CFrame.RightVector end
                if move.Magnitude > 0 then
                    root.CFrame = root.CFrame + (move.Unit * (speed * dt))
                end
                root.CFrame = CFrame.new(root.Position, root.Position + Camera.CFrame.LookVector)
            end)
        else
            if pcFlyConn then pcFlyConn:Disconnect() pcFlyConn = nil end
            local char = LocalPlayer.Character
            if char then
                char:FindFirstChildOfClass("Humanoid").PlatformStand = false
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then root.Anchored = false end
            end
        end
    end,
})

local mobileFlyConn = nil
LocalBox:AddToggle("FlyMobile", {
    Text = "Advanced Fly (Mobile)",
    Default = false,
    Callback = function(Value)
        if Value then
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not root or not hum then return end
            hum.PlatformStand = true
            root.Anchored = true
            mobileFlyConn = RunService.RenderStepped:Connect(function(dt)
                if not root or not root.Parent then return end
                local moveDir = hum.MoveDirection
                local speed = 100
                if moveDir.Magnitude > 0.1 then
                    local camLook = Camera.CFrame.LookVector
                    local camRight = Camera.CFrame.RightVector
                    local moveCalc = (camLook * moveDir.Z * -1) + (camRight * moveDir.X)
                    root.CFrame = root.CFrame + (moveCalc * (speed * dt))
                end
                root.CFrame = CFrame.new(root.Position, root.Position + Camera.CFrame.LookVector)
            end)
        else
            if mobileFlyConn then mobileFlyConn:Disconnect() mobileFlyConn = nil end
            local char = LocalPlayer.Character
            if char then
                char:FindFirstChildOfClass("Humanoid").PlatformStand = false
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then root.Anchored = false end
            end
        end
    end,
})

local VisualsBox = Tabs.Visuals:AddLeftGroupbox("ESP Features")
local fbLoop = nil
VisualsBox:AddToggle("FullBright", {
    Text = "Full Brightness",
    Default = false,
    Callback = function(Value)
        if Value then
            fbLoop = RunService.Heartbeat:Connect(function()
                Lighting.GlobalShadows = false
                Lighting.ClockTime = 14
                local cam = Workspace.CurrentCamera
                if cam and not cam:FindFirstChild("RepzFBLight") then
                    local light = Instance.new("PointLight")
                    light.Name = "RepzFBLight"
                    light.Brightness = 2.5
                    light.Range = 250
                    light.Shadows = false
                    light.Parent = cam
                end
            end)
        else
            if fbLoop then fbLoop:Disconnect() fbLoop = nil end
            Lighting.GlobalShadows = true
            local cam = Workspace.CurrentCamera
            if cam and cam:FindFirstChild("RepzFBLight") then
                cam.RepzFBLight:Destroy()
            end
        end
    end,
})

local autoSuppressEnabled = false
local suppressConns = {}
local function initHighlightSuppress(char)
    if not char then return end
    local function check(h)
        if h:IsA("Highlight") and (h.Name == "Highlight" or h.Name == "HIGHLIGHT") then
            local r, g, b = math.floor(h.FillColor.R*255), math.floor(h.FillColor.G*255), math.floor(h.FillColor.B*255)
            if h.DepthMode == Enum.HighlightDepthMode.Occluded or (r >= 250 and g <= 10 and b <= 10) then
                local function sync()
                    if autoSuppressEnabled then
                        if h.FillTransparency ~= 1 then h.FillTransparency = 1 end
                        if h.OutlineTransparency ~= 1 then h.OutlineTransparency = 1 end
                    end
                end
                sync()
                table.insert(suppressConns, h:GetPropertyChangedSignal("FillTransparency"):Connect(sync))
                table.insert(suppressConns, h:GetPropertyChangedSignal("OutlineTransparency"):Connect(sync))
                table.insert(suppressConns, h:GetPropertyChangedSignal("FillColor"):Connect(sync))
            end
        end
    end
    for _, v in ipairs(char:GetDescendants()) do check(v) end
    table.insert(suppressConns, char.DescendantAdded:Connect(check))
end

for i = 1, 64 do
    pcall(function()
        local h = Ins("Highlight")
        h.Enabled = true
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.OutlineTransparency = 0
        h.FillTransparency = 0.5
        h.Parent = TargetGUI
        espData.pool[i] = h
    end)
end

local activeTargets = {}
local targetsPool = {}
local espCategories = {
    {name = "killers", tbl = espData.killers, prio = 0},
    {name = "survivors", tbl = espData.survivors, prio = 10},
    {name = "traps", tbl = espData.traps, prio = 50},
    {name = "minions", tbl = espData.minions, prio = 60},
    {name = "generators", tbl = espData.generators, prio = 200},
    {name = "batteries", tbl = espData.batteries, prio = 300},
    {name = "fuses", tbl = espData.fuses, prio = 400}
}

local function runPoolESP()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    
    if not isRoundActive() then
        for i = 1, 64 do
            local h = espData.pool[i]
            if h and h.Enabled then h.Adornee = nil; h.Enabled = false end
        end
        return
    end

    local camPos = cam.CFrame.Position
    local screenSize = cam.ViewportSize
    
    local targetsCount = 0
    
    if not espData._fuseBoxes or not espData._fuseBoxes:IsDescendantOf(workspace) then
        local maps = workspace:FindFirstChild("MAPS")
        local gameMap = maps and maps:FindFirstChild("GAME MAP")
        espData._fuseBoxes = gameMap and gameMap:FindFirstChild("FuseBoxes")
    end
    local fuseBoxes = espData._fuseBoxes
    
    local currentFusePositions = {}
    if fuseBoxes then
        for _, fuse in ipairs(fuseBoxes:GetChildren()) do
            local fPos = (fuse:IsA("Model") and fuse:GetPivot().Position) or (fuse:IsA("BasePart") and fuse.Position)
            if fPos then table.insert(currentFusePositions, fPos) end
        end
    end
    
    for _, cat in ipairs(espCategories) do
        local tblName = cat.name
        local tbl = cat.tbl
        local priority = cat.prio or 1000
        
        for obj, colorInfo in pairs(tbl) do
            if not obj or not obj.Parent then
                tbl[obj] = nil
                continue
            end
            
            local bPos = (obj:IsA("Model") and obj:GetPivot().Position) or (obj:IsA("BasePart") and obj.Position)
            if bPos then
                local dist = (camPos - bPos).Magnitude
                if dist < 5000 then
                    local isRelevant = false
                    if dist < 80 then
                        isRelevant = true
                    else
                        local sPos, onScreen = cam:WorldToViewportPoint(bPos)
                        isRelevant = (sPos.Z > 0 and (sPos.X > -350 and sPos.X < screenSize.X + 350) and (sPos.Y > -350 and sPos.Y < screenSize.Y + 350))
                    end
                
                    if isRelevant then
                        local isDocked = false
                        if tblName == "batteries" and fuseBoxes then
                            if obj:IsDescendantOf(fuseBoxes) then
                                isDocked = true
                            else
                                for _, fPos in ipairs(currentFusePositions) do
                                    if (bPos - fPos).Magnitude < 1.5 then isDocked = true break end
                                end
                            end
                        end
                        
                        if not isDocked then
                            targetsCount = targetsCount + 1
                            local t = targetsPool[targetsCount]
                            if not t then
                                t = {}
                                targetsPool[targetsCount] = t
                            end
                            t.obj = obj
                            t.dist = dist
                            t.prio = priority
                            t.fill = colorInfo.fill
                            t.outline = colorInfo.outline or colorInfo.fill
                            activeTargets[targetsCount] = t
                        end
                    end
                end
            end
        end
    end
    
    for i = targetsCount + 1, #activeTargets do
        activeTargets[i] = nil
    end
    
    table.sort(activeTargets, function(a, b) 
        if a.prio ~= b.prio then return a.prio < b.prio end
        return a.dist < b.dist 
    end)
    
    for i = 1, 64 do
        local h = espData.pool[i]
        local target = activeTargets[i]
        if target and i <= 31 then
            if target.obj:IsA("Model") and target.prio == 10 then
                local c = getSurvivorColor(target.obj)
                h.FillColor, h.OutlineColor = c, c
            else
                h.FillColor, h.OutlineColor = target.fill, target.outline
            end
            h.Adornee = target.obj
            h.Enabled = true
        else
            if h.Enabled then
                h.Adornee = nil 
                h.Enabled = false
            end
        end
    end
end

local espUpdateTick = 0
espData.highlightTaskLoop = RunService.Heartbeat:Connect(function()
    local now = tick()
    if now - espUpdateTick < 0.05 then return end
    espUpdateTick = now
    pcall(runPoolESP)
end)

local function runTextESP()
    local cam = Workspace.CurrentCamera
    if not cam then return end

    if not isRoundActive() then
        if espData.texts then
            for _, data in pairs(espData.texts) do
                if data.gui then data.gui.Enabled = false end
            end
        end
        if espData.genBills then
            for _, data in pairs(espData.genBills) do
                if data.bill then data.bill.Enabled = false end
            end
        end
        return
    end

    local screenSize = cam.ViewportSize
    
    local function processTextTable(tbl, keyIsGUI)
        if type(tbl) ~= "table" then return end
        for c, data in pairs(tbl) do
            local gui = keyIsGUI and data.bill or data.gui
            if not (c and c.Parent and c:IsDescendantOf(workspace)) then
                pcall(function() if gui then gui:Destroy() end end)
                tbl[c] = nil
                continue
            end

            if gui and gui.Parent then
                local adornee = gui.Adornee
                local aPos = adornee and (adornee:IsA("BasePart") and adornee.Position or (adornee:IsA("Model") and adornee:GetPivot().Position))
                if aPos then
                    local dist = (cam.CFrame.Position - aPos).Magnitude
                    if dist < 60 then
                        gui.Enabled = true
                    else
                        local sPos, onScreen = cam:WorldToViewportPoint(aPos)
                        gui.Enabled = (sPos.Z > 0 and (sPos.X > -250 and sPos.X < screenSize.X + 250) and (sPos.Y > -250 and sPos.Y < screenSize.Y + 250))
                    end
                end
            end
        end
    end
    
    processTextTable(espData.texts, false)
    processTextTable(espData.genBills, true)
end

local textUpdateTick = 0
espData.textTaskLoop = RunService.Heartbeat:Connect(function()
    local now = tick()
    if now - textUpdateTick < 0.07 then return end
    textUpdateTick = now
    pcall(runTextESP)
end)

local function addESP(tbl, obj, fillColor, outlineColor)
    if obj and obj ~= LocalPlayer.Character then tbl[obj] = {fill = fillColor, outline = outlineColor} end
end
local function removeESP(tbl, obj)
    if tbl then tbl[obj] = nil end
end
local function clearESP(tbl)
    if tbl then table.clear(tbl) end
end

local function addSimpleTextLabel(obj, textLabel, color, offset)
    if not obj or not obj.Parent then return end
    if espData.texts[obj] and espData.texts[obj].gui then return espData.texts[obj].gui end

    local bill = Ins("BillboardGui")
    bill.Name = "RepzSimpleESP"
    
    local adornee = obj
    if obj:IsA("Model") then
        adornee = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart") or obj
    end
    bill.Adornee = adornee
    
    bill.Size = U2(0, 100, 0, 30)
    bill.StudsOffset = offset or V3(0, 2, 0)
    bill.AlwaysOnTop = true
    bill.MaxDistance = 2500
    bill.Parent = TargetGUI

    local txt = Ins("TextLabel", bill)
    txt.Size = U2(1, 0, 1, 0)
    txt.BackgroundTransparency = 1
    txt.Text = textLabel
    txt.TextColor3 = color
    txt.TextStrokeTransparency = 0
    txt.Font = Enum.Font.GothamBold
    txt.TextSize = 14
    return bill
end

local function addTextESP(char, roleColor)
    if char == LocalPlayer.Character then return end
    if espData.texts[char] or pendingESP[char] then return end
    pendingESP[char] = true

    for _, name in pairs({"RepzHeaderESP", "RepzBodyESP", "RepzNameESP", "RepzMainESP"}) do
        local old = char:FindFirstChild(name, true)
        if old then old:Destroy() end
    end
    if espData.texts[char] then
        local data = espData.texts[char]
        if data.conns then for _, c in ipairs(data.conns) do if c then c:Disconnect() end end end
        if data.gui then data.gui:Destroy() end
        espData.texts[char] = nil
    end

    local adornee = nil
    for i = 1, 15 do
        adornee = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildWhichIsA("BasePart")
        if adornee then break end
        task.wait(0.3)
    end
    if not adornee then 
        pendingESP[char] = nil
        return 
    end
    
    local billboard = Ins("BillboardGui")
    billboard.Name = "RepzMainESP"
    billboard.Adornee = adornee
    billboard.Size = U2(0, 150, 0, 80)
    billboard.StudsOffset = V3(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 2500
    billboard.Parent = TargetGUI

    local layout = Ins("UIListLayout")
    layout.Parent = billboard
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UD(0, 1)

    local infoLabel = Ins("TextLabel")
    infoLabel.Name = "InfoLabel"
    infoLabel.Parent = billboard
    infoLabel.LayoutOrder = 1
    infoLabel.BackgroundTransparency = 1
    infoLabel.Size = U2(1, 0, 0, 30)
    infoLabel.Font = Enum.Font.GothamBold
    infoLabel.TextSize = 12
    infoLabel.RichText = true
    infoLabel.TextStrokeTransparency = 0
    infoLabel.TextStrokeColor3 = C3(0, 0, 0)

    local isKiller = (char.Parent and char.Parent.Name == "KILLER")
    local colRole = isKiller and C3(255, 80, 80) or roleColor
    local colName = isKiller and C3(255, 150, 150) or C3(100, 255, 100)
    local roleTitle = getRoleLabel(char)
    infoLabel.Text = string.format("<font color='%s'>%s</font>\n<font color='%s'>%s</font>", toHex(colRole), roleTitle, toHex(colName), char.Name)

    local hBarBg = Ins("Frame")
    hBarBg.Name = "HealthBar"
    hBarBg.Parent = billboard
    hBarBg.LayoutOrder = 3
    hBarBg.BackgroundColor3 = C3(40, 40, 40)
    hBarBg.BorderSizePixel = 0
    hBarBg.Size = U2(0, 100, 0, 10)

    local hBarFill = Ins("Frame")
    hBarFill.Name = "Fill"
    hBarFill.Parent = hBarBg
    hBarFill.BackgroundColor3 = C3(0, 255, 0)
    hBarFill.BorderSizePixel = 0
    hBarFill.Size = U2(1, 0, 1, 0)

    local hpTxt = Ins("TextLabel")
    hpTxt.Parent = hBarBg
    hpTxt.BackgroundTransparency = 1
    hpTxt.Size = U2(1, 0, 1, 0)
    hpTxt.Font = Enum.Font.GothamBold
    hpTxt.TextSize = 9
    hpTxt.TextColor3 = C3(255, 255, 255)
    hpTxt.TextStrokeTransparency = 0.5
    hpTxt.ZIndex = 3

    local sBarBg = Ins("Frame")
    sBarBg.Name = "StaminaBar"
    sBarBg.Parent = billboard
    sBarBg.LayoutOrder = 4
    sBarBg.BackgroundColor3 = C3(40, 40, 40)
    sBarBg.BorderSizePixel = 0
    sBarBg.Size = U2(0, 100, 0, 10)

    local sBarFill = Ins("Frame")
    sBarFill.Name = "Fill"
    sBarFill.Parent = sBarBg
    sBarFill.BackgroundColor3 = C3(100, 200, 255)
    sBarFill.BorderSizePixel = 0
    sBarFill.Size = U2(1, 0, 1, 0)

    local stamTxt = Ins("TextLabel")
    stamTxt.Parent = sBarBg
    stamTxt.BackgroundTransparency = 1
    stamTxt.Size = U2(1, 0, 1, 0)
    stamTxt.Font = Enum.Font.GothamBold
    stamTxt.TextSize = 9
    stamTxt.TextColor3 = C3(255, 255, 255)
    stamTxt.TextStrokeTransparency = 0.5
    stamTxt.ZIndex = 3

    local lastHP, lastSTM = -1, -1
    local function updateStats()
        if not char or not char.Parent then return end
        
        local stam = char:GetAttribute("Stamina")
        local mxS = char:GetAttribute("MaxStamina") or 100
        if lastSTM ~= stam then
            lastSTM = stam
            local sPercent = 1
            local sVal = "N/A"
            if type(stam) == "number" and stam ~= math.huge then 
                sPercent = clamp(stam / mxS, 0, 1)
                sVal = tostring(floor(stam))
            elseif stam == math.huge then
                sVal = "INF"
            end
            sBarFill.Size = U2(sPercent, 0, 1, 0)
            stamTxt.Text = "STM: " .. sVal
        end

        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            local hp = hum.Health
            if floor(hp) ~= floor(lastHP) then
                lastHP = hp
                local mxH = hum.MaxHealth > 0 and hum.MaxHealth or 100
                local p = clamp(hp / mxH, 0, 1)
                hBarFill.Size = U2(p, 0, 1, 0)
                hpTxt.Text = "HP: " .. floor(hp) .. " / " .. floor(mxH)
                
                local barColor = (p > 0.5 and C3(0, 255, 0)) or (p > 0.2 and C3(255, 255, 0)) or C3(255, 0, 0)
                hBarFill.BackgroundColor3 = barColor
            end
        end
    end

    updateStats()
    local c1 = char:GetAttributeChangedSignal("Stamina"):Connect(updateStats)
    local c2 = char:GetAttributeChangedSignal("MaxStamina"):Connect(updateStats)
    local hum = char:FindFirstChildOfClass("Humanoid")
    local c3 = hum and hum:GetPropertyChangedSignal("Health"):Connect(updateStats) or nil
    
    espData.texts[char] = { gui = billboard, conns = {c1, c2, c3} }
    pendingESP[char] = nil
end

local function removeTextESP(char)
    local data = espData.texts[char]
    if data then
        pcall(function()
            if data.gui then data.gui:Destroy() end
            if data.conns then 
                for _, c in ipairs(data.conns) do 
                    if c and c.Disconnect then c:Disconnect() end 
                end 
            end
        end)
        espData.texts[char] = nil
    end
    if pendingESP then pendingESP[char] = nil end
end

local function clearTextESP(tbl)
    if not tbl then return end
    for char, data in pairs(tbl) do
        pcall(function()
            if data.gui then data.gui:Destroy() end
            if data.conns then 
                for _, c in ipairs(data.conns) do 
                    if c and c.Disconnect then c:Disconnect() end 
                end 
            end
        end)
        tbl[char] = nil
    end
    if pendingESP then table.clear(pendingESP) end
end

local function getClosestSurvivorName(pos)
    local closestName = "Someone"
    local shortest = 25 
    local aliveFolder = workspace:FindFirstChild("PLAYERS") and workspace.PLAYERS:FindFirstChild("ALIVE")
    if aliveFolder then
        for _, v in ipairs(aliveFolder:GetChildren()) do
            local hrp = v:FindFirstChild("HumanoidRootPart")
            if hrp then
                local d = (hrp.Position - pos).Magnitude
                if d < shortest then
                    shortest = d
                    closestName = v.Name
                end
            end
        end
    end
    return closestName
end

VisualsBox:AddToggle("NameStamESP", {
    Text = "Name & Stamina ESP",
    Default = false,
    Callback = function(Value)
        if Value then
            local function setupFolder(folder, isKiller)
                if not folder then return end
                local function onAdded(c) 
                    if c ~= LocalPlayer.Character then
                        task.spawn(addTextESP, c, isKiller and Color3.fromRGB(255, 80, 80) or getSurvivorColor(c))
                    end
                end
                local function onRemoved(c) removeTextESP(c) end
                
                for _, c in ipairs(folder:GetChildren()) do onAdded(c) end
                table.insert(espData.nameStamConns, folder.ChildAdded:Connect(onAdded))
                table.insert(espData.nameStamConns, folder.ChildRemoved:Connect(onRemoved))
            end

            local function init()
                local players = getPlayersFolder()
                if players then
                    setupFolder(players:FindFirstChild("ALIVE"), false)
                    setupFolder(players:FindFirstChild("KILLER"), true)
                end
            end
            
            espData.nameStamConns = {}
            init()
        else
            if espData.nameStamConns then
                for _, c in ipairs(espData.nameStamConns) do if c then c:Disconnect() end end
                espData.nameStamConns = nil
            end
            clearTextESP(espData.texts)
        end
    end
})

VisualsBox:AddToggle("SurvESP", {
    Text = "Highlight all survivors",
    Default = false,
    Callback = function(Value)
        local p = getPlayersFolder()
        local aliveFolder = p and p:FindFirstChild("ALIVE")
        if Value and aliveFolder then
            for _, v in ipairs(aliveFolder:GetChildren()) do 
                if v:IsA("Model") and v ~= LocalPlayer.Character then addESP(espData.survivors, v, getSurvivorColor(v)) end 
            end
            espData.survivorAdd = aliveFolder.ChildAdded:Connect(function(v) 
                if v:IsA("Model") and v ~= LocalPlayer.Character then addESP(espData.survivors, v, getSurvivorColor(v)) end 
            end)
            espData.survivorRemove = aliveFolder.ChildRemoved:Connect(function(v) removeESP(espData.survivors, v) end)
        else
            if espData.survivorAdd then espData.survivorAdd:Disconnect() end
            if espData.survivorRemove then espData.survivorRemove:Disconnect() end
            clearESP(espData.survivors)
        end
    end
})

VisualsBox:AddToggle("KillerESP", {
    Text = "Detect Killer",
    Default = false,
    Callback = function(Value)
        autoSuppressEnabled = Value
        local p = getPlayersFolder()
        local killerFolder = p and p:FindFirstChild("KILLER")
        if Value and killerFolder then
            for _, v in ipairs(killerFolder:GetChildren()) do 
                if v:IsA("Model") and v ~= LocalPlayer.Character then 
                    addESP(espData.killers, v, Color3.fromRGB(255, 80, 80)) 
                    initHighlightSuppress(v)
                end 
            end
            espData.killerAdd = killerFolder.ChildAdded:Connect(function(v) 
                if v:IsA("Model") and v ~= LocalPlayer.Character then 
                    addESP(espData.killers, v, Color3.fromRGB(255, 80, 80)) 
                    initHighlightSuppress(v)
                end 
            end)
            espData.killerRemove = killerFolder.ChildRemoved:Connect(function(v) removeESP(espData.killers, v) end)
        else
            if espData.killerAdd then espData.killerAdd:Disconnect() end
            if espData.killerRemove then espData.killerRemove:Disconnect() end
            clearESP(espData.killers)
            for _, c in ipairs(suppressConns) do if c then c:Disconnect() end end
            table.clear(suppressConns)
        end
    end
})

local function isMinionObj(v)
    if not v or not v.Name then return false end
    local n = string.lower(v.Name)
    return string.find(n, "minion", 1, true) or string.find(n, "ennard", 1, true) or string.find(n, "stalker", 1, true) or string.find(n, "baby", 1, true) or string.find(n, "bidybab", 1, true) or string.find(n, "bon-bon", 1, true) or string.find(n, "bonnet", 1, true)
end

local function isTrapObj(v)
    if not v or not v.Name then return false end
    local n = string.lower(v.Name)
    local inTrapsFolder = false
    local p = v.Parent
    if p and p.Name == "Traps" then
        local pp = p.Parent
        if pp and pp.Name == "IGNORE" then
            inTrapsFolder = true
        end
    end
    return inTrapsFolder or string.find(n, "trap") or string.find(n, "beartrap") or string.find(n, "bear trap") or string.find(n, "springtrap") or string.find(n, "tripwire") or string.find(n, "mine") or string.find(n, "sensor")
end

VisualsBox:AddToggle("MinionESP", {
    Text = "Ennard's minions ESP",
    Default = false,
    Callback = function(Value)
        if Value then
            local function checkAndAddMinion(v)
                if not v or v == LocalPlayer.Character then return end
                if not activeKillerRole or not activeKillerRole:lower():find("ennard") then 
                    if espData.minions[v] then removeESP(espData.minions, v) end
                    return 
                end
                if not (v:IsA("Model") or v:IsA("BasePart")) then return end
                if isMinionObj(v) then
                    if v:IsA("BasePart") and v.Parent and isMinionObj(v.Parent) then return end
                    if not espData.minions[v] then
                        addESP(espData.minions, v, Color3.fromRGB(138, 43, 226), Color3.fromRGB(255, 255, 255))
                        local lbl = addSimpleTextLabel(v, "Minion", Color3.fromRGB(200, 100, 255), V3(0, 3, 0))
                        if lbl then espData.texts[v] = {gui = lbl, tag = "minion"} end
                    end
                end
            end
            local pPlayers = getPlayersFolder()
            local kFolder = pPlayers and pPlayers:FindFirstChild("KILLER")
            if kFolder then
                for _, v in ipairs(kFolder:GetChildren()) do pcall(checkAndAddMinion, v) end
            end
            local maps = workspace:FindFirstChild("MAPS")
            if maps then
                for _, v in ipairs(maps:GetDescendants()) do pcall(checkAndAddMinion, v) end
            end
            espData.minionAdd = workspace.DescendantAdded:Connect(function(v) pcall(checkAndAddMinion, v) end)
            espData.minionRemove = workspace.DescendantRemoving:Connect(function(v)
                removeESP(espData.minions, v)
                if espData.texts[v] and espData.texts[v].tag == "minion" then
                    pcall(function() if espData.texts[v].gui then espData.texts[v].gui:Destroy() end end)
                    espData.texts[v] = nil
                end
            end)
        else
            if espData.minionAdd then espData.minionAdd:Disconnect() end
            if espData.minionRemove then espData.minionRemove:Disconnect() end
            clearESP(espData.minions)
            for k, data in pairs(espData.texts) do
                if data and type(data) == "table" and data.tag == "minion" then
                    pcall(function() if data.gui then data.gui:Destroy() end end)
                    espData.texts[k] = nil
                end
            end
        end
    end
})

VisualsBox:AddToggle("TrapESP", {
    Text = "Springtrap's bear-trap ESP",
    Default = false,
    Callback = function(Value)
        if Value then
            -- Broken Endo Cleanup
            local function clearEndos()
                local maps = workspace:FindFirstChild("MAPS")
                local gm = maps and maps:FindFirstChild("GAME MAP")
                local other = gm and gm:FindFirstChild("Other")
                local endoFolder = other and other:FindFirstChild("Broken Endo")
                if endoFolder then
                    for _, v in ipairs(endoFolder:GetChildren()) do 
                        pcall(function() v:Destroy() end) 
                    end
                    return endoFolder
                end
            end
            
            local be = clearEndos()
            if be then
                espData.endoCleanup = be.ChildAdded:Connect(function(v)
                    pcall(function() v:Destroy() end)
                end)
            end

            local function checkAndAddTrap(v)
                if not v or v == LocalPlayer.Character then return end
                if not activeKillerRole or not activeKillerRole:lower():find("springtrap") then
                    if espData.traps[v] then removeESP(espData.traps, v) end
                    return 
                end
                if not (v:IsA("Model") or v:IsA("BasePart")) then return end
                if isTrapObj(v) then
                    if v:IsA("BasePart") and v.Parent and isTrapObj(v.Parent) then return end
                    if not espData.traps[v] then
                        addESP(espData.traps, v, Color3.fromRGB(255, 69, 0), Color3.fromRGB(255, 0, 0))
                        local lbl = addSimpleTextLabel(v, "Trap", Color3.fromRGB(255, 100, 100), V3(0, 2, 0))
                        if lbl then espData.texts[v] = {gui = lbl, tag = "trap"} end
                    end
                end
            end
            for _, v in ipairs(workspace:GetDescendants()) do pcall(checkAndAddTrap, v) end
            espData.trapAdd = workspace.DescendantAdded:Connect(function(v) pcall(checkAndAddTrap, v) end)
            espData.trapRemove = workspace.DescendantRemoving:Connect(function(v)
                removeESP(espData.traps, v)
                if espData.texts[v] and espData.texts[v].tag == "trap" then
                    pcall(function() if espData.texts[v].gui then espData.texts[v].gui:Destroy() end end)
                    espData.texts[v] = nil
                end
            end)
        else
            if espData.endoCleanup then espData.endoCleanup:Disconnect(); espData.endoCleanup = nil end
            if espData.trapAdd then espData.trapAdd:Disconnect() end
            if espData.trapRemove then espData.trapRemove:Disconnect() end
            clearESP(espData.traps)
            for k, data in pairs(espData.texts) do
                if data and type(data) == "table" and data.tag == "trap" then
                    pcall(function() if data.gui then data.gui:Destroy() end end)
                    espData.texts[k] = nil
                end
            end
        end
    end
})

VisualsBox:AddSlider("FOV", {
    Text = "Field of View",
    Default = 90,
    Min = 90,
    Max = 500,
    Rounding = 0,
    Suffix = " FOV",
    Callback = function(Value)
        Workspace.CurrentCamera.FieldOfView = Value
    end,
})

VisualsBox:AddToggle("GenESP", {
    Text = "Highlight all generators",
    Default = false,
    Callback = function(Value)
        if Value then
            local function checkGen(v)
                if v:IsA("Model") and v.Name == "Generator" then 
                    addESP(espData.generators, v, Color3.fromRGB(255, 255, 0), Color3.fromRGB(255, 255, 255)) 
                    
                    -- Progress ESP Logic
                    if not espData.genBills[v] then
                        local bill = Ins("BillboardGui")
                        bill.Name = "GenProgressESP"
                        bill.Adornee = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart")
                        bill.Size = U2(0, 100, 0, 18)
                        bill.StudsOffset = V3(0, 3, 0)
                        bill.AlwaysOnTop = true
                        bill.MaxDistance = 250
                        bill.Parent = TargetGUI

                        local barBg = Ins("Frame", bill)
                        barBg.AnchorPoint = Vector2.new(0.5, 0.5)
                        barBg.Position = U2(0.5, 0, 0.5, 0)
                        barBg.BackgroundColor3 = C3(40, 40, 40)
                        barBg.BorderSizePixel = 0
                        barBg.Size = U2(0, 90, 0, 12)

                        local barFill = Ins("Frame", barBg)
                        barFill.BorderSizePixel = 0
                        barFill.Size = U2(0, 0, 1, 0)
                        barFill.BackgroundColor3 = getGenColor(0)

                        local lbl = Ins("TextLabel", barBg)
                        lbl.Size = U2(1, 0, 1, 0)
                        lbl.BackgroundTransparency = 1
                        lbl.Font = Enum.Font.GothamBold
                        lbl.TextSize = 9
                        lbl.TextStrokeTransparency = 0
                        lbl.Text = "0%"
                        lbl.TextColor3 = C3(255, 255, 255)
                        lbl.ZIndex = 3

                        local function updateProg()
                            if not v or not v.Parent then return end
                            local prog = v:GetAttribute("Progress") or 0
                            lbl.Text = prog .. "%"
                            local c = getGenColor(prog)
                            barFill.Size = U2(prog / 100, 0, 1, 0)
                            barFill.BackgroundColor3 = c
                        end

                        local function updateProg()
                            if not v or not v.Parent then return end
                            local prog = v:GetAttribute("Progress") or 0
                            lbl.Text = prog .. "%"
                            local c = getGenColor(prog)
                            barFill.Size = U2(prog / 100, 0, 1, 0)
                            barFill.BackgroundColor3 = c
                            
                            if prog >= 100 or v:GetAttribute("Completed") == true or v:GetAttribute("Repaired") == true then
                                if espData.genBills[v] then
                                    pcall(function()
                                        espData.genBills[v].bill:Destroy()
                                        if espData.genBills[v].conn then espData.genBills[v].conn:Disconnect() end
                                        if espData.genBills[v].cConn then espData.genBills[v].cConn:Disconnect() end
                                        if espData.genBills[v].rConn then espData.genBills[v].rConn:Disconnect() end
                                    end)
                                    espData.genBills[v] = nil
                                end
                                removeESP(espData.generators, v)
                            end
                        end

                        local conn = v:GetAttributeChangedSignal("Progress"):Connect(updateProg)
                        local cConn = v:GetAttributeChangedSignal("Completed"):Connect(updateProg)
                        local rConn = v:GetAttributeChangedSignal("Repaired"):Connect(updateProg)
                        updateProg()
                        espData.genBills[v] = { bill = bill, conn = conn, cConn = cConn, rConn = rConn }
                    end
                end
            end

            for _, v in ipairs(workspace:GetDescendants()) do
                checkGen(v)
            end

            local maps = workspace:FindFirstChild("MAPS")
            if maps then
                espData.genAdd = workspace.DescendantAdded:Connect(function(v)
                    checkGen(v)
                end)
            end

            espData.genRemove = workspace.DescendantRemoving:Connect(function(v)
                if espData.generators[v] then removeESP(espData.generators, v) end
                if espData.genBills[v] then
                    pcall(function()
                        espData.genBills[v].bill:Destroy()
                        espData.genBills[v].conn:Disconnect()
                    end)
                    espData.genBills[v] = nil
                end
            end)
        else
            if espData.genAdd then espData.genAdd:Disconnect() end
            if espData.genRemove then espData.genRemove:Disconnect() end
            clearESP(espData.generators)
            for v, data in pairs(espData.genBills) do
                pcall(function()
                    data.bill:Destroy()
                    data.conn:Disconnect()
                end)
            end
            table.clear(espData.genBills)
        end
    end
})

VisualsBox:AddToggle("FuseESP", {
    Text = "Highlight all fuses",
    Default = false,
    Callback = function(Value)
        if Value then
            local function checkAndAdd(v)
                local maps = workspace:FindFirstChild("MAPS")
                local gameMap = maps and maps:FindFirstChild("GAME MAP")
                local fuseBoxes = gameMap and gameMap:FindFirstChild("FuseBoxes")
                if fuseBoxes and v:IsDescendantOf(fuseBoxes) then
                    if v:IsA("Model") or v:IsA("BasePart") then
                         addESP(espData.fuses, v, Color3.fromRGB(255, 20, 147), Color3.fromRGB(255, 165, 0))
                         
                         task.spawn(function()
                             local completed = false
                             while espData.fuses[v] and not completed do
                                 local isDone = false
                                 if v:GetAttribute("Inserted") == true then
                                     isDone = true
                                 end
                                 if not isDone then
                                     for _, child in ipairs(v:GetDescendants()) do
                                         if child:IsA("PointLight") and child.Enabled and child.Color.G > child.Color.R then
                                             isDone = true
                                             break
                                         end
                                     end
                                 end
                                 if isDone then
                                     completed = true
                                     local restorer = getClosestSurvivorName(v:IsA("Model") and v:GetPivot().Position or v.Position)
                                     Library:Notify("[" .. restorer .. "] Has Restored A FuseBox!", 5)
                                     removeESP(espData.fuses, v)
                                 end
                                 task.wait(0.5)
                             end
                         end)
                     end
                 end
             end
             
             local maps = workspace:FindFirstChild("MAPS")
             local gameMap = maps and maps:FindFirstChild("GAME MAP")
             local fuseBoxes = gameMap and gameMap:FindFirstChild("FuseBoxes")
             if fuseBoxes then
                 for _, v in ipairs(fuseBoxes:GetChildren()) do
                     addESP(espData.fuses, v, Color3.fromRGB(255, 20, 147), Color3.fromRGB(255, 165, 0))
                 end
             end
            
            espData.fuseAdd = workspace.DescendantAdded:Connect(function(v)
                checkAndAdd(v)
            end)
        else
            if espData.fuseAdd then espData.fuseAdd:Disconnect() end
            clearESP(espData.fuses)
        end
    end
})

VisualsBox:AddToggle("BatESP", {
    Text = "Highlight all batteries",
    Default = false,
    Callback = function(Value)
        if Value then
            for _, v in ipairs(workspace:GetDescendants()) do
                if v:IsA("MeshPart") and v.Name == "Battery" then addESP(espData.batteries, v, Color3.fromRGB(0, 255, 255)) end
            end
            espData.batAdd = workspace.DescendantAdded:Connect(function(v)
                if v:IsA("MeshPart") and v.Name == "Battery" then addESP(espData.batteries, v, Color3.fromRGB(0, 255, 255)) end
            end)
            espData.batRemove = workspace.DescendantRemoving:Connect(function(v)
                if espData.batteries[v] then removeESP(espData.batteries, v) end
            end)
        else
            if espData.batAdd then espData.batAdd:Disconnect() end
            if espData.batRemove then espData.batRemove:Disconnect() end
            clearESP(espData.batteries)
        end
    end
})

VisualsBox:AddToggle("DoorHits", {
    Text = "Show hits left on doors",
    Default = false,
    Callback = function(Value)
        if Value then
            local function addDoor(v)
                local maps = workspace:FindFirstChild("MAPS")
                local gameMap = maps and maps:FindFirstChild("GAME MAP")
                local doorsFolder = gameMap and gameMap:FindFirstChild("Doors")
				
                if not (doorsFolder and v:IsDescendantOf(doorsFolder)) then
                    return
                end

				if doubleDoorsFolder and v:IsDescendantOf(doubleDoorsFolder) then
					return
				end

                local breaks = v:GetAttribute("Breaks")
                if breaks == nil then return end

                local gui = addSimpleTextLabel(
                    v,
                    "(" .. tostring(breaks) .. ")",
                    Color3.fromRGB(255, 200, 100),
                    V3(0, 3, 0)
                )

                if not gui then return end

                task.spawn(function()
                    while v.Parent do
                        local newBreaks = v:GetAttribute("Breaks")

                        if newBreaks == nil then
                            gui:Destroy()
                            break
                        end

                        local txt = gui:FindFirstChildOfClass("TextLabel")
                        if txt then
                            txt.Text = "(" .. tostring(newBreaks) .. ")"
                        end

                        task.wait(0.5)
                    end
                end)
            end

            for _, v in ipairs(workspace:GetDescendants()) do
                pcall(addDoor, v)
            end

            espData.doorConn = workspace.DescendantAdded:Connect(function(v)
                pcall(addDoor, v)
            end)
        else
            if espData.doorConn then
                espData.doorConn:Disconnect()
                espData.doorConn = nil
            end
        end
    end
})

local CombatBox = Tabs.Combat:AddLeftGroupbox("Aimbot & Parry")
local aimbotConn = nil
local aimbotEnabledState = false

CombatBox:AddToggle("CombatAimbot", {
    Text = "Aimbot (Killer Focus)",
    Default = false,
    Callback = function(Value)
        aimbotEnabledState = Value
        if Value then
            aimbotConn = RunService.RenderStepped:Connect(function()
                local killer = getActiveKiller()
                if killer and killer:FindFirstChild("HumanoidRootPart") then
                    local killerPos = killer.HumanoidRootPart.Position
                    local camPos = Camera.CFrame.Position
                    Camera.CFrame = CFrame.new(camPos, killerPos)
                end
            end)
        else
            if aimbotConn then aimbotConn:Disconnect() aimbotConn = nil end
        end
    end
}):AddKeyPicker("AimbotToggleKey", {
    Default = "Q",
    SyncToggleState = true,
    Mode = "Toggle",
    Text = "Aimbot Keybind",
    NoUI = false
})

CombatBox:AddToggle("CombatSilentAim", {
    Text = "Silent Aim (Hit Redirection)",
    Default = false,
    Callback = function(Value)
        silentAimEnabled = Value
    end
})

CombatBox:AddToggle("SilentAimPrediction", {
    Text = "Enable Prediction",
    Default = false,
    Callback = function(Value)
        silentAimPrediction = Value
    end
})


CombatBox:AddDropdown("ProjectilePresets", {
    Values = { "Instant / Melee", "Fast Projectile (Gun)", "Medium (Throw)", "Slow (Projectile)" },
    Default = 1,
    Text = "Projectile Presets",
    Callback = function(Value)
        if Value == "Instant / Melee" then
            Options.ProjectileSpeed:SetValue(5000)
            Options.PredictionScale:SetValue(0.5) -- Small lead for melee
        elseif Value == "Fast Projectile (Gun)" then
            Options.ProjectileSpeed:SetValue(1500)
            Options.PredictionScale:SetValue(1.0)
        elseif Value == "Medium (Throw)" then
            Options.ProjectileSpeed:SetValue(500)
            Options.PredictionScale:SetValue(1.0)
        elseif Value == "Slow (Projectile)" then
            Options.ProjectileSpeed:SetValue(100)
            Options.PredictionScale:SetValue(1.0)
        end
    end,
})

CombatBox:AddSlider("PredictionScale", {
    Text = "Prediction Scale",
    Default = 1.0,
    Min = 0,
    Max = 3,
    Rounding = 2,
    Callback = function(Value)
        predictionVelocityScale = Value
    end
})

CombatBox:AddSlider("ProjectileSpeed", {
    Text = "Projectile Speed",
    Default = 750,
    Min = 1,
    Max = 5000,
    Rounding = 0,
    Callback = function(Value)
        predictionProjectileSpeed = Value
    end
})



local autoParryEnabled = false
local autoParryRadius = 15 -- Keep the radius variable
local parryConns = {}
local WarpInputClient = nil

local function initWarpInputClient()
    if not WarpInputClient then
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local Modules = ReplicatedStorage:FindFirstChild("Modules")
        local WarpModule = Modules and Modules:FindFirstChild("Warp")
        if WarpModule then
            local success, result = pcall(function() return require(WarpModule).Client("Input") end)
            if success and result then
                WarpInputClient = result
            else
                warn("Failed to get Warp.Client(\"Input\"): ", result)
            end
        else
            warn("Warp module not found.")
        end
    end
end



local function onKillerAdded(k)
    task.spawn(function()
        local animator = k:FindFirstChildWhichIsA("Animator", true) or k:WaitForChild("Animator", 5)
        if animator then
            table.insert(parryConns, animator.AnimationPlayed:Connect(function(track)
                if autoParryEnabled and WarpInputClient then
                    local parryAnims = {
                        ["rbxassetid://102810363618918"] = true, -- Example attack animation ID
                        ["rbxassetid://71147082224885"] = true,  -- Example attack animation ID
                        ["rbxassetid://70869035406359"] = true,  -- Example attack animation ID
                        ["rbxassetid://119495869953586"] = true,
                        ["rbxassetid://133752270724243"] = true,
                        ["rbxassetid://112503015929213"] = true,
                        ["rbxassetid://109788581549466"] = true,
                        ["rbxassetid://95722006705414"] = true,
                        ["rbxassetid://106673226682917"] = true,
                        ["rbxassetid://120428956410756"] = true
                    }

                    if parryAnims[track.Animation.AnimationId] then
                        local char = LocalPlayer.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        local killerRoot = k:FindFirstChild("HumanoidRootPart")

                        if root and killerRoot and (root.Position - killerRoot.Position).Magnitude <= autoParryRadius then
                            -- Trigger parry using the Warp module
                            WarpInputClient:Fire(true, {"Ability", 2})
                            -- Add a small debounce to prevent spamming
                            task.wait(0.5)
                        end
                    end
                end
            end))
        end
    end)
end

CombatBox:AddToggle("AutoParry", {
    Text = "Auto Parry",
    Default = false,
    Callback = function(Value)
        autoParryEnabled = Value
        if Value then
            initWarpInputClient()
            if WarpInputClient then
                local p = getPlayersFolder()
                local killerFolder = p and p:FindFirstChild("KILLER")
                if killerFolder then
                    for _, k in ipairs(killerFolder:GetChildren()) do
                        onKillerAdded(k)
                    end
                    table.insert(parryConns, killerFolder.ChildAdded:Connect(onKillerAdded))
                end
            else
                Library:Notify("Warp Input Client not available. Auto Parry may not work.", 5)
                Options.AutoParry:SetValue(false)
            end
        else
            for _, conn in ipairs(parryConns) do if conn.Disconnect then conn:Disconnect() end end
            table.clear(parryConns)
        end
    end
})

CombatBox:AddSlider("ParryRadius", {
    Text = "Auto-Parry Radius",
    Default = 15,
    Min = 5,
    Max = 17,
    Rounding = 0,
    Suffix = " Studs",
    Callback = function(Value)
        autoParryRadius = Value
        debugLog("Radius updated to: " .. Value)
    end
})


local AntiLagBox = Tabs.AntiLag:AddLeftGroupbox("FPS Optimizations")
AntiLagBox:AddToggle("MazesLowGFX", {
    Text = "MAZES LOW GFX OPTIMIZER MORE FPS!",
    Default = false,
    Callback = function(Value)
        if Value then
            for _, v in pairs(workspace:GetDescendants()) do
                if v:IsA("BasePart") and not v:IsA("MeshPart") then
                    v.Material = Enum.Material.SmoothPlastic
                    v.Reflectance = 0
                elseif v:IsA("Decal") or v:IsA("Texture") then
                    v.Transparency = 1
                end
            end
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 9e9
        end
    end
})

AntiLagBox:AddToggle("BoostFPS", {
    Text = "Boost FPS",
    Default = false,
    Callback = function(Value)
        if Value then
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04
        end
    end
})

AntiLagBox:AddToggle("ReduceLag", {
    Text = "Reduce Lag (Disable Particles)",
    Default = false,
    Callback = function(Value)
        if Value then
            for _, v in pairs(workspace:GetDescendants()) do
                if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then
                    v.Enabled = false
                end
            end
        end
    end
})

AntiLagBox:AddToggle("OptimizeNetwork", {
    Text = "Optimize Network",
    Default = false,
    Callback = function(Value)
        if Value then
            settings().Network.IncomingReplicationLag = 0
        end
    end
})

AntiLagBox:AddToggle("DisableShadows", {
    Text = "Disable Shadows",
    Default = false,
    Callback = function(Value)
        if Value then
            Lighting.GlobalShadows = false
            for _, v in pairs(workspace:GetDescendants()) do
                if v:IsA("BasePart") then
                    v.CastShadow = false
                end
            end
        end
    end
})

AntiLagBox:AddToggle("ClearDebris", {
    Text = "Clear Workspace Debris",
    Default = false,
    Callback = function(Value)
        if Value then
            for _, v in pairs(workspace:GetChildren()) do
                if v.Name == "Blood" or v.Name == "BulletHole" or v:IsA("Tool") then
                    v:Destroy()
                end
            end
        end
    end
})

AntiLagBox:AddToggle("LowRenderAvatars", {
    Text = "Low Render Avatars",
    Default = false,
    Callback = function(Value)
        if Value then
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    for _, part in pairs(player.Character:GetDescendants()) do
                        if part:IsA("BasePart") or part:IsA("Decal") then
                            part.Transparency = 1
                        end
                    end
                end
            end
        end
    end
})


local OtherScriptsBox = Tabs.Other:AddLeftGroupbox("External Hubs")
OtherScriptsBox:AddButton({
    Text = "Infinite Yield",
    Func = function()
        loadstring(game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source'))()
    end
})
OtherScriptsBox:AddButton({
    Text = "CMD-X",
    Func = function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/CMD-X/CMD-X/master/Source", true))()
    end
})
OtherScriptsBox:AddButton({
    Text = "Nameless Admin",
    Func = function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/FilteringEnabled/NamelessAdmin/main/Source"))()
    end
})


local MenuGroup = Tabs.UISettings:AddLeftGroupbox("Menu")
MenuGroup:AddToggle("KeybindMenuOpen", {
    Default = Library.KeybindFrame.Visible,
    Text = "Open Keybind Menu",
    Callback = function(value)
        Library.KeybindFrame.Visible = value
    end,
})
MenuGroup:AddToggle("ShowCustomCursor", {
    Text = "Custom Cursor",
    Default = true,
    Callback = function(Value)
        Library.ShowCustomCursor = Value
    end,
})
MenuGroup:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "Notification Side",
    Callback = function(Value)
        Library:SetNotifySide(Value)
    end,
})
MenuGroup:AddDropdown("DPIDropdown", {
    Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
    Default = "100%",
    Text = "DPI Scale",
    Callback = function(Value)
        Value = Value:gsub("%%", "")
        local DPI = tonumber(Value)
        Library:SetDPIScale(DPI)
    end,
})
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })

MenuGroup:AddButton("Unload", function()
    Library:Unload()
end)

Library.ToggleKeybind = Options.MenuKeybind


ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("RepzHub")
SaveManager:SetFolder("RepzHub/BBN")
SaveManager:BuildConfigSection(Tabs.UISettings)
ThemeManager:ApplyToTab(Tabs.UISettings)
SaveManager:LoadAutoloadConfig()



getgenv().CustomOST_MP3Url = ""
getgenv().CustomOST_Sound = nil

getgenv().RepzHubUnload = function()
    pcall(function()
        if espData then
            if espData.highlightTaskLoop then espData.highlightTaskLoop:Disconnect() end
            if espData.textTaskLoop then espData.textTaskLoop:Disconnect() end
            if espData.pool then for _, h in ipairs(espData.pool) do if h then h:Destroy() end end end
        end
    end)
    
    for _, tbl in pairs({espData.survivors, espData.killers, espData.generators, espData.batteries, espData.fuses, espData.minions, espData.traps}) do
        table.clear(tbl)
    end

    pcall(function()

        local function clean(c) if c then c:Disconnect() end end
        if activeEmoteTrack then activeEmoteTrack:Stop() end
        if type(activeEffects) == "table" then
            for _, effect in ipairs(activeEffects) do if effect and effect.Parent then effect:Destroy() end end
        end

        autoRepairEnabled = false
        if autoRepairTask then task.cancel(autoRepairTask) end
        if dotConn then dotConn:Disconnect() end
        if autoKillConn then autoKillConn:Disconnect() end
        if autoShakeConn then autoShakeConn:Disconnect() end

		autoEscape = false
        if autoEscapeConn then autoEscapeConn:Disconnect() autoEscapeConn = nil end
        autoGenEnabled = false
        if autoGenTask then task.cancel(autoGenTask) autoGenTask = nil end

        if instantPromptConn then instantPromptConn:Disconnect() end
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                local old = obj:GetAttribute("HoldDurationOld")
                if old and old ~= 0 then obj.HoldDuration = old end
            end
        end

        if sprintConn then sprintConn:Disconnect() end
        if charAddConn then charAddConn:Disconnect() end
        if noclipTask then noclipTask:Disconnect() end
        if noclipCharAdd then noclipCharAdd:Disconnect() end
        if pcFlyConn then pcFlyConn:Disconnect() end
        if mobileFlyConn then mobileFlyConn:Disconnect() end
        
        local char = LocalPlayer.Character
        if char then
            pcall(function()
                char:SetAttribute("Running", false)
                char:SetAttribute("WalkSpeed", 12)
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false end
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then root.Anchored = false end
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = true end
                end
            end)
        end
			
        _G.SnakeGod = false
        if fbLoop then fbLoop:Disconnect() end
        if _G.CustomOST_Sound then _G.CustomOST_Sound:Stop(); _G.CustomOST_Sound:Destroy(); _G.CustomOST_Sound = nil end
        Lighting.GlobalShadows = true
        local cam = Workspace.CurrentCamera
        if cam and cam:FindFirstChild("RepzFBLight") then cam.RepzFBLight:Destroy() end
        
        if espData.survivorAdd then espData.survivorAdd:Disconnect() end
        if espData.survivorRemove then espData.survivorRemove:Disconnect() end
        if espData.killerAdd then espData.killerAdd:Disconnect() end
        if espData.killerRemove then espData.killerRemove:Disconnect() end
        if espData.genAdd then espData.genAdd:Disconnect() end
        if espData.genRemove then espData.genRemove:Disconnect() end
        if espData.batAdd then espData.batAdd:Disconnect() end
        if espData.batRemove then espData.batRemove:Disconnect() end
        if espData.fuseAdd then espData.fuseAdd:Disconnect() end
        if espData.minionAdd then espData.minionAdd:Disconnect() end
        if espData.minionRemove then espData.minionRemove:Disconnect() end
        if espData.trapAdd then espData.trapAdd:Disconnect() end
        if espData.trapRemove then espData.trapRemove:Disconnect() end
        
        if suppressConns then
            for _, c in ipairs(suppressConns) do if c then c:Disconnect() end end
            table.clear(suppressConns)
        end
        
        for _, tbl in pairs({espData.survivors, espData.killers, espData.generators, espData.batteries, espData.fuses, espData.minions, espData.traps}) do
            for obj, h in pairs(tbl) do pcall(function() h:Destroy() end) end
            table.clear(tbl)
        end
        
        if type(espData.texts) == "table" then
            for char, data in pairs(espData.texts) do
                pcall(function()
                    if data.gui then data.gui:Destroy() end
                    if data.conns then 
                        for _, c in ipairs(data.conns) do 
                            if c and c.Disconnect then c:Disconnect() end 
                        end 
                    end
                end)
            end
            table.clear(espData.texts)
        end
        if type(pendingESP) == "table" then table.clear(pendingESP) end
        if type(espData.nameStamConns) == "table" then
            for _, c in ipairs(espData.nameStamConns) do if c then c:Disconnect() end end
            table.clear(espData.nameStamConns)
        end
        if espData.highlightTask then task.cancel(espData.highlightTask) end

        if aimbotConn then aimbotConn:Disconnect() end
        for _, conn in ipairs(parryConns or {}) do if conn then conn:Disconnect() end end
        if parryConns then table.clear(parryConns) end
    end)
end


local lastRoundState = false
RunService.Heartbeat:Connect(function()
    local currentActive = isRoundActive()
    
    -- Update active killer role
    if currentActive then
        local k = getActiveKiller()
        activeKillerRole = k and getRoleLabel(k) or nil
    else
        activeKillerRole = nil
    end

    if currentActive and not lastRoundState then
        task.spawn(function()
            task.wait(1.5)
            local targetToggles = {"SurvESP", "KillerESP", "MinionESP", "TrapESP", "GenESP", "FuseESP", "BatESP", "NameStamESP", "AutoParry"}
            for _, toggleKey in ipairs(targetToggles) do
                local t = Toggles[toggleKey]
                if t and t.Value then
                    t:SetValue(false)
                    t:SetValue(true)
                end
            end
        end)
    end
    lastRoundState = currentActive
end)

RunService.RenderStepped:Connect(function()
    if silentAimEnabled and isRoundActive() and ennardEHeld and getMyRole() == "Ennard" then
        local target = getSilentAimTarget()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local tPart = target and (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChildWhichIsA("BasePart"))
        if root and tPart then
            local pos = tPart.Position
            root.CFrame = CFrame.new(root.Position, Vector3.new(pos.X, root.Position.Y, pos.Z))
        end
    end
end)


Library:OnUnload(function()
        if getgenv().RepzHubUnload then
            getgenv().RepzHubUnload()
        end
        if _G.CustomOST_Sound then
            _G.CustomOST_Sound:Stop()
            _G.CustomOST_Sound:Destroy()
            _G.CustomOST_Sound = nil
        end
        if _G.CustomOST_MuteLoop then
            _G.CustomOST_MuteLoop:Disconnect()
            _G.CustomOST_MuteLoop = nil
        end
        _G.CustomOST_Active = false
end)
