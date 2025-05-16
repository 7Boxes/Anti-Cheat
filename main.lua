local Config = {
    Enabled = true, -- Toggle entire anti-cheat system
    DebugMode = false, -- Show detection messages in output (for testing only)
    
    SpeedCheck = true,
    MaxSpeedMultiplier = 1.5, 
    SpeedSampleCount = 5, 
    SpeedSampleInterval = 0.2, -- seconds
    SpeedViolationThreshold = 3, -- max violations 
    
    TeleportCheck = true,
    MaxAllowedDistance = 50, 
    TeleportCooldown = 0.5, -- seconds
    TeleportViolationThreshold = 2, -- max violations 
    
    NoclipCheck = true,
    NoclipCheckInterval = 1, -- seconds 
    NoclipViolationThreshold = 3, -- max violations 
    
    FlyCheck = true,
    MaxAirTime = 3, -- seconds
    FlyViolationThreshold = 2, -- max violations 
    
    Punishments = {
        LogOnly = false, -- log without punishing (for testing)
        KickAfter = 3, -- violations before kick
        BanAfter = 5, -- violations before ban 
        TempBanDuration = 86400, -- 24 hours 
    },
    
    Whitelist = {
        -- people who can bypass the anti-cheat
        -- [1234567] = true,
    }
}

local AntiCheat = {}
AntiCheat.__index = AntiCheat

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local playerData = {}

local function isWhitelisted(player)
    return Config.Whitelist[player.UserId] or false
end

local function logDetection(player, checkType, details)
    if Config.DebugMode then
        print(string.format("[ANTICHEAT] Detection - Player: %s, Check: %s, Details: %s", 
            player.Name, checkType, details))
    end
    
    -- add a dc webhook or datastore so we can see bans
end

local function punishPlayer(player, violationType)
    if Config.Punishments.LogOnly or isWhitelisted(player) then
        logDetection(player, violationType, "Detection logged (no punishment)")
        return
    end
    
    local data = playerData[player]
    if not data then return end
    
    data.violations = (data.violations or 0) + 1
    logDetection(player, violationType, string.format("Violation #%d", data.violations))
    
    if data.violations >= Config.Punishments.BanAfter then
        -- put ban logic here (kicking / banning etc)
        player:Kick("Banned for cheating. Appeal at our website.")
        logDetection(player, violationType, "BANNED")
    elseif data.violations >= Config.Punishments.KickAfter then
        player:Kick("Kicked for suspicious activity. Further violations may result in a ban.")
        logDetection(player, violationType, "KICKED")
    end
end

local function setupSpeedCheck(player)
    local data = playerData[player]
    if not data or not Config.SpeedCheck then return end
    
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")
    
    local lastPosition = rootPart.Position
    local lastCheckTime = os.clock()
    local speedSamples = {}
    local speedViolations = 0
    
    local maxSpeed = humanoid.WalkSpeed * Config.MaxSpeedMultiplier
    
    local function checkSpeed()
        if not character or not rootPart or not humanoid or humanoid.Health <= 0 then
            return
        end
        
        local now = os.clock()
        local deltaTime = now - lastCheckTime
        lastCheckTime = now
        
        if deltaTime <= 0 then return end
        
        local currentPosition = rootPart.Position
        local distance = (currentPosition - lastPosition).Magnitude
        lastPosition = currentPosition
        
        local speed = distance / deltaTime
        
        table.insert(speedSamples, speed)
        if #speedSamples > Config.SpeedSampleCount then
            table.remove(speedSamples, 1)
        end
        
        local avgSpeed = 0
        for _, s in ipairs(speedSamples) do
            avgSpeed = avgSpeed + s
        end
        avgSpeed = avgSpeed / #speedSamples
        
        if avgSpeed > maxSpeed and #speedSamples >= Config.SpeedSampleCount then
            speedViolations = speedViolations + 1
            logDetection(player, "SPEED", string.format("Speed: %.2f > %.2f", avgSpeed, maxSpeed))
            
            if speedViolations >= Config.SpeedViolationThreshold then
                punishPlayer(player, "SPEED_HACK")
                speedViolations = 0
            end
        else
            speedViolations = math.max(0, speedViolations - 0.1)
        end
    end
    
    data.speedCheckConnection = RunService.Heartbeat:Connect(function()
        pcall(checkSpeed)
    end)
end

local function setupTeleportCheck(player)
    local data = playerData[player]
    if not data or not Config.TeleportCheck then return end
    
    local character = player.Character or player.CharacterAdded:Wait()
    local rootPart = character:WaitForChild("HumanoidRootPart")
    
    local lastPosition = rootPart.Position
    local lastCheckTime = os.clock()
    local teleportViolations = 0
    
    local function checkTeleport()
        if not character or not rootPart or not rootPart:IsDescendantOf(workspace) then
            return
        end
        
        local now = os.clock()
        local deltaTime = now - lastCheckTime
        
        if deltaTime < Config.TeleportCooldown then
            return
        end
        
        lastCheckTime = now
        local currentPosition = rootPart.Position
        local distance = (currentPosition - lastPosition).Magnitude
        lastPosition = currentPosition
        
        if distance > Config.MaxAllowedDistance then
            teleportViolations = teleportViolations + 1
            logDetection(player, "TELEPORT", string.format("Distance: %.2f > %.2f", distance, Config.MaxAllowedDistance))
            
            if teleportViolations >= Config.TeleportViolationThreshold then
                punishPlayer(player, "TELEPORT_HACK")
                teleportViolations = 0
            end
        else
            teleportViolations = math.max(0, teleportViolations - 0.1)
        end
    end
    
    data.teleportCheckConnection = RunService.Heartbeat:Connect(function()
        pcall(checkTeleport)
    end)
