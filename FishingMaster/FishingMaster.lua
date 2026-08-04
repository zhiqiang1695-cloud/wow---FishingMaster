local addonName, ns = ...

-- ========================= 初始化 SavedVariables =========================
-- 注意：SavedVariables 在 Lua 文件执行后、ADDON_LOADED 前从磁盘加载
-- 所以文件级的初始化会被覆盖，必须放在 ADDON_LOADED 中
-- 这里仅声明前向引用的函数名，实际初始化在 ADDON_LOADED 事件中

-- ========================= 钓鱼法术ID（复刻FishingRangeAlert） =========================
local FishingSpellIDs = {
    [131474] = true, [131490] = true, [88868] = true, [51294] = true,
    [18248] = true, [33095] = true, [7732] = true,
    [7731] = true, [7620] = true, [62734] = true
}

-- ========================= 创建主框架 =========================
local mainFrame = CreateFrame("Frame", "LootStatsMainFrame", UIParent)
local mainFrameHeight = 420

mainFrame:SetSize(292, mainFrameHeight)
mainFrame:SetPoint("CENTER", UIParent, "CENTER")
mainFrame:SetMovable(true)
mainFrame:SetClampedToScreen(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
mainFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

-- ========================= 钓鱼横条 =========================
-- 触发钓鱼时在屏幕顶部居中显示一条横条（替代自动弹出主界面）
-- 可拖动，拖动位置记录到 LootStatsDB.barPos；弹出/关闭逻辑与原 mainFrame 一致
local fmBar = CreateFrame("Frame", "FishingMasterBar", UIParent)
-- 提前声明核心变量：UpdateFishingBar 等函数在第85行就引用这些变量，
-- 但它们的实际初始化在第351行之后。若不提前声明，Lua 会把它们编译为全局访问 → nil。
local fishingStatusText
local totalMoney, startTime, timerActive, timerPaused, timerTicker
local recentLoots, lastLootTime, isFishing, fishingCooldownTimer, fishingCountdownTicker
local SetMinimapButtonAngle  -- 在文件末尾定义，但 ADDON_LOADED 回调（前文）需要调用，提前声明避免前向引用
fmBar:SetSize(300, 30)
fmBar:SetPoint("TOP", UIParent, "TOP", 0, -16)
fmBar:SetFrameStrata("HIGH")
fmBar:SetMovable(true)
fmBar:SetClampedToScreen(true)
fmBar:EnableMouse(true)
fmBar:RegisterForDrag("LeftButton")
fmBar:Hide()

-- 背景（深色半透明，扁平）
fmBar.bg = fmBar:CreateTexture(nil, "BACKGROUND")
fmBar.bg:SetAllPoints()
fmBar.bg:SetColorTexture(0.118, 0.137, 0.173, 0.92)  -- #1E232C

-- 信息文本（单行，内联颜色）
fmBar.text = fmBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
fmBar.text:SetPoint("LEFT", fmBar, "LEFT", 14, 0)
fmBar.text:SetJustifyH("LEFT")
fmBar.text:SetTextColor(0.91, 0.92, 0.93)

-- 关闭按钮
fmBar.close = ns.Style.CreateFlatButton(fmBar, 20, 20, "X")
fmBar.close:SetPoint("RIGHT", fmBar, "RIGHT", -8, 0)
fmBar.close:SetScript("OnClick", function()
    fmBar:Hide()
    autoShowed = false
end)

fmBar:SetScript("OnDragStart", function(self) self:StartMoving() end)
fmBar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint(1)
    LootStatsDB.barPos = { p = p, x = x, y = y }
end)

-- 千位分隔
local function BarCommaValue(n)
    local s = tostring(math.floor(n))
    local len = #s
    if len <= 3 then return s end
    local out, cnt = "", 0
    for i = len, 1, -1 do
        out = string.sub(s, i, i) .. out
        cnt = cnt + 1
        if cnt % 3 == 0 and i > 1 then out = "," .. out end
    end
    return out
end

-- 刷新横条内容（直接读取现有数据，不改动原逻辑）
local function UpdateFishingBar()
    if not fmBar:IsShown() then return end
    local status = fishingStatusText:GetText() or ""
    if status == "" then status = "记录中" end
    local statusColor = status:find("停止") and "ffffcc00" or "ff58C98A"
    local g = math.floor(totalMoney / 10000)
    local s = math.floor(totalMoney % 10000 / 100)
    local goldStr = BarCommaValue(g) .. " g " .. s .. " s"
    local timeStr = "00:00:00"
    if timerActive and startTime then
        local e = GetTime() - startTime
        timeStr = string.format("%02d:%02d:%02d", math.floor(e / 3600), math.floor((e % 3600) / 60), math.floor(e % 60))
    end
    local fishRank, goldRank, online = "未连接", "未连接", "—"
    if FishingMasterAPI and FishingMasterAPI.IsCommEnabled and FishingMasterAPI.IsCommEnabled() then
        local r1 = FishingMasterAPI.GetSelfRank("fishCount")
        local r2 = FishingMasterAPI.GetSelfRank("gold")
        if r1 and r1.total and r1.total > 0 then fishRank = "#" .. r1.rank .. "/" .. r1.total end
        if r2 and r2.total and r2.total > 0 then goldRank = "#" .. r2.rank .. "/" .. r2.total end
        local cs = FishingMasterAPI.GetChannelStats()
        if cs and cs.online then online = tostring(cs.online) end
    end
    local txt = "|c" .. statusColor .. status .. "|r"
        .. "  |cff9BA1A8收益|r |cffF2C14E" .. goldStr .. "|r"
        .. "  |cff9BA1A8用时|r |cffE8EAED" .. timeStr .. "|r"
        .. "  |cff9BA1A8钓榜|r |cffF2C14E" .. fishRank .. "|r"
        .. "  |cff9BA1A8金榜|r |cff58C98A" .. goldRank .. "|r"
        .. "  |cff9BA1A8在线|r |cff88ccff" .. online .. "|r"
    fmBar.text:SetText(txt)
    local w = fmBar.text:GetStringWidth() + 14 + 30
    fmBar:SetWidth(math.max(w, 260))
end

local function ShowFishingBar()
    fmBar:Show()
    UpdateFishingBar()
end

local function HideFishingBar()
    fmBar:Hide()
end

-- 背景
mainFrame.bg = mainFrame:CreateTexture(nil, "BACKGROUND")
mainFrame.bg:SetAllPoints()
mainFrame.bg:SetColorTexture(0, 0, 0, 0.5)

-- ========================= 标题栏 =========================
local titleBarHeight = 30
local titleBar = CreateFrame("Frame", nil, mainFrame)
titleBar:SetSize(292, titleBarHeight)
titleBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, 0)
titleBar:SetHeight(titleBarHeight)
-- 标题栏可拖拽
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
titleBar:SetScript("OnDragStop", function() mainFrame:StopMovingOrSizing() end)

