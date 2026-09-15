local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local Font = require("ui/font")
local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")

local WIN_FACE   = Blitbuffer.Color8(0xC0)
local WIN_SHADOW = Blitbuffer.Color8(0x80)
local WIN_LIGHT  = Blitbuffer.COLOR_WHITE
local WIN_TEXT   = Blitbuffer.COLOR_BLACK

local Poker = InputContainer:extend{
    balance = 1000,
    bet = 10,
    phase = "idle",
    cards = {},
    held = {},
    deck = {},
    status = "Нажмите РАЗДАТЬ",
    on_result = nil,
    on_bet_change = nil,
    root_layout = nil,
    offset_y = 0,
    height = 0,

    z_card_y = 0,
    z_card_h = 0,
    z_card_w = 0,
    z_card_gap = 0,
    z_card_start_x = 0,

    z_btn_w = 0,
    z_btn_h = 0,
    z_btn_x = 0,
    z_btn_y = 0,

    z_bet_btn_w = 0,
    z_bet_btn_h = 0,
    z_bet_gap = 0,
    z_bet_start_x = 0,
    z_bet_y = 0,
}

local SUITS = {"♠", "♥", "♦", "♣"}
local RANKS = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}
local BET_VALUES = {5, 10, 25, 50}

local BTN_DRAW  = "РАЗДАТЬ"
local BTN_DRAW2 = "ОБМЕН"

function Poker:init()
end

function Poker:refresh()
    if self.root_layout then
        UIManager:setDirty(self.root_layout, "ui")
    else
        UIManager:setDirty(self, "ui")
    end
end

