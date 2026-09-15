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

local Dice = InputContainer:extend{
    balance = 1000,
    bet = 10,
    chosen_bet_type = "seven",
    die1 = 0,
    die2 = 0,
    status = "Выберите ставку и жмите БРОСОК",
    on_result = nil,
    on_bet_change = nil,
    root_layout = nil,
    offset_y = 0,
    height = 0,

    z_row_h = 0,
    z_types = 0,
    z_btn_w = 0,
    z_btn_h = 0,
    z_gap = 0,
    z_bets = 0,
    z_bet_start_x = 0,
    z_roll_w = 0,
    z_roll_h = 0,
    z_roll = 0,
    z_roll_x = 0,
}

local BET_TYPES = {
    { key = "seven",   label = "Сумма = 7",   payout = 5, match = function(s) return s == 7 end },
    { key = "eleven",  label = "Сумма = 11",  payout = 6, match = function(s) return s == 11 end },
    { key = "low",     label = "Сумма 2-6",   payout = 2, match = function(s) return s >= 2 and s <= 6 end },
    { key = "high",    label = "Сумма 8-12",  payout = 2, match = function(s) return s >= 8 and s <= 12 end },
    { key = "doubles", label = "Дубли",       payout = 8, match = function(s, d1, d2) return d1 == d2 end },
}

local BET_VALUES = {5, 10, 25, 50}

function Dice:init()
end

function Dice:refresh()
    if self.root_layout then
        UIManager:setDirty(self.root_layout, "ui")
    else
        UIManager:setDirty(self, "ui")
    end
end

function Dice:doRoll()
    if self.balance < self.bet then
        self.status = "Недостаточно средств!"
        self:refresh()
        return
    end

    self.balance = self.balance - self.bet
    self.die1 = math.random(1, 6)
    self.die2 = math.random(1, 6)
    local total = self.die1 + self.die2

    local chosen
    local bt
    for _, bt in ipairs(BET_TYPES) do
        if bt.key == self.chosen_bet_type then chosen = bt break end
    end

    local win = 0
    if chosen.match(total, self.die1, self.die2) then
        win = self.bet * chosen.payout
        self.balance = self.balance + win
        self.status = string.format("Выпало %d! ВЫИГРЫШ $%d", total, win)
    else
        self.status = string.format("Выпало %d. Проигрыш.", total)
    end

    if self.on_result then
        self.on_result(self.bet, win, self.balance)
    end

    self:refresh()
end

function Dice:onTap(ges)
    local pos = ges.pos
    if self.z_types == 0 then return false end

    local i, bt
    for i, bt in ipairs(BET_TYPES) do
        local ry = self.z_types + (i - 1) * (self.z_row_h + 2)
        if pos.y >= ry and pos.y <= ry + self.z_row_h then
            self.chosen_bet_type = bt.key
            self:refresh()
            return true
        end
    end

    if pos.y >= self.z_bets and pos.y <= self.z_bets + self.z_btn_h then
        local j, val
        for j, val in ipairs(BET_VALUES) do
            local bx = self.z_bet_start_x + (j - 1) * (self.z_btn_w + self.z_gap)
            if pos.x >= bx and pos.x <= bx + self.z_btn_w then
                self.bet = val
                if self.on_bet_change then self.on_bet_change(val) end
                self:refresh()
                return true
            end
        end
    end

    if pos.y >= self.z_roll and pos.y <= self.z_roll + self.z_roll_h then
        if pos.x >= self.z_roll_x and pos.x <= self.z_roll_x + self.z_roll_w then
            self:doRoll()
            return true
        end
    end

    return false
end

