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

local Blackjack = InputContainer:extend{
    balance = 1000,
    bet = 10,
    phase = "idle",
    deck = {},
    player_cards = {},
    dealer_cards = {},
    status = "Нажмите НОВАЯ РАЗДАЧА",
    on_result = nil,
    on_bet_change = nil,
    root_layout = nil,
    offset_y = 0,
    height = 0,

    z_action_y = 0,
    z_action_h = 0,
    z_action_w = 0,
    z_action_gap = 0,
    z_action_x = 0,

    z_bet_y = 0,
    z_bet_h = 0,
    z_bet_w = 0,
    z_bet_gap = 0,
    z_bet_x = 0,
}

local SUITS = {"♠", "♥", "♦", "♣"}
local RANKS = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}
local BET_VALUES = {5, 10, 25, 50}

local BTN_HIT    = "ВЗЯТЬ"
local BTN_STAND  = "ХВАТИТ"
local BTN_DOUBLE = "УДВОИТЬ"
local BTN_NEW    = "НОВАЯ РАЗДАЧА"

function Blackjack:init()
end

function Blackjack:refresh()
    if self.root_layout then
        UIManager:setDirty(self.root_layout, "ui")
    else
        UIManager:setDirty(self, "ui")
    end
end

function Blackjack:newDeck()
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

function Blackjack:cardValue(card)
    local first = card:sub(1, 1)
    if first == "A" then return 11 end
    if first == "K" then return 10 end
    if first == "Q" then return 10 end
    if first == "J" then return 10 end
    if first == "1" and card:sub(2, 2) == "0" then return 10 end
    return tonumber(first) or 0
end

function Blackjack:handTotal(cards)
    local total = 0
    local aces = 0
    local i, c
    for i, c in ipairs(cards) do
        local v = self:cardValue(c)
        if v == 11 then aces = aces + 1 end
        total = total + v
    end
    while total > 21 and aces > 0 do
        total = total - 10
        aces = aces - 1
    end
    return total
end

function Blackjack:drawCard()
    if #self.deck == 0 then
        self.deck = self:newDeck()
    end
    return table.remove(self.deck)
end

-- ==================== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ КАРТ ====================

function Blackjack:suitOf(card)
    local i
    for i = #card, 1, -1 do
        local b = card:byte(i)
        if b < 128 or b >= 192 then
            return card:sub(i)
        end
    end
    return ""
end

function Blackjack:rankOf(card)
    local i
    for i = #card, 1, -1 do
        local b = card:byte(i)
        if b < 128 or b >= 192 then
            return card:sub(1, i - 1)
        end
    end
    return card
end

-- ==================== ИГРОВАЯ ЛОГИКА ====================

