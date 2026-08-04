-- ============================================================================
-- CommCore.lua  —  通信核心
-- 负责：频道加入/退出、心跳与握手、消息收发、离线检测、自动重连。
-- 暴露全局表 FishingMasterComm（facade），供 FishingMaster.lua 的钩子与 UI 调用。
-- ============================================================================
local MAJOR = "FishingMasterComm"
local FishingMasterComm = _G[MAJOR] or {}
_G[MAJOR] = FishingMasterComm

local AceComm = LibStub("AceComm-3.0")
local Protocol = FishingMasterComm.Protocol
local PeerRegistry = FishingMasterComm.PeerRegistry

-- 私有状态
local state = {
    db          = nil,   -- LootStatsDB
    comm        = nil,   -- LootStatsDB.comm
    enabled     = false, -- 用户是否开启（持久化）
    running     = false, -- 是否已成功加入频道并运行
    channelID   = 0,
    channelName = "RealmDataSync",
    retryCount  = 0,
    retryHandle = nil,
    heartbeatTimer = nil,
    offlineTimer   = nil,
    firstDelay     = nil,
}
FishingMasterComm._state = state

local frame = CreateFrame("Frame")
FishingMasterComm._frame = frame

-- ---------------------------------------------------------------------------
-- 自身摘要
-- ---------------------------------------------------------------------------
local function GetSelfSummary(msgType)
    local comm = state.comm
    local today = date("%Y-%m-%d")
    local daily = (state.db.dailyStats and state.db.dailyStats[today]) or { totalPickups = 0, totalCopper = 0 }
    local total = state.db.totalStats or { totalPickups = 0, totalCopper = 0 }
    local _, classToken = UnitClass("player")
    local pt = (Auctionator and Auctionator.API and Auctionator.API.v1) and 1 or 3
    return {
        t  = msgType or Protocol.MSG.HEARTBEAT,
        v  = Protocol.VERSION,
        n  = UnitName("player"),
        r  = GetRealmName(),
        c  = classToken,
        l  = UnitLevel("player"),
        z  = GetMinimapZoneText() or "",
        fc = total.totalPickups or 0,
        fd = daily.totalPickups or 0,
        gc = total.totalCopper or 0,
        gd = daily.totalCopper or 0,
        pt = pt,
        ts = time(),
    }
end
FishingMasterComm.GetSelfSummary = GetSelfSummary

-- ---------------------------------------------------------------------------
-- 发送
-- ---------------------------------------------------------------------------
local function SendChannel(payload)
    if not state.running or state.channelID == 0 then return end
    local msg = Protocol.Encode(payload)
    if not msg or #msg > 240 then return end  -- 预留 AceComm 头部空间
    AceComm:SendCommMessage(Protocol.PREFIX, msg, "CHANNEL", state.channelID, "BULK")
end

local function SendWhisper(payload, target)
    if not target then return end
    local msg = Protocol.Encode(payload)
    if not msg or #msg > 240 then return end
    AceComm:SendCommMessage(Protocol.PREFIX, msg, "WHISPER", target, "BULK")
end

