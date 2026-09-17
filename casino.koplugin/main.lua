local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")
local RenderText = require("ui/rendertext")
local Font = require("ui/font")

local StatusBar = require("statusbar")
local Switcher = require("switcher")
local Dice = require("games.dice")
local Poker = require("games.poker")
local PokerAI = require("games.poker_ai")
local Blackjack = require("games.blackjack")
local Durak = require("games.durak")

local WIN_FACE   = Blitbuffer.Color8(0xC0)
local WIN_SHADOW = Blitbuffer.Color8(0x80)
local WIN_LIGHT  = Blitbuffer.COLOR_WHITE
local WIN_TEXT   = Blitbuffer.COLOR_BLACK

local Casino = InputContainer:extend{
    name = "casino",
}

function Casino:init()
    self.ui.menu:registerToMainMenu(self)

    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/casino.lua")
    self.balance = self.settings:readSetting("balance", 1000)

    self.layout = nil
    self.current = "dice"
    self.start_menu_open = false
    self.menu_zones = {}
end

function Casino:addToMainMenu(menu_items)
    menu_items.casino = {
        text = _("Казино"),
        sorting_hint = "more_tools",
        callback = function() self:showCasino() end,
    }
end

function Casino:showCasino()
    self.status_bar = StatusBar:new{
        balance = self.balance,
        on_close = function() self:closeCasino() end,
    }

    self.dice = Dice:new{
        balance = self.balance,
        bet = 10,
        on_result = function(bet, win, new_balance)
            self.balance = new_balance
            self.status_bar:updateBalance(new_balance)
            if self.switcher then self.switcher:updateBalance(new_balance) end
            self:saveBalance()
        end,
        on_bet_change = function(val) end,
    }

    self.blackjack = Blackjack:new{
        balance = self.balance,
        bet = 10,
        on_result = function(bet, win, new_balance)
            self.balance = new_balance
            self.status_bar:updateBalance(new_balance)
            if self.switcher then self.switcher:updateBalance(new_balance) end
            self:saveBalance()
        end,
        on_bet_change = function(val) end,
    }

    self.poker = Poker:new{
        balance = self.balance,
        bet = 10,
        on_result = function(bet, win, new_balance)
            self.balance = new_balance
            self.status_bar:updateBalance(new_balance)
            if self.switcher then self.switcher:updateBalance(new_balance) end
            self:saveBalance()
        end,
        on_bet_change = function(val) end,
    }

    self.poker_ai = PokerAI:new{
        balance = self.balance,
        bet = 10,
        on_result = function(bet, win, new_balance)
            self.balance = new_balance
            self.status_bar:updateBalance(new_balance)
            if self.switcher then self.switcher:updateBalance(new_balance) end
            self:saveBalance()
        end,
        on_bet_change = function(val) end,
    }

    self.durak = Durak:new{
        balance = self.balance,
        bet = 10,
        on_result = function(bet, win, new_balance)
            self.balance = new_balance
            self.status_bar:updateBalance(new_balance)
            if self.switcher then self.switcher:updateBalance(new_balance) end
            self:saveBalance()
        end,
        on_bet_change = function(val) end,
    }

    self.switcher = Switcher:new{
        balance = self.balance,
        on_start = function()
            self.start_menu_open = not self.start_menu_open
            if self.switcher then
                self.switcher:setStartActive(self.start_menu_open)
            end
            if self.layout then
                UIManager:setDirty(self.layout, "ui")
            end
        end,
        on_close = function() self:closeCasino() end,
        on_balance_reset = function() self:resetBalance() end,
    }

    self.layout = self:buildLayout()

    self.status_bar.root_layout = self.layout
    self.dice.root_layout = self.layout
    self.blackjack.root_layout = self.layout
    self.poker.root_layout = self.layout
    self.poker_ai.root_layout = self.layout
    self.durak.root_layout = self.layout
    self.switcher.root_layout = self.layout

    self.switcher:startClock()
    UIManager:show(self.layout)
end

function Casino:currentGame()
    if self.current == "durak" then
        self.durak.balance = self.balance
        return self.durak
    end
    if self.current == "poker_ai" then
        self.poker_ai.balance = self.balance
        return self.poker_ai
    end
    if self.current == "poker" then
        self.poker.balance = self.balance
        return self.poker
    end
    if self.current == "blackjack" then
        self.blackjack.balance = self.balance
        return self.blackjack
    end
    self.dice.balance = self.balance
    return self.dice
end

