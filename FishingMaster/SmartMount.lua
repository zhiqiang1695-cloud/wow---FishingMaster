local addonName, ns = ...

-------------------------------------------------
-- SmartMount 采集上马子模块
-- 集成在钓鱼高手插件中
-------------------------------------------------

-- 默认配置
local defaults = {
    enabled = true,
    autoMount = false,
    autoMountDelay = 1.5,
    groundIndex = 1,
    flyIndex = 1,
}

local db

-- 简易定时器
local timerFrame = CreateFrame("Frame")
local timers = {}
local timerId = 0

timerFrame:SetScript("OnUpdate", function(self)
    local now = GetTime()
    for id, t in pairs(timers) do
        if now >= t.endTime then
            timers[id] = nil
            t.callback()
        end
    end
end)

local function SetTimer(delay, callback)
    timerId = timerId + 1
    timers[timerId] = { endTime = GetTime() + delay, callback = callback }
    return timerId
end

local function CancelTimer(id)
    if id then timers[id] = nil end
end

local mountTimerId = nil
local autoMountTimerId = nil

-------------------------------------------------
-- 上马核心
-------------------------------------------------

local function TryMount(index)
    if index and index > 0 then
        local numMounts = GetNumCompanions("MOUNT")
        if numMounts and numMounts > 0 and index <= numMounts then
            CallCompanion("MOUNT", index)
            return true
        end
    end
    return false
end

local function CanMount()
    if UnitAffectingCombat("player") then return false end
    if IsMounted() then return false end
    if IsInInstance() then return false end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return false end
    if IsIndoors() then return false end
    local _, class = UnitClass("player")
    if class == "DRUID" then
        local form = GetShapeshiftForm()
        if form and form > 0 then
            local _, _, _, spellId = GetShapeshiftFormInfo(form)
            if spellId == 783 or spellId == 33943 or spellId == 40120 then
                return false
            end
        end
    end
    return true
end

local function CanFlyInArea()
    if not IsFlyableArea() then return false end
    local hasRidingSkill = IsSpellKnown(34090) or IsSpellKnown(34091)
    if not hasRidingSkill then return false end
    local mapID = GetCurrentMapAreaID()
    if mapID == 113 then
        if not IsSpellKnown(54197) then return false end
    end
    if mapID == 125 then return false end
    return true
end

-------------------------------------------------
-- 上马逻辑
-------------------------------------------------

local function DoMount()
    if not db.enabled then return end
    if not CanMount() then return end

    if CanFlyInArea() and db.flyIndex > 0 then
        TryMount(db.flyIndex)
    else
        TryMount(db.groundIndex)
    end
end

local function MountNow()
    if not CanMount() then return end
    if CanFlyInArea() and db.flyIndex > 0 then
        TryMount(db.flyIndex)
    else
        TryMount(db.groundIndex)
    end
end

local function ScheduleMount()
    CancelTimer(mountTimerId)
    mountTimerId = SetTimer(db.autoMountDelay, function()
        mountTimerId = nil
        DoMount()
    end)
end

local function ScheduleAutoMount()
    CancelTimer(autoMountTimerId)
    autoMountTimerId = SetTimer(db.autoMountDelay, function()
        autoMountTimerId = nil
        if db.autoMount and db.enabled then
            DoMount()
        end
    end)
end

local function CancelAllTimers()
    CancelTimer(mountTimerId)
    mountTimerId = nil
    CancelTimer(autoMountTimerId)
    autoMountTimerId = nil
end

-------------------------------------------------
-- 自动上马 OnUpdate
-------------------------------------------------
local moveCheckFrame = CreateFrame("Frame")
moveCheckFrame:Hide()
local wasMoving = false

moveCheckFrame:SetScript("OnUpdate", function(self)
    if not db.autoMount or not db.enabled then
        self:Hide()
        return
    end
    local speed = GetUnitSpeed("player")
    local isMoving = speed > 0
    if wasMoving and not isMoving then
        ScheduleAutoMount()
    elseif not wasMoving and isMoving then
        CancelTimer(autoMountTimerId)
        autoMountTimerId = nil
    end
    wasMoving = isMoving
end)

-------------------------------------------------
-- 事件处理
-------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("LOOT_CLOSED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "LOOT_CLOSED" then
        if db.enabled then ScheduleMount() end
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit = ...
        if unit == "player" then CancelAllTimers() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        CancelAllTimers()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if db.autoMount and db.enabled then
            ScheduleAutoMount()
        end
    end
end)

