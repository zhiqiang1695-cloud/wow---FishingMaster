local addonName, ns = ...
local FM = ns.FM
local FishingMasterComm = _G.FishingMasterComm

ns.PageHelp = {}
local page = ns.PageHelp
local built = false

local CARD_BG = {0.149, 0.173, 0.212}
local GOLD = "ffF2C14E"
local GREEN = "ff58C98A"
local GRAY = "ff9BA1A8"
local LIGHT = "ffe8eaed"

local function MakeCard(parent, x, y, w, h)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(w, h)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    card.bg = card:CreateTexture(nil, "BACKGROUND")
    card.bg:SetAllPoints()
    card.bg:SetColorTexture(CARD_BG[1], CARD_BG[2], CARD_BG[3])
    return card
end

function page.Build(content)
    if built then return end

    local w = content:GetWidth() or 410

    -- 1. Intro line
    local intro = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    intro:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -14)
    intro:SetWidth(w - 24)
    intro:SetJustifyH("LEFT")
    intro:SetText("|c" .. LIGHT .. "钓鱼高手 · 收益追踪与渔友圈|r")

    -- 2A. Promo card A
    local cardA = MakeCard(content, 12, -44, w - 24, 90)
    local titleA = cardA:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    titleA:SetPoint("TOPLEFT", cardA, "TOPLEFT", 12, -12)
    titleA:SetText("|c" .. GOLD .. "■|r |c" .. LIGHT .. "钓鱼交流群①|r")

    local numA = cardA:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    numA:SetPoint("TOPLEFT", cardA, "TOPLEFT", 12, -38)
    numA:SetText("|c" .. GOLD .. "1043976142|r")

    local subA = cardA:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    subA:SetPoint("TOPLEFT", cardA, "TOPLEFT", 12, -68)
    subA:SetText("|c" .. GRAY .. "进阶钓鱼插件 / 鱼价讨论|r")

    -- 2B. Promo card B
    local cardB = MakeCard(content, 12, -146, w - 24, 90)
    local titleB = cardB:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    titleB:SetPoint("TOPLEFT", cardB, "TOPLEFT", 12, -12)
    titleB:SetText("|c" .. GOLD .. "■|r |c" .. LIGHT .. "钓鱼交流群②|r")

    local numB = cardB:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    numB:SetPoint("TOPLEFT", cardB, "TOPLEFT", 12, -38)
    numB:SetText("|c" .. GOLD .. "1041294189|r")

    local subB = cardB:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    subB:SetPoint("TOPLEFT", cardB, "TOPLEFT", 12, -68)
    subB:SetText("|c" .. GRAY .. "进阶钓鱼插件 / 鱼价讨论|r")

    -- 3. Closing gray note
    local note = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    note:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -250)
    note:SetWidth(w - 24)
    note:SetJustifyH("LEFT")
    note:SetText("|c" .. GRAY .. "更多功能请关注群内公告。|r")

    built = true
end

function page.Refresh()
    if not built then return end
end
