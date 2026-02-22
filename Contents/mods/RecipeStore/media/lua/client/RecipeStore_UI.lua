RecipeStore = RecipeStore or {}
RecipeStore.BuyableItems = {}

-- Helper to get options safely
function RecipeStore.getOption(name)
    if SandboxVars and SandboxVars.RecipeStore and SandboxVars.RecipeStore[name] then
        return SandboxVars.RecipeStore[name]
    end
    if name == "FilterMode" then return false end
    if name == "CategoryFilter" or name == "ItemFilter" then return "" end
    return 0
end

-- Helper: Parse comma separated string
local function parseFilterString(str)
    local list = {}
    if not str or str == "" then return list end

    for word in string.gmatch(str, '([^,]+)') do
        local cleanWord = string.trim(word)
        local isExact = false

        -- Check for quotes at start and end
        if string.len(cleanWord) > 1 and string.sub(cleanWord, 1, 1) == '"' and string.sub(cleanWord, -1) == '"' then
            isExact = true
            cleanWord = string.sub(cleanWord, 2, -2)
        end

        cleanWord = cleanWord:lower()
        if cleanWord ~= "" then
            table.insert(list, {text = cleanWord, exact = isExact})
        end
    end
    return list
end

-- Helper: Check matches
local function matchesAny(target, filterList)
    if #filterList == 0 then return false end
    if not target then return false end
    local cleanTarget = target:lower()

    for _, filter in ipairs(filterList) do
        if filter.exact then
            if cleanTarget == filter.text then return true end
        else
            if string.find(cleanTarget, filter.text, 1, true) then return true end
        end
    end
    return false
end

-- 1. Build Item List
function RecipeStore.buildItemList()
    RecipeStore.BuyableItems = {}

    local isWhitelist = RecipeStore.getOption("FilterMode")
    local catFilters = parseFilterString(RecipeStore.getOption("CategoryFilter"))
    local itemFilters = parseFilterString(RecipeStore.getOption("ItemFilter"))

    if isWhitelist and #catFilters == 0 and #itemFilters == 0 then return end

    local allRecipes = ScriptManager.instance:getAllRecipes()
    local craftableItems = {}
    local ingredientItems = {}

    -- Find Craftables & Ingredients
    for i=0, allRecipes:size()-1 do
        local recipe = allRecipes:get(i)
        local result = recipe:getResult():getFullType()
        craftableItems[result] = true

        local sources = recipe:getSource()
        for j=0, sources:size()-1 do
            local source = sources:get(j)
            local items = source:getItems()
            for k=0, items:size()-1 do
                ingredientItems[items:get(k)] = true
            end
        end
    end

    -- Filter
    for itemType, _ in pairs(ingredientItems) do
        if not craftableItems[itemType] then
            local scriptItem = ScriptManager.instance:getItem(itemType)
            if scriptItem and not scriptItem:getObsolete() then

                local itemName = scriptItem:getDisplayName()
                -- SAFETY: Default to "Misc" if nil
                local internalCat = scriptItem:getDisplayCategory()
                if not internalCat or internalCat == "" then internalCat = "Misc" end

                -- Check against Internal ID
                local matchesCat = matchesAny(internalCat, catFilters)

                -- Check against Display Name
                local displayCat = getText("IGUI_ItemCat_" .. internalCat)
                if displayCat == "IGUI_ItemCat_" .. internalCat then displayCat = internalCat end
                if not matchesCat then matchesCat = matchesAny(displayCat, catFilters) end

                local matchesName = matchesAny(itemName, itemFilters)
                local isMatch = matchesCat or matchesName

                local shouldAdd = false

                if isWhitelist then
                    if isMatch then shouldAdd = true end
                else
                    shouldAdd = true
                    if isMatch then shouldAdd = false end
                end

                if shouldAdd then
                    table.insert(RecipeStore.BuyableItems, scriptItem)
                end
            end
        end
    end
end

-- 3. Right Click Hook
local function onFillWorldObjectContextMenu(player, context, worldObjects, test)

    RecipeStore.buildItemList()

    if #RecipeStore.BuyableItems == 0 then return end

    local playerObj = getSpecificPlayer(player)
    local modData = playerObj:getModData()
    local points = modData.RS_Points or 0

    -- Add Main Option
    local storeOption = context:addOption("Recipe Store", worldObjects, nil)
    local storeSubMenu = context:getNew(context)
    context:addSubMenu(storeOption, storeSubMenu)

    local header = storeSubMenu:addOption("Points: " .. points, nil, nil)
    header.notAvailable = true

    -- Group items by Display Name for the UI
    local categorizedItems = {}
    -- Store the mapping from Display Name -> Internal ID for the header
    local categoryInternalIDs = {}

    for _, item in ipairs(RecipeStore.BuyableItems) do
        local internalCat = item:getDisplayCategory()
        if not internalCat or internalCat == "" then internalCat = "Misc" end

        local displayCat = getText("IGUI_ItemCat_" .. internalCat)
        if displayCat == "IGUI_ItemCat_" .. internalCat then displayCat = internalCat end

        if not categorizedItems[displayCat] then
            categorizedItems[displayCat] = {}
            categoryInternalIDs[displayCat] = internalCat -- Save the ID for later
        end
        table.insert(categorizedItems[displayCat], item)
    end

    local sortedCategories = {}
    for catName, _ in pairs(categorizedItems) do table.insert(sortedCategories, catName) end
    table.sort(sortedCategories)

    for _, catName in ipairs(sortedCategories) do
        local items = categorizedItems[catName]
        table.sort(items, function(a,b) return a:getDisplayName() < b:getDisplayName() end)

        local catOption = storeSubMenu:addOption(catName, nil, nil)
        local catSubMenu = storeSubMenu:getNew(storeSubMenu)
        storeSubMenu:addSubMenu(catOption, catSubMenu)

        -- NEW HEADER: Display the Internal ID
        local internalID = categoryInternalIDs[catName] or "Unknown"
        local idHeader = catSubMenu:addOption("ID: " .. internalID, nil, nil)
        idHeader.notAvailable = true

        for _, item in ipairs(items) do
            local name = item:getDisplayName()
            local fullType = item:getFullName()

            local buyOption = catSubMenu:addOption(name, playerObj, function(pl)
                local pData = pl:getModData()
                if pData.RS_Points and pData.RS_Points >= 1 then
                    pData.RS_Points = pData.RS_Points - 1
                    pl:getInventory():AddItem(fullType)
                    pl:setHaloNote("Purchased: " .. name, 0, 255, 0, 300)
                else
                    pl:setHaloNote("Not enough points!", 255, 0, 0, 300)
                end
            end)

            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip:setName(name)
            tooltip.description = "Cost: 1 Point"
            buyOption.toolTip = tooltip
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