-- 标题栏背景
local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
titleBg:SetAllPoints()
titleBg:SetColorTexture(0, 0.3, 0.1, 0.8)

-- 标题文字（彩色闪动）
local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
titleText:SetText("钓鱼高手")

-- 彩色闪动动画
local titleColors = {
    {1, 0.84, 0},       -- 金色
    {0, 1, 0},           -- 绿色
    {0, 0.8, 1},         -- 青色
    {1, 0.5, 0},         -- 橙色
    {0.6, 0.8, 1},       -- 淡蓝
}
local titleColorIndex = 1
C_Timer.NewTicker(10, function()
    titleColorIndex = (titleColorIndex % #titleColors) + 1
    local c = titleColors[titleColorIndex]
    titleText:SetTextColor(c[1], c[2], c[3])
end)

local textWidth = 260
local textHeight = 40

-- 收益文本
mainFrame.text = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
mainFrame.text:SetSize(textWidth, textHeight)
mainFrame.text:SetPoint("TOP", mainFrame, "TOP", 0, -titleBarHeight)
mainFrame.text:SetJustifyH("CENTER")
mainFrame.text:SetText("收益: 0 g 0 s")
mainFrame.text:SetTextColor(1, 1, 0)

-- 内联人民币显示
local inlineCNYLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
inlineCNYLabel:SetPoint("TOP", mainFrame.text, "BOTTOM", 0, -2)
inlineCNYLabel:SetJustifyH("CENTER")
inlineCNYLabel:SetText("≈ 0.00 元")
inlineCNYLabel:SetTextColor(0, 1, 0)

-- 计时器文本
local timerText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
timerText:SetSize(textWidth, textHeight)
timerText:SetPoint("TOP", mainFrame, "TOP", 0, -45 - titleBarHeight)
timerText:SetJustifyH("CENTER")
timerText:SetText("用时: 00:00:00")
timerText:SetFont("Fonts\\FRIZQT__.TTF", 14)
timerText:SetTextColor(1, 1, 0)

-- 单行按钮：重 | 区 | 收 | 互 | 拾 | 开
local btnW, btnH, btnGap = 28, 28, 3

local resetCurrentButton = ns.Style.CreateFlatButton(mainFrame, btnW, btnH, "重")
resetCurrentButton:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 10, 8)
resetCurrentButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("重置当前收益和计时", 1, 1, 1); GameTooltip:Show() end)
resetCurrentButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local statsButton = ns.Style.CreateFlatButton(mainFrame, btnW, btnH, "区")
statsButton:SetPoint("LEFT", resetCurrentButton, "RIGHT", btnGap, 0)
statsButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("区域物品拾取统计", 1, 1, 1); GameTooltip:Show() end)
statsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local incomeStatsButton = ns.Style.CreateFlatButton(mainFrame, btnW, btnH, "收")
incomeStatsButton:SetPoint("LEFT", statsButton, "RIGHT", btnGap, 0)
incomeStatsButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("每日/累计收益统计", 1, 1, 1); GameTooltip:Show() end)
incomeStatsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local rangeAlertButton = ns.Style.CreateFlatButton(mainFrame, btnW, btnH, "互")
rangeAlertButton:SetPoint("LEFT", incomeStatsButton, "RIGHT", btnGap, 0)
rangeAlertButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("互动范围提醒开关", 1, 1, 1); GameTooltip:Show() end)
rangeAlertButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local quickLootButton = ns.Style.CreateFlatButton(mainFrame, btnW, btnH, "拾")
quickLootButton:SetPoint("LEFT", rangeAlertButton, "RIGHT", btnGap, 0)
quickLootButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("快速拾取开关", 1, 1, 1); GameTooltip:Show() end)
quickLootButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local helpButton = ns.Style.CreateFlatButton(mainFrame, btnW, btnH, "帮")
helpButton:SetPoint("LEFT", quickLootButton, "RIGHT", btnGap, 0)
helpButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("显示帮助信息", 1, 1, 1); GameTooltip:Show() end)
helpButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local startPauseButton = ns.Style.CreateFlatButton(mainFrame, btnW, btnH, "开")
startPauseButton:SetPoint("LEFT", helpButton, "RIGHT", btnGap, 0)
startPauseButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("开始/暂停计时", 1, 1, 1); GameTooltip:Show() end)
startPauseButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- 采集上马按钮
local mountButton = ns.Style.CreateFlatButton(mainFrame, btnW, btnH, "坐")
mountButton:SetPoint("LEFT", startPauseButton, "RIGHT", btnGap, 0)
mountButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("采集上马设置", 1, 1, 1); GameTooltip:Show() end)
mountButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
mountButton:SetScript("OnClick", function()
    if ns.SmartMount then
        ns.SmartMount.OpenOptions()
    end
end)

-- 角色切换音效按钮
local charSwitchButton = ns.Style.CreateFlatButton(mainFrame, btnW, btnH, "切")
charSwitchButton:SetPoint("LEFT", mountButton, "RIGHT", btnGap, 0)
charSwitchButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("角色切换音效开关", 1, 1, 1); GameTooltip:Show() end)
charSwitchButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- 渔友圈按钮
local netButton = ns.Style.CreateFlatButton(mainFrame, btnW, btnH, "网")
netButton:SetPoint("LEFT", charSwitchButton, "RIGHT", btnGap, 0)
netButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("渔友圈（同服在线玩家共享）", 1, 1, 1); GameTooltip:Show() end)
netButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
netButton:SetScript("OnClick", function()
    if ns.MainUI then
        ns.MainUI.Toggle()
        if ns.MainUI.frame:IsShown() then
            netButton:SetText("|cff00ff00网|r")
        else
            netButton:SetText("|cffFF0000网|r")
        end
    end
    if rateEdit then rateEdit:ClearFocus() end
end)

-- 钓鱼状态指示
fishingStatusText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fishingStatusText:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 42)
fishingStatusText:SetJustifyH("CENTER")
fishingStatusText:SetText("")
fishingStatusText:SetTextColor(0, 0.8, 1)

-- ========================= 汇率设置区域 =========================
local rateLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
rateLabel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -90 - titleBarHeight)
rateLabel:SetText("10000金 =")
rateLabel:SetTextColor(1, 1, 0)

local rateEdit = CreateFrame("EditBox", nil, mainFrame, "InputBoxTemplate")
rateEdit:SetSize(80, 25)
rateEdit:SetPoint("LEFT", rateLabel, "RIGHT", 5, 0)
rateEdit:SetText("0")
rateEdit:SetAutoFocus(false)
rateEdit:SetTextColor(1, 1, 1)
-- 按 Enter 或 Escape 时清除焦点
rateEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
rateEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
-- 点击外部失焦：获得焦点时创建全屏拦截帧，点击任意位置即失焦
local focusCatcher = nil
rateEdit:SetScript("OnEditFocusGained", function(self)
    if not focusCatcher then
        focusCatcher = CreateFrame("Button", nil, UIParent)
        focusCatcher:SetAllPoints(UIParent)
        focusCatcher:SetFrameStrata("TOOLTIP")
        focusCatcher:Hide()
        focusCatcher:SetScript("OnClick", function()
            self:ClearFocus()
        end)
    end
    focusCatcher:Show()
end)
rateEdit:SetScript("OnEditFocusLost", function(self)
    if focusCatcher then focusCatcher:Hide() end
end)

local unitLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
unitLabel:SetPoint("LEFT", rateEdit, "RIGHT", 5, 0)
unitLabel:SetText("元")
unitLabel:SetTextColor(1, 1, 0)

-- 合计人民币
local totalCNYLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
totalCNYLabel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -120 - titleBarHeight)
totalCNYLabel:SetText("合计: 0.00 元")
totalCNYLabel:SetTextColor(0, 1, 0)

-- 时薪
local hourlyCNYLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
hourlyCNYLabel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -145 - titleBarHeight)
hourlyCNYLabel:SetText("时薪: 0.00 元/小时")
hourlyCNYLabel:SetTextColor(0, 1, 0)

-- 最近3次拾取记录
local lootLogLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lootLogLabel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -170 - titleBarHeight)
lootLogLabel:SetWidth(240)
lootLogLabel:SetJustifyH("LEFT")
lootLogLabel:SetText("最近拾取：\n")
lootLogLabel:SetTextColor(0.8, 0.8, 1)

-- ========================= 核心变量 =========================
totalMoney = 0
startTime = nil
local pauseTime = nil
timerActive = false
timerPaused = false
timerTicker = nil
recentLoots = {}
lastLootTime = 0
isFishing = false
fishingCooldownTimer = nil
fishingCountdownTicker = nil
local autoShowed = false

-- ========================= 互动范围提醒（复刻FishingRangeAlert） =========================
local rangeAlertCasting = false
local rangeAlertInteractable = false
local rangeAlertTimer = nil
local RANGE_ALERT_DELAY = 1.1
local RANGE_ALERT_SOUND_FAIL = "Interface\\Addons\\FishingMaster\\Sounds\\Glass.mp3"

-- 范围提示防重复标记
local hasShownSuccess = false
local hasShownFail = false

-- ========================= 辅助函数 =========================
local function GetRate()
    local rate = tonumber(rateEdit:GetText())
    return rate and rate > 0 and rate or 0
end

local function ParseTotalMoney()
    local text = mainFrame.text:GetText()
    local gold, silver = text:match("收益: (%d+) g (%d+) s")
    if gold and silver then
        return tonumber(gold) * 10000 + tonumber(silver) * 100
    end
    return 0
end

local function ParseElapsedSeconds()
    local text = timerText:GetText()
    local h, m, s = text:match("用时: (%d+):(%d+):(%d+)")
    if h and m and s then
        return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
    end
    return 0
end

local function UpdateGold()
    local gold = math.floor(totalMoney / 10000)
    local silver = math.floor(totalMoney % 10000 / 100)
    mainFrame.text:SetText(string.format("收益: %d g %d s", gold, silver))
end

local function UpdateTime()
    if timerActive then
        local currentTime = GetTime()
        local elapsedTime = currentTime - startTime
        local hours = math.floor(elapsedTime / 3600)
        local minutes = math.floor((elapsedTime % 3600) / 60)
        local seconds = math.floor(elapsedTime % 60)
        timerText:SetText(string.format("用时: %02d:%02d:%02d", hours, minutes, seconds))
    end
end

local function UpdateCNYDisplay()
    local totalCopper = ParseTotalMoney()
    local rate = GetRate()
    if rate > 0 then
        local totalCNY = totalCopper * rate / 100000000
        totalCNYLabel:SetText(string.format("合计: %.2f 元", totalCNY))
        inlineCNYLabel:SetText(string.format("≈ %.2f 元", totalCNY))
        local elapsedSec = ParseElapsedSeconds()
        if elapsedSec > 0 then
            local hourly = totalCNY / (elapsedSec / 3600)
            hourlyCNYLabel:SetText(string.format("时薪: %.2f 元/小时", hourly))
        else
            hourlyCNYLabel:SetText("时薪: 0.00 元/小时")
        end
    else
        totalCNYLabel:SetText("合计: 0.00 元")
        inlineCNYLabel:SetText("≈ 0.00 元")
        hourlyCNYLabel:SetText("时薪: 0.00 元/小时")
    end
end

local function TruncateString(str, maxLen)
    if #str > maxLen then
        return str:sub(1, maxLen-3) .. "..."
    end
    return str
end

local function UpdateLootLogDisplay()
    if #recentLoots == 0 then
        lootLogLabel:SetText("最近拾取：\n无")
        return
    end
    local lines = {}
    for i, entry in ipairs(recentLoots) do
        local itemsStr = entry.itemsDisplay
        local cnyStr = string.format("%.4f", entry.totalCNY)
        local coordStr = entry.coord and entry.coord ~= "" and (" " .. entry.coord) or ""
        table.insert(lines, string.format("%d. %s%s: %s 元", i, itemsStr, coordStr, cnyStr))
    end
    local text = "最近拾取：\n" .. table.concat(lines, "\n")
    lootLogLabel:SetText(text)
end

-- ========================= 区域名称 =========================
local function GetCurrentZone()
    local zone = GetRealZoneText() or ""
    local subZone = GetSubZoneText() or ""
    local minimapZone = GetMinimapZoneText() or ""
    local parts = {}
    if zone ~= "" then table.insert(parts, zone) end
    if subZone ~= "" and subZone ~= zone then table.insert(parts, subZone) end
    if minimapZone ~= "" and minimapZone ~= zone and minimapZone ~= subZone then
        table.insert(parts, minimapZone)
    end
    if #parts == 0 then return "未知区域" end
    return table.concat(parts, " - ")
end

local function GetCurrentCoords()
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            local pos = C_Map.GetPlayerMapPosition(mapID, "player")
            if pos then
                local x, y = pos.x or 0, pos.y or 0
                if x > 0 or y > 0 then
                    return string.format("(%.1f, %.1f)", x * 100, y * 100)
                end
            end
        end
    end
    return ""
end

-- ========================= 每日/累计统计 =========================
local function GetCurrentDate()
    return date("%Y-%m-%d")
end

local function UpdateDailyAndTotalStats(copperGain, pickupCount)
    if not LootStatsDB.dailyStats then LootStatsDB.dailyStats = {} end
    if not LootStatsDB.totalStats then LootStatsDB.totalStats = { totalCopper = 0, totalPickups = 0 } end
    local today = GetCurrentDate()
    if not LootStatsDB.dailyStats[today] then
        LootStatsDB.dailyStats[today] = { totalCopper = 0, totalPickups = 0 }
    end
    LootStatsDB.dailyStats[today].totalCopper = LootStatsDB.dailyStats[today].totalCopper + copperGain
    LootStatsDB.dailyStats[today].totalPickups = LootStatsDB.dailyStats[today].totalPickups + pickupCount
    LootStatsDB.totalStats.totalCopper = LootStatsDB.totalStats.totalCopper + copperGain
    LootStatsDB.totalStats.totalPickups = LootStatsDB.totalStats.totalPickups + pickupCount
