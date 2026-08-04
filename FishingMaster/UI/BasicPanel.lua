-- ============================================================================
-- BasicPanel.lua  —  基础版渔友圈面板
-- 显示：自身排名（双维度）+ 匿名频道汇总 + 鱼价手册
-- 不展示其他玩家个人信息（符合基础版范围边界）。
-- ============================================================================
local MAJOR = "FishingMasterComm"
local FishingMasterComm = _G[MAJOR] or {}
_G[MAJOR] = FishingMasterComm

local Protocol = FishingMasterComm.Protocol

-- ---------------------------------------------------------------------------
-- 工具
-- ---------------------------------------------------------------------------
local function FormatCopper(copper)
    copper = math.max(0, math.floor(copper or 0))
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    if g > 0 then
        return string.format("%d g %d s", g, s)
    end
    return string.format("%d s", s)
end

local function FormatInt(n)
    n = math.floor(n or 0)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    out = out:gsub("^,", "")
    return out
end

local function FormatAge(ts)
    if not ts then return "未知" end
    local diff = time() - ts
    if diff < 60 then return (diff < 0 and 0 or diff) .. "秒前" end
    if diff < 3600 then return math.floor(diff / 60) .. "分钟前" end
    if diff < 86400 then return math.floor(diff / 3600) .. "小时前" end
    return math.floor(diff / 86400) .. "天前"
end

-- ---------------------------------------------------------------------------
-- 创建面板
-- ---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "FMStatsPanel", UIParent)
panel:SetSize(300, 440)
panel:SetPoint("CENTER", UIParent, "CENTER")
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
panel:Hide()

panel.bg = panel:CreateTexture(nil, "BACKGROUND")
panel.bg:SetAllPoints()
panel.bg:SetColorTexture(0, 0, 0, 0.75)

-- 标题
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", panel, "TOP", 0, -8)
title:SetText("渔友圈")
title:SetTextColor(0, 1, 0.4)

-- 关闭按钮
local closeBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
closeBtn:SetSize(50, 22)
closeBtn:SetText("关闭")
closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)
closeBtn:SetScript("OnClick", function() panel:Hide() end)

-- 滚动区
local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -38)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 36)

local scrollChild = CreateFrame("Frame", nil, scroll)
scrollChild:SetSize(270, 10)
scroll:SetScrollChild(scrollChild)
panel.scrollChild = scrollChild

local content = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
content:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
content:SetWidth(265)
content:SetJustifyH("LEFT")
scrollChild.content = content

-- 刷新鱼价按钮
local refreshBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
refreshBtn:SetSize(110, 24)
refreshBtn:SetText("刷新全部鱼价")
refreshBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
refreshBtn:SetScript("OnClick", function()
    if FishingMasterComm.StatsSync then
        local n = FishingMasterComm.StatsSync:QueryAllKnownPrices()
        print("|cff00ff00[FishingMaster 渔友圈]|r 已向频道查询 " .. (n or 0) .. " 种鱼的的价格")
    end
end)

-- 开启/关闭按钮
local toggleBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
toggleBtn:SetSize(78, 24)
toggleBtn:SetText("退出渔友圈")
toggleBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)
toggleBtn:SetScript("OnClick", function()
    if FishingMasterComm:IsEnabled() then
        FishingMasterComm:Disable()
        print("|cffff0000[FishingMaster 渔友圈]|r 已关闭")
    else
        FishingMasterComm:Enable()
    end
    BasicPanel:Refresh()
end)

-- 高级面板按钮（仅当 FishingMasterPro 已加载时可用）
local proBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
proBtn:SetSize(78, 24)
proBtn:SetText("高级面板")
proBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 8)
proBtn:SetScript("OnClick", function()
    if not FishingMasterComm.AdvancedPanel then
        FishingMasterComm:TryLoadPro()
    end
    if FishingMasterComm.AdvancedPanel then
        FishingMasterComm.AdvancedPanel:Show()
    else
        print("|cffff0000[FishingMaster 渔友圈]|r 未安装高级版 FishingMasterPro")
    end
end)

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------
local BasicPanel = {}
FishingMasterComm.BasicPanel = BasicPanel

function BasicPanel:IsOpen() return panel:IsShown() end

function BasicPanel:Show()
    panel:Show()
    self:Refresh()
end

function BasicPanel:Hide()
    panel:Hide()
end

function BasicPanel:Toggle()
    if panel:IsShown() then
        panel:Hide()
        return false
    end
    panel:Show()
    self:Refresh()
    return true
end

function BasicPanel:OnCommStateChanged(running)
    if panel:IsShown() then self:Refresh() end
end