function Blackjack:startNewHand()
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
    self.player_cards = {}
    self.dealer_cards = {}

    self.player_cards[#self.player_cards + 1] = self:drawCard()
    self.dealer_cards[#self.dealer_cards + 1] = self:drawCard()
    self.player_cards[#self.player_cards + 1] = self:drawCard()
    self.dealer_cards[#self.dealer_cards + 1] = self:drawCard()

    self.phase = "player"
    self.status = "Ваш ход"

    local p = self:handTotal(self.player_cards)
    if p == 21 then
        self:finishHand()
        return
    end

    self:refresh()
end

function Blackjack:hit()
    if self.phase ~= "player" then return end
    self.player_cards[#self.player_cards + 1] = self:drawCard()
    local p = self:handTotal(self.player_cards)
    if p > 21 then
        self.status = "Перебор!"
        self:finishHand()
        return
    end
    if p == 21 then
        self:finishHand()
        return
    end
    self:refresh()
end

function Blackjack:stand()
    if self.phase ~= "player" then return end
    self.phase = "dealer"
    self:finishHand()
end

function Blackjack:double()
    if self.phase ~= "player" then return end
    if #self.player_cards ~= 2 then
        self.status = "Удвоение только на первых двух картах"
        self:refresh()
        return
    end
    if self.balance < self.bet then
        self.status = "Недостаточно средств для удвоения"
        self:refresh()
        return
    end

    self.balance = self.balance - self.bet
    if self.on_result then
        self.on_result(self.bet, 0, self.balance)
    end
    self.bet = self.bet * 2

    self.player_cards[#self.player_cards + 1] = self:drawCard()
    self.phase = "dealer"
    self:finishHand()
end

function Blackjack:finishHand()
    self.phase = "done"

    local player_total = self:handTotal(self.player_cards)
    local dealer_total = self:handTotal(self.dealer_cards)

    while dealer_total < 17 do
        self.dealer_cards[#self.dealer_cards + 1] = self:drawCard()
        dealer_total = self:handTotal(self.dealer_cards)
    end

    local win = 0
    local result_text = ""

    if player_total > 21 then
        result_text = string.format("Перебор (%d). Дилер: %d. Проигрыш.", player_total, dealer_total)
    elseif dealer_total > 21 then
        win = self.bet * 2
        self.balance = self.balance + win
        result_text = string.format("Дилер перебрал (%d). Вы: %d. ВЫИГРЫШ $%d", dealer_total, player_total, win)
    elseif player_total > dealer_total then
        win = self.bet * 2
        self.balance = self.balance + win
        result_text = string.format("Вы: %d, дилер: %d. ВЫИГРЫШ $%d", player_total, dealer_total, win)
    elseif player_total < dealer_total then
        result_text = string.format("Вы: %d, дилер: %d. Проигрыш.", player_total, dealer_total)
    else
        win = self.bet
        self.balance = self.balance + win
        result_text = string.format("Вы: %d, дилер: %d. Ничья (возврат $%d)", player_total, dealer_total, win)
    end

    self.status = result_text

    if self.on_result then
        self.on_result(0, win, self.balance)
    end
    self:refresh()
end

-- ==================== ОБРАБОТКА ТАПОВ ====================

function Blackjack:onTap(ges)
    if self.z_bet_y == 0 then return false end
    local pos = ges.pos

    if pos.y >= self.z_bet_y and pos.y <= self.z_bet_y + self.z_bet_h then
        local j, val
        for j, val in ipairs(BET_VALUES) do
            local bx = self.z_bet_x + (j - 1) * (self.z_bet_w + self.z_bet_gap)
            if pos.x >= bx and pos.x <= bx + self.z_bet_w then
                self.bet = val
                if self.on_bet_change then self.on_bet_change(val) end
                self:refresh()
                return true
            end
        end
    end

    if pos.y >= self.z_action_y and pos.y <= self.z_action_y + self.z_action_h then
        if self.phase == "idle" or self.phase == "done" then
            if pos.x >= self.z_action_x and pos.x <= self.z_action_x + self.z_action_w then
                self:startNewHand()
                return true
            end
        end
        if self.phase == "player" then
            local x1 = self.z_action_x
            if pos.x >= x1 and pos.x <= x1 + self.z_action_w then
                self:hit()
                return true
            end
            local x2 = x1 + self.z_action_w + self.z_action_gap
            if pos.x >= x2 and pos.x <= x2 + self.z_action_w then
                self:stand()
                return true
            end
            local x3 = x2 + self.z_action_w + self.z_action_gap
            if pos.x >= x3 and pos.x <= x3 + self.z_action_w then
                self:double()
                return true
            end
        end
    end

    return false
end

-- ==================== ОТРИСОВКА КАРТ ====================

function Blackjack:renderCard(bb, x, y, card, cw, ch, face_up)
    if not face_up then
        -- Рубашка
        bb:paintRect(x, y, cw, ch, WIN_FACE)
        local step = Screen:scaleBySize(8)
        local thick = Screen:scaleBySize(2)
        local i
        for i = -ch, cw, step do
            local j
            for j = 0, ch do
                local px = x + i + j
                local py = y + ch - j
                if px >= x and px < x + cw - thick and py >= y and py < y + ch - thick then
                    bb:paintRect(px, py, thick, thick, WIN_SHADOW)
                end
            end
        end
        bb:paintRect(x, y, cw, 2, WIN_LIGHT)
        bb:paintRect(x, y, 2, ch, WIN_LIGHT)
        bb:paintRect(x, y + ch - 2, cw, 2, WIN_TEXT)
        bb:paintRect(x + cw - 2, y, 2, ch, WIN_TEXT)
        return
    end

    -- Лицо карты
    bb:paintRect(x, y, cw, ch, WIN_LIGHT)
    bb:paintRect(x, y, cw, 2, WIN_TEXT)
    bb:paintRect(x, y + ch - 2, cw, 2, WIN_TEXT)
    bb:paintRect(x, y, 2, ch, WIN_TEXT)
    bb:paintRect(x + cw - 2, y, 2, ch, WIN_TEXT)

    local rank = self:rankOf(card)
    local suit = self:suitOf(card)
    local color = (suit == "♥" or suit == "♦") and Blitbuffer.Color8(0x80) or WIN_TEXT

    local f = Font:getFace("cfont", 28)
    RenderText:renderUtf8Text(bb, x + 8, y + 42, f, rank, false, false, color)
    RenderText:renderUtf8Text(bb, x + 8, y + 85, f, suit, false, false, color)
end

function Blackjack:renderCardsRow(bb, x, y, cards, hidden_second, cw, ch, gap)
    local cx = x
    local i, c
    for i, c in ipairs(cards) do
        local face_up = not (i == 2 and hidden_second)
        self:renderCard(bb, cx, y, c, cw, ch, face_up)
        cx = cx + cw + gap
    end
end

function Blackjack:paintTo(bb, x, y)
    local w = bb:getWidth()
    local game_h = self.height

    self.offset_y = y

    bb:paintRect(x, y, w, game_h, WIN_FACE)

    local label_font  = Font:getFace("cfont", 20)
    local score_font  = Font:getFace("cfont", 18)
    local status_font = Font:getFace("cfont", 20)
    local btn_font    = Font:getFace("cfont", 22)
    local bet_font    = Font:getFace("cfont", 24)

    local card_w = Screen:scaleBySize(80)
    local card_h = Screen:scaleBySize(115)
    local card_gap = Screen:scaleBySize(10)

    local left_x = x + 30

    -- ============================================================
    -- Дилер
    -- ============================================================
    local cur_y = y + 50
    RenderText:renderUtf8Text(bb, left_x, cur_y,
        label_font, "Дилер", false, false, WIN_TEXT)

    cur_y = cur_y + 30
    self:renderCardsRow(bb, left_x, cur_y, self.dealer_cards,
        self.phase == "player", card_w, card_h, card_gap)

    -- Очки дилера — ниже карт
    cur_y = cur_y + card_h + 40
    local dealer_total_text = ""
    if self.phase == "player" and #self.dealer_cards >= 2 then
        local visible_total = self:cardValue(self.dealer_cards[1])
        dealer_total_text = string.format("Очки: %d + ?", visible_total)
    elseif #self.dealer_cards > 0 then
        dealer_total_text = string.format("Очки: %d", self:handTotal(self.dealer_cards))
    end
    if dealer_total_text ~= "" then
        RenderText:renderUtf8Text(bb, left_x, cur_y,
            score_font, dealer_total_text, false, false, WIN_TEXT)
    end

    -- ============================================================
    -- Игрок
    -- ============================================================
    cur_y = cur_y + 50
    RenderText:renderUtf8Text(bb, left_x, cur_y,
        label_font, "Вы", false, false, WIN_TEXT)

    cur_y = cur_y + 30
    self:renderCardsRow(bb, left_x, cur_y, self.player_cards,
        false, card_w, card_h, card_gap)

    -- Очки игрока — ниже карт
    cur_y = cur_y + card_h + 40
    if #self.player_cards > 0 then
        local pt = string.format("Очки: %d", self:handTotal(self.player_cards))
        RenderText:renderUtf8Text(bb, left_x, cur_y,
            score_font, pt, false, false, WIN_TEXT)
    end

    -- ============================================================
    -- Расчёт позиций кнопок
    -- ============================================================
    self.z_bet_w = Screen:scaleBySize(130)
    self.z_bet_h = Screen:scaleBySize(65)
    self.z_bet_gap = Screen:scaleBySize(10)
    local total_bets_w = #BET_VALUES * self.z_bet_w + (#BET_VALUES - 1) * self.z_bet_gap
    self.z_bet_x = x + (w - total_bets_w) / 2
    self.z_bet_y = y + game_h - self.z_bet_h - Screen:scaleBySize(15)

    self.z_action_w = Screen:scaleBySize(180)
    self.z_action_h = Screen:scaleBySize(60)
    self.z_action_gap = Screen:scaleBySize(15)
    self.z_action_y = self.z_bet_y - self.z_action_h - Screen:scaleBySize(15)

    -- ============================================================
    -- Статус (над кнопками)
    -- ============================================================
    local status_y = self.z_action_y - Screen:scaleBySize(30)
    local sw = RenderText:sizeUtf8Text(0, w, status_font, self.status).x
    RenderText:renderUtf8Text(bb, x + (w - sw) / 2, status_y,
        status_font, self.status, false, false, WIN_TEXT)

    -- ============================================================
    -- Кнопка НОВАЯ РАЗДАЧА
    -- ============================================================
    if self.phase == "idle" or self.phase == "done" then
        local new_w = Screen:scaleBySize(380)
        local new_h = Screen:scaleBySize(60)
        local new_x = x + (w - new_w) / 2
        local new_y = self.z_action_y

        self.z_action_x = new_x
        self.z_action_w = new_w
        self.z_action_h = new_h
        self.z_action_y = new_y

        bb:paintRect(new_x, new_y, new_w, new_h, WIN_FACE)
        bb:paintRect(new_x, new_y, new_w, 2, WIN_LIGHT)
        bb:paintRect(new_x, new_y, 2, new_h, WIN_LIGHT)
        bb:paintRect(new_x, new_y + new_h - 2, new_w, 2, WIN_SHADOW)
        bb:paintRect(new_x + new_w - 2, new_y, 2, new_h, WIN_SHADOW)

        local lw = RenderText:sizeUtf8Text(0, new_w, btn_font, BTN_NEW).x
        RenderText:renderUtf8Text(bb,
            new_x + (new_w - lw) / 2,
            new_y + new_h / 2 + 8,
            btn_font, BTN_NEW, false, false, WIN_TEXT)
    end

    -- ============================================================
    -- Кнопки ВЗЯТЬ / ХВАТИТ / УДВОИТЬ
    -- ============================================================
    if self.phase == "player" then
        local total_btn_w = 3 * self.z_action_w + 2 * self.z_action_gap
        self.z_action_x = x + (w - total_btn_w) / 2

        local labels = { BTN_HIT, BTN_STAND, BTN_DOUBLE }
        local i
        for i = 1, 3 do
            local bx = self.z_action_x + (i - 1) * (self.z_action_w + self.z_action_gap)
            bb:paintRect(bx, self.z_action_y, self.z_action_w, self.z_action_h, WIN_FACE)
            bb:paintRect(bx, self.z_action_y, self.z_action_w, 2, WIN_LIGHT)
            bb:paintRect(bx, self.z_action_y, 2, self.z_action_h, WIN_LIGHT)
            bb:paintRect(bx, self.z_action_y + self.z_action_h - 2, self.z_action_w, 2, WIN_SHADOW)
            bb:paintRect(bx + self.z_action_w - 2, self.z_action_y, 2, self.z_action_h, WIN_SHADOW)

            local lw = RenderText:sizeUtf8Text(0, self.z_action_w, btn_font, labels[i]).x
            RenderText:renderUtf8Text(bb,
                bx + (self.z_action_w - lw) / 2,
                self.z_action_y + self.z_action_h / 2 + 8,
                btn_font, labels[i], false, false, WIN_TEXT)
        end
    end

    -- ============================================================
    -- Кнопки ставок
    -- ============================================================
    local j, val
    for j, val in ipairs(BET_VALUES) do
        local bx = self.z_bet_x + (j - 1) * (self.z_bet_w + self.z_bet_gap)
        local is_active = (val == self.bet)
        local disabled = (self.phase ~= "idle" and self.phase ~= "done")

        if is_active and not disabled then
            bb:paintRect(bx, self.z_bet_y, self.z_bet_w, self.z_bet_h, WIN_FACE)
            bb:paintRect(bx, self.z_bet_y, self.z_bet_w, 2, WIN_SHADOW)
            bb:paintRect(bx, self.z_bet_y, 2, self.z_bet_h, WIN_SHADOW)
            bb:paintRect(bx, self.z_bet_y + self.z_bet_h - 2, self.z_bet_w, 2, WIN_LIGHT)
            bb:paintRect(bx + self.z_bet_w - 2, self.z_bet_y, 2, self.z_bet_h, WIN_LIGHT)
        else
            bb:paintRect(bx, self.z_bet_y, self.z_bet_w, self.z_bet_h, WIN_FACE)
            bb:paintRect(bx, self.z_bet_y, self.z_bet_w, 2, WIN_LIGHT)
            bb:paintRect(bx, self.z_bet_y, 2, self.z_bet_h, WIN_LIGHT)
            bb:paintRect(bx, self.z_bet_y + self.z_bet_h - 2, self.z_bet_w, 2, WIN_SHADOW)
            bb:paintRect(bx + self.z_bet_w - 2, self.z_bet_y, 2, self.z_bet_h, WIN_SHADOW)
        end

        local label = "$" .. val
        local lw = RenderText:sizeUtf8Text(0, self.z_bet_w, bet_font, label).x
        RenderText:renderUtf8Text(bb,
            bx + (self.z_bet_w - lw) / 2,
            self.z_bet_y + self.z_bet_h / 2 + 9,
            bet_font, label, false, false, WIN_TEXT)
    end
end

return Blackjack