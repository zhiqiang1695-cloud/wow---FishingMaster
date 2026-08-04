-- ============================================================================
-- Style.lua — 统一颜色色板 + 扁平化按钮工厂
-- 所有 Page 文件通过 ns.Style 引用，确保 UI 风格一致
-- ============================================================================
local addonName, ns = ...

ns.Style = {}

-- 统一色板（深色扁平化）
ns.Style.C = {
    bg      = {0.118, 0.137, 0.173},   -- 主窗口背景
    sidebar = {0.09, 0.105, 0.13},     -- 侧栏背景
    content = {0.149, 0.173, 0.212},   -- 内容区背景
    card    = {0.184, 0.212, 0.259},   -- 卡片背景
    gold    = {0.949, 0.757, 0.306},   -- 金色 #F2C14E
    green   = {0.345, 0.788, 0.541},   -- 绿色 #58C98A
    red     = {1, 0.2, 0.2},           -- 红色
    gray    = {0.608, 0.631, 0.659},   -- 灰色
    light   = {0.91, 0.92, 0.93},      -- 浅灰白
}

-- 扁平化按钮工厂
-- 用法和 GameMenuButtonTemplate 一致：返回后可 SetSize / SetText / SetPoint / SetScript
-- 额外支持：btn:SetText() / btn:GetFontString():SetTextColor()
function ns.Style.CreateFlatButton(parent, w, h, text)
    local btn = CreateFrame("Button", nil, parent)
    if w and h then btn:SetSize(w, h) end

    -- 背景
    btn._bg = btn:CreateTexture(nil, "BACKGROUND")
    btn._bg:SetAllPoints()
    btn._bg:SetColorTexture(0.22, 0.25, 0.31, 0.95)

    -- 细边框（用 1px 内缩 Texture 模拟）
    btn._border = btn:CreateTexture(nil, "BORDER")
    btn._border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    btn._border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    btn._border:SetColorTexture(0.33, 0.36, 0.42, 0.6)

    -- 内层背景（盖在边框上，留出 1px 边框效果）
    btn._inner = btn:CreateTexture(nil, "ARTWORK")
    btn._inner:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn._inner:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn._inner:SetColorTexture(0.22, 0.25, 0.31, 0.95)

    -- 文字（公开字段 btn.text，调用方可直接 SetText/SetTextColor 绕过 SetFontString 的不确定性）
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("CENTER", btn, "CENTER", 0, 1)
    btn.text:SetText(text or "")
    btn.text:SetTextColor(0.91, 0.92, 0.93, 1)  -- 显式传 alpha，避免 nil 被当作 0
    btn:SetFontString(btn.text)

    -- 悬浮高亮
    btn:SetScript("OnEnter", function()
        btn._inner:SetColorTexture(0.30, 0.33, 0.40, 0.98)
        btn.text:SetTextColor(0.949, 0.757, 0.306, 1)
    end)
    btn:SetScript("OnLeave", function()
        btn._inner:SetColorTexture(0.22, 0.25, 0.31, 0.95)
        btn.text:SetTextColor(0.91, 0.92, 0.93, 1)
    end)
    btn:SetScript("OnMouseDown", function()
        btn._inner:SetColorTexture(0.16, 0.18, 0.23, 0.98)
    end)
    btn:SetScript("OnMouseUp", function()
        btn._inner:SetColorTexture(0.22, 0.25, 0.31, 0.95)
    end)

    return btn
end