end

local function setupNoclipCheck(player)
    local data = playerData[player]
    if not data or not Config.NoclipCheck then return end
    
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")
    
    local noclipViolations = 0
    local lastCheckTime = os.clock()
    
    local function checkNoclip()
        if not character or not rootPart or humanoid.Health <= 0 then
            return
        end
        
        local now = os.clock()
        if now - lastCheckTime < Config.NoclipCheckInterval then
            return
        end
        lastCheckTime = now
        
        local rayOrigin = rootPart.Position
        local rayDirection = Vector3.new(0, -5, 0) -- Adjust based on your game
        local raycastParams = RaycastParams.new()
        raycastParams.FilterDescendantsInstances = {character, workspace.Terrain}
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
        
        local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
        
        if not raycastResult and not humanoid:GetState() == Enum.HumanoidStateType.Jumping then
            noclipViolations = noclipViolations + 1
            logDetection(player, "NOCLIP", "Possible noclip detected")
            
            if noclipViolations >= Config.NoclipViolationThreshold then
                punishPlayer(player, "NOCLIP_HACK")
                noclipViolations = 0
            end
        else
            noclipViolations = math.max(0, noclipViolations - 0.1)
        end
    end
    
    data.noclipCheckConnection = RunService.Heartbeat:Connect(function()
        pcall(checkNoclip)
    end)
end

local function setupFlyCheck(player)
    local data = playerData[player]
    if not data or not Config.FlyCheck then return end
    
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")
    
    local airTime = 0
    local lastOnGround = true
    local flyViolations = 0
    
    local function checkFlying()
        if not character or not rootPart or humanoid.Health <= 0 then
            return
        end
        
        local rayOrigin = rootPart.Position
        local rayDirection = Vector3.new(0, -5, 0) -- Adjust based on your game
        local raycastParams = RaycastParams.new()
        raycastParams.FilterDescendantsInstances = {character, workspace.Terrain}
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
        
        local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
        local onGround = raycastResult ~= nil
        
        if not onGround and not lastOnGround then
            airTime = airTime + RunService.Heartbeat:Wait()
            
            if airTime > Config.MaxAirTime and not humanoid:GetState() == Enum.HumanoidStateType.Jumping then
                flyViolations = flyViolations + 1
                logDetection(player, "FLY", string.format("Air time: %.2f > %.2f", airTime, Config.MaxAirTime))
                
                if flyViolations >= Config.FlyViolationThreshold then
                    punishPlayer(player, "FLY_HACK")
                    flyViolations = 0
                end
            end
        else
            airTime = 0
            flyViolations = math.max(0, flyViolations - 0.1)
        end
        
        lastOnGround = onGround
    end
    
    data.flyCheckConnection = RunService.Heartbeat:Connect(function()
        pcall(checkFlying)
    end)
end

local function initPlayer(player)
    if not Config.Enabled or isWhitelisted(player) then return end
    
    local data = {
        violations = 0,
        connections = {}
    }
    playerData[player] = data
    
    player.CharacterAdded:Connect(function(character)
        if Config.SpeedCheck then setupSpeedCheck(player) end
        if Config.TeleportCheck then setupTeleportCheck(player) end
        if Config.NoclipCheck then setupNoclipCheck(player) end
        if Config.FlyCheck then setupFlyCheck(player) end
    end)
    
    player.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            cleanupPlayer(player)
        end
    end)
end

local function cleanupPlayer(player)
    local data = playerData[player]
    if not data then return end
    
    if data.speedCheckConnection then data.speedCheckConnection:Disconnect() end
    if data.teleportCheckConnection then data.teleportCheckConnection:Disconnect() end
    if data.noclipCheckConnection then data.noclipCheckConnection:Disconnect() end
    if data.flyCheckConnection then data.flyCheckConnection:Disconnect() end
    
    playerData[player] = nil
end

local function init()
    for _, player in ipairs(Players:GetPlayers()) do
        initPlayer(player)
    end
    
    Players.PlayerAdded:Connect(initPlayer)
    
    Players.PlayerRemoving:Connect(cleanupPlayer)
    
    print("[ANTICHEAT] System initialized with config:")
    print("Enabled:", Config.Enabled)
    print("Speed Check:", Config.SpeedCheck)
    print("Teleport Check:", Config.TeleportCheck)
    print("Noclip Check:", Config.NoclipCheck)
    print("Fly Check:", Config.FlyCheck)
end

init()

return AntiCheat
