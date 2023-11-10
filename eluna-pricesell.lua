local json = require("json")
-- CONFIG
local payoutCap = 5000000 -- Max amount that can be payed out by .sell
local marketValueDiv = 5 -- Divde the market value average by this amount
local numMonths = 16
local servers = {
    "us",
    "eu"
}
local debugMode = false -- Set to true to enable debug logging
-- END CONFIG

local marketValues = {}
local requestCount = 0
local completedRequests = 0



local function debugLog(...)
    if debugMode then
        print(...)
    end
end

-- Helper function to calculate the mean of a table
local function calculateMean(t)
    local sum = 0
    local count = 0

    for _, value in pairs(t) do
        sum = sum + value.marketValue
        count = count + value.count
    end

    return (count == 0) and 0 or (sum / count)
end

-- Helper function to calculate the standard deviation of a table
local function calculateStandardDeviation(t, mean)
    local variance = 0
    local count = 0

    for _, value in pairs(t) do
        variance = variance + ((value.marketValue - mean) ^ 2) * value.count
        count = count + value.count
    end

    return (count == 0) and 0 or math.sqrt(variance / count)
end

-- Function to add market value data
local function addMarketValueData(marketValue)
    -- Add the market value to the global list
    table.insert(marketValues, marketValue)
end

-- Function to filter out the outliers
local function filterOutliers(values, mean, stdDev)
    local filteredValues = {}
    local threshold = stdDev * 1.5 -- Change this to adjust the sensitivity

    for _, value in pairs(values) do
        if math.abs(value.marketValue - mean) <= threshold then
            table.insert(filteredValues, value)
        end
    end

    return filteredValues
end

function GetAllItemsFromPlayer(player, orig_itemLink)
    local items = {}
    -- Backpack slots are always 23-38
    for slot = 23, 38 do
        local item = player:GetItemByPos(255, slot)
        if item then
            local itemLink = item:GetItemLink()
            if itemLink == orig_itemLink and item:GetCount() == item:GetMaxStackCount() then
                return item
            end
        end
    end
    -- Equipped bag slots are 19-22
    for bag = 19, 22 do
        -- Get the container item for the bag slot
        local container = player:GetItemByPos(255, bag)
        if container then
            -- Get the number of slots in the bag
            local bagSlots = container:GetBagSize()
            for slot = 0, bagSlots - 1 do
                local item = player:GetItemByPos(bag, slot)
                if item then
                    local itemLink = item:GetItemLink()
                    if itemLink == orig_itemLink and item:GetCount() == item:GetMaxStackCount() then
                        return item
                    end
                end
            end
        end
    end
    return nil
end


function GetFormattedGoldString(copper)
    local gold = math.floor(copper / (100 * 100))
    local remainingCopper = copper % (100 * 100)
    local silver = math.floor(remainingCopper / 100)
    remainingCopper = remainingCopper % 100

    -- Building the string based on the amount of gold, silver, and copper.
    local goldString = ""
    if gold > 0 then
        goldString = goldString .. gold .. "G "
    end
    if silver > 0 or gold > 0 then -- Include silver if there's also gold
        goldString = goldString .. silver .. "s "
    end
    goldString = goldString .. remainingCopper .. "c"

    return goldString
end