function Casino:buildLayout()
    local Layout = InputContainer:extend{
        status_bar = self.status_bar,
        switcher = self.switcher,
        casino = self,
        _zones_registered = false,
        _menu_items = {},
    }

    function Layout:paintTo(bb, x, y)
        if not self._zones_registered then
            self._zones_registered = true
            local this = self
            this:registerTouchZones({
                {
                    id = "casino_layout_tap",
                    ges = "tap",
                    screen_zone = {
                        ratio_x = 0, ratio_y = 0,
                        ratio_w = 1, ratio_h = 1,
                    },
                    handler = function(ges)
                        return this:dispatchTap(ges)
                    end,
                },
            })
        end

        local w = bb:getWidth()
        local h = bb:getHeight()
        local sb_h = Screen:scaleBySize(50)
        local sw_h = Screen:scaleBySize(60)
        local game_h = h - sb_h - sw_h

        bb:paintRect(x, y, w, h, WIN_FACE)

        self.status_bar:paintTo(bb, x, y)

        local game = self.casino:currentGame()
        game.height = game_h
        game:paintTo(bb, x, y + sb_h)

        self.switcher:paintTo(bb, x, y + sb_h + game_h)

        if self.casino.start_menu_open then
            self:paintStartMenu(bb, x, y, w, h, sb_h, sw_h)
        end
    end

    function Layout:paintStartMenu(bb, x, y, w, h, sb_h, sw_h)
        local menu_w = Screen:scaleBySize(250)
        local item_h = Screen:scaleBySize(50)
        local items = {
            { label = "Кости", action = "dice" },
            { label = "21", action = "blackjack" },
            { label = "Покер", action = "poker" },
            { label = "Покер с ИИ", action = "poker_ai" },
            { label = "Дурак", action = "durak" },
            { label = "-", action = "separator" },
            { label = "Выключение казино", action = "close" },
        }

        local menu_h = #items * item_h + Screen:scaleBySize(8)
        local mx = x + Screen:scaleBySize(5)
        local my = y + h - sw_h - menu_h

        bb:paintRect(mx, my, menu_w, menu_h, WIN_FACE)
        bb:paintRect(mx, my, menu_w, 2, WIN_LIGHT)
        bb:paintRect(mx, my, 2, menu_h, WIN_LIGHT)
        bb:paintRect(mx, my + menu_h - 2, menu_w, 2, WIN_SHADOW)
        bb:paintRect(mx + menu_w - 2, my, 2, menu_h, WIN_SHADOW)

        local menu_font = Font:getFace("cfont", 20)
        local i, item
        for i, item in ipairs(items) do
            local iy = my + (i - 1) * item_h + Screen:scaleBySize(4)
            if item.action == "separator" then
                bb:paintRect(mx + 4, iy + item_h / 2, menu_w - 8, 2, WIN_SHADOW)
                bb:paintRect(mx + 4, iy + item_h / 2 + 2, menu_w - 8, 1, WIN_LIGHT)
            else
                local is_active = (item.action == self.casino.current)
                if is_active then
                    bb:paintRect(mx + 4, iy, menu_w - 8, item_h, WIN_SHADOW)
                end
                local color = is_active and WIN_LIGHT or WIN_TEXT
                RenderText:renderUtf8Text(bb, mx + Screen:scaleBySize(12),
                    iy + item_h / 2 + 7, menu_font, item.label, false, false, color)
            end
        end

        self._menu_items = {}
        for i, item in ipairs(items) do
            local iy = my + (i - 1) * item_h + Screen:scaleBySize(4)
            self._menu_items[#self._menu_items + 1] = {
                x = mx, y = iy, w = menu_w, h = item_h, action = item.action,
            }
        end
    end

    function Layout:dispatchTap(ges)
        if self.casino.start_menu_open then
            local pos = ges.pos
            local item
            for _, item in ipairs(self._menu_items) do
                if pos.x >= item.x and pos.x <= item.x + item.w
                   and pos.y >= item.y and pos.y <= item.y + item.h then
                    if item.action == "close" then
                        self.casino:closeCasino()
                    elseif item.action == "separator" then
                    else
                        self.casino.current = item.action
                        self.casino.start_menu_open = false
                        if self.casino.switcher then
                            self.casino.switcher:setStartActive(false)
                        end
                        UIManager:setDirty(self, "ui")
                    end
                    return true
                end
            end
            self.casino.start_menu_open = false
            if self.casino.switcher then
                self.casino.switcher:setStartActive(false)
            end
            UIManager:setDirty(self, "ui")
            return true
        end

        if self.status_bar:onTap(ges) then return true end
        local game = self.casino:currentGame()
        if game:onTap(ges) then return true end
        if self.switcher:onTap(ges) then return true end
        return true
    end

    return Layout:new{}
end

function Casino:saveBalance()
    self.settings:saveSetting("balance", self.balance)
    self.settings:flush()
end

function Casino:resetBalance()
    self.balance = 1000
    self:saveBalance()
    if self.status_bar then self.status_bar.balance = 1000 end
    if self.switcher then self.switcher:updateBalance(1000) end
    if self.dice then self.dice.balance = 1000 end
    if self.blackjack then self.blackjack.balance = 1000 end
    if self.poker then self.poker.balance = 1000 end
    if self.poker_ai then self.poker_ai.balance = 1000 end
    if self.durak then self.durak.balance = 1000 end
    if self.layout then UIManager:setDirty(self.layout, "ui") end
end

function Casino:closeCasino()
    self:saveBalance()
    if self.switcher then self.switcher:stopClock() end
    if self.layout then UIManager:close(self.layout) end
    self.layout = nil
    self.status_bar = nil
    self.dice = nil
    self.blackjack = nil
    self.poker = nil
    self.poker_ai = nil
    self.durak = nil
    self.switcher = nil
    self.start_menu_open = false
end

return Casino