end

-- ========================= 收益统计窗口 =========================
local incomeStatsFrame = nil
local function UpdateIncomeStatsDisplay()
    if not incomeStatsFrame then return end
    local contentText = incomeStatsFrame.contentText
    if not contentText then return end
    if not LootStatsDB.dailyStats then LootStatsDB.dailyStats = {} end
    if not LootStatsDB.totalStats then LootStatsDB.totalStats = { totalCopper = 0, totalPickups = 0 } end
    local rate = GetRate()
    local today = GetCurrentDate()
    local daily = LootStatsDB.dailyStats[today] or { totalCopper = 0, totalPickups = 0 }
    local total = LootStatsDB.totalStats
    local function CopperToGoldSilver(copper)
        return math.floor(copper / 10000), math.floor((copper % 10000) / 100)
    end
    local dailyGold, dailySilver = CopperToGoldSilver(daily.totalCopper)
    local totalGold, totalSilver = CopperToGoldSilver(total.totalCopper)
    local lines = {}
    table.insert(lines, "|cffffcc00======== 每日收益 ========|r")
    table.insert(lines, string.format("日期: %s", today))
    table.insert(lines, string.format("拾取总数: %d", daily.totalPickups))
    table.insert(lines, string.format("金币: %d g %d s", dailyGold, dailySilver))
    table.insert(lines, rate > 0 and string.format("人民币: %.2f 元", daily.totalCopper * rate / 100000000) or "人民币: 未设置汇率")
    table.insert(lines, "")
    table.insert(lines, "|cffffcc00======== 累计收益 ========|r")
    table.insert(lines, string.format("总拾取数: %d", total.totalPickups))
    table.insert(lines, string.format("总金币: %d g %d s", totalGold, totalSilver))
    table.insert(lines, rate > 0 and string.format("总人民币: %.2f 元", total.totalCopper * rate / 100000000) or "总人民币: 未设置汇率")
    contentText:SetText(table.concat(lines, "\n"))
    if incomeStatsFrame.scrollChild then
        incomeStatsFrame.scrollChild:SetHeight(contentText:GetStringHeight() + 10)
    end
end

local function CreateIncomeStatsWindow()
    if incomeStatsFrame then return end
    incomeStatsFrame = CreateFrame("Frame", "LootIncomeStatsWindow", UIParent)
    incomeStatsFrame:SetSize(400, 500)
    incomeStatsFrame:SetPoint("CENTER", UIParent, "CENTER")
    incomeStatsFrame:SetMovable(true)
    incomeStatsFrame:EnableMouse(true)
    incomeStatsFrame:RegisterForDrag("LeftButton")
    incomeStatsFrame:SetScript("OnDragStart", function(s) s:StartMoving() end)
    incomeStatsFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    incomeStatsFrame.bg = incomeStatsFrame:CreateTexture(nil, "BACKGROUND")
    incomeStatsFrame.bg:SetAllPoints()
    incomeStatsFrame.bg:SetColorTexture(0, 0, 0, 0.8)
    local title = incomeStatsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", incomeStatsFrame, "TOP", 0, -10)
    title:SetText("收益统计")
    local closeBtn = ns.Style.CreateFlatButton(incomeStatsFrame, 50, 25, "关闭")
    closeBtn:SetPoint("BOTTOMRIGHT", incomeStatsFrame, "BOTTOMRIGHT", -10, 10)
    closeBtn:SetScript("OnClick", function() incomeStatsFrame:Hide() end)
    local resetStatsBtn = ns.Style.CreateFlatButton(incomeStatsFrame, 80, 25, "重置累计")
    resetStatsBtn:SetPoint("BOTTOMLEFT", incomeStatsFrame, "BOTTOMLEFT", 10, 10)
    resetStatsBtn:SetScript("OnClick", function()
        LootStatsDB.totalStats = { totalCopper = 0, totalPickups = 0 }
        UpdateIncomeStatsDisplay()
    end)
    local scrollFrame = CreateFrame("ScrollFrame", nil, incomeStatsFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", incomeStatsFrame, "TOPLEFT", 10, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", incomeStatsFrame, "BOTTOMRIGHT", -10, 50)
    scrollFrame:SetScrollChild(CreateFrame("Frame", "IncomeStatsScrollChild"))
    local scrollChild = scrollFrame:GetScrollChild()
    scrollChild:SetSize(380, 10)
    incomeStatsFrame.scrollChild = scrollChild
    local contentText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contentText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    contentText:SetWidth(360)
    contentText:SetJustifyH("LEFT")
    incomeStatsFrame.contentText = contentText
    incomeStatsFrame:HookScript("OnShow", UpdateIncomeStatsDisplay)
end

-- ========================= 区域统计窗口 =========================
local zoneStatsFrame = nil
local function UpdateZoneStatsDisplay()
    if not zoneStatsFrame then return end
    local scrollChild = zoneStatsFrame.scrollChild
    if not scrollChild then return end
    local contentText = scrollChild.contentText
    if not contentText then return end
    local lines = {}
    if not LootStatsDB.zones or next(LootStatsDB.zones) == nil then
        lines = {"暂无数据"}
    else
        for zone, items in pairs(LootStatsDB.zones) do
            table.insert(lines, "|cffffcc00" .. zone .. "|r")
            local zoneTotal = LootStatsDB.zoneTotals[zone] or 0
            local zoneCopper = 0
            if LootStatsDB.zoneItemCopper and LootStatsDB.zoneItemCopper[zone] then
                for _, v in pairs(LootStatsDB.zoneItemCopper[zone]) do
                    zoneCopper = zoneCopper + v
                end
            end
            local zGold = math.floor(zoneCopper / 10000)
            local zSilver = math.floor((zoneCopper % 10000) / 100)
            table.insert(lines, string.format("  总计: %d件 - %d g %d s", zoneTotal, zGold, zSilver))
            local sorted = {}
            for item, qty in pairs(items) do
                local copperValue = 0
                if LootStatsDB.zoneItemCopper and LootStatsDB.zoneItemCopper[zone] then
                    copperValue = LootStatsDB.zoneItemCopper[zone][item] or 0
                end
                table.insert(sorted, {name = item, qty = qty, copper = copperValue})
            end
            table.sort(sorted, function(a, b) return a.qty > b.qty end)
            for _, entry in ipairs(sorted) do
                local pct = (zoneTotal > 0) and (entry.qty / zoneTotal * 100) or 0
                local goldVal = math.floor(entry.copper / 10000)
                local silverVal = math.floor((entry.copper % 10000) / 100)
                local coord = ""
                if LootStatsDB.zoneItemCoords and LootStatsDB.zoneItemCoords[zone] then
                    coord = LootStatsDB.zoneItemCoords[zone][entry.name] or ""
                end
                local coordStr = coord ~= "" and (" |cff888888" .. coord .. "|r") or ""
                table.insert(lines, string.format("  %s: %d (%.1f%%) - %d g %d s%s",
                    entry.name, entry.qty, pct, goldVal, silverVal, coordStr))
            end
            table.insert(lines, "")
        end
    end
    contentText:SetText(table.concat(lines, "\n"))
    scrollChild:SetHeight(contentText:GetStringHeight() + 10)