-- Function to call after all requests are done
local function allRequestsComplete(playerGUID, itemLink, sell)
    local player = GetPlayerByGUID(playerGUID)
    local mean = calculateMean(marketValues)
    local stdDev = calculateStandardDeviation(marketValues, mean)

    -- Filter out individual data points that are outliers
    local filteredMarketValues = filterOutliers(marketValues, mean, stdDev)

    local totalMarketValue = 0
    local totalCount = 0

    -- Sum all market values from the filtered list
    for _, value in pairs(filteredMarketValues) do
        totalMarketValue = totalMarketValue + value.marketValue
        totalCount = totalCount + 1 -- Count should be 1 per data point
    end

    debugLog("Filtered Total Market Value: ", totalMarketValue)
    debugLog("Filtered Total Count: ", totalCount)

    -- Fetch the item details from the player's bags
    local item = GetAllItemsFromPlayer(player, itemLink) -- Assuming this function returns the correct item
    if not item then
        player:SendBroadcastMessage("Item not found in inventory. Must be a full stack if stackable.")
        return
    end

    -- Calculate grand average and send it to the player
    if totalCount > 300 then
        local grandAverageMarketValue = totalMarketValue / totalCount
        local goldAmount = math.ceil(grandAverageMarketValue / marketValueDiv)
        if goldAmount > payoutCap then
            goldAmount = payoutCap
        end
        if item:IsSoulBound() then
            player:SendBroadcastMessage("Soulbound items cannot be sold.")
            return
        end

        local stack = item:GetCount()
        local name = item:GetName()
        local message

        if stack > 1 then
            if sell then
                goldAmount = goldAmount * stack
                local goldString = GetFormattedGoldString(goldAmount)
                player: RemoveItem(item, item:GetMaxStackCount())
                current_coinage = player:GetCoinage()
                player:SetCoinage(current_coinage+goldAmount)
                message = string.format("%d %s sold for %s!", stack, name, goldString)
            else
                goldAmount = goldAmount * stack
                local goldString = GetFormattedGoldString(goldAmount)
                message = string.format("%d %s would sell for for %s!", stack, name, goldString)
            end

        else
            if sell then
                local goldString = GetFormattedGoldString(goldAmount)
                player: RemoveItem(item, item:GetMaxStackCount())
                current_coinage = player:GetCoinage()
                player:SetCoinage(current_coinage+goldAmount)
                message = string.format("%s sold for %s!", name, goldString)
            else
                local goldString = GetFormattedGoldString(goldAmount)
                message = string.format("%s would sell for for %s!", name, goldString)
            end
        end

        player:SendBroadcastMessage(message)
    elseif totalCount > 0 then
        player:SendBroadcastMessage("Not enough data to make a reliable estimation after excluding outliers.")
    else
        player:SendBroadcastMessage("No valid price entries found across all servers after excluding outliers.")
    end

    -- Clear the table for the next command invocation
    marketValues = {}
end


-- Function to extract and format the item name
local function extractAndFormatItemName(input)
    debugLog("Input String: ", input)

    -- Pattern to extract the item name
    local itemName = input:match("%|h%[(.-)%]%|h")
    if not itemName then
        debugLog("Item name not found.")
        return nil
    end

    debugLog("Extracted Item Name: ", itemName)

    -- Convert to lowercase, replace spaces with hyphens, and remove punctuation
    itemName = itemName:lower():gsub("%p", ""):gsub("%s", "-")
    debugLog("Formatted Item Name: ", itemName)

    return itemName
end

-- Modified fetchItemPrices to work with global storage and a completion check
local function fetchItemPrices(playerGUID, server, itemName, itemLink, sell)
    local url = string.format("https://api.nexushub.co/wow-classic/v1/items/%s/%s/prices?timerange=16&region=true", server, itemName)
    
    requestCount = requestCount + 1 -- Increment total request count
    
    HttpRequest("GET", url, function(status, body, headers)
        completedRequests = completedRequests + 1 -- Increment completed request count

        if status ~= 200 then
            local player = GetPlayerByGUID(playerGUID)
            player:SendBroadcastMessage("Failed to fetch prices for item: " .. itemName .. " on " .. server)
        else
            local parsedBody = json.decode(body)
            if parsedBody and parsedBody.data and #parsedBody.data > 0 then
                for i, dataPoint in ipairs(parsedBody.data) do
                    -- Add each market value to the global list
                    addMarketValueData({marketValue = dataPoint.marketValue, count = 1})
                end
                debugLog("Data fetched for " .. itemName .. " on " .. server)
            else
                debugLog("No data found for " .. itemName .. " on " .. server)
            end
        end
        
        -- If all requests have completed, calculate the grand average
        if completedRequests == requestCount then
            allRequestsComplete(playerGUID, itemLink, sell)
        end
    end)
end


RegisterPlayerEvent(42, function(event, player, command)
    local cmd, itemLink = command:match("^(%S+)%s+(|c.-|r)$")
    if cmd == "sell" and itemLink then
        print(itemLink)
        local itemName = extractAndFormatItemName(itemLink)
        if itemName then
            local playerGUID = player:GetGUID()
            -- Assuming you want to handle all factions and servers, loop through each
            for _, region in ipairs(servers) do
                
                -- Call the fetchItemPrices with correct parameters
                fetchItemPrices(playerGUID, region, itemName, itemLink, true)
            end
        else
            player:SendBroadcastMessage("Could not extract item name.")
        end
        return false -- Important to return false to prevent the default command handler
    end
    if cmd == "price" and itemLink then
        print(itemLink)
        local itemName = extractAndFormatItemName(itemLink)
        if itemName then
            local playerGUID = player:GetGUID()
            -- Assuming you want to handle all factions and servers, loop through each
            for _, region in ipairs(servers) do
                
                -- Call the fetchItemPrices with correct parameters
                fetchItemPrices(playerGUID, region, itemName, itemLink, false)
            end
        else
            player:SendBroadcastMessage("Could not extract item name.")
        end
        return false -- Important to return false to prevent the default command handler
    end
end)