-- ---------------------------------------------------------------------------
-- 初始化（由 FishingMaster.lua ADDON_LOADED 钩子调用）
-- ---------------------------------------------------------------------------
function FishingMasterComm:Initialize(LootStatsDB)
    state.db = LootStatsDB
    if not LootStatsDB.comm then LootStatsDB.comm = {} end
    local comm = LootStatsDB.comm
    if comm.enabled == nil then comm.enabled = false end
    if comm.channelName == nil then comm.channelName = "RealmDataSync" end
    if comm.broadcastGold == nil then comm.broadcastGold = true end
    if comm.lastSelfReport == nil then comm.lastSelfReport = 0 end
    if comm.ignored == nil then comm.ignored = {} end
    if not LootStatsDB.commPeers then LootStatsDB.commPeers = {} end
    if not LootStatsDB.priceBook then LootStatsDB.priceBook = {} end

    state.comm = comm
    state.channelName = comm.channelName

    PeerRegistry.Init(LootStatsDB.commPeers, comm.ignored)

    AceComm:RegisterComm(Protocol.PREFIX, function(_, message, distribution, sender)
        FishingMasterComm:OnMessage(message, distribution, sender)
    end)

    frame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    frame:RegisterEvent("CHAT_MSG_SYSTEM")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:RegisterEvent("PLAYER_LEAVING_WORLD")
    frame:SetScript("OnEvent", function(_, event, ...)
        FishingMasterComm:OnEvent(event, ...)
    end)

    -- 若用户曾开启，则载入即自动重连（配置已持久化）
    if comm.enabled then
        FishingMasterComm:Enable()
    end

    -- 便捷命令：/fm 开关渔友圈面板
    SLASH_FMNET1 = "/fm"
    function SlashCmdList.FMNET()
        FishingMasterComm:ToggleMainPanel()
    end

    -- 诊断命令：/fmtest 测试通信是否正常工作
    SLASH_FMTEST1 = "/fmtest"
    function SlashCmdList.FMTEST()
        local c = FishingMasterComm
        if not c then
            print("|cffff0000[FishingMaster 测试]|r FishingMasterComm 未载入")
            return
        end
        local P = c.Protocol
        local R = c.PeerRegistry
        print("|cff00ff00[FishingMaster 通信测试]|r ==========")

        -- 1) 序列化往返（不需要网络，验证 Encode/Decode + Base64 链路）
        local sample = { t = P.MSG.HEARTBEAT, v = P.VERSION, n = "TestBot", r = "Realm",
            c = "WARRIOR", l = 60, z = "测试", fc = 123, fd = 45, gc = 67890, gd = 12, ts = time() }
        local enc = P.Encode(sample)
        local dec = P.Decode(enc)
        local rtOK = dec and type(dec) == "table" and dec.n == "TestBot"
            and dec.fc == 123 and dec.gc == 67890 and dec.c == "WARRIOR"
        print("  1) 序列化往返: " .. (rtOK and "|cff00ff00通过|r" or "|cffff0000失败|r")
            .. "  (长度 " .. (enc and #enc or 0) .. " 字符)")

        -- 2) 前缀与版本
        print("  2) 通信前缀: " .. P.PREFIX .. "  协议版本: v" .. P.VERSION)

        -- 3) 运行状态
        print("  3) 启用: " .. (c:IsEnabled() and "是" or "否")
            .. "  运行: " .. (c:IsRunning() and "是" or "否"))
        print("  4) 频道名: " .. (state.channelName or "?")
            .. "  频道ID: " .. (state.channelID or 0))

        -- 5) 已知/在线玩家
        local peers, online = R:GetAll(), R:GetOnline()
        print("  5) 已知玩家: " .. #peers .. "  当前在线: " .. #online)

        -- 6) 若已加入频道，广播一次 HELLO 探测，让同频道其他人回心跳
        if c:IsRunning() then
            c:SendHello()
            print("  6) 已广播 HELLO 探测包，|cff00ff00几秒后观察『在线玩家』是否增加|r")
            print("     也可用 /fm 打开面板查看排行与鱼价是否刷新")
        else
            print("  6) 未加入频道：先输入 |cffffcc00/fm|r 开启渔友圈，再运行 /fmtest")
        end
        print("|cff00ff00[FishingMaster 通信测试]|r ==========")
    end
end

-- ---------------------------------------------------------------------------
-- 启用 / 禁用
-- ---------------------------------------------------------------------------
function FishingMasterComm:Enable()
    if state.running then return true end
    state.enabled = true
    if state.db and state.db.comm then state.db.comm.enabled = true end
    state.retryCount = 0
    self:JoinChannel()
    return true
end

function FishingMasterComm:Disable()
    self:SendLeave()
    if state.channelID and state.channelID ~= 0 then
        LeaveChannelByName(state.channelName)
    end
    self:StopTimers()
    state.running = false
    state.enabled = false
    if state.db and state.db.comm then state.db.comm.enabled = false end
    PeerRegistry.MarkAllOffline()
    self:NotifyUIUpdate()
end

function FishingMasterComm:IsEnabled() return state.enabled end
function FishingMasterComm:IsRunning() return state.running end

-- ---------------------------------------------------------------------------
-- 频道加入
-- ---------------------------------------------------------------------------
function FishingMasterComm:JoinChannel()
    state.running = false
    JoinChannelByName(state.channelName)
    -- 兜底：3 秒后若仍无 YOU_JOINED 事件，则主动检查
    if state.retryHandle then state.retryHandle:Cancel() end
    state.retryHandle = C_Timer.After(3, function()
        if not state.running then
            local id = GetChannelName(state.channelName)
            if id and id > 0 then
                state.channelID = id
                self:OnJoined()
            else
                self:ScheduleReconnect()
            end
        end
    end)
end

function FishingMasterComm:OnJoined()
    if state.running then return end
    state.running = true
    state.retryCount = 0
    state.channelID = GetChannelName(state.channelName) or state.channelID

    if not state.offlineTimer then
        state.offlineTimer = C_Timer.NewTicker(5, function() PeerRegistry.RefreshOnline() end)
    end

    -- 首次启动延迟 random(0,10) 秒
    local delay = math.random(0, 10)
    if state.firstDelay then state.firstDelay:Cancel() end
    state.firstDelay = C_Timer.After(delay, function()
        self:SendHello()
        self:ScheduleNextHeartbeat()
    end)

    print("|cff00ff00[FishingMaster 渔友圈]|r 已加入频道 " .. state.channelName)
    if self.BasicPanel and self.BasicPanel.OnCommStateChanged then
        self.BasicPanel:OnCommStateChanged(true)
    end
    self:NotifyUIUpdate()