end

local function CreateZoneStatsWindow()
    if zoneStatsFrame then return end
    zoneStatsFrame = CreateFrame("Frame", "LootZoneStatsWindow", UIParent)
    zoneStatsFrame:SetSize(400, 500)
    zoneStatsFrame:SetPoint("CENTER", UIParent, "CENTER")
    zoneStatsFrame:SetMovable(true)
    zoneStatsFrame:EnableMouse(true)
    zoneStatsFrame:RegisterForDrag("LeftButton")
    zoneStatsFrame:SetScript("OnDragStart", function(s) s:StartMoving() end)
    zoneStatsFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    zoneStatsFrame.bg = zoneStatsFrame:CreateTexture(nil, "BACKGROUND")
    zoneStatsFrame.bg:SetAllPoints()
    zoneStatsFrame.bg:SetColorTexture(0, 0, 0, 0.8)
    local title = zoneStatsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", zoneStatsFrame, "TOP", 0, -10)
    title:SetText("区域物品拾取统计")
    local closeBtn = ns.Style.CreateFlatButton(zoneStatsFrame, 50, 25, "关闭")
    closeBtn:SetPoint("BOTTOMRIGHT", zoneStatsFrame, "BOTTOMRIGHT", -10, 10)
    closeBtn:SetScript("OnClick", function() zoneStatsFrame:Hide() end)
    local resetStatsBtn = ns.Style.CreateFlatButton(zoneStatsFrame, 80, 25, "重置统计")
    resetStatsBtn:SetPoint("BOTTOMLEFT", zoneStatsFrame, "BOTTOMLEFT", 10, 10)
    resetStatsBtn:SetScript("OnClick", function()
        LootStatsDB.zones = {}
        LootStatsDB.zoneTotals = {}
        LootStatsDB.zoneItemCopper = {}
        LootStatsDB.zoneItemCoords = {}
        UpdateZoneStatsDisplay()
    end)
    local scrollFrame = CreateFrame("ScrollFrame", nil, zoneStatsFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", zoneStatsFrame, "TOPLEFT", 10, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", zoneStatsFrame, "BOTTOMRIGHT", -10, 50)
    scrollFrame:SetScrollChild(CreateFrame("Frame", "ZoneStatsScrollChild"))
    local scrollChild = scrollFrame:GetScrollChild()
    scrollChild:SetSize(380, 10)
    zoneStatsFrame.scrollChild = scrollChild
    local contentText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contentText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    contentText:SetWidth(360)
    contentText:SetJustifyH("LEFT")
    scrollChild.contentText = contentText
    zoneStatsFrame:HookScript("OnShow", UpdateZoneStatsDisplay)
end

-- ========================= 计时器控制 =========================
local function ToggleTimer()
    if timerActive then
        if timerPaused then
            timerPaused = false
            startPauseButton:SetText("暂")
            timerTicker = C_Timer.NewTicker(1, UpdateTime)
            startTime = startTime + (GetTime() - pauseTime)
        else
            timerPaused = true
            startPauseButton:SetText("继")
            if timerTicker then timerTicker:Cancel(); timerTicker = nil end
            pauseTime = GetTime()
        end
    else
        timerActive = true
        startTime = GetTime()
        timerPaused = false
        startPauseButton:SetText("暂")
        timerTicker = C_Timer.NewTicker(1, UpdateTime)
    end
end

local function ResetCurrent()
    totalMoney = 0
    startTime = nil
    pauseTime = nil
    timerActive = false
    timerPaused = false
    if timerTicker then timerTicker:Cancel(); timerTicker = nil end
    startPauseButton:SetText("开始")
    timerText:SetText("用时: 00:00:00")
    recentLoots = {}
    UpdateGold()
    UpdateLootLogDisplay()
    UpdateCNYDisplay()
    if zoneStatsFrame and zoneStatsFrame:IsShown() then UpdateZoneStatsDisplay() end
end

