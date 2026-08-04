-- ========================= 快速拾取模块 =========================
-- 所有状态下自动拾取，跳过拾取窗口
-- 参考 SpeedyAutoLoot 实现

local addonName, ns = ...

-- ========================= 版本检测 =========================
local isClassicEra = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC or WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC

-- ========================= 隐藏帧 =========================
local hiddenFrame = CreateFrame("Frame", nil, UIParent)
hiddenFrame:Hide()

local isLooting = false
local lootFailure = false
local lootTicker = nil
local lastNumLoot = nil
local slotsLooted = {}
local initialized = false

-- ========================= 接口 =========================
local QuickLoot = {}
ns.QuickLoot = QuickLoot

function QuickLoot:IsEnabled()
    return LootStatsDB and LootStatsDB.quickLootEnabled == true
end

function QuickLoot:Toggle()
    if not LootStatsDB then return false end
    LootStatsDB.quickLootEnabled = not LootStatsDB.quickLootEnabled
    if LootStatsDB.quickLootEnabled then
        QuickLoot:HideFrame()
    else
        QuickLoot:RestoreFrame()
    end
    return LootStatsDB.quickLootEnabled
end

-- ========================= LootFrame 操作 =========================
function QuickLoot:HideFrame()
    if LootFrame then
        LootFrame:SetParent(hiddenFrame)
    end
end

function QuickLoot:RestoreFrame()
    if LootFrame then
        LootFrame:SetParent(UIParent)
    end
end

function QuickLoot:ShowFrame()
    if not LootFrame then return end
    LootFrame:SetParent(UIParent)
    LootFrame:SetFrameStrata("HIGH")
    if GetCVarBool("lootUnderMouse") then
        local x, y = GetCursorPosition()
        local scale = LootFrame:GetEffectiveScale()
        LootFrame:ClearAllPoints()
        LootFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x / scale) - 40, (y / scale) + 20)
        LootFrame:Raise()
    else
        LootFrame:ClearAllPoints()
        LootFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -125)
    end
end

-- ========================= 背包空间检查 =========================
local function ItemFitsInBag(itemLink, itemQuantity)
    if not itemLink then return false end
    local itemFamily = C_Item.GetItemFamily(itemLink)
    local itemStackCount = select(8, C_Item.GetItemInfo(itemLink))
    local isCraftingReagent = select(10, C_Item.GetItemInfo(itemLink))

    -- Classic Era: 钥匙环检查
    if isClassicEra and itemFamily == 256 then
        local freeKeyringSlots = C_Container.GetContainerNumFreeSlots(Enum.BagIndex.Keyring)
        if freeKeyringSlots and freeKeyringSlots > 0 then
            return true
        end
    end

    -- 已有物品的可堆叠检查
    if itemStackCount and itemStackCount > 1 then
        local inventoryItemCount = C_Item.GetItemCount(itemLink)
        if inventoryItemCount > 0 and ((itemStackCount - inventoryItemCount) % itemStackCount) >= itemQuantity then
            return true
        end
    end

    for bagSlot = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS do
        local freeSlots, bagFamily = C_Container.GetContainerNumFreeSlots(bagSlot)
        if freeSlots and freeSlots > 0 then
            if bagSlot == 5 then
                if isCraftingReagent then return true end
            else
                if not bagFamily or bagFamily == 0 or (itemFamily and bit.band(itemFamily, bagFamily) > 0) then
                    return true
                end
            end
        end
    end
    return false
end

-- ========================= 拾取单个 slot =========================
local function LootSlotSafe(slot)
    local slotType = GetLootSlotType(slot)
    if slotType == Enum.LootSlotType.None then return true end

    local itemLink = GetLootSlotLink(slot)
    local lootQuantity, _, lootQuality, lootLocked, isQuestItem = select(3, GetLootSlotInfo(slot))
    if lootLocked or (lootQuality and lootQuality >= 10) then
        lootFailure = true
        return false
    end

    -- 非 Item 类型直接拾取（金币等）
    -- Classic 下不对 questItem 特殊处理，统一走背包检查
    if slotType ~= Enum.LootSlotType.Item then
        LootSlot(slot)
        slotsLooted[slot] = true
        if isClassicEra and (not IsInGroup() or C_PartyInfo.GetLootMethod() == "freeforall") then
            ConfirmLootSlot(slot)
        end
        return true
    end

    -- Item 类型：检查背包空间
    if ItemFitsInBag(itemLink, lootQuantity or 1) then
        LootSlot(slot)
        slotsLooted[slot] = true
        if isClassicEra and (not IsInGroup() or C_PartyInfo.GetLootMethod() == "freeforall") then
            ConfirmLootSlot(slot)
        end
        return true
    end
    return false
end

-- ========================= 逐个拾取 =========================
local function StartLooting(numItems)
    if lootTicker then lootTicker:Cancel() end
    local currentSlot = numItems
    lootFailure = false

    lootTicker = C_Timer.NewTicker(0.033, function()
        if currentSlot >= 1 then
            if not LootSlotSafe(currentSlot) then
                lootFailure = true
            end
            currentSlot = currentSlot - 1
        else
            if lootFailure then
                QuickLoot:ShowFrame()
            end
            if lootTicker then lootTicker:Cancel(); lootTicker = nil end
        end
    end, numItems + 1)
end

-- ========================= 事件处理 =========================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= addonName then return end
        -- SavedVariables 此时已从磁盘加载完毕
        if not LootStatsDB then LootStatsDB = {} end
        if LootStatsDB.quickLootEnabled == nil then LootStatsDB.quickLootEnabled = true end

        -- 延迟隐藏 LootFrame，等 Blizzard 框架完全加载（参考 SpeedyAutoLoot）
        C_Timer.After(5, function()
            if LootStatsDB.quickLootEnabled then
                QuickLoot:HideFrame()
            end
        end)
        return
    end

    if event == "PLAYER_LOGIN" then
        initialized = true
        -- 注册拾取事件
        self:RegisterEvent("LOOT_READY")
        self:RegisterEvent("LOOT_OPENED")
        self:RegisterEvent("LOOT_CLOSED")
        self:RegisterEvent("UI_ERROR_MESSAGE")
        if isClassicEra then
            self:RegisterEvent("LOOT_SLOT_CHANGED")
        end
        return
    end

    if not initialized or not LootStatsDB or not LootStatsDB.quickLootEnabled then return end

    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        local numItems = GetNumLootItems()
        if numItems == 0 or lastNumLoot == numItems then return end
        isLooting = true
        QuickLoot:HideFrame()
        StartLooting(numItems)
        lastNumLoot = numItems

    elseif event == "LOOT_CLOSED" then
        isLooting = false
        lastNumLoot = nil
        lootFailure = false
        if lootTicker then lootTicker:Cancel(); lootTicker = nil end
        if isClassicEra then
            wipe(slotsLooted)
        end
        -- 重新隐藏 LootFrame，防止原生 LootFrame 下次闪现
        QuickLoot:HideFrame()

    elseif event == "LOOT_SLOT_CHANGED" then
        -- Classic Era: 修复堆叠物品拾取失败的 bug
        local slot = ...
        if isLooting and slotsLooted[slot] and LootSlotHasItem(slot) then
            LootSlotSafe(slot)
        end

    elseif event == "UI_ERROR_MESSAGE" then
        local _, msg = ...
        if msg == ERR_INV_FULL or msg == ERR_ITEM_MAX_COUNT then
            if isLooting then
                QuickLoot:ShowFrame()
            end
        end
    end
end)