end

function FishingMasterComm:SendHello()
    SendChannel(GetSelfSummary(Protocol.MSG.HELLO))
end

function FishingMasterComm:SendHeartbeat()
    SendChannel(GetSelfSummary(Protocol.MSG.HEARTBEAT))
    if state.db and state.db.comm then state.db.comm.lastSelfReport = time() end
    self:ScheduleNextHeartbeat()
end

-- 基础间隔 30s ± 5s 随机抖动
function FishingMasterComm:ScheduleNextHeartbeat()
    if state.heartbeatTimer then state.heartbeatTimer:Cancel() end
    local interval = 30 + math.random(-5, 5)
    state.heartbeatTimer = C_Timer.NewTimer(interval, function() self:SendHeartbeat() end)
end

function FishingMasterComm:SendLeave()
    SendChannel({
        t = Protocol.MSG.LEAVE, v = Protocol.VERSION,
        n = UnitName("player"), r = GetRealmName(), ts = time(),
    })
end

-- ---------------------------------------------------------------------------
-- 消息接收
-- ---------------------------------------------------------------------------
function FishingMasterComm:OnMessage(message, distribution, sender)
    local data = Protocol.Decode(message)
    if not data or type(data) ~= "table" then return end
    if not data.v or data.v > Protocol.VERSION then return end  -- 版本不兼容，静默丢弃

    -- 忽略自己
    if data.n == UnitName("player") and data.r == GetRealmName() then return end

    local id = (data.r and data.n) and (data.r .. ":" .. data.n) or nil
    if id and PeerRegistry.IsIgnored(id) then return end

    local t = data.t
    if t == Protocol.MSG.HEARTBEAT or t == Protocol.MSG.HELLO then
        local res = PeerRegistry.Upsert(data)
        if t == Protocol.MSG.HELLO then
            -- 老玩家延迟 random(0,2) 秒回一次正常心跳
            C_Timer.After(math.random(0, 2), function()
                SendChannel(GetSelfSummary(Protocol.MSG.HEARTBEAT))
            end)
        end
        self:NotifyUIUpdate()
    elseif t == Protocol.MSG.LEAVE then
        if id then PeerRegistry.MarkOffline(id) end
        self:NotifyUIUpdate()
    elseif t == Protocol.MSG.QUERY then
        self:OnQuery(data, sender)
    elseif t == Protocol.MSG.RESPONSE then
        self:OnResponse(data)
    end
end

function FishingMasterComm:OnQuery(data, sender)
    if data.q ~= "PRICE" or not data.item then return end
    local book = state.db and state.db.priceBook
    local entry = book and book[data.item]
    if entry and entry.price and entry.price > 0 then
        SendWhisper({
            t = Protocol.MSG.RESPONSE, v = Protocol.VERSION,
            q = "PRICE", item = data.item,
            price = entry.price, tier = entry.tier or 3,
            ts = time(),
        }, sender)
    end
end

function FishingMasterComm:OnResponse(data)
    if data.q ~= "PRICE" or not data.item then return end
    if FishingMasterComm.StatsSync then
        FishingMasterComm.StatsSync:MergePrice(data.item, data.price, data.tier, data.n, data.r, data.ts)
        self:NotifyUIUpdate()
    end
end

-- 广播价格查询（供 UI 调用）
function FishingMasterComm:QueryPrice(itemName)
    if not itemName or itemName == "" then return end
    SendChannel({ t = Protocol.MSG.QUERY, v = Protocol.VERSION, q = "PRICE", item = itemName, ts = time() })
end

-- ---------------------------------------------------------------------------
-- 事件处理
-- ---------------------------------------------------------------------------
function FishingMasterComm:OnEvent(event, ...)
    if event == "CHAT_MSG_CHANNEL_NOTICE" then
        local notice, _, _, _, _, _, _, chanName = ...
        if chanName ~= state.channelName then return end
        if notice == "YOU_JOINED" then
            state.channelID = GetChannelName(state.channelName) or state.channelID
            self:OnJoined()
        elseif notice == "YOU_LEFT" then
            state.running = false
        elseif notice == "WRONG_PASSWORD" or notice == "BANNED" or notice == "INVALID_NAME" then
            self:ScheduleReconnect()
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = ...
        if msg and msg:find(state.channelName) and (msg:find("离开") or msg:find("left") or msg:find("kicked") or msg:find("removed")) then
            state.running = false
            self:ScheduleReconnect()
        end
    elseif event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
        self:SendLeave()
    end
end

