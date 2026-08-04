local addonName, ns = ...
local FM = ns.FM
local FishingMasterComm = _G.FishingMasterComm

ns.PageStats = {}
local page = ns.PageStats
local built = false

-- current active tab
local activeTab = "income"

-- references kept across Refresh()
local tabIncome, tabZone
local incomePanel, zonePanel
local incomeText, zoneText

-- color helpers
local C = {
    card   = {0.149, 0.173, 0.212},
    gold   = {0.949, 0.757, 0.306},
    green  = {0.345, 0.788, 0.541},
    gray   = {0.608, 0.631, 0.659},
    light  = {0.91, 0.92, 0.93},
}

local function fmtCopper(c)
    c = c or 0
    local g = math.floor(c / 10000)
    local s = math.floor(c % 10000 / 100)
    if g > 0 then
        return string.format("%d g %d s", g, s)
    end
    return string.format("%d s", s)
end

local function setCardBg(frame)
    if not frame.bg then
        frame.bg = frame:CreateTexture(nil, "BACKGROUND")
        frame.bg:SetAllPoints(frame)
    end
    frame.bg:SetColorTexture(unpack(C.card))
end

local function makeTabButton(parent, label, x)
    local btn = ns.Style.CreateFlatButton(parent, 190, 26, label)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -4)
    return btn
end

local function makeResetButton(parent)
    local btn = ns.Style.CreateFlatButton(parent, 120, 26)
    return btn
end

local function buildIncomePanel(content)
    local panel = CreateFrame("Frame", nil, content)
    panel:SetAllPoints(content)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -40)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 6)

    local sc = CreateFrame("Frame", nil, scroll)
    sc:SetSize(panel:GetWidth() - 34, 10)
    scroll:SetScrollChild(sc)

    local text = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("TOPLEFT", sc, "TOPLEFT", 6, 0)
    text:SetWidth(sc:GetWidth() - 12)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(C.light))

    local reset = makeResetButton(panel)
    reset:SetText("重置累计")
    reset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -34, 10)
    reset:SetScript("OnClick", function()
        FM.ResetTotalStats()
        page.Refresh()
    end)

    incomePanel = panel
    incomeText = text
end

local function buildZonePanel(content)
    local panel = CreateFrame("Frame", nil, content)
    panel:SetAllPoints(content)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -40)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 6)

    local sc = CreateFrame("Frame", nil, scroll)
    sc:SetSize(panel:GetWidth() - 34, 10)
    scroll:SetScrollChild(sc)

    local text = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("TOPLEFT", sc, "TOPLEFT", 6, 0)
    text:SetWidth(sc:GetWidth() - 12)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(C.light))

    local reset = makeResetButton(panel)
    reset:SetText("重置统计")
    reset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -34, 10)
    reset:SetScript("OnClick", function()
        FM.ResetZoneStats()
        page.Refresh()
    end)

    zonePanel = panel
    zoneText = text
end

local function refreshIncome()
    if not incomeText then return end

    local rate = FM.GetRate() or 0
    local daily = FM.GetDailyStats() or { totalCopper = 0, totalPickups = 0 }
    local total = FM.GetTotalStats() or { totalCopper = 0, totalPickups = 0 }

    local today = date("%Y-%m-%d")

    local dailyRMB = "未设置汇率"
    if rate and rate > 0 then
        dailyRMB = string.format("%.2f 元", (daily.totalCopper or 0) * rate / 100000000)
    end
    local totalRMB = "未设置汇率"
    if rate and rate > 0 then
        totalRMB = string.format("%.2f 元", (total.totalCopper or 0) * rate / 100000000)
    end

    local lines = {}
    table.insert(lines, string.format("|cff%s每日|r", "f2c14e"))
    table.insert(lines, string.format("  日期: %s", today))
    table.insert(lines, string.format("  拾取总数: %d", daily.totalPickups or 0))
    table.insert(lines, string.format("  金币: %s", fmtCopper(daily.totalCopper or 0)))
    table.insert(lines, string.format("  人民币: %s", dailyRMB))
    table.insert(lines, "")
    table.insert(lines, string.format("|cff%s累计|r", "f2c14e"))
    table.insert(lines, string.format("  总拾取数: %d", total.totalPickups or 0))
    table.insert(lines, string.format("  总金币: %s", fmtCopper(total.totalCopper or 0)))
    table.insert(lines, string.format("  总人民币: %s", totalRMB))

    local str = table.concat(lines, "\n")
    incomeText:SetText(str)
    incomeText:GetParent():SetHeight(incomeText:GetStringHeight() + 10)
end

local function refreshZone()
    if not zoneText then return end

    local data = FM.GetZoneData()
    local zones = data and data.zones or {}
    local zoneTotals = data and data.zoneTotals or {}
    local zoneItemCopper = data and data.zoneItemCopper or {}

    -- collect sorted zone names
    local zoneNames = {}
    for z in pairs(zones) do
        table.insert(zoneNames, z)
    end
    table.sort(zoneNames)

    local lines = {}
    if #zoneNames == 0 then
        table.insert(lines, "暂无数据")
    else
        for _, zone in ipairs(zoneNames) do
            local zoneItems = zones[zone] or {}
            local zoneCopper = zoneItemCopper[zone] or {}
            local zoneTotal = 0
            -- sum copper for the zone
            local copperSum = 0
            for item, qty in pairs(zoneItems) do
                zoneTotal = zoneTotal + (qty or 0)
                copperSum = copperSum + (zoneCopper[item] or 0)
            end
            -- use provided zoneTotals if present, else computed
            local totalN = zoneTotals[zone] or zoneTotal

            table.insert(lines, string.format("|cff%s%s|r", "58c98a", tostring(zone)))
            table.insert(lines, string.format("  总计: %d件 - %s", totalN, fmtCopper(copperSum)))

            -- sort items by qty desc
            local items = {}
            for item, qty in pairs(zoneItems) do
                table.insert(items, { item = item, qty = qty })
            end
            table.sort(items, function(a, b) return (a.qty or 0) > (b.qty or 0) end)

            for _, entry in ipairs(items) do
                local item = entry.item
                local qty = entry.qty or 0
                local pct = 0
                if totalN and totalN > 0 then
                    pct = qty / totalN * 100
                end
                local copper = zoneCopper[item] or 0
                table.insert(lines, string.format("  %s: %d (%.1f%%) - %s", tostring(item), qty, pct, fmtCopper(copper)))
            end
            table.insert(lines, "")
        end
    end

    local str = table.concat(lines, "\n")
    zoneText:SetText(str)
    zoneText:GetParent():SetHeight(zoneText:GetStringHeight() + 10)
end

function page.Build(content)
    -- tabs
    tabIncome = makeTabButton(content, "收益统计", 6)
    tabZone = makeTabButton(content, "区域统计", 200)

    tabIncome:SetScript("OnClick", function()
        activeTab = "income"
        incomePanel:Show()
        zonePanel:Hide()
        page.Refresh()
    end)
    tabZone:SetScript("OnClick", function()
        activeTab = "zone"
        incomePanel:Hide()
        zonePanel:Show()
        page.Refresh()
    end)

    buildIncomePanel(content)
    buildZonePanel(content)

    -- tab visual highlight
    if activeTab == "income" then
        incomePanel:Show()
        zonePanel:Hide()
    else
        incomePanel:Hide()
        zonePanel:Show()
    end

    built = true
    page.Refresh()
end

function page.Refresh()
    if not built then return end
    if activeTab == "income" then
        refreshIncome()
    else
        refreshZone()
    end
end
