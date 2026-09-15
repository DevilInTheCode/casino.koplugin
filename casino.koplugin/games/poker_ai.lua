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

local PokerAI = InputContainer:extend{
    balance = 1000,
    bet = 10,
    phase = "idle",
    deck = {},
    player_cards = {},
    ai_cards = {},
    community = {},
    pot = 0,
    player_bet_round = 0,
    ai_bet_round = 0,
    raises_this_round = 0,
    status = "Нажмите НОВАЯ РАЗДАЧА",
    last_result = "",
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
local MAX_RAISES = 3

local BTN_FOLD  = "ФОЛД"
local BTN_CALL  = "КОЛЛ"
local BTN_RAISE = "РЕЙЗ"
local BTN_NEW   = "НОВАЯ РАЗДАЧА"

function PokerAI:init()
end

function PokerAI:refresh()
    if self.root_layout then
        UIManager:setDirty(self.root_layout, "ui")
    else
        UIManager:setDirty(self, "ui")
    end
end

function PokerAI:newDeck()
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

function PokerAI:rankValue(card)
    local first = card:sub(1, 1)
    if first == "A" then return 14 end
    if first == "K" then return 13 end
    if first == "Q" then return 12 end
    if first == "J" then return 11 end
    if first == "1" and card:sub(2, 2) == "0" then return 10 end
    return tonumber(first) or 0
end

function PokerAI:suitOf(card)
    return card:sub(-1)
end

function PokerAI:evaluate5(cards)
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

    local quads, trips, pair_count = 0, 0, 0
    local k, n
    for k, n in pairs(counts) do
        if n == 4 then quads = quads + 1
        elseif n == 3 then trips = trips + 1
        elseif n == 2 then pair_count = pair_count + 1 end
    end

    if straight and flush and values[1] == 10 then
        return { score = 9, name = "РОЯЛ-ФЛЕШ" }
    end
    if straight and flush then
        return { score = 8, name = "СТРИТ-ФЛЕШ" }
    end
    if quads == 1 then
        return { score = 7, name = "КАРЕ" }
    end
    if trips == 1 and pair_count == 1 then
        return { score = 6, name = "ФУЛЛ-ХАУС" }
    end
    if flush then
        return { score = 5, name = "ФЛЕШ" }
    end
    if straight then
        return { score = 4, name = "СТРИТ" }
    end
    if trips == 1 then
        return { score = 3, name = "ТРОЙКА" }
    end
    if pair_count >= 2 then
        return { score = 2, name = "ДВЕ ПАРЫ" }
    end
    if pair_count == 1 then
        return { score = 1, name = "ПАРА" }
    end
    return { score = 0, name = "НИЧЕГО" }
end

function PokerAI:evaluate7(cards)
    local best = { score = -1, name = "НИЧЕГО" }
    local n = #cards
    local i1, i2, i3, i4, i5
    for i1 = 1, n - 4 do
        for i2 = i1 + 1, n - 3 do
            for i3 = i2 + 1, n - 2 do
                for i4 = i3 + 1, n - 1 do
                    for i5 = i4 + 1, n do
                        local hand = { cards[i1], cards[i2], cards[i3], cards[i4], cards[i5] }
                        local res = self:evaluate5(hand)
                        if res.score > best.score then
                            best = res
                        end
                    end
                end
            end
        end
    end
    return best
end

function PokerAI:aiKnownCards()
    local known = {}
    local i
    for i = 1, #self.ai_cards do known[#known + 1] = self.ai_cards[i] end
    for i = 1, #self.community do known[#known + 1] = self.community[i] end
    return known
end

function PokerAI:aiDecide(to_call)
    to_call = to_call or 0

    local known = self:aiKnownCards()
    local strength = self:evaluate7(known).score
    local s = strength / 9.0

    if #self.community == 0 then
        local v1 = self:rankValue(self.ai_cards[1])
        local v2 = self:rankValue(self.ai_cards[2])
        local high = math.max(v1, v2)
        local low = math.min(v1, v2)
        local pair = (v1 == v2) and 1 or 0
        local suited = (self:suitOf(self.ai_cards[1]) == self:suitOf(self.ai_cards[2])) and 1 or 0
        local connected = (math.abs(v1 - v2) == 1) and 1 or 0
        s = (high / 14.0) * 0.35 + pair * 0.40 + suited * 0.10 + connected * 0.10 + (low / 14.0) * 0.05
    end

    local r = math.random()

    if to_call == 0 then
        if s > 0.55 and self.raises_this_round < MAX_RAISES then
            return "raise"
        end
        if s < 0.25 and r < 0.25 and self.raises_this_round < MAX_RAISES then
            return "raise"
        end
        return "call"
    end

    if s < 0.35 and r < 0.25 then
        return "raise"
    end

    if s > 0.60 and self.raises_this_round < MAX_RAISES then
        return "raise"
    end

    if s > 0.30 then
        return "call"
    end

    if s > 0.15 and r < 0.55 then
        return "call"
    end

    if r < 0.25 then
        return "call"
    end

    return "fold"
end

function PokerAI:startNewHand()
    if self.balance < self.bet * 2 then
        self.status = "Недостаточно средств (нужно 2x ставка)!"
        self:refresh()
        return
    end

    self.balance = self.balance - self.bet
    self.pot = self.bet * 2
    self.player_bet_round = self.bet
    self.ai_bet_round = self.bet

    if self.on_result then
        self.on_result(self.bet, 0, self.balance)
    end

    self.deck = self:newDeck()
    self.player_cards = {}
    self.ai_cards = {}
    self.community = {}
    self.raises_this_round = 0

    self.player_cards[1] = table.remove(self.deck)
    self.ai_cards[1] = table.remove(self.deck)
    self.player_cards[2] = table.remove(self.deck)
    self.ai_cards[2] = table.remove(self.deck)

    self.phase = "preflop"
    self.status = "Префлоп. Ваш ход"
    self.last_result = ""
    self:refresh()
end

function PokerAI:dealFlop()
    local i
    for i = 1, 3 do
        self.community[#self.community + 1] = table.remove(self.deck)
    end
    self.phase = "flop"
    self.raises_this_round = 0
    self.player_bet_round = 0
    self.ai_bet_round = 0
    self.status = "Флоп. Ваш ход"
    self:refresh()
end

function PokerAI:dealTurn()
    self.community[#self.community + 1] = table.remove(self.deck)
    self.phase = "turn"
    self.raises_this_round = 0
    self.player_bet_round = 0
    self.ai_bet_round = 0
    self.status = "Тёрн. Ваш ход"
    self:refresh()
end

function PokerAI:dealRiver()
    self.community[#self.community + 1] = table.remove(self.deck)
    self.phase = "river"
    self.raises_this_round = 0
    self.player_bet_round = 0
    self.ai_bet_round = 0
    self.status = "Ривер. Ваш ход"
    self:refresh()
end

function PokerAI:showdown()
    self.phase = "showdown"

    local player_all = {}
    local i
    for i = 1, #self.player_cards do player_all[#player_all + 1] = self.player_cards[i] end
    for i = 1, #self.community do player_all[#player_all + 1] = self.community[i] end

    local ai_all = {}
    for i = 1, #self.ai_cards do ai_all[#ai_all + 1] = self.ai_cards[i] end
    for i = 1, #self.community do ai_all[#ai_all + 1] = self.community[i] end

    local p = self:evaluate7(player_all)
    local a = self:evaluate7(ai_all)

    local win = 0
    if p.score > a.score then
        win = self.pot
        self.balance = self.balance + win
        self.status = string.format("Вы: %s. ИИ: %s. ВЫИГРЫШ $%d", p.name, a.name, win)
    elseif p.score < a.score then
        self.status = string.format("Вы: %s. ИИ: %s. Проигрыш.", p.name, a.name)
    else
        win = self.pot
        self.balance = self.balance + win
        self.status = string.format("Вы: %s. ИИ: %s. Ничья (возврат $%d)", p.name, a.name, win)
    end

    self.last_result = self.status
    self.pot = 0

    if self.on_result then
        self.on_result(0, win, self.balance)
    end
    self.phase = "done"
    self:refresh()
end

function PokerAI:playerFold()
    if self.phase == "idle" or self.phase == "done" then return end
    self.status = "Вы сфолдили. ИИ забирает банк."
    self.last_result = self.status
    self.pot = 0
    self.phase = "done"
    self:refresh()
end

function PokerAI:playerCall()
    if self.phase == "idle" or self.phase == "done" then return end

    local to_call = self.ai_bet_round - self.player_bet_round
    if to_call > 0 then
        if self.balance < to_call then
            self.status = "Недостаточно средств для колла!"
            self:refresh()
            return
        end
        self.balance = self.balance - to_call
        self.pot = self.pot + to_call
        self.player_bet_round = self.ai_bet_round
    end

    local action = self:aiDecide(0)

    if action == "fold" then
        local win = self.pot
        self.balance = self.balance + win
        self.status = string.format("ИИ сфолдил! ВЫИГРЫШ $%d", win)
        self.last_result = self.status
        self.pot = 0
        self.phase = "done"
        if self.on_result then
            self.on_result(0, win, self.balance)
        end
        self:refresh()
        return
    elseif action == "raise" then
        self.raises_this_round = self.raises_this_round + 1
        local raise_amount = self.bet
        self.ai_bet_round = self.ai_bet_round + raise_amount
        self.pot = self.pot + raise_amount
        self.status = string.format("ИИ повышает на $%d. Ваш ход", raise_amount)
        self:refresh()
        return
    else
        local ai_to_call = self.player_bet_round - self.ai_bet_round
        if ai_to_call > 0 then
            self.ai_bet_round = self.ai_bet_round + ai_to_call
            self.pot = self.pot + ai_to_call
        end
        self:nextStreet()
        return
    end
end

function PokerAI:playerRaise()
    if self.phase == "idle" or self.phase == "done" then return end
    if self.raises_this_round >= MAX_RAISES then
        self.status = "Лимит рейзов исчерпан. Делайте КОЛЛ или ФОЛД."
        self:refresh()
        return
    end

    local raise_amount = self.bet
    if self.balance < raise_amount then
        self.status = "Недостаточно средств для рейза!"
        self:refresh()
        return
    end

    self.balance = self.balance - raise_amount
    self.pot = self.pot + raise_amount
    self.player_bet_round = self.player_bet_round + raise_amount
    self.raises_this_round = self.raises_this_round + 1

    local ai_to_call = self.player_bet_round - self.ai_bet_round
    local action = self:aiDecide(ai_to_call)

    if action == "fold" then
        local win = self.pot
        self.balance = self.balance + win
        self.status = string.format("ИИ сфолдил! ВЫИГРЫШ $%d", win)
        self.last_result = self.status
        self.pot = 0
        self.phase = "done"
        if self.on_result then
            self.on_result(0, win, self.balance)
        end
        self:refresh()
        return
    elseif action == "raise" and self.raises_this_round < MAX_RAISES then
        self.raises_this_round = self.raises_this_round + 1
        local ai_raise = self.bet
        self.ai_bet_round = self.ai_bet_round + ai_raise
        self.pot = self.pot + ai_raise
        self.status = string.format("ИИ переповышает на $%d. Ваш ход", ai_raise)
        self:refresh()
        return
    else
        local ai_need = self.player_bet_round - self.ai_bet_round
        if ai_need > 0 then
            self.ai_bet_round = self.ai_bet_round + ai_need
            self.pot = self.pot + ai_need
        end
        self:nextStreet()
        return
    end
end

function PokerAI:nextStreet()
    if self.phase == "preflop" then
        self:dealFlop()
    elseif self.phase == "flop" then
        self:dealTurn()
    elseif self.phase == "turn" then
        self:dealRiver()
    elseif self.phase == "river" then
        self:showdown()
    end
end

function PokerAI:onTap(ges)
    if self.z_bet_y == 0 then return false end
    local pos = ges.pos

    if pos.y >= self.z_bet_y and pos.y <= self.z_bet_y + self.z_bet_h then
        local j, val
        for j, val in ipairs(BET_VALUES) do
            local bx = self.z_bet_x + (j - 1) * (self.z_bet_w + self.z_bet_gap)
            if pos.x >= bx and pos.x <= bx + self.z_bet_w then
                if self.phase == "idle" or self.phase == "done" then
                    self.bet = val
                    if self.on_bet_change then self.on_bet_change(val) end
                    self:refresh()
                end
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
        else
            local x1 = self.z_action_x
            if pos.x >= x1 and pos.x <= x1 + self.z_action_w then
                self:playerFold()
                return true
            end
            local x2 = x1 + self.z_action_w + self.z_action_gap
            if pos.x >= x2 and pos.x <= x2 + self.z_action_w then
                self:playerCall()
                return true
            end
            local x3 = x2 + self.z_action_w + self.z_action_gap
            if pos.x >= x3 and pos.x <= x3 + self.z_action_w then
                self:playerRaise()
                return true
            end
        end
    end

    return false
end

function PokerAI:renderCard(bb, x, y, card, hidden, card_w, card_h)
    if hidden then
        bb:paintRect(x, y, card_w, card_h, WIN_SHADOW)
    else
        bb:paintRect(x, y, card_w, card_h, WIN_LIGHT)
    end
    bb:paintRect(x, y, card_w, 3, WIN_TEXT)
    bb:paintRect(x, y + card_h - 3, card_w, 3, WIN_TEXT)
    bb:paintRect(x, y, 3, card_h, WIN_TEXT)
    bb:paintRect(x + card_w - 3, y, 3, card_h, WIN_TEXT)

    local text
    if hidden then
        text = "?"
    else
        text = card
    end

    local color = hidden and WIN_LIGHT or WIN_TEXT
    local card_font = Font:getFace("cfont", 28)
    local tw = RenderText:sizeUtf8Text(0, card_w, card_font, text).x
    RenderText:renderUtf8Text(bb,
        x + (card_w - tw) / 2,
        y + card_h / 2 + 10,
        card_font, text, false, false, color)
end

function PokerAI:renderCardsRow(bb, x, y, cards, hidden, card_w, card_h, gap)
    local cx = x
    local i, c
    for i, c in ipairs(cards) do
        self:renderCard(bb, cx, y, c, hidden, card_w, card_h)
        cx = cx + card_w + gap
    end
end

function PokerAI:paintTo(bb, x, y)
    local w = bb:getWidth()
    local game_h = self.height

    self.offset_y = y

    bb:paintRect(x, y, w, game_h, WIN_FACE)

    local label_font  = Font:getFace("cfont", 20)
    local score_font  = Font:getFace("cfont", 18)
    local status_font = Font:getFace("cfont", 20)
    local btn_font    = Font:getFace("cfont", 24)
    local bet_font    = Font:getFace("cfont", 24)
    local pot_font    = Font:getFace("cfont", 22)

    local card_w = Screen:scaleBySize(100)
    local card_h = Screen:scaleBySize(120)   -- уменьшил высоту карт с 135 до 120
    local card_gap = Screen:scaleBySize(10)

    local left_x = x + 30

    -- ============================================================
    -- ИИ
    -- ============================================================
    local cur_y = y + 30
    RenderText:renderUtf8Text(bb, left_x, cur_y,
        label_font, "ИИ", false, false, WIN_TEXT)
    cur_y = cur_y + 25
    if #self.ai_cards > 0 then
        self:renderCardsRow(bb, left_x, cur_y, self.ai_cards, true, card_w, card_h, card_gap)
    end
    cur_y = cur_y + card_h + 35

    -- ============================================================
    -- Стол
    -- ============================================================
    RenderText:renderUtf8Text(bb, left_x, cur_y,
        label_font, "Стол", false, false, WIN_TEXT)
    cur_y = cur_y + 25
    if #self.community > 0 then
        self:renderCardsRow(bb, left_x, cur_y, self.community, false, card_w, card_h, card_gap)
    else
        local i
        for i = 1, 5 do
            local cx = left_x + (i - 1) * (card_w + card_gap)
            bb:paintRect(cx, cur_y, card_w, card_h, WIN_FACE)
            bb:paintRect(cx, cur_y, card_w, 3, WIN_SHADOW)
            bb:paintRect(cx, cur_y + card_h - 3, card_w, 3, WIN_SHADOW)
            bb:paintRect(cx, cur_y, 3, card_h, WIN_SHADOW)
            bb:paintRect(cx + card_w - 3, cur_y, 3, card_h, WIN_SHADOW)
        end
    end
    cur_y = cur_y + card_h + 35

    -- ============================================================
    -- Банк + Статус
    -- ============================================================
    local pot_text = string.format("Банк: $%d", self.pot)
    RenderText:renderUtf8Text(bb, left_x, cur_y,
        pot_font, pot_text, false, false, WIN_TEXT)

    local sw = RenderText:sizeUtf8Text(0, w, status_font, self.status).x
    RenderText:renderUtf8Text(bb, x + (w - sw) / 2, cur_y,
        status_font, self.status, false, false, WIN_TEXT)

    cur_y = cur_y + 40

    -- ============================================================
    -- Игрок
    -- ============================================================
    RenderText:renderUtf8Text(bb, left_x, cur_y,
        label_font, "Вы", false, false, WIN_TEXT)
    cur_y = cur_y + 25
    if #self.player_cards > 0 then
        self:renderCardsRow(bb, left_x, cur_y, self.player_cards, false, card_w, card_h, card_gap)
    end
    cur_y = cur_y + card_h + 45

    if #self.player_cards == 2 then
        local known = {}
        local i
        for i = 1, #self.player_cards do known[#known + 1] = self.player_cards[i] end
        for i = 1, #self.community do known[#known + 1] = self.community[i] end
        if #known >= 5 then
            local res = self:evaluate7(known)
            local pt = string.format("Комбинация: %s", res.name)
            RenderText:renderUtf8Text(bb, left_x, cur_y,
                score_font, pt, false, false, WIN_TEXT)
        end
    end

    -- ============================================================
    -- Кнопки
    -- ============================================================
    self.z_bet_w = Screen:scaleBySize(130)
    self.z_bet_h = Screen:scaleBySize(65)
    self.z_bet_gap = Screen:scaleBySize(10)
    local total_bets_w = #BET_VALUES * self.z_bet_w + (#BET_VALUES - 1) * self.z_bet_gap
    self.z_bet_x = x + (w - total_bets_w) / 2
    self.z_bet_y = y + game_h - self.z_bet_h - Screen:scaleBySize(15)

    self.z_action_w = Screen:scaleBySize(180)
    self.z_action_h = Screen:scaleBySize(60)
    self.z_action_gap = Screen:scaleBySize(20)
    self.z_action_y = self.z_bet_y - self.z_action_h - Screen:scaleBySize(15)

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
    else
        local total_btn_w = 3 * self.z_action_w + 2 * self.z_action_gap
        self.z_action_x = x + (w - total_btn_w) / 2

        local labels = { BTN_FOLD, BTN_CALL, BTN_RAISE }
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

return PokerAI