-------------------------------------------------
-- 初始化（由FishingMaster的ADDON_LOADED调用）
-------------------------------------------------
local function Init()
    if not LootStatsDB then LootStatsDB = {} end
    if not LootStatsDB.smartMount then LootStatsDB.smartMount = {} end
    -- 清理旧字段
    LootStatsDB.smartMount.groundMountSpell = nil
    LootStatsDB.smartMount.flyMountSpell = nil
    LootStatsDB.smartMount.groundMountIndex = nil
    LootStatsDB.smartMount.flyMountIndex = nil
    LootStatsDB.smartMount.groundName = nil
    LootStatsDB.smartMount.flyName = nil
    LootStatsDB.smartMount.groundMountName = nil
    LootStatsDB.smartMount.flyMountName = nil
    LootStatsDB.smartMount.delay = nil

    db = setmetatable(LootStatsDB.smartMount, { __index = defaults })

    if db.autoMount then
        moveCheckFrame:Show()
    end
end

-------------------------------------------------
-- 设置面板
-------------------------------------------------
local optionsFrame

local function OpenOptions()
    if optionsFrame then
        optionsFrame:Show()
        if optionsFrame.RefreshHighlight then optionsFrame:RefreshHighlight() end
        return
    end

    local numMounts = GetNumCompanions("MOUNT") or 0

    optionsFrame = CreateFrame("Frame", "SmartMountOptionsFrame", UIParent, "BackdropTemplate")
    optionsFrame:SetSize(440, 540)
    optionsFrame:SetPoint("CENTER")
    optionsFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    optionsFrame:SetBackdropColor(0, 0, 0, 0.9)
    optionsFrame:SetMovable(true)
    optionsFrame:EnableMouse(true)
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
    optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)
    optionsFrame:SetFrameStrata("DIALOG")

    -- 标题
    local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cFF00FF00SmartMount|r 智能上马设置")

    -- 关闭
    local close = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    ---- 第一行：启用 / 自动上马 / 立刻上马 ----
    local enableCheck = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", 24, -48)
    local enableText = enableCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    enableText:SetPoint("LEFT", enableCheck, "RIGHT", 4, 0)
    enableText:SetText("启用采集上马")
    enableCheck:SetChecked(db.enabled)
    enableCheck:SetScript("OnClick", function(self)
        db.enabled = self:GetChecked() and true or false
    end)

    local autoCheck = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    autoCheck:SetPoint("TOPLEFT", 24, -76)
    local autoText = autoCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoText:SetPoint("LEFT", autoCheck, "RIGHT", 4, 0)
    autoText:SetText("自动上马")
    autoCheck:SetChecked(db.autoMount)
    autoCheck:SetScript("OnClick", function(self)
        local val = self:GetChecked() and true or false
        db.autoMount = val
        if val then
            moveCheckFrame:Show()
        else
            moveCheckFrame:Hide()
            CancelTimer(autoMountTimerId)
            autoMountTimerId = nil
        end
    end)

    local mountNowBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    mountNowBtn:SetPoint("TOPRIGHT", -24, -48)
    mountNowBtn:SetSize(80, 24)
    mountNowBtn:SetText("立刻上马")
    mountNowBtn:SetScript("OnClick", function()
        MountNow()
    end)

    ---- 上马延迟 ----
    local delayLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    delayLabel:SetPoint("TOPLEFT", 24, -104)
    delayLabel:SetText("上马延迟: " .. format("%.1f", db.autoMountDelay) .. "秒")

    local delaySlider = CreateFrame("Slider", "SmartMountDelaySlider", optionsFrame, "OptionsSliderTemplate")
    delaySlider:SetPoint("TOPLEFT", 24, -120)
    delaySlider:SetWidth(200)
    delaySlider:SetMinMaxValues(0.5, 5.0)
    delaySlider:SetValueStep(0.1)
    delaySlider:SetObeyStepOnDrag(true)
    delaySlider:SetValue(db.autoMountDelay)
    _G[delaySlider:GetName() .. "Low"]:SetText("0.5")
    _G[delaySlider:GetName() .. "High"]:SetText("5.0")
    _G[delaySlider:GetName() .. "Text"]:SetText("")
    delaySlider:SetScript("OnValueChanged", function(self, value)
        db.autoMountDelay = tonumber(format("%.1f", value))
        delayLabel:SetText("上马延迟: " .. format("%.1f", db.autoMountDelay) .. "秒")
    end)

    ---- 坐骑选择区域 ----
    local groundBtns = {}
    local flyBtns = {}

    local function CreateMountGrid(parent, label, yOffset, btnRefs, configField)
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 24, yOffset)
        header:SetText(label)

        local selLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        selLabel:SetPoint("LEFT", header, "RIGHT", 8, 0)

        local function UpdateSelText()
            if db[configField] and db[configField] > 0 then
                selLabel:SetText("|cFF00FF00第" .. db[configField] .. "只|r")
            else
                selLabel:SetText("|cFF888888未选择|r")
            end
        end
        UpdateSelText()

        local btnSize = 32
        local btnSpacing = 4
        local cols = 10
        local startY = yOffset - 22

        for i = 1, numMounts do
            local row = math.floor((i - 1) / cols)
            local col = (i - 1) % cols
            local x = 24 + col * (btnSize + btnSpacing)
            local y = startY - row * (btnSize + btnSpacing)

            local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", x, y)
            btn:SetText(tostring(i))
            btn:SetNormalFontObject("GameFontNormalSmall")
            btn:GetFontString():SetPoint("CENTER", 0, 0)

            local function UpdateBtnHighlight()
                if db[configField] == i then
                    btn:LockHighlight()
                else
                    btn:UnlockHighlight()
                end
            end
            UpdateBtnHighlight()

            btn:SetScript("OnClick", function()
                db[configField] = i
                UpdateSelText()
                for _, b in ipairs(btnRefs) do
                    b.UpdateHighlight()
                end
            end)

            btn.UpdateHighlight = UpdateBtnHighlight
            tinsert(btnRefs, btn)
        end

        local nameRow = math.floor(numMounts / cols) + 1
        local clearY = startY - nameRow * (btnSize + btnSpacing) - 4

        local clearBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        clearBtn:SetPoint("TOPLEFT", 24, clearY)
        clearBtn:SetSize(60, 20)
        clearBtn:SetText("清除")
        clearBtn:SetScript("OnClick", function()
            db[configField] = 0
            UpdateSelText()
            for _, b in ipairs(btnRefs) do
                b.UpdateHighlight()
            end
        end)

        return clearY - 30
    end

    -- 地面坐骑
    local nextY = CreateMountGrid(optionsFrame, "|cFFFFFFFF地面坐骑:|r", -148, groundBtns, "groundIndex")

    -- 飞行坐骑
    CreateMountGrid(optionsFrame, "|cFFFFFFFF飞行坐骑:|r", nextY, flyBtns, "flyIndex")

    -- 刷新高亮函数
    function optionsFrame:RefreshHighlight()
        for _, b in ipairs(groundBtns) do b.UpdateHighlight() end
        for _, b in ipairs(flyBtns) do b.UpdateHighlight() end
    end

    -- 底部提示
    local tip = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    tip:SetPoint("BOTTOM", 0, 12)
    tip:SetWidth(400)
    tip:SetJustifyH("CENTER")
    tip:SetText("点击编号选择坐骑 | /sm 立刻上马 | /sm auto 自动上马")

    optionsFrame:Show()