function Dice:paintTo(bb, x, y)
    local w = bb:getWidth()
    local game_h = self.height

    self.offset_y = y

    bb:paintRect(x, y, w, game_h, WIN_FACE)

    local big   = Font:getFace("cfont", 64)
    local med   = Font:getFace("cfont", 24)
    local small = Font:getFace("cfont", 20)

    -- ============================================================
    -- Кубики (верх)
    -- ============================================================
    local cur_y = y + 30
    local dice_text
    if self.die1 == 0 then
        dice_text = "[ ]   [ ]"
    else
        dice_text = "[" .. self.die1 .. "]   [" .. self.die2 .. "]"
    end
    local dw = RenderText:sizeUtf8Text(0, w, big, dice_text).x
    RenderText:renderUtf8Text(bb, x + (w - dw) / 2, cur_y + 70,
        big, dice_text, false, false, WIN_TEXT)

    -- ============================================================
    -- Статус
    -- ============================================================
    local status_y = y + 160
    local sw = RenderText:sizeUtf8Text(0, w, med, self.status).x
    RenderText:renderUtf8Text(bb, x + (w - sw) / 2, status_y + 28,
        med, self.status, false, false, WIN_TEXT)

    -- ============================================================
    -- Типы ставок
    -- ============================================================
    self.z_row_h = 48
    self.z_types = y + 220

    cur_y = self.z_types
    local i, bt
    for i, bt in ipairs(BET_TYPES) do
        local is_active = (bt.key == self.chosen_bet_type)
        local rx = x + Screen:scaleBySize(40)
        local rw = w - Screen:scaleBySize(80)

        if is_active then
            bb:paintRect(rx, cur_y, rw, self.z_row_h, WIN_FACE)
            bb:paintRect(rx, cur_y, rw, 2, WIN_SHADOW)
            bb:paintRect(rx, cur_y, 2, self.z_row_h, WIN_SHADOW)
            bb:paintRect(rx, cur_y + self.z_row_h - 2, rw, 2, WIN_LIGHT)
            bb:paintRect(rx + rw - 2, cur_y, 2, self.z_row_h, WIN_LIGHT)
        else
            bb:paintRect(rx, cur_y, rw, 1, WIN_SHADOW)
            bb:paintRect(rx, cur_y + self.z_row_h - 1, rw, 1, WIN_SHADOW)
        end

        local label = string.format("%s   выплата %d:1", bt.label, bt.payout)
        local lw = RenderText:sizeUtf8Text(0, rw, small, label).x
        RenderText:renderUtf8Text(bb, rx + (rw - lw) / 2, cur_y + self.z_row_h / 2 + 8,
            small, label, false, false, WIN_TEXT)

        cur_y = cur_y + self.z_row_h + 2
    end

    -- ============================================================
    -- Кнопки ставок (самый низ игровой зоны)
    -- ============================================================
    self.z_btn_w = Screen:scaleBySize(140)
    self.z_btn_h = Screen:scaleBySize(70)
    self.z_gap = Screen:scaleBySize(10)
    local total_w = #BET_VALUES * self.z_btn_w + (#BET_VALUES - 1) * self.z_gap
    self.z_bet_start_x = x + (w - total_w) / 2
    self.z_bets = y + game_h - self.z_btn_h - Screen:scaleBySize(15)

    local j, val
    for j, val in ipairs(BET_VALUES) do
        local bx = self.z_bet_start_x + (j - 1) * (self.z_btn_w + self.z_gap)
        local is_active = (val == self.bet)

        if is_active then
            bb:paintRect(bx, self.z_bets, self.z_btn_w, self.z_btn_h, WIN_FACE)
            bb:paintRect(bx, self.z_bets, self.z_btn_w, 2, WIN_SHADOW)
            bb:paintRect(bx, self.z_bets, 2, self.z_btn_h, WIN_SHADOW)
            bb:paintRect(bx, self.z_bets + self.z_btn_h - 2, self.z_btn_w, 2, WIN_LIGHT)
            bb:paintRect(bx + self.z_btn_w - 2, self.z_bets, 2, self.z_btn_h, WIN_LIGHT)
        else
            bb:paintRect(bx, self.z_bets, self.z_btn_w, self.z_btn_h, WIN_FACE)
            bb:paintRect(bx, self.z_bets, self.z_btn_w, 2, WIN_LIGHT)
            bb:paintRect(bx, self.z_bets, 2, self.z_btn_h, WIN_LIGHT)
            bb:paintRect(bx, self.z_bets + self.z_btn_h - 2, self.z_btn_w, 2, WIN_SHADOW)
            bb:paintRect(bx + self.z_btn_w - 2, self.z_bets, 2, self.z_btn_h, WIN_SHADOW)
        end

        local label = "$" .. val
        local lw = RenderText:sizeUtf8Text(0, self.z_btn_w, med, label).x
        RenderText:renderUtf8Text(bb, bx + (self.z_btn_w - lw) / 2, self.z_bets + self.z_btn_h / 2 + 8,
            med, label, false, false, WIN_TEXT)
    end

    -- ============================================================
    -- Кнопка БРОСОК (над ставками)
    -- ============================================================
    self.z_roll_w = Screen:scaleBySize(450)
    self.z_roll_h = Screen:scaleBySize(90)
    self.z_roll = self.z_bets - self.z_roll_h - Screen:scaleBySize(20)
    self.z_roll_x = x + (w - self.z_roll_w) / 2

    bb:paintRect(self.z_roll_x, self.z_roll, self.z_roll_w, self.z_roll_h, WIN_FACE)
    bb:paintRect(self.z_roll_x, self.z_roll, self.z_roll_w, 2, WIN_LIGHT)
    bb:paintRect(self.z_roll_x, self.z_roll, 2, self.z_roll_h, WIN_LIGHT)
    bb:paintRect(self.z_roll_x, self.z_roll + self.z_roll_h - 2, self.z_roll_w, 2, WIN_SHADOW)
    bb:paintRect(self.z_roll_x + self.z_roll_w - 2, self.z_roll, 2, self.z_roll_h, WIN_SHADOW)

    local roll_label = "БРОСОК"
    local rlw = RenderText:sizeUtf8Text(0, self.z_roll_w, big, roll_label).x
    RenderText:renderUtf8Text(bb,
        self.z_roll_x + (self.z_roll_w - rlw) / 2,
        self.z_roll + self.z_roll_h / 2 + 22,
        big, roll_label, false, false, WIN_TEXT)
end

return Dice