-- 指数退避重连 10s → 30s → 60s
function FishingMasterComm:ScheduleReconnect()
    if not state.enabled then return end
    state.retryCount = math.min(state.retryCount + 1, 3)
    local delays = { 10, 30, 60 }
    local d = delays[state.retryCount] or 60
    print("|cffff0000[FishingMaster 渔友圈]|r 频道连接失败，" .. d .. " 秒后重试...")
    if state.retryHandle then state.retryHandle:Cancel() end
    state.retryHandle = C_Timer.After(d, function() self:JoinChannel() end)
end

function FishingMasterComm:StopTimers()
    if state.heartbeatTimer then state.heartbeatTimer:Cancel(); state.heartbeatTimer = nil end
    if state.offlineTimer then state.offlineTimer:Cancel(); state.offlineTimer = nil end
    if state.firstDelay then state.firstDelay:Cancel(); state.firstDelay = nil end
end

-- ---------------------------------------------------------------------------
-- 忽略
-- ---------------------------------------------------------------------------
function FishingMasterComm:IgnorePeer(id)
    if not id then return end
    PeerRegistry.SetIgnored(id, true)
    PeerRegistry.RemovePeer(id)  -- 立即丢弃其数据
    self:NotifyUIUpdate()
end

function FishingMasterComm:UnignorePeer(id)
    if not id then return end
    PeerRegistry.SetIgnored(id, false)
    self:NotifyUIUpdate()
end

-- ---------------------------------------------------------------------------
-- 钩子：每次拾取后由 FishingMaster.lua 调用
-- ---------------------------------------------------------------------------
function FishingMasterComm:NotifyLoot(itemsInThisLoot, totalCopperForLog)
    if not state.db then return end
    if FishingMasterComm.StatsSync then
        FishingMasterComm.StatsSync:RecordSelfPrices()
    end
end

-- ---------------------------------------------------------------------------
-- UI 控制
-- ---------------------------------------------------------------------------
function FishingMasterComm:NotifyUIUpdate()
    if self.BasicPanel and self.BasicPanel.Refresh then self.BasicPanel:Refresh() end
    if self.AdvancedPanel and self.AdvancedPanel.Refresh then self.AdvancedPanel:Refresh() end
end

function FishingMasterComm:IsPanelOpen()
    return self.BasicPanel and self.BasicPanel:IsOpen() or false
end

function FishingMasterComm:ToggleMainPanel()
    if not state.enabled then
        self:PromptEnable()
        return false
    end
    if self.BasicPanel then
        return self.BasicPanel:Toggle()
    end
    return false
end

function FishingMasterComm:PromptEnable()
    StaticPopupDialogs["FM_COMM_ENABLE"] = StaticPopupDialogs["FM_COMM_ENABLE"] or {
        text = "是否加入 " .. state.channelName .. " 频道并开启渔友圈？\n频道名已伪装为通用数据同步，仅与同服在线玩家共享你的钓鱼数与金币。",
        button1 = "开启",
        button2 = "取消",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function()
            FishingMasterComm:Enable()
            if FishingMasterComm.BasicPanel then FishingMasterComm.BasicPanel:Show() end
        end,
    }
    StaticPopup_Show("FM_COMM_ENABLE")
end

-- ---------------------------------------------------------------------------
-- 加载高级版（如已安装）
-- ---------------------------------------------------------------------------
function FishingMasterComm:TryLoadPro()
    local name = "FishingMasterPro"
    -- 现代客户端(10.x+/Interface>=100000)已将 LoadAddOn 移入 C_AddOns 命名空间，
    -- 旧全局 LoadAddOn 被移除（为 nil），这里做兼容。
    local loader
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        loader = C_AddOns.LoadAddOn
    elseif type(LoadAddOn) == "function" then
        loader = LoadAddOn
    end

    local ok = loader and loader(name)
    if ok then
        if self.AdvancedPanel and self.AdvancedPanel.Init then
            self.AdvancedPanel:Init()
        end
        return true
    end

    -- 给出明确原因，便于排查
    if C_AddOns and type(C_AddOns.GetAddOnInfo) == "function" then
        local _, title, _, loadable, reason = C_AddOns.GetAddOnInfo(name)
        if title then
            if not loadable then
                print("|cffff0000[FishingMaster]|r 高级版 " .. tostring(title)
                    .. " 已安装但被禁用(reason=" .. tostring(reason) .. ")，请在插件列表启用后重载。")
                return false
            end
        else
            print("|cffff0000[FishingMaster]|r 未找到高级版 FishingMasterPro（需单独安装到 AddOns 目录并启用）。")
            return false
        end
    end
    print("|cffff0000[FishingMaster]|r 未找到高级版 FishingMasterPro（需单独安装并启用）。")
    return false
end
