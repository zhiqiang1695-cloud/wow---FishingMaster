local addonName, ns = ...
local FM = ns.FM                         -- data accessors, provided by FishingMaster.lua
local FishingMasterComm = _G.FishingMasterComm   -- global, may be nil; not needed for this page

ns.PageDashboard = {}
local page = ns.PageDashboard
local built = false

local function fmtCopper(c)
    c = math.max(0, math.floor(c or 0))
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    if g > 0 then return string.format("%d g %d s", g, s) end
    return string.format("%d s", s)
end

-- colors (dark flat)
local CARD_BG_LITE = {0.184, 0.212, 0.259}   -- slightly lighter card bg
local GOLD   = {0.949, 0.757, 0.306}         -- #F2C14E
local GREEN  = {0.345, 0.788, 0.541}         -- #58C98A
local GRAY   = {0.608, 0.631, 0.659}
local LIGHT  = {0.91, 0.92, 0.93}

-- dynamic references kept in upvalues for Refresh()
local dailyVal, totalVal, hourlyVal
local elapsedText, timerBtn, resetBtn
local lootText, rateText

local function makeCard(parent, x, y, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    t:SetColorTexture(CARD_BG_LITE[1], CARD_BG_LITE[2], CARD_BG_LITE[3], 1)
    return f
end

function page.Build(content)
    local W = content:GetWidth()
    local pad = 12
    local gap = 6

    -- 1) Three stat cards in a row
    local statW = (W - 2 * pad - 2 * gap) / 3
    local statH = 70
    local statY = pad

    local titles = {"今日收益", "累计收益", "时薪"}
    for i, title in ipairs(titles) do
        local x = pad + (i - 1) * (statW + gap)
        local card = makeCard(content, x, statY, statW, statH)

        local tt = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        tt:SetPoint("TOP", card, "TOP", 0, -10)
        tt:SetText(title)
        tt:SetTextColor(GRAY[1], GRAY[2], GRAY[3])

        local v = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        v:SetPoint("BOTTOM", card, "BOTTOM", 0, 10)
        if i == 1 then
            dailyVal = v
            v:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        elseif i == 2 then
            totalVal = v
            v:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        else
            hourlyVal = v
            v:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        end
    end

    -- 2) 本次用时 card with timer + reset buttons on the right
    local cardW = W - 2 * pad
    local cardH = 64
    local timeCardY = statY + statH + gap
    local tcard = makeCard(content, pad, timeCardY, cardW, cardH)

    local timeTitle = tcard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    timeTitle:SetPoint("TOPLEFT", tcard, "TOPLEFT", 12, -10)
    timeTitle:SetText("本次用时")
    timeTitle:SetTextColor(GRAY[1], GRAY[2], GRAY[3])

    elapsedText = tcard:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    elapsedText:SetPoint("LEFT", tcard, "LEFT", 12, -6)
    elapsedText:SetTextColor(LIGHT[1], LIGHT[2], LIGHT[3])

    timerBtn = ns.Style.CreateFlatButton(tcard, 64, 26)
    timerBtn:SetPoint("RIGHT", tcard, "RIGHT", -12, 14)
    timerBtn:SetScript("OnClick", function()
        FM.ToggleTimer()
    end)

    resetBtn = ns.Style.CreateFlatButton(tcard, 64, 26, "重置")
    resetBtn:SetPoint("RIGHT", tcard, "RIGHT", -12, -14)
    resetBtn:SetScript("OnClick", function()
        FM.ResetCurrent()
    end)

    -- 3) 最近拾取 card
    local lootY = timeCardY + cardH + gap
    local lootH = 110
    local lcard = makeCard(content, pad, lootY, cardW, lootH)

    local lootTitle = lcard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lootTitle:SetPoint("TOPLEFT", lcard, "TOPLEFT", 12, -10)
    lootTitle:SetText("最近拾取")
    lootTitle:SetTextColor(GRAY[1], GRAY[2], GRAY[3])

    lootText = lcard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lootText:SetPoint("TOPLEFT", lcard, "TOPLEFT", 12, -34)
    lootText:SetWidth(cardW - 24)
    lootText:SetJustifyH("LEFT")
    lootText:SetTextColor(LIGHT[1], LIGHT[2], LIGHT[3])

    -- 4) 汇率换算 card
    local rateY = lootY + lootH + gap
    local rateH = 50
    local rcard = makeCard(content, pad, rateY, cardW, rateH)

    local rateTitle = rcard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rateTitle:SetPoint("TOPLEFT", rcard, "TOPLEFT", 12, -10)
    rateTitle:SetText("汇率换算")
    rateTitle:SetTextColor(GRAY[1], GRAY[2], GRAY[3])

    rateText = rcard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rateText:SetPoint("LEFT", rcard, "LEFT", 12, 0)
    rateText:SetTextColor(LIGHT[1], LIGHT[2], LIGHT[3])

    built = true
    page.Refresh()
end

function page.Refresh()
    if not built then return end

    -- three stat values
    local daily = FM.GetDailyStats() or {}
    local total = FM.GetTotalStats() or {}
    dailyVal:SetText(fmtCopper(daily.totalCopper))
    totalVal:SetText(fmtCopper(total.totalCopper))

    local rate = FM.GetRate() or 0
    local el = FM.GetElapsed() or 0
    if rate > 0 and el > 0 then
        local cny = FM.GetTotalMoney() * rate / 100000000
        local hourly = cny / (el / 3600)
        hourlyVal:SetText(string.format("%.2f 元/时", hourly))
    else
        hourlyVal:SetText("0.00 元/时")
    end

    -- elapsed time HH:MM:SS
    local h = math.floor(el / 3600)
    local m = math.floor((el % 3600) / 60)
    local s = math.floor(el % 60)
    elapsedText:SetText(string.format("%02d:%02d:%02d", h, m, s))

    -- timer button label (start / continue / pause)
    if not FM.IsTimerActive() then
        timerBtn:SetText("开始")
    elseif FM.IsTimerPaused() then
        timerBtn:SetText("继续")
    else
        timerBtn:SetText("暂停")
    end

    -- recent loots (up to 3)
    local loots = FM.GetRecentLoots() or {}
    if #loots == 0 then
        lootText:SetText("无")
    else
        local lines = {}
        local n = math.min(3, #loots)
        for i = 1, n do
            local item = loots[i] or {}
            local line = (item.itemsDisplay or "")
                .. "   "
                .. string.format("%.4f", item.totalCNY or 0)
                .. " 元"
                .. ((item.coord and item.coord ~= "") and (" " .. item.coord) or "")
            table.insert(lines, line)
        end
        lootText:SetText(table.concat(lines, "\n"))
    end

    -- rate line
    rateText:SetText("10000 金 = " .. (rate > 0 and tostring(rate) or "?") .. " 元")
end