-- ========================= 事件处理 =========================
local function OnLootReady()
    if GetTime() - lastLootTime < 0.5 then return end
    lastLootTime = GetTime()

    local numberOfItems = GetNumLootItems()
    if numberOfItems == 0 then return end

    local totalValue = 0
    local callerID = "EarnOnGathering"
    local currentZone = GetCurrentZone()
    local currentCoord = GetCurrentCoords()
    local itemsInThisLoot = {}
    local itemCopperMap = {}
    local totalQuantityThisLoot = 0
    local totalCopperForLog = 0

    for i = 1, numberOfItems do
        local itemLink = GetLootSlotLink(i)
        if itemLink then
            local _, itemName, itemQuantity = GetLootSlotInfo(i)
            if itemName and itemQuantity and itemQuantity > 0 then
                if not itemsInThisLoot[itemName] then itemsInThisLoot[itemName] = 0 end
                itemsInThisLoot[itemName] = itemsInThisLoot[itemName] + itemQuantity
                totalQuantityThisLoot = totalQuantityThisLoot + itemQuantity

                local price = nil
                if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink then
                    price = Auctionator.API.v1.GetAuctionPriceByItemLink(callerID, itemLink)
                end
                if not price and EasyAuction_GetPriceHistoryMinUnit then
                    local itemID = strmatch(itemLink, "item:(%d+)")
                    if itemID and itemName then
                        price = EasyAuction_GetPriceHistoryMinUnit(itemName .. ":" .. itemID)
                    end
                end
                local copper = 0
                if price then
                    copper = price * itemQuantity
                    totalValue = totalValue + copper
                    totalCopperForLog = totalCopperForLog + copper
                end
                itemCopperMap[itemName] = (itemCopperMap[itemName] or 0) + copper
            end
        end
    end

    totalMoney = totalMoney + totalValue
    UpdateGold()

    -- 更新区域统计
    if currentZone and currentZone ~= "" and next(itemsInThisLoot) then
        if not LootStatsDB.zones[currentZone] then LootStatsDB.zones[currentZone] = {} end
        if not LootStatsDB.zoneTotals[currentZone] then LootStatsDB.zoneTotals[currentZone] = 0 end
        if not LootStatsDB.zoneItemCopper then LootStatsDB.zoneItemCopper = {} end
        if not LootStatsDB.zoneItemCopper[currentZone] then LootStatsDB.zoneItemCopper[currentZone] = {} end
        local zoneData = LootStatsDB.zones[currentZone]
        local zoneTotal = LootStatsDB.zoneTotals[currentZone]
        local zoneCopper = LootStatsDB.zoneItemCopper[currentZone]
        for itemName, quantity in pairs(itemsInThisLoot) do
            if not zoneData[itemName] then zoneData[itemName] = 0 end
            zoneData[itemName] = zoneData[itemName] + quantity
            zoneTotal = zoneTotal + quantity
            local copperGain = itemCopperMap[itemName] or 0
            if not zoneCopper[itemName] then zoneCopper[itemName] = 0 end
            zoneCopper[itemName] = zoneCopper[itemName] + copperGain
        end
        LootStatsDB.zoneTotals[currentZone] = zoneTotal
        if currentCoord ~= "" then
            if not LootStatsDB.zoneItemCoords[currentZone] then LootStatsDB.zoneItemCoords[currentZone] = {} end
            for itemName in pairs(itemsInThisLoot) do
                LootStatsDB.zoneItemCoords[currentZone][itemName] = currentCoord
            end
        end
    end

    -- 更新每日和累计统计
    if totalValue > 0 or totalQuantityThisLoot > 0 then
        UpdateDailyAndTotalStats(totalValue, totalQuantityThisLoot)
    end

    -- 最近拾取显示
    if next(itemsInThisLoot) then
        local itemsDisplayList = {}
        for itemName, quantity in pairs(itemsInThisLoot) do
            table.insert(itemsDisplayList, string.format("%s x%d", itemName, quantity))
        end
        table.sort(itemsDisplayList)
        local rate = GetRate()
        table.insert(recentLoots, 1, {
            itemsDisplay = table.concat(itemsDisplayList, ", "),
            totalCNY = totalCopperForLog * rate / 100000000,
            coord = currentCoord
        })
        while #recentLoots > 3 do table.remove(recentLoots) end
        UpdateLootLogDisplay()
    end

    -- 刷新打开的窗口
    if zoneStatsFrame and zoneStatsFrame:IsShown() then UpdateZoneStatsDisplay() end
    if incomeStatsFrame and incomeStatsFrame:IsShown() then UpdateIncomeStatsDisplay() end
    UpdateCNYDisplay()

    -- 渔友圈：通知通信层本次拾取（用于鱼价手册自我贡献）
    if FishingMasterComm then FishingMasterComm:NotifyLoot(itemsInThisLoot, totalCopperForLog) end
end

-- ========================= 按钮状态更新函数 =========================
-- 必须在事件注册前定义，因为 ADDON_LOADED 中会调用
local function UpdateRangeAlertButton()
    if LootStatsDB and LootStatsDB.rangeAlertEnabled then
        rangeAlertButton:SetText("|cff00ff00互|r")
    else
        rangeAlertButton:SetText("|cffFF0000互|r")
    end
end

local function UpdateQuickLootButton()
    if LootStatsDB and LootStatsDB.quickLootEnabled then
        quickLootButton:SetText("|cff00ff00拾|r")
    else
        quickLootButton:SetText("|cffFF0000拾|r")
    end
end

local function UpdateCharSwitchButton()
    if LootStatsDB and LootStatsDB.charSwitchEnabled then
        charSwitchButton:SetText("|cff00ff00切|r")
    else
        charSwitchButton:SetText("|cffFF0000切|r")
    end
end

-- ========================= 角色切换音效 =========================
local LOGOUT_SOUND_PATH = "Interface\\AddOns\\FishingMaster\\Sounds\\11.wav"
local ENTER_WORLD_SOUND_PATH = "Interface\\AddOns\\FishingMaster\\Sounds\\22.ogg"

local function PlayCharSwitchLogoutSound()
    if LootStatsDB and LootStatsDB.charSwitchEnabled then
        PlaySoundFile(LOGOUT_SOUND_PATH, "Master")
    end
end

-- 挂钩登出命令
hooksecurefunc("Logout", PlayCharSwitchLogoutSound)
if Camp then hooksecurefunc("Camp", PlayCharSwitchLogoutSound) end