function BasicPanel:Refresh()
    if not panel:IsShown() then return end
    local lines = {}

    if not FishingMasterComm:IsEnabled() then
        table.insert(lines, "|cffffcc00==== 渔友圈 ====|r")
        table.insert(lines, "尚未开启渔友圈。")
        table.insert(lines, "点击右下「加入渔友圈」。")
        table.insert(lines, "")
        table.insert(lines, "开启后你将与同服在线玩家")
        table.insert(lines, "共享钓鱼数 / 金币统计，")
        table.insert(lines, "并可查看鱼价手册。")
        content:SetText(table.concat(lines, "\n"))
        scrollChild:SetHeight(content:GetStringHeight() + 10)
        toggleBtn:SetText("加入渔友圈")
        return
    end

    if not FishingMasterComm:IsRunning() then
        table.insert(lines, "|cffffcc00==== 渔友圈 ====|r")
        table.insert(lines, "|cffff6666正在连接频道...|r")
        content:SetText(table.concat(lines, "\n"))
        scrollChild:SetHeight(content:GetStringHeight() + 10)
        toggleBtn:SetText("退出渔友圈")
        return
    end

    toggleBtn:SetText("退出渔友圈")

    local stats = FishingMasterComm.StatsSync:GetChannelStats()
    table.insert(lines, "|cffffcc00==== 频道概况 ====|r")
    table.insert(lines, string.format("频道在线: %d 人    累计已知: %d 人", stats.online, stats.known))
    table.insert(lines, string.format("今日频道总产出: %s", FormatCopper(stats.todayGold)))
    table.insert(lines, "")

    -- 自身排名（双维度）
    local fishRank = FishingMasterComm.StatsSync:GetSelfRank("fishCount")
    local goldRank = FishingMasterComm.StatsSync:GetSelfRank("gold")
    local selfEntry = (function()
        local db = FishingMasterComm._state.db
        local today = date("%Y-%m-%d")
        local daily = (db.dailyStats and db.dailyStats[today]) or { totalPickups = 0, totalCopper = 0 }
        local total = db.totalStats or { totalPickups = 0, totalCopper = 0 }
        return { fc = total.totalPickups or 0, fd = daily.totalPickups or 0, gc = total.totalCopper or 0, gd = daily.totalCopper or 0 }
    end)()

    table.insert(lines, "|cffffcc00==== 你的排名 ====|r")
    table.insert(lines, string.format("钓鱼数榜: 第 %d 名 / %d 人", fishRank.rank, fishRank.total))
    table.insert(lines, string.format("  累计 %s 条   今日 %s 条",
        FormatInt(selfEntry.fc), FormatInt(selfEntry.fd)))
    table.insert(lines, string.format("金币榜:   第 %d 名 / %d 人", goldRank.rank, goldRank.total))
    table.insert(lines, string.format("  累计 %s   今日 %s",
        FormatCopper(selfEntry.gc), FormatCopper(selfEntry.gd)))
    table.insert(lines, "")
    table.insert(lines, string.format("频道平均: 钓鱼 %s 条  金币 %s",
        FormatInt(stats.avgFish), FormatCopper(stats.avgGold)))
    table.insert(lines, string.format("频道最高: 钓鱼 %s 条 (匿名)", FormatInt(stats.maxFish)))
    table.insert(lines, "")

    -- 鱼价手册（按区域分组，匿名来源）
    table.insert(lines, "|cffffcc00==== 鱼价手册 ====|r")
    local db = FishingMasterComm._state.db
    if db.zones and next(db.zones) then
        local zoneNames = {}
        for z in pairs(db.zones) do table.insert(zoneNames, z) end
        table.sort(zoneNames)
        for _, zone in ipairs(zoneNames) do
            table.insert(lines, "|cff88ccff▼ " .. zone .. "|r")
            local fishList = {}
            for fish in pairs(db.zones[zone]) do table.insert(fishList, fish) end
            table.sort(fishList)
            if #fishList == 0 then
                table.insert(lines, "  (暂无记录)")
            end
            for _, fish in ipairs(fishList) do
                local e = db.priceBook and db.priceBook[fish]
                if e and e.price and e.price > 0 then
                    local tierLabel = Protocol.TIER_LABEL[e.tier] or "价"
                    local stale = (e.ts and (time() - e.ts) > 3600)
                    local c = stale and "|cff888888" or "|cffccffcc"
                    table.insert(lines, string.format("  %s  [%s]  %s  %s%s|r",
                        fish, tierLabel, FormatCopper(e.price), c, FormatAge(e.ts)))
                else
                    table.insert(lines, string.format("  %s  [未知]", fish))
                end
            end
            table.insert(lines, "")
        end
    else
        table.insert(lines, "暂无区域鱼获记录。")
        table.insert(lines, "")
    end

    content:SetText(table.concat(lines, "\n"))
    scrollChild:SetHeight(content:GetStringHeight() + 10)
end

-- 首次打开时刷新一次
panel:SetScript("OnShow", function() BasicPanel:Refresh() end)
