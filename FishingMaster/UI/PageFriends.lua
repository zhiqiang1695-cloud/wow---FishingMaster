-- ============================================================================
-- PageFriends.lua  —  渔友圈（Friends Circle）导航页
-- 左侧栏导航 UI 的一屏：展示频道共享的社区钓鱼统计 / 排名 / 鱼价手册。
-- 本文件只负责把 UI 构建进 shell 提供的 content 帧，不创建独立窗口。
-- ============================================================================
local addonName, ns = ...
local FM = ns.FM
local FishingMasterComm = _G.FishingMasterComm   -- GLOBAL; may be nil if comm module missing

ns.PageFriends = {}
local page = ns.PageFriends
local built = false

-- 渲染所需的帧引用（供 Refresh 复用）
local contentFrame, scrollFrame, scrollChild, textFS, refreshBtn, joinBtn

-- ---------------------------------------------------------------------------
-- 工具（复制自 BasicPanel.lua，自包含）
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

-- 取协议表（可能为 nil）
local function GetProtocol()
    if FishingMasterComm and FishingMasterComm.Protocol then
        return FishingMasterComm.Protocol
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Build：在 shell 提供的 content 帧内构建 UI（仅执行一次）
-- ---------------------------------------------------------------------------
function page.Build(content)
    -- 刷新全部鱼价 按钮（顶部）
    refreshBtn = ns.Style.CreateFlatButton(content, 130, 24, "刷新全部鱼价")
    refreshBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
    refreshBtn:SetScript("OnClick", function()
        if FishingMasterComm and FishingMasterComm.StatsSync then
            local ok, n = pcall(function()
                return FishingMasterComm.StatsSync:QueryAllKnownPrices()
            end)
            if ok then
                print("|cff00ff00[FishingMaster 渔友圈]|r 已向频道查询 " .. (n or 0) .. " 种鱼的价格")
            else
                print("|cffff0000[FishingMaster 渔友圈]|r 查询鱼价失败")
            end
        else
            print("|cffff0000[FishingMaster 渔友圈]|r 渔友圈通讯模块未加载")
        end
        page.Refresh()
    end)

    -- 加入渔友圈 按钮（仅未开启时显示，固定在底部居中）
    joinBtn = ns.Style.CreateFlatButton(content, 130, 24, "加入渔友圈")
    joinBtn:SetPoint("BOTTOM", content, "BOTTOM", 0, 8)
    joinBtn:Hide()
    joinBtn:SetScript("OnClick", function()
        if FishingMasterComm and FishingMasterComm.Enable then
            pcall(function() FishingMasterComm:Enable() end)
        elseif FishingMasterComm then
            pcall(function() FishingMasterComm:Enable() end)
        end
        page.Refresh()
    end)

    -- 滚动区（长内容可滚动）
    scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -36)
    scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -28, 8)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(content:GetWidth() - 34, 10)
    scrollFrame:SetScrollChild(scrollChild)

    -- 唯一 FontString（整页文本拼接）
    textFS = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textFS:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    textFS:SetWidth(content:GetWidth() - 34)
    textFS:SetJustifyH("LEFT")
    textFS:SetTextColor(0.91, 0.92, 0.93)  -- 浅灰白，确保无 |c 码的行也清晰可读

    contentFrame = content
    built = true
end

