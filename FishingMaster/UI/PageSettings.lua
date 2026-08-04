-- FishingMaster - 设置 (Settings) page
-- Builds the Settings navigation page inside the provided content frame.

local addonName, ns = ...
local FM = ns.FM
local FishingMasterComm = _G.FishingMasterComm

ns.PageSettings = {}
local page = ns.PageSettings
local built = false

-- Color palette (dark flat)
local COLOR = {
    card   = {0.149, 0.173, 0.212},
    gold   = {0.949, 0.757, 0.306},
    green  = {0.345, 0.788, 0.541},
    red    = {1, 0.2, 0.2},
    gray   = {0.608, 0.631, 0.659},
    light  = {0.91, 0.92, 0.93},
}

-- Defensive FM access helpers ---------------------------------------------
local function fmGet(fn, default)
    if type(FM) ~= "table" or type(fn) ~= "function" then return default end
    local ok, v = pcall(fn)
    if ok then return v end
    return default
end

-- Upvalue references (reset each Build)
local toggles = {}      -- list of {button, getFn}
local slider, sliderLabel
local rateEdit, rateLine

-- Update a toggle button's text + color from a boolean state
local function setToggleState(btn, on)
    if not btn or not btn.text then return end
    if on then
        btn.text:SetText("开")
        local c = COLOR.green
        btn.text:SetTextColor(c[1], c[2], c[3], 1)
    else
        btn.text:SetText("关")
        local c = COLOR.red
        btn.text:SetTextColor(c[1], c[2], c[3], 1)
    end
end

-- Create a label + toggle button row.
-- Returns the button so Refresh can update it.
local function makeToggle(parent, x, y, getFn, toggleFn, labelText)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(labelText or "")
    label:SetTextColor(unpack(COLOR.light))

    local btn = ns.Style.CreateFlatButton(parent, 70, 24)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, y)
    btn:SetScript("OnClick", function()
        if type(toggleFn) == "function" then
            local ok, err = pcall(toggleFn)
            if not ok and FishingMasterComm then
                if FishingMasterComm.PrintDebug then
                    FishingMasterComm.PrintDebug("toggle error: " .. tostring(err))
                end
            end
        end
        page.Refresh()
    end)

    -- 立即初始化按钮状态
    local on = false
    if type(getFn) == "function" then
        local ok, v = pcall(getFn)
        if ok then on = not not v end
    end
    if on then
        btn.text:SetText("开")
        local c = COLOR.green
        btn.text:SetTextColor(c[1], c[2], c[3], 1)
    else
        btn.text:SetText("关")
        local c = COLOR.red
        btn.text:SetTextColor(c[1], c[2], c[3], 1)
    end

    table.insert(toggles, {button = btn, getFn = getFn})
    return btn
end

-- Rate display string helper
local function rateText()
    local r = fmGet(function() return FM.GetRate() end, 0)
    return (r and r > 0) and tostring(r) or ""
end

