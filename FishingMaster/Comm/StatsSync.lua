-- ============================================================================
-- StatsSync.lua  —  统计聚合与鱼价手册
-- 负责：
--   * 自身排名计算（双维度：钓鱼数 / 金币）
--   * 频道汇总统计（在线数、累计已知、今日总产出、平均、最高）
--   * 鱼价手册合并（多源交叉：Tier1 优先、同 Tier 取中位数、记录来源）
--   * 自我取价链（复用 FishingMaster 现有 Auctionator/EasyAuction/售价 降级）
--   * 价格查询广播
-- ============================================================================
local MAJOR = "FishingMasterComm"
local FishingMasterComm = _G[MAJOR] or {}
_G[MAJOR] = FishingMasterComm

local Protocol = FishingMasterComm.Protocol
local PeerRegistry = FishingMasterComm.PeerRegistry

local StatsSync = {}
FishingMasterComm.StatsSync = StatsSync

local function DB()
    return FishingMasterComm._state and FishingMasterComm._state.db
end

-- ---------------------------------------------------------------------------
-- 自身条目（用于排名/汇总）
-- ---------------------------------------------------------------------------
local function SelfEntry()
    local db = DB()
    if not db then return { n = UnitName("player"), r = GetRealmName(), fc = 0, fd = 0, gc = 0, gd = 0, self = true } end
    local today = date("%Y-%m-%d")
    local daily = (db.dailyStats and db.dailyStats[today]) or { totalPickups = 0, totalCopper = 0 }
    local total = db.totalStats or { totalPickups = 0, totalCopper = 0 }
    return {
        n = UnitName("player"), r = GetRealmName(),
        fc = total.totalPickups or 0, fd = daily.totalPickups or 0,
        gc = total.totalCopper or 0, gd = daily.totalCopper or 0,
        self = true,
    }
end

-- ---------------------------------------------------------------------------
-- 排名
-- dim: "fishCount"（钓鱼数） | "gold"（金币）
-- 返回 { rank, total, value }
-- ---------------------------------------------------------------------------
function StatsSync:GetSelfRank(dim)
    dim = dim or "fishCount"
    local selfE = SelfEntry()
    local peers = PeerRegistry.GetAll()
    local list = { selfE }
    for _, p in ipairs(peers) do table.insert(list, p) end

    table.sort(list, function(a, b)
        if dim == "gold" then
            return (a.gc or 0) > (b.gc or 0)
        end
        return (a.fc or 0) > (b.fc or 0)
    end)

    local rank, total = 0, #list
    for i, p in ipairs(list) do
        if p.self then rank = i; break end
    end
    local value = dim == "gold" and selfE.gc or selfE.fc
    return { rank = rank, total = total, value = value }
end

-- ---------------------------------------------------------------------------
-- 频道汇总
-- ---------------------------------------------------------------------------
function StatsSync:GetChannelStats()
    local online = PeerRegistry.GetOnline()
    local all = PeerRegistry.GetAll()
    local todayGold = 0
    for _, p in ipairs(online) do
        todayGold = todayGold + (p.gd or 0)
    end
    local fishSum, goldSum, maxFish = 0, 0, 0
    for _, p in ipairs(all) do
        fishSum = fishSum + (p.fc or 0)
        goldSum = goldSum + (p.gc or 0)
        if (p.fc or 0) > maxFish then maxFish = p.fc end
    end
    local total = #all
    return {
        online   = #online,
        known    = total,
        todayGold = todayGold,
        avgFish  = total > 0 and math.floor(fishSum / total) or 0,
        avgGold  = total > 0 and math.floor(goldSum / total) or 0,
        maxFish  = maxFish,
    }
end

-- ---------------------------------------------------------------------------
-- 鱼价手册
-- ---------------------------------------------------------------------------
function StatsSync:GetPriceBook()
    local db = DB()
    return (db and db.priceBook) or {}
end

-- 价格 Tier 取值链（与 FishingMaster.lua 一致）
function StatsSync:GetItemPrice(link, itemName)
    local price, tier = nil, 3
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink then
        price = Auctionator.API.v1.GetAuctionPriceByItemLink("FishingMasterComm", link)
        if price then tier = 1 end
    end
    if not price and EasyAuction_GetPriceHistoryMinUnit then
        local itemID = link:match("item:(%d+)")
        if itemID and itemName then
            price = EasyAuction_GetPriceHistoryMinUnit(itemName .. ":" .. itemID)
            if price then tier = 2 end
        end
    end
    if not price then
        local _, _, _, _, _, _, _, _, _, _, vendor = GetItemInfo(link)
        if vendor and vendor > 0 then price = vendor; tier = 3 end
    end
    return price, tier
end

-- 拾取时记录自身已知价格到鱼价手册
function StatsSync:RecordSelfPrices()
    local n = (GetNumLootItems and GetNumLootItems()) or 0
    if n == 0 then return end
    local selfName, selfRealm = UnitName("player"), GetRealmName()
    local now = time()
    for i = 1, n do
        local link = GetLootSlotLink(i)
        if link then
            local _, name = GetLootSlotInfo(i)
            if name then
                local price, tier = self:GetItemPrice(link, name)
                if price and price > 0 then
                    self:MergePrice(name, price, tier, selfName, selfRealm, now, true)
                end
            end
        end
    end
end

-- 合并一条价格上报（多源：Tier1 优先，同 Tier 取中位数，记录来源）
function StatsSync:MergePrice(item, price, tier, name, realm, ts, isSelf)
    local db = DB()
    if not db then return end
    if not db.priceBook then db.priceBook = {} end
    local book = db.priceBook
    if not book[item] then book[item] = { price = 0, tier = 3, sources = {}, ts = 0 } end
    local e = book[item]
    if not e.sources then e.sources = {} end

    local srcId = (realm and name) and (realm .. ":" .. name) or (isSelf and "self" or "anon")
    e.sources[srcId] = { price = price, tier = tier, name = name, realm = realm, ts = ts or time() }

    -- 选价：优先最低 Tier；同 Tier 取中位数避免单一玩家操控
    local bestTier = 99
    for _, s in pairs(e.sources) do
        if s.tier and s.tier < bestTier then bestTier = s.tier end
    end
    local vals = {}
    for _, s in pairs(e.sources) do
        if s.tier == bestTier then table.insert(vals, s.price) end
    end
    table.sort(vals)
    e.price = vals[math.ceil(#vals / 2)] or price
    e.tier = bestTier
    e.ts = ts or time()
end

-- 刷新所有已知鱼价（遍历全部已记录区域）
function StatsSync:QueryAllKnownPrices()
    local db = DB()
    if not db or not db.zones then return end
    local count = 0
    for zone, items in pairs(db.zones) do
        for item in pairs(items) do
            FishingMasterComm:QueryPrice(item)
            count = count + 1
        end
    end
    return count
end

-- 仅刷新当前区域鱼价
function StatsSync:QueryCurrentZonePrices()
    local db = DB()
    if not db or not db.zones then return 0 end
    local zone = GetRealZoneText() or ""
    local items = db.zones[zone]
    if not items then return 0 end
    local count = 0
    for item in pairs(items) do
        FishingMasterComm:QueryPrice(item)
        count = count + 1
    end
    return count
end