function Poker:newDeck()
    local d = {}
    local i, j
    for i = 1, #SUITS do
        for j = 1, #RANKS do
            d[#d + 1] = RANKS[j] .. SUITS[i]
        end
    end
    for i = #d, 2, -1 do
        local k = math.random(i)
        d[i], d[k] = d[k], d[i]
    end
    return d
end

function Poker:rankValue(card)
    local first = card:sub(1, 1)
    if first == "A" then return 14 end
    if first == "K" then return 13 end
    if first == "Q" then return 12 end
    if first == "J" then return 11 end
    if first == "1" and card:sub(2, 2) == "0" then return 10 end
    return tonumber(first) or 0
end

function Poker:suitOf(card)
    return card:sub(-1)
end

function Poker:evaluate(cards)
    local values = {}
    local counts = {}
    local i, v
    for i = 1, #cards do
        v = self:rankValue(cards[i])
        values[#values + 1] = v
        counts[v] = (counts[v] or 0) + 1
    end
    table.sort(values)

    local flush = true
    for i = 2, #cards do
        if self:suitOf(cards[i]) ~= self:suitOf(cards[1]) then
            flush = false
            break
        end
    end

    local straight = true
    for i = 2, #values do
        if values[i] ~= values[i - 1] + 1 then
            straight = false
            break
        end
    end
    local wheel = (values[1] == 2 and values[2] == 3 and values[3] == 4
        and values[4] == 5 and values[5] == 14)
    if wheel then straight = true end

    local quads, trips, pair_list = {}, {}, {}
    local k, n
    for k, n in pairs(counts) do
        if n == 4 then quads[#quads + 1] = k
        elseif n == 3 then trips[#trips + 1] = k
        elseif n == 2 then pair_list[#pair_list + 1] = k end
    end

    if straight and flush and values[1] == 10 then
        return { name = "РОЯЛ-ФЛЕШ", payout = 250 }
    end
    if straight and flush then
        return { name = "СТРИТ-ФЛЕШ", payout = 50 }
    end
    if #quads == 1 then
        return { name = "КАРЕ", payout = 25 }
    end
    if #trips == 1 and #pair_list == 1 then
        return { name = "ФУЛЛ-ХАУС", payout = 9 }
    end
    if flush then
        return { name = "ФЛЕШ", payout = 6 }
    end
    if straight then
        return { name = "СТРИТ", payout = 4 }
    end
    if #trips == 1 then
        return { name = "ТРОЙКА", payout = 3 }
    end
    if #pair_list >= 2 then
        return { name = "ДВЕ ПАРЫ", payout = 2 }
    end
    if #pair_list == 1 then
        for _, p in ipairs(pair_list) do
            if p >= 11 then
                return { name = "ПАРА (J+)", payout = 1 }
            end
        end
    end
    return { name = "НИЧЕГО", payout = 0 }
end

function Poker:draw()
    if self.balance < self.bet then
        self.status = "Недостаточно средств!"
        self:refresh()
        return
    end

    self.balance = self.balance - self.bet
    if self.on_result then
        self.on_result(self.bet, 0, self.balance)
    end

    self.deck = self:newDeck()
    self.cards = {}
    self.held = {}
    local i
    for i = 1, 5 do
        self.cards[i] = table.remove(self.deck)
        self.held[i] = false
    end

    self.phase = "hold"
    self.status = "Отметьте карты, затем ОБМЕН"
    self:refresh()
end

function Poker:exchange()
    if self.phase ~= "hold" then return end

    local i
    for i = 1, 5 do
        if not self.held[i] then
            self.cards[i] = table.remove(self.deck)
        end
    end

    self.phase = "done"

    local result = self:evaluate(self.cards)
    if result.payout > 0 then
        local win = self.bet * result.payout
        self.balance = self.balance + win
        self.status = string.format("%s! ВЫИГРЫШ $%d", result.name, win)
        if self.on_result then
            self.on_result(0, win, self.balance)
        end
    else
        self.status = string.format("%s. Проигрыш.", result.name)
    end

    self:refresh()
end

function Poker:onTap(ges)
    if self.z_card_y == 0 then return false end
    local pos = ges.pos

    -- Карты (только в фазе hold)
    if self.phase == "hold" then
        if pos.y >= self.z_card_y and pos.y <= self.z_card_y + self.z_card_h then
            local i
            for i = 1, 5 do
                local cx = self.z_card_start_x + (i - 1) * (self.z_card_w + self.z_card_gap)
                if pos.x >= cx and pos.x <= cx + self.z_card_w then
                    self.held[i] = not self.held[i]
                    self:refresh()
                    return true
                end
            end
        end
    end

    -- Кнопки ставок (всегда)
    if pos.y >= self.z_bet_y and pos.y <= self.z_bet_y + self.z_bet_btn_h then
        local j, val
        for j, val in ipairs(BET_VALUES) do
            local bx = self.z_bet_start_x + (j - 1) * (self.z_bet_btn_w + self.z_bet_gap)
            if pos.x >= bx and pos.x <= bx + self.z_bet_btn_w then
                self.bet = val
                if self.on_bet_change then self.on_bet_change(val) end
                self:refresh()
                return true
            end
        end
    end

    -- Кнопка РАЗДАТЬ / ОБМЕН
    if pos.y >= self.z_btn_y and pos.y <= self.z_btn_y + self.z_btn_h then
        if pos.x >= self.z_btn_x and pos.x <= self.z_btn_x + self.z_btn_w then
            if self.phase == "idle" or self.phase == "done" then
                self:draw()
            elseif self.phase == "hold" then
                self:exchange()
            end
            return true
        end
    end

    return false
end

function Poker:paintTo(bb, x, y)
    local w = bb:getWidth()
    local game_h = self.height

    self.offset_y = y

    bb:paintRect(x, y, w, game_h, WIN_FACE)

    local card_font   = Font:getFace("cfont", 38)
    local title_font  = Font:getFace("cfont", 24)
    local status_font = Font:getFace("cfont", 22)
    local hold_font   = Font:getFace("cfont", 16)
    local btn_font    = Font:getFace("cfont", 34)
    local bet_font    = Font:getFace("cfont", 26)
    local small_font  = Font:getFace("cfont", 16)

    -- ============================================================
    -- Заголовок
    -- ============================================================
    local title = "ПОКЕР"
    local tw = RenderText:sizeUtf8Text(0, w, title_font, title).x
    RenderText:renderUtf8Text(bb, x + (w - tw) / 2, y + 36,
        title_font, title, false, false, WIN_TEXT)

    -- ============================================================
    -- Карты
    -- ============================================================
    self.z_card_w = Screen:scaleBySize(100)
    self.z_card_h = Screen:scaleBySize(140)
    self.z_card_gap = Screen:scaleBySize(15)
    local total_cards_w = 5 * self.z_card_w + 4 * self.z_card_gap
    self.z_card_start_x = x + (w - total_cards_w) / 2
    self.z_card_y = y + 70

    local i
    for i = 1, 5 do
        local cx = self.z_card_start_x + (i - 1) * (self.z_card_w + self.z_card_gap)
        local cy = self.z_card_y

        if self.phase == "hold" and self.held[i] then
            bb:paintRect(cx, cy, self.z_card_w, self.z_card_h, WIN_SHADOW)
        else
            bb:paintRect(cx, cy, self.z_card_w, self.z_card_h, WIN_LIGHT)
        end
        bb:paintRect(cx, cy, self.z_card_w, 3, WIN_TEXT)
        bb:paintRect(cx, cy + self.z_card_h - 3, self.z_card_w, 3, WIN_TEXT)
        bb:paintRect(cx, cy, 3, self.z_card_h, WIN_TEXT)
        bb:paintRect(cx + self.z_card_w - 3, cy, 3, self.z_card_h, WIN_TEXT)

        local text
        if self.phase == "idle" or not self.cards[i] then
            text = "?"
        else
            text = self.cards[i]
        end

        local color = WIN_TEXT
        if self.phase == "hold" and self.held[i] then
            color = WIN_LIGHT
        end

        local tw2 = RenderText:sizeUtf8Text(0, self.z_card_w, card_font, text).x
        RenderText:renderUtf8Text(bb,
            cx + (self.z_card_w - tw2) / 2,
            cy + self.z_card_h / 2 + 14,
            card_font, text, false, false, color)

        if self.phase == "hold" and self.held[i] then
            local hw = RenderText:sizeUtf8Text(0, self.z_card_w, hold_font, "HOLD").x
            RenderText:renderUtf8Text(bb,
                cx + (self.z_card_w - hw) / 2,
                cy + self.z_card_h - 28,
                hold_font, "HOLD", false, false, WIN_LIGHT)
        end
    end

    -- ============================================================
    -- Статус (под картами)
    -- ============================================================
    local status_y = self.z_card_y + self.z_card_h + 40
    local sw = RenderText:sizeUtf8Text(0, w, status_font, self.status).x
    RenderText:renderUtf8Text(bb, x + (w - sw) / 2, status_y,
        status_font, self.status, false, false, WIN_TEXT)

    -- ============================================================
    -- Кнопка РАЗДАТЬ / ОБМЕН (под статусом)
    -- ============================================================
    self.z_btn_w = Screen:scaleBySize(360)
    self.z_btn_h = Screen:scaleBySize(80)
    self.z_btn_x = x + (w - self.z_btn_w) / 2
    self.z_btn_y = status_y + 30

    local btn_label
    if self.phase == "hold" then btn_label = BTN_DRAW2
    else btn_label = BTN_DRAW end

    bb:paintRect(self.z_btn_x, self.z_btn_y, self.z_btn_w, self.z_btn_h, WIN_FACE)
    bb:paintRect(self.z_btn_x, self.z_btn_y, self.z_btn_w, 2, WIN_LIGHT)
    bb:paintRect(self.z_btn_x, self.z_btn_y, 2, self.z_btn_h, WIN_LIGHT)
    bb:paintRect(self.z_btn_x, self.z_btn_y + self.z_btn_h - 2, self.z_btn_w, 2, WIN_SHADOW)
    bb:paintRect(self.z_btn_x + self.z_btn_w - 2, self.z_btn_y, 2, self.z_btn_h, WIN_SHADOW)

    local blw = RenderText:sizeUtf8Text(0, self.z_btn_w, btn_font, btn_label).x
    RenderText:renderUtf8Text(bb,
        self.z_btn_x + (self.z_btn_w - blw) / 2,
        self.z_btn_y + self.z_btn_h / 2 + 12,
        btn_font, btn_label, false, false, WIN_TEXT)

    -- ============================================================
    -- Таблица выплат (под кнопкой)
    -- ============================================================
    local table_lines = {
        "РОЯЛ-ФЛЕШ 250x    СТРИТ-ФЛЕШ 50x    КАРЕ 25x",
        "ФУЛЛ-ХАУС 9x    ФЛЕШ 6x    СТРИТ 4x",
        "ТРОЙКА 3x    ДВЕ ПАРЫ 2x    ПАРА J+ 1x",
    }
    local ty = self.z_btn_y + self.z_btn_h + 25
    local line_text
    for _, line_text in ipairs(table_lines) do
        local lw = RenderText:sizeUtf8Text(0, w, small_font, line_text).x
        RenderText:renderUtf8Text(bb, x + (w - lw) / 2, ty,
            small_font, line_text, false, false, WIN_TEXT)
        ty = ty + 26
    end

    -- ============================================================
    -- Кнопки ставок (в самом низу игровой зоны)
    -- ============================================================
    self.z_bet_btn_w = Screen:scaleBySize(140)
    self.z_bet_btn_h = Screen:scaleBySize(70)
    self.z_bet_gap = Screen:scaleBySize(10)
    local total_bets_w = #BET_VALUES * self.z_bet_btn_w + (#BET_VALUES - 1) * self.z_bet_gap
    self.z_bet_start_x = x + (w - total_bets_w) / 2
    self.z_bet_y = y + game_h - self.z_bet_btn_h - Screen:scaleBySize(15)

    local j, val
    for j, val in ipairs(BET_VALUES) do
        local bx = self.z_bet_start_x + (j - 1) * (self.z_bet_btn_w + self.z_bet_gap)
        local is_active = (val == self.bet)

        if is_active then
            bb:paintRect(bx, self.z_bet_y, self.z_bet_btn_w, self.z_bet_btn_h, WIN_FACE)
            bb:paintRect(bx, self.z_bet_y, self.z_bet_btn_w, 2, WIN_SHADOW)
            bb:paintRect(bx, self.z_bet_y, 2, self.z_bet_btn_h, WIN_SHADOW)
            bb:paintRect(bx, self.z_bet_y + self.z_bet_btn_h - 2, self.z_bet_btn_w, 2, WIN_LIGHT)
            bb:paintRect(bx + self.z_bet_btn_w - 2, self.z_bet_y, 2, self.z_bet_btn_h, WIN_LIGHT)
        else
            bb:paintRect(bx, self.z_bet_y, self.z_bet_btn_w, self.z_bet_btn_h, WIN_FACE)
            bb:paintRect(bx, self.z_bet_y, self.z_bet_btn_w, 2, WIN_LIGHT)
            bb:paintRect(bx, self.z_bet_y, 2, self.z_bet_btn_h, WIN_LIGHT)
            bb:paintRect(bx, self.z_bet_y + self.z_bet_btn_h - 2, self.z_bet_btn_w, 2, WIN_SHADOW)
            bb:paintRect(bx + self.z_bet_btn_w - 2, self.z_bet_y, 2, self.z_bet_btn_h, WIN_SHADOW)
        end

        local label = "$" .. val
        local lw = RenderText:sizeUtf8Text(0, self.z_bet_btn_w, bet_font, label).x
        RenderText:renderUtf8Text(bb,
            bx + (self.z_bet_btn_w - lw) / 2,
            self.z_bet_y + self.z_bet_btn_h / 2 + 10,
            bet_font, label, false, false, WIN_TEXT)
    end
end

return Poker