end

-------------------------------------------------
-- 命令行
-------------------------------------------------
SLASH_SMARTMOUNT1 = "/sm"
SLASH_SMARTMOUNT2 = "/smartmount"
SlashCmdList["SMARTMOUNT"] = function(msg)
    msg = msg or ""
    msg = msg:match("^%s*(.-)%s*$") or ""
    local lowerMsg = msg:lower()

    if lowerMsg == "on" or lowerMsg == "enable" then
        db.enabled = true
    elseif lowerMsg == "off" or lowerMsg == "disable" then
        db.enabled = false
        CancelAllTimers()
    elseif lowerMsg == "now" then
        MountNow()
    elseif lowerMsg == "auto" then
        db.autoMount = not db.autoMount
        if db.autoMount then
            moveCheckFrame:Show()
        else
            moveCheckFrame:Hide()
            CancelTimer(autoMountTimerId)
            autoMountTimerId = nil
        end
    elseif lowerMsg:find("^ground") then
        local idx = tonumber(msg:match("ground%s+(%d+)"))
        if idx then
            db.groundIndex = idx
        end
    elseif lowerMsg:find("^fly") then
        local idx = tonumber(msg:match("fly%s+(%d+)"))
        if idx then
            db.flyIndex = idx
        end
    end
    OpenOptions()
end

-------------------------------------------------
-- 暴露给FishingMaster的接口
-------------------------------------------------
ns.SmartMount = {
    Init = Init,
    OpenOptions = OpenOptions,
    MountNow = MountNow,
}
