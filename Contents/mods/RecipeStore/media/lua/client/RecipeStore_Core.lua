RecipeStore = RecipeStore or {}

-- Helper to get options safely.
function RecipeStore.getOption(name)
    if SandboxVars and SandboxVars.RecipeStore and SandboxVars.RecipeStore[name] then
        return SandboxVars.RecipeStore[name]
    end
    return 0
end

-- Initialize ModData on player creation
local function initPlayerPoints(playerIndex, player)
    local modData = player:getModData()

    if modData.RS_Points == nil then modData.RS_Points = 0 end
    if modData.RS_KillCounter == nil then modData.RS_KillCounter = 0 end

    -- Only initialize timers if the feature is actually enabled
    -- This saves a tiny bit of memory/processing if features are off

    if RecipeStore.getOption("DaysPerPoint") > 0 then
        if modData.RS_LastDayCheck == nil then
            modData.RS_LastDayCheck = getGameTime():getWorldAgeHours() / 24
        end
    end

    if RecipeStore.getOption("MinutesPerPoint") > 0 then
        if modData.RS_LastRealTimeCheck == nil then
            modData.RS_LastRealTimeCheck = os.time()
        end
    end
end

-- 1. TRACK ZOMBIE KILLS
local function onZombieDead(zombie)
    -- OPTIMIZATION: Check setting first. If 0, stop immediately.
    local zombiesNeeded = RecipeStore.getOption("ZombiesPerPoint")
    if not zombiesNeeded or zombiesNeeded <= 0 then return end

    local player = zombie:getAttackedBy()
    if not player or not instanceof(player, "IsoPlayer") or not player:isLocalPlayer() then return end

    local modData = player:getModData()
    modData.RS_KillCounter = (modData.RS_KillCounter or 0) + 1

    if modData.RS_KillCounter >= zombiesNeeded then
        modData.RS_Points = (modData.RS_Points or 0) + 1
        modData.RS_KillCounter = 0

        player:setHaloNote("Point Earned! (" .. modData.RS_Points .. ")", 0, 255, 0, 300)
    end
end

-- 2. TRACK TIME (Every Minute Tick)
local function onEveryOneMinute()
    local player = getPlayer()
    if not player then return end
    local modData = player:getModData()

    -- A. Check In-Game Days
    local daysNeeded = RecipeStore.getOption("DaysPerPoint")

    -- LOGIC: Only run if setting is > 0
    if daysNeeded and daysNeeded > 0 then
        local currentDay = getGameTime():getWorldAgeHours() / 24

        -- Initialize if missing (e.g. enabled mid-game)
        if not modData.RS_LastDayCheck then modData.RS_LastDayCheck = currentDay end

        if (currentDay - modData.RS_LastDayCheck) >= daysNeeded then
            modData.RS_Points = (modData.RS_Points or 0) + 1
            modData.RS_LastDayCheck = currentDay

            player:setHaloNote("Survival Bonus! +1 Point", 0, 255, 0, 300)
        end
    end

    -- B. Check Real Time Minutes
    local minsNeeded = RecipeStore.getOption("MinutesPerPoint")

    -- LOGIC: Only run if setting is > 0
    if minsNeeded and minsNeeded > 0 then
        local currentTime = os.time()

        -- Initialize if missing (e.g. enabled mid-game)
        if not modData.RS_LastRealTimeCheck then modData.RS_LastRealTimeCheck = currentTime end

        local diffSeconds = currentTime - modData.RS_LastRealTimeCheck

        -- Check if enough seconds passed (minutes * 60)
        if diffSeconds >= (minsNeeded * 60) then
            modData.RS_Points = (modData.RS_Points or 0) + 1
            modData.RS_LastRealTimeCheck = currentTime

            player:setHaloNote("Playtime Bonus! +1 Point", 0, 255, 0, 300)
        end
    end
end

Events.OnCreatePlayer.Add(initPlayerPoints)
Events.OnZombieDead.Add(onZombieDead)
Events.EveryOneMinute.Add(onEveryOneMinute)
