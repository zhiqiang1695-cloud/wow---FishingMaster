-- ============================================================================
-- PublicAPI.lua  —  暴露给高级版（FishingMasterPro）的全局 API
-- 高级版通过 FishingMasterAPI 读取渔友圈，不直接访问内部模块。
-- ============================================================================
local MAJOR = "FishingMasterComm"
local FishingMasterComm = _G[MAJOR]
if not FishingMasterComm then return end

local PeerRegistry = FishingMasterComm.PeerRegistry
local StatsSync = FishingMasterComm.StatsSync

-- 暴露到全局（高级版依赖此表）
FishingMasterAPI = {
    -- 返回所有已知玩家（含离线）
    GetPeers      = function() return PeerRegistry:GetAll() end,
    -- 返回在线玩家
    GetOnlinePeers = function() return PeerRegistry:GetOnline() end,
    -- dim = "fishCount" | "gold"，返回 { rank, total, value }
    GetSelfRank   = function(dim) return StatsSync:GetSelfRank(dim or "fishCount") end,
    -- 鱼价手册（按鱼名索引）
    GetPriceBook  = function() return StatsSync:GetPriceBook() end,
    -- 频道汇总 { online, known, todayGold, avgFish, avgGold, maxFish }
    GetChannelStats = function() return StatsSync:GetChannelStats() end,
    -- 通信是否运行中
    IsEnabled     = function() return FishingMasterComm:IsRunning() end,
    -- 用户是否开启
    IsCommEnabled = function() return FishingMasterComm:IsEnabled() end,
    -- 忽略 / 取消忽略某玩家（id = "realm:name"）
    IgnorePeer    = function(id) return FishingMasterComm:IgnorePeer(id) end,
    UnignorePeer  = function(id) return FishingMasterComm:UnignorePeer(id) end,
    -- 刷新鱼价
    QueryPrice    = function(item) return FishingMasterComm:QueryPrice(item) end,
    QueryAllKnownPrices = function() return StatsSync:QueryAllKnownPrices() end,
    -- 协议/频道信息
    GetChannelName = function() return FishingMasterComm._state and FishingMasterComm._state.channelName end,
}