-- ========================= 注册事件 =========================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("LOOT_READY")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
eventFrame:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= addonName then return end
        -- SavedVariables 此时已从磁盘加载完毕，在此初始化默认值
        if not LootStatsDB then LootStatsDB = {} end
        if not LootStatsDB.zones then LootStatsDB.zones = {} end
        if not LootStatsDB.zoneTotals then LootStatsDB.zoneTotals = {} end
        if not LootStatsDB.zoneItemCopper then LootStatsDB.zoneItemCopper = {} end
        if not LootStatsDB.dailyStats then LootStatsDB.dailyStats = {} end
        if not LootStatsDB.totalStats then LootStatsDB.totalStats = { totalCopper = 0, totalPickups = 0 } end
        if not LootStatsDB.zoneItemCoords then LootStatsDB.zoneItemCoords = {} end
        if LootStatsDB.rangeAlertEnabled == nil then LootStatsDB.rangeAlertEnabled = false end
        if LootStatsDB.quickLootEnabled == nil then LootStatsDB.quickLootEnabled = true end
        if LootStatsDB.charSwitchEnabled == nil then LootStatsDB.charSwitchEnabled = true end
        -- 恢复汇率到输入框
        if LootStatsDB.rate then
            rateEdit:SetText(tostring(LootStatsDB.rate))
        end
        -- 设置 UIErrorsFrame 字体大小用于范围提示
        UIErrorsFrame:SetFont("Fonts\\FRIZQT__.TTF", 30, "")
        -- 根据 SavedVariables 更新按钮状态
        UpdateRangeAlertButton()
        UpdateQuickLootButton()
        UpdateCharSwitchButton()
        -- 初始化SmartMount子模块
        if ns.SmartMount then
            ns.SmartMount.Init()
        end
        -- 恢复钓鱼横条位置（默认顶部居中）
        fmBar:ClearAllPoints()
        if LootStatsDB.barPos and LootStatsDB.barPos.p then
            fmBar:SetPoint(LootStatsDB.barPos.p, UIParent, LootStatsDB.barPos.p, LootStatsDB.barPos.x, LootStatsDB.barPos.y)
        else
            fmBar:SetPoint("TOP", UIParent, "TOP", 0, -16)
        end
        -- 恢复小地图按钮位置
        if LootStatsDB.minimapAngle then
            SetMinimapButtonAngle(LootStatsDB.minimapAngle)
        end
        -- 欢迎信息
        print("|cff00ff00~~~~~~~~~~~~~~~~~~~~~~~|r")
        print("|cff00ff00欢迎使用|cffffcc00钓鱼高手|cff00ff00插件包。|r")
        print("|cff00ff00进阶钓鱼插件请加群。|r")
        print("|cff00ff00钓鱼交流群①：|cffffcc001043976142|r")
        print("|cff00ff00钓鱼交流群②：|cffffcc001041294189|r")
        print("|cff00ff00~~~~~~~~~~~~~~~~~~~~~~~|r")

        -- 渔友圈：初始化通信层（传入 SavedVariables）
        if FishingMasterComm then FishingMasterComm:Initialize(LootStatsDB) end

        -- 载入确认（调试用）
        local commOK = FishingMasterComm and FishingMasterComm.Initialize
            and FishingMasterComm.Protocol and FishingMasterComm.PeerRegistry
            and FishingMasterComm.StatsSync and _G.FishingMasterAPI
        print("|cff00ff00[钓鱼高手]|r 已载入 |cffffcc00v1.0|r"
            .. (commOK and " |cff00ff00(渔友圈模块就绪)|r" or " |cffff0000(渔友圈模块缺失!)|r"))
        return
    end

    if event == "LOOT_READY" then
        OnLootReady()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if LootStatsDB and LootStatsDB.charSwitchEnabled then
            PlaySoundFile(ENTER_WORLD_SOUND_PATH, "Master")
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, _, _, spellID = ...
        if unit == "player" and spellID and FishingSpellIDs[spellID] then
            isFishing = true
            if fishingCooldownTimer then fishingCooldownTimer = nil end
            if fishingCountdownTicker then fishingCountdownTicker:Cancel(); fishingCountdownTicker = nil end
            if not timerActive or timerPaused then ToggleTimer() end
            fishingStatusText:SetText("钓鱼中...")
            if not fmBar:IsShown() then
                ShowFishingBar()
                autoShowed = true
            else
                UpdateFishingBar()
            end
            -- 互动范围提醒：重置状态
            if LootStatsDB.rangeAlertEnabled then
                rangeAlertCasting = false
                rangeAlertInteractable = false
                hasShownSuccess = false
                hasShownFail = false
                if rangeAlertTimer then rangeAlertTimer:Cancel(); rangeAlertTimer = nil end
            end
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit = ...
        if unit == "player" and LootStatsDB.rangeAlertEnabled then
            rangeAlertCasting = true
            rangeAlertInteractable = false
            if rangeAlertTimer then rangeAlertTimer:Cancel() end
            rangeAlertTimer = C_Timer.NewTimer(RANGE_ALERT_DELAY, function()
                if not rangeAlertInteractable then
                    PlaySoundFile(RANGE_ALERT_SOUND_FAIL, "Master")
                    if not hasShownFail then
                        UIErrorsFrame:AddMessage("无效互动范围", 1, 0, 0, 1)
                        hasShownFail = true
                    end
                end
                if rangeAlertTimer then rangeAlertTimer:Cancel(); rangeAlertTimer = nil end
            end)
        end
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        if LootStatsDB.rangeAlertEnabled and rangeAlertCasting then
            local targetName = UnitName("softinteract")
            if targetName then
                rangeAlertInteractable = true
                if not hasShownSuccess then
                    UIErrorsFrame:AddMessage("有效互动范围", 0, 1, 0, 1)
                    hasShownSuccess = true
                end
                if rangeAlertTimer then rangeAlertTimer:Cancel(); rangeAlertTimer = nil end
            else
                rangeAlertInteractable = false
            end
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit = ...
        if unit == "player" and isFishing then
            -- 重置互动范围状态
            rangeAlertCasting = false
            rangeAlertInteractable = false
            if rangeAlertTimer then rangeAlertTimer:Cancel(); rangeAlertTimer = nil end

            if fishingCooldownTimer then fishingCooldownTimer = nil end
            if fishingCountdownTicker then fishingCountdownTicker:Cancel() end
            local cooldownLeft = 30
            fishingStatusText:SetText("即将停止记录 " .. cooldownLeft .. "s")
            fishingCountdownTicker = C_Timer.NewTicker(1, function()
                cooldownLeft = cooldownLeft - 1
                if cooldownLeft <= 0 then
                    fishingCountdownTicker:Cancel()
                    fishingCountdownTicker = nil
                    isFishing = false
                    fishingCooldownTimer = nil
                    fishingStatusText:SetText("")
                    if timerActive and not timerPaused then
                        ToggleTimer()
                    end
                    if autoShowed then
                        HideFishingBar()
                        autoShowed = false
                    end
                else
                    fishingStatusText:SetText("即将停止记录 " .. cooldownLeft .. "s")
                end
            end)
        end
    end
end)

-- ========================= 按钮回调 =========================
resetCurrentButton:SetScript("OnClick", function()
    ResetCurrent()
    if rateEdit then rateEdit:ClearFocus() end
end)

startPauseButton:SetScript("OnClick", function()
    ToggleTimer()
    if rateEdit then rateEdit:ClearFocus() end
end)

helpButton:SetScript("OnClick", function()
    print("|cff00ff00~~~~~~~~~~~~~~~~~~~~~~~|r")
    print("|cff00ff00欢迎使用|cffffcc00钓鱼高手|cff00ff00插件包。|r")
    print("|cff00ff00进阶钓鱼插件请加群。|r")
    print("|cff00ff00钓鱼交流群①：|cffffcc001043976142|r")
    print("|cff00ff00钓鱼交流群②：|cffffcc001041294189|r")
    print("|cff00ff00~~~~~~~~~~~~~~~~~~~~~~~|r")
    if rateEdit then rateEdit:ClearFocus() end
end)

statsButton:SetScript("OnClick", function()
    if not zoneStatsFrame then CreateZoneStatsWindow() end
    if zoneStatsFrame:IsShown() then zoneStatsFrame:Hide() else UpdateZoneStatsDisplay(); zoneStatsFrame:Show() end
    if rateEdit then rateEdit:ClearFocus() end
end)

incomeStatsButton:SetScript("OnClick", function()
    if not incomeStatsFrame then CreateIncomeStatsWindow() end
    if incomeStatsFrame:IsShown() then incomeStatsFrame:Hide() else UpdateIncomeStatsDisplay(); incomeStatsFrame:Show() end
    if rateEdit then rateEdit:ClearFocus() end
end)

quickLootButton:SetScript("OnClick", function()
    if ns.QuickLoot then
        ns.QuickLoot:Toggle()
    end
    UpdateQuickLootButton()
    if rateEdit then rateEdit:ClearFocus() end
end)

rangeAlertButton:SetScript("OnClick", function()
    LootStatsDB.rangeAlertEnabled = not LootStatsDB.rangeAlertEnabled
    UpdateRangeAlertButton()
    if rateEdit then rateEdit:ClearFocus() end

    if not LootStatsDB.rangeAlertEnabled then
        rangeAlertCasting = false
        rangeAlertInteractable = false
        if rangeAlertTimer then rangeAlertTimer:Cancel(); rangeAlertTimer = nil end
    end
end)

charSwitchButton:SetScript("OnClick", function()
    LootStatsDB.charSwitchEnabled = not LootStatsDB.charSwitchEnabled
    UpdateCharSwitchButton()
    if rateEdit then rateEdit:ClearFocus() end
end)

