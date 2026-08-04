-- ============================================================================
-- Protocol.lua  —  渔友圈通信协议层
-- 负责：消息类型定义、协议版本、序列化（AceSerializer + Base64 封装，确保安全传输）
-- 不持有状态，纯工具模块。
-- ============================================================================
local MAJOR = "FishingMasterComm"
local FishingMasterComm = _G[MAJOR] or {}
_G[MAJOR] = FishingMasterComm

local AceSerializer = LibStub("AceSerializer-3.0")

local Protocol = {}

-- addon message 前缀（频道内其他插件不会识别）
Protocol.PREFIX = "FM"
-- 协议版本（未来兼容预留）
Protocol.VERSION = 1
-- 频道名（伪装为通用数据同步，与钓鱼无关）
Protocol.CHANNEL_NAME = "RealmDataSync"

-- 消息类型
Protocol.MSG = {
    HEARTBEAT = "H",   -- 广播：自身摘要
    LEAVE     = "L",   -- 广播：主动离线通知
    HELLO     = "HELLO", -- 广播：新玩家加入，触发老玩家回应
    QUERY     = "Q",   -- 广播：查询请求（如 Q:PRICE:鱼名）
    RESPONSE  = "R",   -- 单播：响应回复（如 R:PRICE:鱼名:价格:Tier）
}

-- ---------------------------------------------------------------------------
-- Base64 编解码
-- 原因：AceSerializer 输出可能包含控制字符，且角色/服务器名含 UTF-8 多字节；
--       经 Base64 后仅含 [A-Za-z0-9+/=]，可安全穿过 SendAddonMessage 字符集限制。
-- ---------------------------------------------------------------------------
-- 使用 URL-safe Base64 字母表（- 与 _ 替代 + 与 /），避开 SendAddonMessage 可能限制的字符
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64_REV = {}
for i = 1, #B64 do B64_REV[B64:sub(i, i)] = i - 1 end

function Protocol.Base64Encode(input)
    local output = ""
    local len = #input
    local i = 1
    while i <= len do
        local b1, b2, b3 = input:byte(i, i + 2)
        b2 = b2 or 0
        b3 = b3 or 0
        local n = b1 * 65536 + b2 * 256 + b3
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        output = output .. B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
        if i + 1 <= len then output = output .. B64:sub(c3 + 1, c3 + 1) else output = output .. "=" end
        if i + 2 <= len then output = output .. B64:sub(c4 + 1, c4 + 1) else output = output .. "=" end
        i = i + 3
    end
    return output
end

function Protocol.Base64Decode(input)
    input = (input or ""):gsub("[^%w-_=]", "")
    local output = ""
    local len = #input
    local i = 1
    while i <= len do
        local c1 = B64_REV[input:sub(i, i)] or 0
        local c2 = B64_REV[input:sub(i + 1, i + 1)] or 0
        local c3 = B64_REV[input:sub(i + 2, i + 2)] or 0
        local c4 = B64_REV[input:sub(i + 3, i + 3)] or 0
        local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
        output = output .. string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
        i = i + 4
    end
    return output
end

-- 序列化 payload -> 可发送字符串
function Protocol.Encode(data)
    local ok, s = pcall(function() return AceSerializer:Serialize(data) end)
    if not ok or not s then return nil end
    return Protocol.Base64Encode(s)
end

-- 反序列化接收到的字符串 -> payload（失败返回 nil）
function Protocol.Decode(str)
    if not str or str == "" then return nil end
    local decoded = Protocol.Base64Decode(str)
    -- AceSerializer:Deserialize 返回 (true, value) 或 (false, errmsg)
    local ok, success, data = pcall(AceSerializer.Deserialize, AceSerializer, decoded)
    if not ok or not success or data == nil then return nil end
    return data
end

-- ---------------------------------------------------------------------------
-- 职业缩写（zhCN）
-- ---------------------------------------------------------------------------
Protocol.CLASS_ABBR = {
    WARRIOR     = "战", MAGE      = "法", ROGUE     = "贼", PRIEST    = "牧",
    DRUID       = "德", HUNTER    = "猎", SHAMAN    = "萨", PALADIN   = "骑",
    WARLOCK     = "术", DEATHKNIGHT = "死", MONK     = "僧", DEMONHUNTER = "DH",
    EVOKER      = "唤",
}

function Protocol.ClassAbbr(token)
    return Protocol.CLASS_ABBR[token or ""] or (token or "?"):sub(1, 1)
end

-- 价格 Tier 文案
Protocol.TIER_LABEL = {
    [1] = "市场价",
    [2] = "历史价",
    [3] = "售价",
}

FishingMasterComm.Protocol = Protocol