-- ---------------------------------------------------------------------------
-- Refresh：根据当前 FishingMasterComm 数据重建文本
-- ---------------------------------------------------------------------------
function page.Refresh()
    if not built then return end

    -- 未加载通讯模块：提示 + 加入按钮（但无模块可加入）
    if not FishingMasterComm then
        joinBtn:Hide()
        textFS:SetText("|cff00ff00==== 渔友圈 ====|r\n|cffffcc00尚未开启渔友圈。|r\n渔友圈通讯模块未加载，\n无法加入频道。")
        scrollChild:SetHeight(textFS:GetStringHeight() + 10)
        return
    end

    -- 未开启：提示卡片 + 加入按钮
    local enabled, enOk = pcall(function() return FishingMasterComm:IsEnabled() end)
    if not (enOk and enabled) then
        joinBtn:Show()
        scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -28, 40)
        textFS:SetText("|cff00ff00==== 渔友圈 ====|r\n|cffffcc00尚未开启渔友圈。|r\n开启后你将与同服在线玩家\n共享钓鱼数 / 金币统计，\n并可查看鱼价手册。\n\n点击下方「加入渔友圈」即可加入。")
        scrollChild:SetHeight(textFS:GetStringHeight() + 10)
        return
    end

    -- 已开启：隐藏加入按钮，滚动区占满
    joinBtn:Hide()
    scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -28, 8)

    -- 正在连接频道
    local running = false
    pcall(function() running = FishingMasterComm:IsRunning() end)
    if not running then
        textFS:SetText("|cff00ff00==== 渔友圈 ====|r\n|cffff6666正在连接频道...|r")
        scrollChild:SetHeight(textFS:GetStringHeight() + 10)
        return
    end

    -- 已开启且运行中：渲染完整内容
    local lines = {}
    local Protocol = GetProtocol()

    -- 自身今日/累计数据（来自 _state.db）
    local selfEntry = { fc = 0, fd = 0, gc = 0, gd = 0 }
    pcall(function()
        local db = FishingMasterComm._state.db
        local today = date("%Y-%m-%d")
        local daily = (db.dailyStats and db.dailyStats[today]) or { totalPickups = 0, totalCopper = 0 }
        local total = db.totalStats or { totalPickups = 0, totalCopper = 0 }
        selfEntry.fc = total.totalPickups or 0
        selfEntry.fd = daily.totalPickups or 0
        selfEntry.gc = total.totalCopper or 0
        selfEntry.gd = daily.totalCopper or 0
    end)

    -- 频道概况
    local stats = {}
    pcall(function() stats = FishingMasterComm.StatsSync:GetChannelStats() end)
    stats = stats or {}
    table.insert(lines, "|cffffcc00==== 频道概况 ====|r")
    table.insert(lines, string.format("频道在线: %d 人    累计已知: %d 人",
        stats.online or 0, stats.known or 0))
    table.insert(lines, string.format("今日频道总产出: %s", FormatCopper(stats.todayGold or 0)))
    table.insert(lines, "")

    -- 你的排名（双维度）
    local fishRank = { rank = 0, total = 0 }
    local goldRank = { rank = 0, total = 0 }
    pcall(function() fishRank = FishingMasterComm.StatsSync:GetSelfRank("fishCount") end)
    pcall(function() goldRank = FishingMasterComm.StatsSync:GetSelfRank("gold") end)
    fishRank = fishRank or { rank = 0, total = 0 }
    goldRank = goldRank or { rank = 0, total = 0 }

    table.insert(lines, "|cffffcc00==== 你的排名 ====|r")
    table.insert(lines, string.format("钓鱼数榜: 第 %d 名 / %d 人", fishRank.rank or 0, fishRank.total or 0))
    table.insert(lines, string.format("  累计 %s 条   今日 %s 条",
        FormatInt(selfEntry.fc), FormatInt(selfEntry.fd)))
    table.insert(lines, string.format("金币榜:   第 %d 名 / %d 人", goldRank.rank or 0, goldRank.total or 0))
    table.insert(lines, string.format("  累计 %s   今日 %s",
        FormatCopper(selfEntry.gc), FormatCopper(selfEntry.gd)))
    table.insert(lines, "")
    table.insert(lines, string.format("频道平均: 钓鱼 %s 条  金币 %s",
        FormatInt(stats.avgFish or 0), FormatCopper(stats.avgGold or 0)))
    table.insert(lines, string.format("频道最高: 钓鱼 %s 条 (匿名)", FormatInt(stats.maxFish or 0)))
    table.insert(lines, "")

    -- 鱼价手册（按区域分组）
    table.insert(lines, "|cffffcc00==== 鱼价手册 ====|r")
    local db = nil
    pcall(function() db = FishingMasterComm._state.db end)
    if db and db.zones and next(db.zones) then
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
                    local tierLabel = (Protocol and Protocol.TIER_LABEL and Protocol.TIER_LABEL[e.tier]) or "价"
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

    textFS:SetText(table.concat(lines, "\n"))
    scrollChild:SetHeight(textFS:GetStringHeight() + 10)
end
