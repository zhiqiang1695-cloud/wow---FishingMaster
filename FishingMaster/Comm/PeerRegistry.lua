-- ============================================================================
-- PeerRegistry.lua  —  频道玩家表
-- 持久化于 LootStatsDB.commPeers，负责：
--   * 心跳/HELLO 写入与更新
--   * 在线状态计算（基于 lastSeen）
--   * 防作弊：累计值单调递增校验、异常暴涨标记
--   * 忽略列表
-- 不负责网络收发（见 CommCore）。
-- ============================================================================
local MAJOR = "FishingMasterComm"
local FishingMasterComm = _G[MAJOR] or {}
_G[MAJOR] = FishingMasterComm

local PeerRegistry = {}
FishingMasterComm.PeerRegistry = PeerRegistry

-- 离线阈值：> 90 秒（3 倍心跳周期 30s）未收到心跳即判离线
local OFFLINE_THRESHOLD = 90
-- 异常暴涨阈值：累计钓鱼数 每秒增量超过此值视为可疑
local SUSPICIOUS_JUMP = 1000
-- 黑白名单：被忽略的玩家 id
local ignored = {}

local DB  -- = LootStatsDB.commPeers

function PeerRegistry.Init(commPeers, ignoredSet)
    DB = commPeers or {}
    ignored = ignoredSet or {}
end

local function MakeId(realm, name)
    return realm .. ":" .. name
end
PeerRegistry.MakeId = MakeId

function PeerRegistry.Get(id)
    return DB[id]
end

function PeerRegistry.GetAll()
    local out = {}
    for id, p in pairs(DB) do
        p.id = id
        table.insert(out, p)
    end
    return out
end

-- 在线玩家：isOnline 且 lastSeen 在阈值内
function PeerRegistry.GetOnline()
    local now = GetTime()
    local out = {}
    for id, p in pairs(DB) do
        if p.isOnline and (now - (p.lastSeen or 0)) <= OFFLINE_THRESHOLD then
            p.id = id
            table.insert(out, p)
        end
    end
    return out
end

function PeerRegistry.IsOnline(id)
    local p = DB[id]
    if not p then return false end
    return p.isOnline and (GetTime() - (p.lastSeen or 0)) <= OFFLINE_THRESHOLD
end

-- 由心跳/HELLO 摘要更新玩家表
-- 返回 "new" | "updated" | "ignored"
function PeerRegistry.Upsert(summary)
    if not summary or not summary.n or not summary.r then return "ignored" end
    local id = MakeId(summary.r, summary.n)
    if ignored[id] then return "ignored" end

    local isNew = (DB[id] == nil)
    local p = DB[id] or {}

    -- 防作弊：累计值必须单调不减
    if p.fc and summary.fc and summary.fc < p.fc then summary.fc = p.fc end
    if p.gc and summary.gc and summary.gc < p.gc then summary.gc = p.gc end
    -- 防作弊：检测 1 秒内的异常暴涨
    if p.fc and summary.fc and summary.ts and p.ts then
        local dt = summary.ts - p.ts
        if dt > 0 and (summary.fc - p.fc) / dt > SUSPICIOUS_JUMP then
            p.suspect = true
        end
    end

    p.id        = id
    p.n         = summary.n
    p.r         = summary.r
    p.c         = summary.c or p.c
    p.l         = summary.l or p.l
    p.z         = summary.z or p.z
    p.fc        = summary.fc or p.fc or 0
    p.fd        = summary.fd or p.fd or 0
    p.gc        = summary.gc or p.gc or 0
    p.gd        = summary.gd or p.gd or 0
    p.pt        = summary.pt or p.pt
    p.ts        = summary.ts or p.ts   -- 记录上次上报的 Unix 时间戳，供防作弊增量判断
    p.lastSeen  = GetTime()
    p.isOnline  = true
    p.suspect   = p.suspect or false
    DB[id] = p
    return isNew and "new" or "updated"
end

-- 主动离线通知（收到 L 消息）
function PeerRegistry.MarkOffline(id)
    local p = DB[id]
    if p then p.isOnline = false end
end

-- 全部标记离线（本机退出/掉线）
function PeerRegistry.MarkAllOffline()
    for _, p in pairs(DB) do p.isOnline = false end
end

-- 周期性刷新在线标志（由 CommCore ticker 调用）
function PeerRegistry.RefreshOnline()
    local now = GetTime()
    for _, p in pairs(DB) do
        p.isOnline = (now - (p.lastSeen or 0)) <= OFFLINE_THRESHOLD
    end
end

function PeerRegistry.RemovePeer(id)
    DB[id] = nil
end

function PeerRegistry.IsIgnored(id)
    return ignored[id] == true
end

function PeerRegistry.SetIgnored(id, flag)
    ignored[id] = flag
end

function PeerRegistry.GetIgnored()
    return ignored
end

FishingMasterComm._PeerRegistry = PeerRegistry
