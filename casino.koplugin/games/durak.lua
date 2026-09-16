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
local WIN_GRAY   = Blitbuffer.Color8(0x60)

local Durak = InputContainer:extend{
    balance = 1000,
    bet = 10,
    phase = "idle",
    deck = {},
    player_hand = {},
    ai_hand = {},
    table_attack = {},
    table_defend = {},
    trump_card = nil,
    trump_suit = nil,
    attacker = "player",
    defender = "ai",
    status = "Нажмите НОВАЯ РАЗДАЧА",
    on_result = nil,
    on_bet_change = nil,
    root_layout = nil,
    offset_y = 0,
    height = 0,

    selected_card = nil,
    selected_index = nil,

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
local RANKS = {"6", "7", "8", "9", "10", "В", "Д", "К", "Т"}
local BET_VALUES = {5, 10, 25, 50}

local BTN_BEAT  = "БИТЬ"
local BTN_TAKE  = "ВЗЯТЬ"
local BTN_MOVE  = "ХОД"
local BTN_PASS  = "ПАС"
local BTN_NEW   = "НОВАЯ РАЗДАЧА"

function Durak:init()
end

function Durak:refresh()
    if self.root_layout then
        UIManager:setDirty(self.root_layout, "ui")
    else
        UIManager:setDirty(self, "ui")
    end
end

function Durak:newDeck()
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

-- Правильное извлечение масти
function Durak:suitOf(card)
    local i
    for i = #card, 1, -1 do
        local b = card:byte(i)
        if b < 128 or b >= 192 then
            return card:sub(i)
        end
    end
    return ""
end

-- Правильное извлечение ранга
function Durak:rankOf(card)
    local i
    for i = #card, 1, -1 do
        local b = card:byte(i)
        if b < 128 or b >= 192 then
            return card:sub(1, i - 1)
        end
    end
    return card
end

function Durak:rankValue(card)
    local rank = self:rankOf(card)
    local map = {["6"]=6,["7"]=7,["8"]=8,["9"]=9,["10"]=10,["В"]=11,["Д"]=12,["К"]=13,["Т"]=14}
    return map[rank] or 0
end

-- Порядок мастей для сортировки (некозырные по порядку, козырь — в конце)
function Durak:suitOrder(suit)
    if suit == self.trump_suit then
        return 100  -- козырь всегда последний
    end
    local order = {["♠"]=1, ["♥"]=2, ["♦"]=3, ["♣"]=4}
    return order[suit] or 50
end

-- Автосортировка руки игрока: некозырные по мастям, козыри справа, по возрастанию
function Durak:sortPlayerHand()
    table.sort(self.player_hand, function(a, b)
        local sa = self:suitOf(a)
        local sb = self:suitOf(b)
        local oa = self:suitOrder(sa)
        local ob = self:suitOrder(sb)
        if oa ~= ob then return oa < ob end
        return self:rankValue(a) < self:rankValue(b)
    end)
end

function Durak:isTrump(card)
    return self:suitOf(card) == self.trump_suit
end

function Durak:canBeat(attack_card, defend_card)
    local a_suit = self:suitOf(attack_card)
    local d_suit = self:suitOf(defend_card)
    local a_rank = self:rankValue(attack_card)
    local d_rank = self:rankValue(defend_card)

    local a_trump = (a_suit == self.trump_suit)
    local d_trump = (d_suit == self.trump_suit)

    if a_trump and not d_trump then return false end
    if not a_trump and d_trump then return true end
    if a_suit ~= d_suit then return false end
    return d_rank > a_rank
end

function Durak:startNewHand()
    if self.balance < self.bet * 2 then
        self.status = "Недостаточно средств!"
        self:refresh()
        return
    end

    self.balance = self.balance - self.bet
    if self.on_result then
        self.on_result(self.bet, 0, self.balance)
    end

    self.deck = self:newDeck()
    self.player_hand = {}
    self.ai_hand = {}
    self.table_attack = {}
    self.table_defend = {}
    self.selected_card = nil
    self.selected_index = nil

    local i
    for i = 1, 6 do
        self.player_hand[#self.player_hand + 1] = table.remove(self.deck)
        self.ai_hand[#self.ai_hand + 1] = table.remove(self.deck)
    end

    self.trump_card = table.remove(self.deck)
    self.trump_suit = self:suitOf(self.trump_card)

    self:sortPlayerHand()

    self.attacker = "player"
    self.defender = "ai"
    self.phase = "player_attack"
    self.status = "Ваш ход. Выделите карту и нажмите ХОД"
    self:refresh()
end

function Durak:refillHands()
    local first = (self.attacker == "player") and self.player_hand or self.ai_hand
    local second = (self.attacker == "player") and self.ai_hand or self.player_hand

    while #first < 6 and #self.deck > 0 do
        first[#first + 1] = table.remove(self.deck)
    end
    while #second < 6 and #self.deck > 0 do
        second[#second + 1] = table.remove(self.deck)
    end

    self:sortPlayerHand()
end

function Durak:checkWin()
    if #self.player_hand == 0 and #self.deck == 0 then
        local win = self.bet * 2
        self.balance = self.balance + win
        self.status = string.format("Вы выиграли! +$%d", win)
        self.phase = "done"
        if self.on_result then
            self.on_result(0, win, self.balance)
        end
        self:refresh()
        return true
    end
    if #self.ai_hand == 0 and #self.deck == 0 then
        self.status = "ИИ выиграл. Вы — дурак!"
        self.phase = "done"
        self:refresh()
        return true
    end
    return false
end

-- ==================== ИГРОК ====================

function Durak:playerMove()
    if self.phase ~= "player_attack" then return end
    if not self.selected_card then
        self.status = "Выделите карту"
        self:refresh()
        return
    end

    local card = self.selected_card
    local idx = self.selected_index

    if #self.table_attack > 0 then
        local ranks_on_table = {}
        local i
        for i = 1, #self.table_attack do
            ranks_on_table[self:rankValue(self.table_attack[i])] = true
        end
        for i = 1, #self.table_defend do
            ranks_on_table[self:rankValue(self.table_defend[i])] = true
        end
        if not ranks_on_table[self:rankValue(card)] then
            self.status = "Нельзя подкинуть эту карту (другой ранг)"
            self:refresh()
            return
        end
    end

    if #self.table_attack >= 6 then
        self.status = "Лимит атаки: 6 карт"
        self:refresh()
        return
    end

    table.remove(self.player_hand, idx)
    self.table_attack[#self.table_attack + 1] = card
    self.selected_card = nil
    self.selected_index = nil

    self:sortPlayerHand()

    self.status = "ИИ думает..."
    self:refresh()
    self:aiDefend()
end

function Durak:playerBeat()
    if self.phase ~= "player_defend" then return end
    if not self.selected_card then
        self.status = "Выделите карту для отбоя"
        self:refresh()
        return
    end

    local attack = self.table_attack[#self.table_attack]
    local defend = self.selected_card

    if not self:canBeat(attack, defend) then
        self.status = "Эта карта не бьёт!"
        self:refresh()
        return
    end

    table.remove(self.player_hand, self.selected_index)
    self.table_defend[#self.table_defend + 1] = defend
    self.selected_card = nil
    self.selected_index = nil

    self:sortPlayerHand()

    self.status = "Вы отбились"
    self.phase = "player_attack"
    self:refresh()
end

function Durak:playerTake()
    if self.phase ~= "player_defend" then return end

    local i
    for i = 1, #self.table_attack do
        self.player_hand[#self.player_hand + 1] = self.table_attack[i]
    end
    for i = 1, #self.table_defend do
        self.player_hand[#self.player_hand + 1] = self.table_defend[i]
    end
    self.table_attack = {}
    self.table_defend = {}
    self.selected_card = nil
    self.selected_index = nil

    self:sortPlayerHand()

    self.attacker = "ai"
    self.defender = "player"
    self:refillHands()

    if self:checkWin() then return end

    self.phase = "ai_attack"
    self.status = "ИИ атакует..."
    self:refresh()
    self:aiAttack()
end

function Durak:playerPass()
    if self.phase ~= "player_attack" then return end
    if #self.table_attack == 0 then
        self.status = "Сначала положите карту"
        self:refresh()
        return
    end

    if #self.table_defend < #self.table_attack then
        local i
        for i = 1, #self.table_attack do
            self.ai_hand[#self.ai_hand + 1] = self.table_attack[i]
        end
        for i = 1, #self.table_defend do
            self.ai_hand[#self.ai_hand + 1] = self.table_defend[i]
        end
        self.table_attack = {}
        self.table_defend = {}
        self.status = "ИИ забирает карты"
    else
        self.table_attack = {}
        self.table_defend = {}
        self.status = "ИИ отбился"
    end

    self.selected_card = nil
    self.selected_index = nil
    self:refillHands()
    if self:checkWin() then return end

    self.attacker = "ai"
    self.defender = "player"
    self.phase = "ai_attack"
    self:refresh()
    self:aiAttack()
end

-- ==================== ИИ ====================

function Durak:aiDefend()
    if #self.table_attack == 0 then return end

    local attack_card = self.table_attack[#self.table_attack]
    local best_idx = nil
    local best_rank = 999

    local i
    for i = 1, #self.ai_hand do
        local card = self.ai_hand[i]
        if self:canBeat(attack_card, card) then
            local r = self:rankValue(card)
            if r < best_rank then
                best_rank = r
                best_idx = i
            end
        end
    end

    if best_idx then
        local card = table.remove(self.ai_hand, best_idx)
        self.table_defend[#self.table_defend + 1] = card
        self.status = "ИИ отбился: " .. card
        self.phase = "player_attack"
        self.status = "Ваш ход (подкидывайте или ПАС)"
    else
        local j
        for j = 1, #self.table_attack do
            self.ai_hand[#self.ai_hand + 1] = self.table_attack[j]
        end
        for j = 1, #self.table_defend do
            self.ai_hand[#self.ai_hand + 1] = self.table_defend[j]
        end
        self.table_attack = {}
        self.table_defend = {}
        self.status = "ИИ не может отбиться, забирает"
        self.phase = "player_attack"
    end

    self:refillHands()
    if self:checkWin() then return end
    self:refresh()
end

function Durak:aiAttack()
    if #self.ai_hand == 0 then return end

    if #self.table_attack > 0 then
        local ranks_on_table = {}
        local i
        for i = 1, #self.table_attack do
            ranks_on_table[self:rankValue(self.table_attack[i])] = true
        end
        for i = 1, #self.table_defend do
            ranks_on_table[self:rankValue(self.table_defend[i])] = true
        end

        local add_idx = nil
        for i = 1, #self.ai_hand do
            if ranks_on_table[self:rankValue(self.ai_hand[i])] then
                add_idx = i
                break
            end
        end

        if add_idx and #self.table_attack < 6 then
            local card = table.remove(self.ai_hand, add_idx)
            self.table_attack[#self.table_attack + 1] = card
            self.status = "ИИ подкинул: " .. card
            self.phase = "player_defend"
            self:refresh()
            return
        else
            local j
            for j = 1, #self.table_attack do
                self.player_hand[#self.player_hand + 1] = self.table_attack[j]
            end
            for j = 1, #self.table_defend do
                self.player_hand[#self.player_hand + 1] = self.table_defend[j]
            end
            self.table_attack = {}
            self.table_defend = {}
            self.status = "ИИ пас. Вы забираете карты"
            self:refillHands()
            if self:checkWin() then return end
            self.attacker = "player"
            self.defender = "ai"
            self.phase = "player_attack"
            self.status = "Ваш ход"
            self:refresh()
            return
        end
    end

    local best_idx = nil
    local best_rank = 999
    local i
    for i = 1, #self.ai_hand do
        local card = self.ai_hand[i]
        if not self:isTrump(card) then
            local r = self:rankValue(card)
            if r < best_rank then
                best_rank = r
                best_idx = i
            end
        end
    end
    if not best_idx then
        for i = 1, #self.ai_hand do
            local r = self:rankValue(self.ai_hand[i])
            if r < best_rank then
                best_rank = r
                best_idx = i
            end
        end
    end

    if best_idx then
        local card = table.remove(self.ai_hand, best_idx)
        self.table_attack[#self.table_attack + 1] = card
        self.status = "ИИ атакует: " .. card
        self.phase = "player_defend"
    end
    self:refresh()
end

-- ==================== ОБРАБОТКА ТАПОВ ====================

function Durak:onTap(ges)
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
        local x1 = self.z_action_x
        local x2 = x1 + self.z_action_w + self.z_action_gap
        local x3 = x2 + self.z_action_w + self.z_action_gap
        local x4 = x3 + self.z_action_w + self.z_action_gap

        if self.phase == "idle" or self.phase == "done" then
            if pos.x >= x1 and pos.x <= x1 + self.z_action_w then
                self:startNewHand()
                return true
            end
        else
            if pos.x >= x1 and pos.x <= x1 + self.z_action_w then
                if self.phase == "player_defend" then
                    self:playerBeat()
                end
                return true
            end
            if pos.x >= x2 and pos.x <= x2 + self.z_action_w then
                if self.phase == "player_defend" then
                    self:playerTake()
                end
                return true
            end
            if pos.x >= x3 and pos.x <= x3 + self.z_action_w then
                if self.phase == "player_attack" then
                    self:playerMove()
                end
                return true
            end
            if pos.x >= x4 and pos.x <= x4 + self.z_action_w then
                if self.phase == "player_attack" then
                    self:playerPass()
                end
                return true
            end
        end
    end

    if self.z_hand_y and pos.y >= self.z_hand_y - Screen:scaleBySize(20)
       and pos.y <= self.z_hand_y + self.z_card_h then
        local i
        for i = #self.player_hand, 1, -1 do
            local cx = self.z_hand_x + (i - 1) * self.z_hand_step
            local visible_right
            if i == #self.player_hand then
                visible_right = cx + self.z_card_w
            else
                visible_right = self.z_hand_x + i * self.z_hand_step
            end
            if pos.x >= cx and pos.x <= visible_right then
                if self.phase == "player_attack" or self.phase == "player_defend" then
                    if self.selected_index == i then
                        self.selected_card = nil
                        self.selected_index = nil
                    else
                        self.selected_card = self.player_hand[i]
                        self.selected_index = i
                    end
                    self:refresh()
                end
                return true
            end
        end
    end

    return false
end

-- ==================== ОТРИСОВКА ====================

function Durak:renderBack(bb, x, y, cw, ch)
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
end

function Durak:renderCard(bb, x, y, card, cw, ch, face_up)
    if not face_up then
        self:renderBack(bb, x, y, cw, ch)
        return
    end
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

function Durak:renderHandRow(bb, cards, x, y, cw, ch, step, face_up, selected_idx)
    local i
    for i = 1, #cards do
        if selected_idx ~= i then
            local cx = x + (i - 1) * step
            self:renderCard(bb, cx, y, cards[i], cw, ch, face_up)
        end
    end
    if selected_idx and selected_idx >= 1 and selected_idx <= #cards then
        local cx = x + (selected_idx - 1) * step
        local cy = y - Screen:scaleBySize(15)
        self:renderCard(bb, cx, cy, cards[selected_idx], cw, ch, face_up)
    end
end

function Durak:paintTo(bb, x, y)
    local w = bb:getWidth()
    local game_h = self.height

    self.offset_y = y
    bb:paintRect(x, y, w, game_h, WIN_FACE)

    local card_w = Screen:scaleBySize(80)
    local card_h = Screen:scaleBySize(115)
    local label_font = Font:getFace("cfont", 20)
    local status_font = Font:getFace("cfont", 20)
    local btn_font = Font:getFace("cfont", 22)
    local bet_font = Font:getFace("cfont", 24)

    local left_x = x + 30
    local right_x = x + w - 30

    -- ===== Карты ИИ =====
    local ai_step = Screen:scaleBySize(12)
    local ai_y = y + 30
    RenderText:renderUtf8Text(bb, left_x, ai_y, label_font, "ИИ", false, false, WIN_TEXT)
    ai_y = ai_y + 30
    self:renderHandRow(bb, self.ai_hand, left_x, ai_y, card_w, card_h, ai_step, false, nil)

    -- ===== Козырь + Колода =====
    local trump_x = right_x - card_w - Screen:scaleBySize(30)
    local trump_y = y + 40
    local deck_x = trump_x + Screen:scaleBySize(30)
    local deck_y = y + 30

    if self.trump_card then
        self:renderCard(bb, trump_x, trump_y, self.trump_card, card_w, card_h, true)
    end
    local deck_count = #self.deck
    local stack = 2
    if deck_count > 4 then stack = 3 end
    if deck_count > 10 then stack = 4 end
    if deck_count > 18 then stack = 5 end
    local s
    for s = 1, stack do
        self:renderCard(bb, deck_x + (s - 1) * 2, deck_y + (s - 1) * 2, nil, card_w, card_h, false)
    end

    -- ===== Стол =====
    local table_y = ai_y + card_h + 30
    local table_step = Screen:scaleBySize(20)
    local attack_x = x + 50

    if #self.table_attack > 0 then
        self:renderHandRow(bb, self.table_attack, attack_x, table_y, card_w, card_h, table_step, true, nil)
    end
    if #self.table_defend > 0 then
        local i
        for i = 1, #self.table_defend do
            local cx = attack_x + (i - 1) * table_step + Screen:scaleBySize(15)
            local cy = table_y + Screen:scaleBySize(15)
            self:renderCard(bb, cx, cy, self.table_defend[i], card_w, card_h, true)
        end
    end

    -- ===== Карты игрока =====
    local player_y = table_y + card_h + 40
    local player_step = Screen:scaleBySize(35)
    local total_w = (#self.player_hand - 1) * player_step + card_w
    if total_w > w - 60 then
        player_step = (w - 60 - card_w) / math.max(1, #self.player_hand - 1)
    end
    self.z_hand_x = left_x
    self.z_hand_y = player_y
    self.z_hand_step = player_step
    self.z_card_w = card_w
    self.z_card_h = card_h

    self:renderHandRow(bb, self.player_hand, left_x, player_y, card_w, card_h, player_step, true, self.selected_index)

    -- ===== РАСЧЁТ КНОПОК =====
    self.z_bet_w = Screen:scaleBySize(130)
    self.z_bet_h = Screen:scaleBySize(65)
    self.z_bet_gap = Screen:scaleBySize(10)
    local total_bets_w = #BET_VALUES * self.z_bet_w + (#BET_VALUES - 1) * self.z_bet_gap
    self.z_bet_x = x + (w - total_bets_w) / 2
    self.z_bet_y = y + game_h - self.z_bet_h - Screen:scaleBySize(15)

    self.z_action_w = Screen:scaleBySize(140)
    self.z_action_h = Screen:scaleBySize(60)
    self.z_action_gap = Screen:scaleBySize(12)
    self.z_action_y = self.z_bet_y - self.z_action_h - Screen:scaleBySize(15)

    local status_y = self.z_action_y - Screen:scaleBySize(30)
    local sw = RenderText:sizeUtf8Text(0, w, status_font, self.status).x
    RenderText:renderUtf8Text(bb, x + (w - sw) / 2, status_y,
        status_font, self.status, false, false, WIN_TEXT)

    -- ===== Кнопки действий =====
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
        RenderText:renderUtf8Text(bb, new_x + (new_w - lw) / 2, new_y + new_h / 2 + 8,
            btn_font, BTN_NEW, false, false, WIN_TEXT)
    else
        local total_btn_w = 4 * self.z_action_w + 3 * self.z_action_gap
        self.z_action_x = x + (w - total_btn_w) / 2

        local labels = { BTN_BEAT, BTN_TAKE, BTN_MOVE, BTN_PASS }
        local active = {
            (self.phase == "player_defend"),
            (self.phase == "player_defend"),
            (self.phase == "player_attack" and self.selected_card ~= nil),
            (self.phase == "player_attack" and #self.table_attack > 0),
        }
        local i
        for i = 1, 4 do
            local bx = self.z_action_x + (i - 1) * (self.z_action_w + self.z_action_gap)
            local col = active[i] and WIN_FACE or WIN_GRAY
            bb:paintRect(bx, self.z_action_y, self.z_action_w, self.z_action_h, col)
            bb:paintRect(bx, self.z_action_y, self.z_action_w, 2, WIN_LIGHT)
            bb:paintRect(bx, self.z_action_y, 2, self.z_action_h, WIN_LIGHT)
            bb:paintRect(bx, self.z_action_y + self.z_action_h - 2, self.z_action_w, 2, WIN_SHADOW)
            bb:paintRect(bx + self.z_action_w - 2, self.z_action_y, 2, self.z_action_h, WIN_SHADOW)
            local lw = RenderText:sizeUtf8Text(0, self.z_action_w, btn_font, labels[i]).x
            RenderText:renderUtf8Text(bb, bx + (self.z_action_w - lw) / 2,
                self.z_action_y + self.z_action_h / 2 + 8,
                btn_font, labels[i], false, false, WIN_TEXT)
        end
    end

    -- ===== Кнопки ставок =====
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
        RenderText:renderUtf8Text(bb, bx + (self.z_bet_w - lw) / 2,
            self.z_bet_y + self.z_bet_h / 2 + 9,
            bet_font, label, false, false, WIN_TEXT)
    end
end

return Durak