function page.Build(content)
    if not content then return end
    -- reset state
    built = false
    toggles = {}
    slider, sliderLabel = nil, nil
    rateEdit, rateLine = nil, nil

    -- 1) Three toggle rows ------------------------------------------------
    local rowY = {-15, -50, -85}
    makeToggle(content, 20, rowY[1],
        function() return FM.IsQuickLoot() end,
        function() FM.ToggleQuickLoot() end,
        "快速拾取")
    makeToggle(content, 20, rowY[2],
        function() return FM.IsRangeAlert() end,
        function() FM.ToggleRangeAlert() end,
        "互动范围提醒")
    makeToggle(content, 20, rowY[3],
        function() return FM.IsCharSwitch() end,
        function() FM.ToggleCharSwitch() end,
        "角色切换音效")

    -- 2) 采集上马 section -------------------------------------------------
    local smTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    smTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -120)
    smTitle:SetText("采集上马")
    smTitle:SetTextColor(unpack(COLOR.gold))

    local smBtn = ns.Style.CreateFlatButton(content, 200, 26, "打开采集上马设置")
    smBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -140)
    smBtn:SetScript("OnClick", function()
        if type(FM) == "table" and type(FM.OpenSmartMountOptions) == "function" then
            pcall(FM.OpenSmartMountOptions)
        end
    end)

    slider = CreateFrame("Slider", "FishingMasterSmartMountDelaySlider", content, "OptionsSliderTemplate")
    slider:SetMinMaxValues(0.5, 5.0)
    slider:SetValueStep(0.1)
    slider:SetWidth(200)
    slider:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -185)
    local lowLbl = _G[slider:GetName() .. "Low"]
    local highLbl = _G[slider:GetName() .. "High"]
    local txtLbl = _G[slider:GetName() .. "Text"]
    if lowLbl then lowLbl:SetText("0.5") end
    if highLbl then highLbl:SetText("5.0") end
    if txtLbl then txtLbl:SetText("") end
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor((value or 0) * 10 + 0.5) / 10
        if type(FM) == "table" and type(FM.SetSmartMountDelay) == "function" then
            pcall(FM.SetSmartMountDelay, value)
        end
        if sliderLabel then
            sliderLabel:SetText("上马延迟: " .. string.format("%.1f", value) .. " 秒")
        end
    end)
    -- initialize from accessor (guard)
    local d = fmGet(function() return FM.GetSmartMountDelay() end, 1.0)
    if type(d) ~= "number" then d = 1.0 end
    slider:SetValue(d)

    sliderLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sliderLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -215)
    sliderLabel:SetTextColor(unpack(COLOR.light))
    sliderLabel:SetText("上马延迟: " .. string.format("%.1f", d) .. " 秒")

    -- 3) 汇率 section -----------------------------------------------------
    local rateTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rateTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -250)
    rateTitle:SetText("汇率")
    rateTitle:SetTextColor(unpack(COLOR.gold))

    rateEdit = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    rateEdit:SetSize(90, 24)
    rateEdit:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -270)
    rateEdit:SetAutoFocus(false)
    rateEdit:SetNumeric(false)
    rateEdit:SetText(rateText())
    rateEdit:SetScript("OnTextChanged", function(self)
        local txt = self:GetText() or ""
        -- sanitize: keep digits and dot, only one dot
        local cleaned = string.gsub(txt, "[^0-9%.]", "")
        local dot = string.find(cleaned, "%.")
        if dot then
            local before = string.sub(cleaned, 1, dot)
            local after = string.gsub(string.sub(cleaned, dot + 1), "%.", "")
            cleaned = before .. after
        end
        if cleaned ~= txt then
            local cur = self:GetCursorPosition() or 0
            self:SetText(cleaned)
            self:SetCursorPosition(math.min(cur, string.len(cleaned)))
        end
        local r = tonumber(self:GetText() or "")
        local setVal = (r and r > 0) and r or nil
        if type(FM) == "table" and type(FM.SetRate) == "function" then
            pcall(FM.SetRate, setVal)
        end
        if rateLine then
            local cur = fmGet(function() return FM.GetRate() end, 0)
            rateLine:SetText("10000 金 = " .. (cur and cur > 0 and tostring(cur) or "?") .. " 元")
        end
    end)

    rateLine = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rateLine:SetPoint("TOPLEFT", content, "TOPLEFT", 120, -274)
    rateLine:SetTextColor(unpack(COLOR.light))
    local r0 = fmGet(function() return FM.GetRate() end, 0)
    rateLine:SetText("10000 金 = " .. (r0 and r0 > 0 and tostring(r0) or "?") .. " 元")

    built = true
    -- 初始化 toggle 状态
    page.Refresh()
end

function page.Refresh()
    if not built then return end

    -- Toggle states
    for i = 1, #toggles do
        local t = toggles[i]
        local on = false
        if type(t.getFn) == "function" then
            local ok, v = pcall(t.getFn)
            if ok then on = not not v end
        end
        setToggleState(t.button, on)
    end

    -- Slider
    if slider and slider:IsShown() then
        local d = fmGet(function() return FM.GetSmartMountDelay() end, 1.0)
        if type(d) ~= "number" then d = 1.0 end
        slider:SetValue(d)
        if sliderLabel then
            sliderLabel:SetText("上马延迟: " .. string.format("%.1f", d) .. " 秒")
        end
    end

    -- Rate editbox (avoid cursor jump when focused) + line
    if rateEdit then
        local rt = rateText()
        if not rateEdit:HasFocus() and rateEdit:GetText() ~= rt then
            rateEdit:SetText(rt)
        end
    end
    if rateLine then
        local cur = fmGet(function() return FM.GetRate() end, 0)
        rateLine:SetText("10000 金 = " .. (cur and cur > 0 and tostring(cur) or "?") .. " 元")
    end
end
