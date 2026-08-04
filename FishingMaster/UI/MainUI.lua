-- ============================================================================
-- MainUI.lua — 导航栏式主界面外壳（左栏导航 + 右侧内容区）
-- 各导航页由独立模块实现：ns.PageDashboard / PageFriends / PageStats /
-- PageSettings / PageHelp，每个暴露 Build(content) 与 Refresh()。
-- ============================================================================
local addonName, ns = ...
local FM = ns.FM

local SIDEBAR_W = 150
local W, H = 560, 460
local SelectPage  -- 提前声明：导航按钮 OnClick（第108行）在 SelectPage 定义（第112行）之前引用它

local PAGES = {
    { key = "dashboard", name = "仪表盘", mod = "PageDashboard" },
    { key = "friends",   name = "渔友圈", mod = "PageFriends" },
    { key = "stats",     name = "统计",   mod = "PageStats" },
    { key = "settings",  name = "设置",   mod = "PageSettings" },
    { key = "help",      name = "帮助",   mod = "PageHelp" },
}
local PAGES_BY_KEY = {}
for _, p in ipairs(PAGES) do PAGES_BY_KEY[p.key] = p end

-- 主窗口
local nav = CreateFrame("Frame", "FishingMasterNav", UIParent)
nav:SetSize(W, H)
nav:SetPoint("CENTER", UIParent, "CENTER")
nav:SetMovable(true)
nav:SetClampedToScreen(true)
nav:EnableMouse(true)
nav:RegisterForDrag("LeftButton")
nav:SetScript("OnDragStart", function(self) self:StartMoving() end)
nav:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
nav:Hide()

nav.bg = nav:CreateTexture(nil, "BACKGROUND")
nav.bg:SetAllPoints()
nav.bg:SetColorTexture(0.118, 0.137, 0.173, 0.98)

-- 左侧导航栏
local sidebar = CreateFrame("Frame", nil, nav)
sidebar:SetSize(SIDEBAR_W, H)
sidebar:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, 0)
sidebar:EnableMouse(true)
sidebar:RegisterForDrag("LeftButton")
sidebar:SetScript("OnDragStart", function() nav:StartMoving() end)
sidebar:SetScript("OnDragStop", function() nav:StopMovingOrSizing() end)

local sbBg = sidebar:CreateTexture(nil, "BACKGROUND")
sbBg:SetAllPoints()
sbBg:SetColorTexture(0.09, 0.105, 0.13, 1)

local logo = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
logo:SetPoint("TOP", sidebar, "TOP", 0, -18)
logo:SetText("钓鱼高手")
logo:SetTextColor(0.949, 0.757, 0.306)

local logoSub = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
logoSub:SetPoint("TOP", logo, "BOTTOM", 0, -2)
logoSub:SetText("FM v1")
logoSub:SetTextColor(0.608, 0.631, 0.659)

-- 右侧内容区
local content = CreateFrame("Frame", nil, nav)
content:SetSize(W - SIDEBAR_W, H)
content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
local cBg = content:CreateTexture(nil, "BACKGROUND")
cBg:SetAllPoints()
cBg:SetColorTexture(0.149, 0.173, 0.212, 1)

-- 关闭按钮
local closeBtn = ns.Style.CreateFlatButton(nav, 22, 22, "X")
closeBtn:SetSize(22, 22)
closeBtn:SetText("X")
closeBtn:SetPoint("TOPRIGHT", nav, "TOPRIGHT", -6, -6)
closeBtn:SetScript("OnClick", function() nav:Hide() end)

-- 每个导航页一个内容帧（懒构建）
local pageFrames = {}
local navButtons = {}
local activeKey = nil

for _, p in ipairs(PAGES) do
    local pf = CreateFrame("Frame", nil, content)
    pf:SetAllPoints()
    pf:Hide()
    pageFrames[p.key] = pf

    local btn = CreateFrame("Button", nil, sidebar)
    btn:SetSize(SIDEBAR_W - 16, 34)
    navButtons[p.key] = btn
end

local yOff = -70
for _, p in ipairs(PAGES) do
    local btn = navButtons[p.key]
    btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, yOff)
    yOff = yOff - 40

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0, 0, 0, 0)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.label:SetPoint("LEFT", btn, "LEFT", 14, 0)
    btn.label:SetText(p.name)
    btn.label:SetTextColor(0.91, 0.92, 0.93)

    btn:SetScript("OnClick", (function(key)
        return function() SelectPage(key) end
    end)(p.key))
end

SelectPage = function(key)
    local p = PAGES_BY_KEY[key]
    if not p then return end
    for _, pp in ipairs(PAGES) do
        if pageFrames[pp.key] then pageFrames[pp.key]:SetShown(pp.key == key) end
        local b = navButtons[pp.key]
        if b then
            local on = (pp.key == key)
            b.bg:SetColorTexture(on and 0.949 or 0, on and 0.757 or 0, on and 0.306 or 0, on and 0.18 or 0)
            b.label:SetTextColor(on and 0.118 or 0.91, on and 0.105 or 0.92, on and 0.13 or 0.93)
        end
    end
    activeKey = key
    local pf = pageFrames[key]
    local mod = ns[p.mod]
    if pf and mod and mod.Build and not pf._built then
        mod.Build(pf)
        pf._built = true
    end
    if mod and mod.Refresh then mod.Refresh() end
end

-- 实时刷新当前页
C_Timer.NewTicker(1, function()
    if nav:IsShown() and activeKey then
        local mod = ns[PAGES_BY_KEY[activeKey].mod]
        if mod and mod.Refresh then mod.Refresh() end
    end
end)

ns.MainUI = {
    frame = nav,
    RefreshActive = function()
        if activeKey then
            local mod = ns[PAGES_BY_KEY[activeKey].mod]
            if mod and mod.Refresh then mod.Refresh() end
        end
    end,
    Toggle = function()
        if nav:IsShown() then nav:Hide()
        else SelectPage(activeKey or "dashboard"); nav:Show() end
    end,
    Show = function() SelectPage(activeKey or "dashboard"); nav:Show() end,
    Hide = function() nav:Hide() end,
}

-- 接管斜杠命令与小地图按钮
SLASH_LOOTSTATS1 = "/ls"
function SlashCmdList.LOOTSTATS() ns.MainUI.Toggle() end

-- /fm 覆盖 CommCore 的旧定义，直接跳到"渔友圈"页
SLASH_FMNET1 = "/fm"
function SlashCmdList.FMNET()
    SelectPage("friends")
    nav:Show()
end

local mm = _G.FishingMasterMinimapButton
if mm then
    mm:SetScript("OnClick", function() ns.MainUI.Toggle() end)
end