-- 汇率输入框事件
rateEdit:SetScript("OnTextChanged", function(self)
    local text = self:GetText()
    local newText = text:gsub("[^%d%.%-]", "")
    if newText ~= text then self:SetText(newText) end
    if newText:match("%..*%.") then self:SetText(newText:gsub("(%..*)%..*", "%1")) end
    -- 持久化保存汇率
    local rate = tonumber(self:GetText())
    if rate and rate > 0 then
        LootStatsDB.rate = rate
    else
        LootStatsDB.rate = nil
    end
    UpdateCNYDisplay()
    if incomeStatsFrame and incomeStatsFrame:IsShown() then UpdateIncomeStatsDisplay() end
end)

-- ========================= 定时更新 =========================
C_Timer.NewTicker(1, UpdateCNYDisplay)
-- 钓鱼横条每秒刷新（仅在显示时）
C_Timer.NewTicker(1, function() if fmBar:IsShown() then UpdateFishingBar() end end)

-- ========================= 斜杠命令 =========================
SLASH_LOOTSTATS1 = "/ls"
function SlashCmdList.LOOTSTATS()
    if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
end

-- ========================= 初始显示 =========================
UpdateGold()
UpdateTime()
UpdateCNYDisplay()
UpdateLootLogDisplay()
mainFrame:Hide()

-- ========================= 小地图按钮 =========================
-- 点击切换主界面，可拖动到小地图边缘任意位置，位置持久化到 LootStatsDB.minimapAngle
local mmBtn = CreateFrame("Button", "FishingMasterMinimapButton", Minimap)
mmBtn:SetSize(31, 31)
mmBtn:SetFrameStrata("MEDIUM")
mmBtn:SetFrameLevel(8)
mmBtn:SetMovable(true)
mmBtn:RegisterForClicks("AnyUp")
mmBtn:RegisterForDrag("LeftButton")

local mmIcon = mmBtn:CreateTexture(nil, "BACKGROUND")
mmIcon:SetTexture("Interface\\Icons\\inv_misc_fish_05")
mmIcon:SetSize(20, 20)
mmIcon:SetPoint("CENTER", mmBtn)

local mmBorder = mmBtn:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetSize(54, 54)
mmBorder:SetPoint("TOPLEFT", mmIcon, "TOPLEFT", -18, 3)

-- 小地图半径（按钮中心距小地图中心的距离）
local MM_RADIUS = 80

-- 按角度（弧度）放置按钮
SetMinimapButtonAngle = function(angle)
    local x = math.cos(angle) * MM_RADIUS
    local y = math.sin(angle) * MM_RADIUS
    mmBtn:ClearAllPoints()
    mmBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    if LootStatsDB then LootStatsDB.minimapAngle = angle end
end

-- 默认放在小地图右侧偏上（-45度，即右上）
SetMinimapButtonAngle(-math.pi / 4)

-- 拖动：跟随鼠标围绕小地图边缘移动
mmBtn:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.atan2(cy - my, cx - mx)
        SetMinimapButtonAngle(angle)
    end)
end)

mmBtn:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
end)

-- 点击：切换主界面

-- ========================= 导航页数据接口（供 UI 子模块读取，勿改动此处） =========================
ns.FM = {
    GetTotalMoney = function() return totalMoney or 0 end,
    GetElapsed = function()
        if timerActive and startTime then return GetTime() - startTime end
        return 0
    end,
    IsTimerActive = function() return timerActive == true end,
    IsTimerPaused = function() return timerPaused == true end,
    ToggleTimer = function() if ToggleTimer then ToggleTimer() end end,
    ResetCurrent = function() if ResetCurrent then ResetCurrent() end end,
    GetRecentLoots = function() return recentLoots or {} end,
    GetRate = function() return (GetRate and GetRate()) or 0 end,
    SetRate = function(v)
        if v and v > 0 then LootStatsDB.rate = v else LootStatsDB.rate = nil end
        if ns.MainUI then ns.MainUI.RefreshActive() end
    end,
    GetDailyStats = function()
        local d = (LootStatsDB.dailyStats and LootStatsDB.dailyStats[GetCurrentDate()]) or {}
        return { totalCopper = d.totalCopper or 0, totalPickups = d.totalPickups or 0 }
    end,
    GetTotalStats = function()
        local t = LootStatsDB.totalStats or { totalCopper = 0, totalPickups = 0 }
        return { totalCopper = t.totalCopper or 0, totalPickups = t.totalPickups or 0 }
    end,
    ResetTotalStats = function()
        LootStatsDB.totalStats = { totalCopper = 0, totalPickups = 0 }
        if ns.MainUI then ns.MainUI.RefreshActive() end
    end,
    GetZoneData = function() return LootStatsDB end,
    ResetZoneStats = function()
        LootStatsDB.zones = {}; LootStatsDB.zoneTotals = {}; LootStatsDB.zoneItemCopper = {}; LootStatsDB.zoneItemCoords = {}
        if ns.MainUI then ns.MainUI.RefreshActive() end
    end,
    IsQuickLoot = function() return LootStatsDB.quickLootEnabled == true end,
    ToggleQuickLoot = function()
        if ns.QuickLoot then ns.QuickLoot:Toggle() end
        if ns.MainUI then ns.MainUI.RefreshActive() end
    end,
    IsRangeAlert = function() return LootStatsDB.rangeAlertEnabled == true end,
    ToggleRangeAlert = function()
        LootStatsDB.rangeAlertEnabled = not (LootStatsDB.rangeAlertEnabled == true)
        if ns.MainUI then ns.MainUI.RefreshActive() end
    end,
    IsCharSwitch = function() return LootStatsDB.charSwitchEnabled == true end,
    ToggleCharSwitch = function()
        LootStatsDB.charSwitchEnabled = not (LootStatsDB.charSwitchEnabled == true)
        if ns.MainUI then ns.MainUI.RefreshActive() end
    end,
    GetSmartMountDelay = function()
        local sm = LootStatsDB.smartMount
        return (sm and sm.autoMountDelay) or 1.0
    end,
    SetSmartMountDelay = function(v)
        if not LootStatsDB.smartMount then LootStatsDB.smartMount = {} end
        LootStatsDB.smartMount.autoMountDelay = v
    end,
    OpenSmartMountOptions = function()
        if ns.SmartMount then ns.SmartMount.OpenOptions() end
    end,
    GetCurrentZone = function() return (GetCurrentZone and GetCurrentZone()) or "" end,
    RefreshMainUI = function() if ns.MainUI then ns.MainUI.RefreshActive() end end,
}
mmBtn:SetScript("OnClick", function()
    if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
end)

-- 悬浮提示
mmBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText("|cffF2C14E钓鱼高手|r", 1, 1, 1)
    GameTooltip:AddLine("点击打开/关闭主界面", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("左键拖动可移动按钮位置", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("命令 /ls 同样可用", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)

mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

