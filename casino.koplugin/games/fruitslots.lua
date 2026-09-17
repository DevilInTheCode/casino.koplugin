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

local FruitSlots = InputContainer:extend{
    balance = 1000,
    bet = 1,
    lines = 9,
    phase = "idle",
    reels = {{}, {}, {}, {}, {}},
    final_reels = {{}, {}, {}, {}, {}},
    win_amount = 0,
    status = "Нажмите СТАРТ",
    on_result = nil,
    on_bet_change = nil,
    root_layout = nil,
    offset_y = 0,
    height = 0,

    risk_dealer = nil,
    risk_cards = {},
    risk_revealed = 0,
    risk_win = 0,

    bonus_lives = 0,
    bonus_sectors = {},
    bonus_marker = 0,
    bonus_center = {},
    bonus_total_win = 0,

    winning_lines = {},
    winner_symbol = nil,

    z_start_x = 0, z_start_y = 0, z_start_w = 0, z_start_h = 0,
    z_lines_x = 0, z_lines_y = 0, z_lines_w = 0, z_lines_h = 0,
    z_bet_y = 0, z_bet_h = 0, z_bet_w = 0, z_bet_gap = 0, z_bet_x = 0,
    z_risk_x1 = 0, z_risk_x2 = 0, z_risk_w = 0, z_risk_y = 0, z_risk_h = 0,
    z_card_x = 0, z_card_y = 0, z_card_w = 0, z_card_h = 0,
}

local SYMBOLS = {"●", "♥", "◆", "★", "♠", "♦", "♣", "FC"}
local PAYOUTS = {
    ["FC"]  = {200, 1000, 5000},
    ["♣"]   = {100, 500, 2000},
    ["★"]   = {30, 100, 500},
    ["♠"]   = {20, 50, 200},
    ["♦"]   = {10, 30, 100},
    ["♥"]   = {5, 10, 50},
    ["◆"]   = {3, 5, 20},
    ["●"]   = {2, 3, 10},
}
local BONUS_SYMBOL = "S"
local WILD = "♣"
local LOGO = "FC"

local LINES = {
    {1, 1, 1, 1, 1},
    {0, 0, 0, 0, 0},
    {2, 2, 2, 2, 2},
    {0, 1, 2, 1, 0},
    {2, 1, 0, 1, 2},
    {1, 1, 0, 1, 1},
    {1, 1, 2, 1, 1},
    {0, 1, 0, 1, 0},
    {2, 1, 2, 1, 2},
}
local LINE_VALUES = {1, 3, 5, 7, 9}
local BET_VALUES = {1, 2, 5, 10, 20, 25}

local SUITS = {"♠", "♥", "♦", "♣"}
local RANKS = {"2","3","4","5","6","7","8","9","10","J","Q","K","A"}

local HELP_ROWS = {
    { sym = "FC", name = "FC",   c3 = "200",  c4 = "1000", c5 = "5000" },
    { sym = "♣",  name = "WILD", c3 = "100",  c4 = "500",  c5 = "2000" },
    { sym = "★",  name = "★",    c3 = "30",   c4 = "100",  c5 = "500"  },
    { sym = "♠",  name = "♠",    c3 = "20",   c4 = "50",   c5 = "200"  },
    { sym = "♦",  name = "♦",    c3 = "10",   c4 = "30",   c5 = "100"  },
    { sym = "♥",  name = "♥",    c3 = "5",    c4 = "10",   c5 = "50"   },
    { sym = "◆",  name = "◆",    c3 = "3",    c4 = "5",    c5 = "20"   },
    { sym = "●",  name = "●",    c3 = "2",    c4 = "3",    c5 = "10"   },
}

function FruitSlots:init()
    math.randomseed(os.time() + math.random(1000000))
    self:generateBonusSectors()
end

function FruitSlots:refresh()
    if self.root_layout then
        UIManager:setDirty(self.root_layout, "ui")
    else
        UIManager:setDirty(self, "ui")
    end
end

function FruitSlots:randomSymbol()
    local weights = {
        ["●"] = 20, ["♥"] = 18, ["◆"] = 16, ["★"] = 12,
        ["♠"] = 10, ["♦"] = 8, ["♣"] = 6, ["FC"] = 3,
        [BONUS_SYMBOL] = 4,
    }
    local total = 0
    local sym
    for sym, w in pairs(weights) do total = total + w end
    local r = math.random(total)
    local acc = 0
    for sym, w in pairs(weights) do
        acc = acc + w
        if r <= acc then return sym end
    end
    return "●"
end

function FruitSlots:spinReels()
    local reels = {}
    local i, j
    for i = 1, 5 do
        reels[i] = {}
        for j = 1, 3 do
            reels[i][j] = self:randomSymbol()
        end
    end
    return reels
end

function FruitSlots:start()
    if self.phase ~= "idle" and self.phase ~= "done" then return end

    local total_bet = self.bet * self.lines
    if self.balance < total_bet then
        self.status = "Недостаточно средств!"
        self:refresh()
        return
    end

    self.balance = self.balance - total_bet
    if self.on_result then
        self.on_result(total_bet, 0, self.balance)
    end

    self.winning_lines = {}
    self.winner_symbol = nil

    self.phase = "spinning"
    self.win_amount = 0
    self.final_reels = self:spinReels()

    local this = self
    local frame = 0
    local function tick()
        frame = frame + 1
        if frame <= 4 then
            this.reels = this:spinReels()
            this:refresh()
            UIManager:scheduleIn(0.3, tick)
        else
            this.reels = this.final_reels
            this:checkWins()
        end
    end
    self.reels = self:spinReels()
    self:refresh()
    UIManager:scheduleIn(0.3, tick)
end

function FruitSlots:checkChainFromEdge(symbols, direction)
    local n = #symbols
    local start_idx = (direction == 1) and 1 or n
    local step = direction

    local best_count = 0
    local best_sym = nil

    for _, sym in ipairs(SYMBOLS) do
        local count = 0
        local idx = start_idx
        while idx >= 1 and idx <= n do
            local s = symbols[idx]
            if s == sym then
                count = count + 1
            elseif s == WILD and sym ~= LOGO then
                count = count + 1
            else
                break
            end
            idx = idx + step
        end
        if count > best_count then
            best_count = count
            best_sym = sym
        end
    end

    return best_count, best_sym
end

function FruitSlots:checkWins()
    self.winning_lines = {}
    self.winner_symbol = nil
    local total_win = 0
    local best_payout = 0

    local line_idx
    for line_idx = 1, self.lines do
        local coords = LINES[line_idx]
        local line_symbols = {}
        local i
        for i = 1, 5 do
            local row = coords[i] + 1
            line_symbols[i] = self.reels[i][row]
        end

        local count_left, sym_left = self:checkChainFromEdge(line_symbols, 1)

        if count_left == 5 then
            local payout = PAYOUTS[sym_left] and PAYOUTS[sym_left][3]
            if payout then
                local cells = {}
                for i = 1, 5 do
                    cells[#cells + 1] = { reel = i, row = coords[i] + 1 }
                end
                self.winning_lines[#self.winning_lines + 1] = {
                    line = line_idx, cells = cells,
                    sym = sym_left, count = 5, payout = payout,
                }
                total_win = total_win + payout * self.bet
                if payout > best_payout then
                    best_payout = payout
                    self.winner_symbol = sym_left
                end
            end
        else
            if count_left >= 3 then
                local payout = PAYOUTS[sym_left] and PAYOUTS[sym_left][count_left - 2]
                if payout then
                    local cells = {}
                    for i = 1, count_left do
                        cells[#cells + 1] = { reel = i, row = coords[i] + 1 }
                    end
                    self.winning_lines[#self.winning_lines + 1] = {
                        line = line_idx, cells = cells,
                        sym = sym_left, count = count_left, payout = payout,
                    }
                    total_win = total_win + payout * self.bet
                    if payout > best_payout then
                        best_payout = payout
                        self.winner_symbol = sym_left
                    end
                end
            end

            local count_right, sym_right = self:checkChainFromEdge(line_symbols, -1)
            if count_right >= 3 then
                local payout = PAYOUTS[sym_right] and PAYOUTS[sym_right][count_right - 2]
                if payout then
                    local cells = {}
                    for i = 1, count_right do
                        local reel = 5 - i + 1
                        cells[#cells + 1] = { reel = reel, row = coords[reel] + 1 }
                    end
                    table.sort(cells, function(a, b) return a.reel < b.reel end)
                    self.winning_lines[#self.winning_lines + 1] = {
                        line = line_idx, cells = cells,
                        sym = sym_right, count = count_right, payout = payout,
                    }
                    total_win = total_win + payout * self.bet
                    if payout > best_payout then
                        best_payout = payout
                        self.winner_symbol = sym_right
                    end
                end
            end
        end
    end

    local bonus_count = 0
    local i, j
    for i = 1, 5 do
        for j = 1, 3 do
            if self.reels[i][j] == BONUS_SYMBOL then
                bonus_count = bonus_count + 1
            end
        end
    end

    if bonus_count >= 3 then
        self.bonus_lives = bonus_count - 2
        self.status = string.format("БОНУС! S: %d, жизней: %d", bonus_count, self.bonus_lives)
        self.phase = "bonus_start"
        self:refresh()
        local this = self
        UIManager:scheduleIn(1.5, function() this:startBonus() end)
        return
    end

    self.win_amount = total_win
    if total_win > 0 then
        self.balance = self.balance + total_win
        if self.on_result then
            self.on_result(0, total_win, self.balance)
        end
        self.status = string.format("ВЫИГРЫШ $%d! ЗАБРАТЬ или РИСК?", total_win)
        self.phase = "result"
    else
        self.status = "Нет выигрыша. Попробуйте ещё"
        self.phase = "idle"
    end
    self:refresh()
end

-- ============ РИСК-ИГРА ============
function FruitSlots:startRisk()
    if self.win_amount <= 0 then return end
    self.risk_win = self.win_amount
    self.risk_revealed = 0
    self.risk_cards = {}
    self.risk_dealer = self:randomCard()

    local i
    for i = 1, 4 do
        self.risk_cards[i] = self:randomCard()
    end

    self.phase = "risk"
    self.status = string.format("Дилер: %s. Выберите карту или ЗАБЕРИТЕ", self.risk_dealer)
    self:refresh()
end

function FruitSlots:randomCard()
    local rank = RANKS[math.random(#RANKS)]
    local suit = SUITS[math.random(#SUITS)]
    return rank .. suit
end

function FruitSlots:cardValue(card)
    local rank = ""
    local i
    for i = #card, 1, -1 do
        local b = card:byte(i)
        if b < 128 or b >= 192 then
            rank = card:sub(1, i - 1)
            break
        end
    end
    local map = {["2"]=2,["3"]=3,["4"]=4,["5"]=5,["6"]=6,["7"]=7,
                 ["8"]=8,["9"]=9,["10"]=10,["J"]=11,["Q"]=12,["K"]=13,["A"]=14}
    return map[rank] or 0
end

function FruitSlots:riskChoose(idx)
    if self.phase ~= "risk" then return end
    if idx < 1 or idx > 4 then return end
    if self.risk_cards[idx] == nil then return end

    local player_card = self.risk_cards[idx]
    local dealer_val = self:cardValue(self.risk_dealer)
    local player_val = self:cardValue(player_card)

    self.risk_revealed = idx

    if player_val > dealer_val then
        self.risk_win = self.risk_win * 2
        self.status = string.format("Ваша карта: %s. ВЫИГРЫШ $%d! ЗАБРАТЬ или ЕЩЁ РАЗ?", player_card, self.risk_win)
        self.phase = "risk_result"
    elseif player_val < dealer_val then
        self.status = string.format("Ваша карта: %s. Проигрыш.", player_card)
        self.risk_win = 0
        self.phase = "risk_lost"
        local this = self
        UIManager:scheduleIn(1.5, function()
            this.phase = "idle"
            this.status = "Нажмите СТАРТ"
            this.risk_revealed = 0
            this:refresh()
        end)
    else
        self.status = string.format("Ваша карта: %s. Ничья — переигровка", player_card)
        local this = self
        UIManager:scheduleIn(1.0, function()
            this.risk_dealer = this:randomCard()
            this.risk_cards = {}
            local i
            for i = 1, 4 do
                this.risk_cards[i] = this:randomCard()
            end
            this.risk_revealed = 0
            this.phase = "risk"
            this.status = string.format("Дилер: %s. Выберите карту", this.risk_dealer)
            this:refresh()
        end)
    end
    self:refresh()
end

function FruitSlots:riskTake()
    if self.phase ~= "risk" and self.phase ~= "risk_result" then return end
    if self.risk_win > 0 then
        self.balance = self.balance + self.risk_win
        if self.on_result then
            self.on_result(0, self.risk_win, self.balance)
        end
        self.status = string.format("Забрано $%d", self.risk_win)
    else
        self.status = "Забрано $0"
    end
    self.risk_win = 0
    self.risk_revealed = 0
    self.phase = "idle"
    self:refresh()
end

function FruitSlots:riskAgain()
    if self.phase ~= "risk_result" then return end
    self.risk_revealed = 0
    self.risk_cards = {}
    self.risk_dealer = self:randomCard()
    local i
    for i = 1, 4 do
        self.risk_cards[i] = self:randomCard()
    end
    self.phase = "risk"
    self.status = string.format("Дилер: %s. Выберите карту", self.risk_dealer)
    self:refresh()
end

-- ============ БОНУС ============
function FruitSlots:generateBonusSectors()
    local bonus_fruits = {"●", "♥", "◆", "★", "♠", "♦", "♣", "FC"}
    local bonus_payouts = {2, 3, 5, 20, 10, 5, 50, 100}

    self.bonus_sectors = {}
    local exit_positions = {1, 8, 15, 22}
    local exit_set = {}
    for _, p in ipairs(exit_positions) do exit_set[p] = true end

    local i
    local fruit_idx = 1
    for i = 1, 26 do
        if exit_set[i] then
            self.bonus_sectors[i] = { sym = "EXIT", payout = 0 }
        else
            local sym = bonus_fruits[fruit_idx]
            local pay = bonus_payouts[fruit_idx]
            self.bonus_sectors[i] = { sym = sym, payout = pay }
            fruit_idx = fruit_idx + 1
            if fruit_idx > #bonus_fruits then fruit_idx = 1 end
        end
    end
end

function FruitSlots:startBonus()
    self.phase = "bonus"
    self.bonus_total_win = 0
    self.bonus_marker = 0
    self.bonus_center = {}
    self:bonusSpin()
end

function FruitSlots:bonusSpin()
    if self.bonus_lives <= 0 then
        self:endBonus()
        return
    end

    self.bonus_center = {
        self:randomSymbol(),
        self:randomSymbol(),
        self:randomSymbol(),
    }

    local this = self
    local frame = 0
    local function tick()
        frame = frame + 1
        if frame <= 5 then
            this.bonus_marker = math.random(26)
            this.status = string.format("Жизней: %d", this.bonus_lives)
            this:refresh()
            UIManager:scheduleIn(0.25, tick)
        else
            this.bonus_marker = math.random(26)
            this:bonusResolve()
        end
    end
    tick()
end

function FruitSlots:bonusResolve()
    local sector = self.bonus_sectors[self.bonus_marker]
    if not sector then
        self:endBonus()
        return
    end

    if sector.sym == "EXIT" then
        self.bonus_lives = self.bonus_lives - 1
        if self.bonus_lives > 0 then
            self.status = string.format("EXIT! Осталось жизней: %d", self.bonus_lives)
            self:refresh()
            UIManager:scheduleIn(1.0, function() self:bonusSpin() end)
        else
            self.status = "EXIT! Бонус окончен"
            self:refresh()
            UIManager:scheduleIn(1.0, function() self:endBonus() end)
        end
        return
    end

    local matches = 0
    local i
    for i = 1, 3 do
        if self.bonus_center[i] == sector.sym then
            matches = matches + 1
        end
    end

    if matches > 0 then
        local win = self.bet * self.lines * sector.payout * matches
        self.bonus_total_win = self.bonus_total_win + win
        self.status = string.format("Совпадение! %s ×%d = $%d", sector.sym, matches, win)
    else
        self.status = string.format("Маркер: %s. Не совпало", sector.sym)
    end

    self:refresh()
    UIManager:scheduleIn(1.5, function() self:bonusSpin() end)
end

function FruitSlots:endBonus()
    if self.bonus_total_win > 0 then
        self.balance = self.balance + self.bonus_total_win
        if self.on_result then
            self.on_result(0, self.bonus_total_win, self.balance)
        end
        self.status = string.format("Бонус окончен. Выигрыш $%d", self.bonus_total_win)
    else
        self.status = "Бонус окончен без выигрыша"
    end
    self.bonus_total_win = 0
    self.phase = "idle"
    self:refresh()
end

-- ============ ОБРАБОТКА ТАПОВ ============
function FruitSlots:onTap(ges)
    if self.z_start_y == 0 and self.z_risk_y == 0 then return false end
    local pos = ges.pos

    if self.phase == "risk" then
        if pos.y >= self.z_risk_y and pos.y <= self.z_risk_y + self.z_risk_h then
            if pos.x >= self.z_risk_x1 and pos.x <= self.z_risk_x1 + self.z_risk_w then
                self:riskTake()
                return true
            end
        end
        local i
        for i = 1, 4 do
            local cx = self.z_card_x + (i - 1) * (self.z_card_w + Screen:scaleBySize(15))
            if pos.x >= cx and pos.x <= cx + self.z_card_w
               and pos.y >= self.z_card_y and pos.y <= self.z_card_y + self.z_card_h then
                self:riskChoose(i)
                return true
            end
        end
        return true
    end

    if self.phase == "risk_result" then
        if pos.y >= self.z_risk_y and pos.y <= self.z_risk_y + self.z_risk_h then
            if pos.x >= self.z_risk_x1 and pos.x <= self.z_risk_x1 + self.z_risk_w then
                self:riskTake()
                return true
            end
            if pos.x >= self.z_risk_x2 and pos.x <= self.z_risk_x2 + self.z_risk_w then
                self:riskAgain()
                return true
            end
        end
        return true
    end

    if self.phase == "risk_lost" then
        return true
    end

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

    if pos.y >= self.z_start_y and pos.y <= self.z_start_y + self.z_start_h then
        if pos.x >= self.z_start_x and pos.x <= self.z_start_x + self.z_start_w then
            if self.phase == "idle" or self.phase == "done" then
                self:start()
            elseif self.phase == "result" then
                if self.win_amount > 0 then
                    self.balance = self.balance + self.win_amount
                    if self.on_result then
                        self.on_result(0, self.win_amount, self.balance)
                    end
                end
                self.win_amount = 0
                self.winning_lines = {}
                self.winner_symbol = nil
                self.phase = "idle"
                self.status = "Забрано. Нажмите СТАРТ"
                self:refresh()
            end
            return true
        end
    end

    if pos.y >= self.z_lines_y and pos.y <= self.z_lines_y + self.z_lines_h then
        if pos.x >= self.z_lines_x and pos.x <= self.z_lines_x + self.z_lines_w then
            if self.phase == "idle" or self.phase == "done" then
                local idx = 1
                local i
                for i, v in ipairs(LINE_VALUES) do
                    if v == self.lines then idx = i break end
                end
                idx = idx + 1
                if idx > #LINE_VALUES then idx = 1 end
                self.lines = LINE_VALUES[idx]
                self:refresh()
            elseif self.phase == "result" then
                if self.win_amount > 0 then
                    self:startRisk()
                end
            end
            return true
        end
    end

    return false
end

-- ============ ОТРИСОВКА ============

-- Рисует звезду вокруг символа S (клубничка)
function FruitSlots:renderStar(bb, x, y, w, h, color)
    local cx = x + w / 2
    local cy = y + h / 2
    local r_out = math.min(w, h) / 2 - 4
    local r_in = r_out / 2

    local points = {}
    local i
    for i = 0, 9 do
        local angle = math.rad(-90 + i * 36)
        local r = (i % 2 == 0) and r_out or r_in
        points[#points + 1] = {
            x = cx + math.cos(angle) * r,
            y = cy + math.sin(angle) * r,
        }
    end

    -- Рисуем 10 линий между точками
    for i = 1, 10 do
        local p1 = points[i]
        local p2 = points[(i % 10) + 1]
        self:drawCustomLine(bb, p1.x, p1.y, p2.x, p2.y, 2, color, false)
    end
end

function FruitSlots:renderSymbolWithDim(bb, x, y, w, h, sym, is_winner, is_dimmed)
    bb:paintRect(x, y, w, h, WIN_LIGHT)

    local border_thick = is_winner and 4 or 2
    local current_text_color = is_dimmed and WIN_GRAY or WIN_TEXT

    bb:paintRect(x, y, w, border_thick, WIN_TEXT)
    bb:paintRect(x, y + h - border_thick, w, border_thick, WIN_TEXT)
    bb:paintRect(x, y, border_thick, h, WIN_TEXT)
    bb:paintRect(x + w - border_thick, y, border_thick, h, WIN_TEXT)

    local f = Font:getFace("cfont", 32)
    local tw = RenderText:sizeUtf8Text(0, w, f, sym).x
    RenderText:renderUtf8Text(bb, x + (w - tw) / 2, y + h / 2 + 12,
        f, sym, false, false, current_text_color)

    -- Если это клубничка (бонус) — рисуем вокруг неё звезду
    if sym == BONUS_SYMBOL then
        self:renderStar(bb, x, y, w, h, WIN_TEXT)
    end
end

function FruitSlots:drawCustomLine(bb, x1, y1, x2, y2, thick, color, is_dashed)
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy
    local x, y = x1, y1

    local pixel_count = 0

    while true do
        if not is_dashed or (math.floor(pixel_count / 6) % 2 == 0) then
            bb:paintRect(x - math.floor(thick / 2), y - math.floor(thick / 2), thick, thick, color)
        end

        if x == x2 and y == y2 then break end
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; x = x + sx end
        if e2 < dx then err = err + dx; y = y + sy end

        pixel_count = pixel_count + 1
    end
end

function FruitSlots:paintTo(bb, x, y)
    local w = bb:getWidth()
    local game_h = self.height

    self.offset_y = y
    bb:paintRect(x, y, w, game_h, WIN_FACE)

    if self.phase == "risk" or self.phase == "risk_result" or self.phase == "risk_lost" then
        self:paintRisk(bb, x, y, w, game_h)
        return
    end
    if self.phase == "bonus" or self.phase == "bonus_start" then
        self:paintBonus(bb, x, y, w, game_h)
        return
    end

    local label_font = Font:getFace("cfont", 18)
    local status_font = Font:getFace("cfont", 20)
    local btn_font = Font:getFace("cfont", 22)
    local help_font = Font:getFace("cfont", 16)

    local left_x = x + 20
    local top_y = y + 45

    RenderText:renderUtf8Text(bb, left_x, top_y,
        label_font, string.format("СТАВКА: $%d  ЛИНИЙ: %d  БАНК: $%d",
            self.bet * self.lines, self.lines, self.balance),
        false, false, WIN_TEXT)

    local reel_y = top_y + 35
    local cell_w = Screen:scaleBySize(105)
    local cell_h = Screen:scaleBySize(80)
    local gap = Screen:scaleBySize(4)

    local field_w = 5 * cell_w + 4 * gap
    local side_marker_w = Screen:scaleBySize(35)
    local field_x = x + (w - field_w) / 2

    -- Определяем выигравшие ячейки и линии
    local winner_cells = {}
    local active_lines_map = {}
    if #self.winning_lines > 0 then
        local wl_idx
        for wl_idx = 1, #self.winning_lines do
            local wl = self.winning_lines[wl_idx]
            active_lines_map[wl.line] = true
            for _, cell in ipairs(wl.cells) do
                winner_cells[cell.reel .. ":" .. cell.row] = true
            end
        end
    end

    -- ===== ШАГ 1: Боковые маркеры линий =====
    local left_markers  = { {2, 4, 8}, {1, 6, 7}, {3, 5, 9} }
    local right_markers = { {2, 5, 8}, {1, 6, 7}, {3, 4, 9} }

    local row_idx
    for row_idx = 1, 3 do
        local cy = reel_y + (row_idx - 1) * (cell_h + gap) + cell_h / 2

        local l_list = left_markers[row_idx]
        local idx, l_num
        for idx, l_num in ipairs(l_list) do
            if l_num <= self.lines then
                local mx = field_x - side_marker_w - 5 + (idx - 1) * Screen:scaleBySize(10)
                local my = cy - Screen:scaleBySize(10)
                local mw = Screen:scaleBySize(12)
                local mh = Screen:scaleBySize(18)

                if active_lines_map[l_num] then
                    bb:paintRect(mx, my, mw, mh, WIN_TEXT)
                    RenderText:renderUtf8Text(bb, mx + 2, my + mh / 2 + 5, help_font,
                        tostring(l_num), false, false, WIN_LIGHT)
                else
                    RenderText:renderUtf8Text(bb, mx, my + mh / 2 + 5, help_font,
                        tostring(l_num), false, false, WIN_GRAY)
                end
            end
        end

        local r_list = right_markers[row_idx]
        for idx, l_num in ipairs(r_list) do
            if l_num <= self.lines then
                local mx = field_x + field_w + 5 + (idx - 1) * Screen:scaleBySize(10)
                local my = cy - Screen:scaleBySize(10)
                local mw = Screen:scaleBySize(12)
                local mh = Screen:scaleBySize(18)

                if active_lines_map[l_num] then
                    bb:paintRect(mx, my, mw, mh, WIN_TEXT)
                    RenderText:renderUtf8Text(bb, mx + 2, my + mh / 2 + 5, help_font,
                        tostring(l_num), false, false, WIN_LIGHT)
                else
                    RenderText:renderUtf8Text(bb, mx, my + mh / 2 + 5, help_font,
                        tostring(l_num), false, false, WIN_GRAY)
                end
            end
        end
    end

    -- ===== ШАГ 2: Барабаны =====
    local i, j
    for i = 1, 5 do
        for j = 1, 3 do
            local cx = field_x + (i - 1) * (cell_w + gap)
            local cy = reel_y + (j - 1) * (cell_h + gap)
            local sym = "?"
            if self.reels[i] and self.reels[i][j] then
                sym = self.reels[i][j]
            end
            local is_winner = winner_cells[i .. ":" .. j] or false
            local dim_light = (#self.winning_lines > 0 and not is_winner)
            self:renderSymbolWithDim(bb, cx, cy, cell_w, cell_h, sym, is_winner, dim_light)
        end
    end

    -- ===== ШАГ 3: Выигрышные линии =====
    if #self.winning_lines > 0 then
        local line_offsets = { -12, -9, -6, -3, 0, 3, 6, 9, 12 }
        local wl_idx
        for wl_idx = 1, #self.winning_lines do
            local wl = self.winning_lines[wl_idx]
            local offset_y = line_offsets[wl.line] or 0
            local coords = LINES[wl.line]

            -- Шлейф от левого маркера до 1-го барабана
            local start_row = coords[1] + 1
            local lx1 = field_x - 10
            local ly1 = reel_y + (start_row - 1) * (cell_h + gap) + cell_h / 2 + offset_y
            local lx2 = field_x + cell_w / 2
            self:drawCustomLine(bb, lx1, ly1, lx2, ly1, 6, WIN_LIGHT, false)
            self:drawCustomLine(bb, lx1, ly1, lx2, ly1, 2, WIN_TEXT, false)

            -- Основная траектория
            local reel_idx
            for reel_idx = 1, 4 do
                local row1 = coords[reel_idx] + 1
                local row2 = coords[reel_idx + 1] + 1

                local x1 = field_x + (reel_idx - 1) * (cell_w + gap) + cell_w / 2
                local y1 = reel_y + (row1 - 1) * (cell_h + gap) + cell_h / 2 + offset_y

                local x2 = field_x + (reel_idx) * (cell_w + gap) + cell_w / 2
                local y2 = reel_y + (row2 - 1) * (cell_h + gap) + cell_h / 2 + offset_y

                local is_dashed = (wl.line % 2 == 0)

                self:drawCustomLine(bb, x1, y1, x2, y2, 8, WIN_LIGHT, false)
                self:drawCustomLine(bb, x1, y1, x2, y2, 3, WIN_TEXT, is_dashed)
            end

            -- Шлейф от 5-го барабана до правого маркера
            local end_row = coords[5] + 1
            local rx1 = field_x + field_w - cell_w / 2
            local ry1 = reel_y + (end_row - 1) * (cell_h + gap) + cell_h / 2 + offset_y
            local rx2 = field_x + field_w + 10
            self:drawCustomLine(bb, rx1, ry1, rx2, ry1, 6, WIN_LIGHT, false)
            self:drawCustomLine(bb, rx1, ry1, rx2, ry1, 2, WIN_TEXT, false)
        end

        -- ===== ШАГ 4: Перерисовка выигравших ячеек поверх линий =====
        for wl_idx = 1, #self.winning_lines do
            local wl = self.winning_lines[wl_idx]
            for _, cell in ipairs(wl.cells) do
                local cx = field_x + (cell.reel - 1) * (cell_w + gap)
                local cy = reel_y + (cell.row - 1) * (cell_h + gap)
                local sym = self.reels[cell.reel][cell.row] or "?"
                self:renderSymbolWithDim(bb, cx, cy, cell_w, cell_h, sym, true, false)
            end
        end
    end

    -- Номера линий под полем
    local lines_y = reel_y + 3 * cell_h + 3 * gap + 30
    RenderText:renderUtf8Text(bb, left_x, lines_y,
        label_font, "ЛИНИИ:", false, false, WIN_TEXT)
    local line_x = left_x + Screen:scaleBySize(80)
    for i = 1, 9 do
        local active = (i <= self.lines)
        local col = active and WIN_TEXT or WIN_GRAY
        RenderText:renderUtf8Text(bb, line_x + (i - 1) * Screen:scaleBySize(30),
            lines_y, label_font, tostring(i), false, false, col)
    end

    -- Справка
    local help_y = lines_y + 50
    RenderText:renderUtf8Text(bb, left_x, help_y,
        help_font, "СИМВОЛ   ×3     ×4     ×5", false, false, WIN_TEXT)
    help_y = help_y + 30

    local row_i
    for row_i = 1, #HELP_ROWS do
        local row = HELP_ROWS[row_i]
        local is_winner = (self.winner_symbol and row.sym == self.winner_symbol)
        local line_text = string.format("%-5s   %-5s  %-5s  %-5s",
            row.name, row.c3, row.c4, row.c5)

        if is_winner then
            local tw = RenderText:sizeUtf8Text(0, w, help_font, line_text).x
            bb:paintRect(left_x - 2, help_y - 16, tw + 6, 24, WIN_TEXT)
            RenderText:renderUtf8Text(bb, left_x, help_y,
                help_font, line_text, false, false, WIN_LIGHT)
        else
            RenderText:renderUtf8Text(bb, left_x, help_y,
                help_font, line_text, false, false, WIN_TEXT)
        end
        help_y = help_y + 30
    end

    -- Кнопки
    self.z_bet_w = Screen:scaleBySize(100)
    self.z_bet_h = Screen:scaleBySize(55)
    self.z_bet_gap = Screen:scaleBySize(8)
    local total_bets_w = #BET_VALUES * self.z_bet_w + (#BET_VALUES - 1) * self.z_bet_gap
    self.z_bet_x = x + (w - total_bets_w) / 2
    self.z_bet_y = y + game_h - self.z_bet_h - Screen:scaleBySize(15)

    self.z_start_w = Screen:scaleBySize(200)
    self.z_start_h = Screen:scaleBySize(55)
    self.z_start_x = x + (w - self.z_start_w) / 2 - Screen:scaleBySize(120)
    self.z_start_y = self.z_bet_y - self.z_start_h - Screen:scaleBySize(10)

    self.z_lines_w = Screen:scaleBySize(200)
    self.z_lines_h = Screen:scaleBySize(55)
    self.z_lines_x = x + (w - self.z_lines_w) / 2 + Screen:scaleBySize(120)
    self.z_lines_y = self.z_start_y

    local status_y = self.z_start_y - Screen:scaleBySize(30)
    local sw = RenderText:sizeUtf8Text(0, w, status_font, self.status).x
    RenderText:renderUtf8Text(bb, x + (w - sw) / 2, status_y,
        status_font, self.status, false, false, WIN_TEXT)

    local start_label = "СТАРТ"
    if self.phase == "result" then start_label = "ЗАБРАТЬ" end

    if self.phase == "idle" or self.phase == "done" or self.phase == "result" then
        bb:paintRect(self.z_start_x, self.z_start_y, self.z_start_w, self.z_start_h, WIN_FACE)
        bb:paintRect(self.z_start_x, self.z_start_y, self.z_start_w, 2, WIN_LIGHT)
        bb:paintRect(self.z_start_x, self.z_start_y, 2, self.z_start_h, WIN_LIGHT)
        bb:paintRect(self.z_start_x, self.z_start_y + self.z_start_h - 2, self.z_start_w, 2, WIN_SHADOW)
        bb:paintRect(self.z_start_x + self.z_start_w - 2, self.z_start_y, 2, self.z_start_h, WIN_SHADOW)

        local lw = RenderText:sizeUtf8Text(0, self.z_start_w, btn_font, start_label).x
        RenderText:renderUtf8Text(bb,
            self.z_start_x + (self.z_start_w - lw) / 2,
            self.z_start_y + self.z_start_h / 2 + 8,
            btn_font, start_label, false, false, WIN_TEXT)
    end

    local lines_label = "ЛИНИИ: " .. self.lines
    if self.phase == "result" then lines_label = "РИСК" end

    if self.phase == "idle" or self.phase == "done" or self.phase == "result" then
        bb:paintRect(self.z_lines_x, self.z_lines_y, self.z_lines_w, self.z_lines_h, WIN_FACE)
        bb:paintRect(self.z_lines_x, self.z_lines_y, self.z_lines_w, 2, WIN_LIGHT)
        bb:paintRect(self.z_lines_x, self.z_lines_y, 2, self.z_lines_h, WIN_LIGHT)
        bb:paintRect(self.z_lines_x, self.z_lines_y + self.z_lines_h - 2, self.z_lines_w, 2, WIN_SHADOW)
        bb:paintRect(self.z_lines_x + self.z_lines_w - 2, self.z_lines_y, 2, self.z_lines_h, WIN_SHADOW)

        local lw = RenderText:sizeUtf8Text(0, self.z_lines_w, btn_font, lines_label).x
        RenderText:renderUtf8Text(bb,
            self.z_lines_x + (self.z_lines_w - lw) / 2,
            self.z_lines_y + self.z_lines_h / 2 + 8,
            btn_font, lines_label, false, false, WIN_TEXT)
    end

    local j2, val
    for j2, val in ipairs(BET_VALUES) do
        local bx = self.z_bet_x + (j2 - 1) * (self.z_bet_w + self.z_bet_gap)
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
        local lw = RenderText:sizeUtf8Text(0, self.z_bet_w, btn_font, label).x
        RenderText:renderUtf8Text(bb,
            bx + (self.z_bet_w - lw) / 2,
            self.z_bet_y + self.z_bet_h / 2 + 8,
            btn_font, label, false, false, WIN_TEXT)
    end
end

function FruitSlots:paintRisk(bb, x, y, w, game_h)
    local label_font = Font:getFace("cfont", 20)
    local btn_font = Font:getFace("cfont", 22)
    local status_font = Font:getFace("cfont", 20)
    local title_font = Font:getFace("cfont", 26)

    bb:paintRect(x, y, w, game_h, WIN_FACE)

    local title = "РИСК-ИГРА"
    local tw = RenderText:sizeUtf8Text(0, w, title_font, title).x
    RenderText:renderUtf8Text(bb, x + (w - tw) / 2, y + 45,
        title_font, title, false, false, WIN_TEXT)

    local sw = RenderText:sizeUtf8Text(0, w, status_font, self.status).x
    RenderText:renderUtf8Text(bb, x + (w - sw) / 2, y + 90,
        status_font, self.status, false, false, WIN_TEXT)

    local pot_text = string.format("На кону: $%d", self.risk_win)
    local pw = RenderText:sizeUtf8Text(0, w, label_font, pot_text).x
    RenderText:renderUtf8Text(bb, x + (w - pw) / 2, y + 125,
        label_font, pot_text, false, false, WIN_TEXT)

    local card_w = Screen:scaleBySize(90)
    local card_h = Screen:scaleBySize(130)
    local card_gap = Screen:scaleBySize(15)
    local card_y = y + 220

    local dealer_x = x + 60
    RenderText:renderUtf8Text(bb, dealer_x, card_y - 30,
        label_font, "ДИЛЕР", false, false, WIN_TEXT)
    self:renderSymbolWithDim(bb, dealer_x, card_y, card_w, card_h, self.risk_dealer or "?", false, false)

    local player_x = dealer_x + card_w + Screen:scaleBySize(60)
    RenderText:renderUtf8Text(bb, player_x, card_y - 30,
        label_font, "ВЫБЕРИТЕ КАРТУ", false, false, WIN_TEXT)

    self.z_card_x = player_x
    self.z_card_y = card_y
    self.z_card_w = card_w
    self.z_card_h = card_h

    local i
    for i = 1, 4 do
        local cx = player_x + (i - 1) * (card_w + card_gap)
        if self.risk_revealed == i then
            self:renderSymbolWithDim(bb, cx, card_y, card_w, card_h, self.risk_cards[i], false, false)
        else
            self:renderSymbolWithDim(bb, cx, card_y, card_w, card_h, "?", false, false)
        end
    end

    self.z_risk_w = Screen:scaleBySize(200)
    self.z_risk_h = Screen:scaleBySize(60)
    self.z_risk_x1 = x + w / 2 - self.z_risk_w - Screen:scaleBySize(20)
    self.z_risk_x2 = x + w / 2 + Screen:scaleBySize(20)
    self.z_risk_y = card_y + card_h + 70

    bb:paintRect(self.z_risk_x1, self.z_risk_y, self.z_risk_w, self.z_risk_h, WIN_FACE)
    bb:paintRect(self.z_risk_x1, self.z_risk_y, self.z_risk_w, 2, WIN_LIGHT)
    bb:paintRect(self.z_risk_x1, self.z_risk_y, 2, self.z_risk_h, WIN_LIGHT)
    bb:paintRect(self.z_risk_x1, self.z_risk_y + self.z_risk_h - 2, self.z_risk_w, 2, WIN_SHADOW)
    bb:paintRect(self.z_risk_x1 + self.z_risk_w - 2, self.z_risk_y, 2, self.z_risk_h, WIN_SHADOW)
    local lw = RenderText:sizeUtf8Text(0, self.z_risk_w, btn_font, "ЗАБРАТЬ").x
    RenderText:renderUtf8Text(bb, self.z_risk_x1 + (self.z_risk_w - lw) / 2,
        self.z_risk_y + self.z_risk_h / 2 + 8, btn_font, "ЗАБРАТЬ", false, false, WIN_TEXT)

    if self.phase == "risk_result" then
        bb:paintRect(self.z_risk_x2, self.z_risk_y, self.z_risk_w, self.z_risk_h, WIN_FACE)
        bb:paintRect(self.z_risk_x2, self.z_risk_y, self.z_risk_w, 2, WIN_LIGHT)
        bb:paintRect(self.z_risk_x2, self.z_risk_y, 2, self.z_risk_h, WIN_LIGHT)
        bb:paintRect(self.z_risk_x2, self.z_risk_y + self.z_risk_h - 2, self.z_risk_w, 2, WIN_SHADOW)
        bb:paintRect(self.z_risk_x2 + self.z_risk_w - 2, self.z_risk_y, 2, self.z_risk_h, WIN_SHADOW)
        lw = RenderText:sizeUtf8Text(0, self.z_risk_w, btn_font, "ЕЩЁ РАЗ").x
        RenderText:renderUtf8Text(bb, self.z_risk_x2 + (self.z_risk_w - lw) / 2,
            self.z_risk_y + self.z_risk_h / 2 + 8, btn_font, "ЕЩЁ РАЗ", false, false, WIN_TEXT)
    else
        bb:paintRect(self.z_risk_x2, self.z_risk_y, self.z_risk_w, self.z_risk_h, WIN_GRAY)
        lw = RenderText:sizeUtf8Text(0, self.z_risk_w, btn_font, "ЕЩЁ РАЗ").x
        RenderText:renderUtf8Text(bb, self.z_risk_x2 + (self.z_risk_w - lw) / 2,
            self.z_risk_y + self.z_risk_h / 2 + 8, btn_font, "ЕЩЁ РАЗ", false, false, WIN_LIGHT)
    end
end

function FruitSlots:paintBonus(bb, x, y, w, game_h)
    local status_font = Font:getFace("cfont", 20)

    bb:paintRect(x, y, w, game_h, WIN_FACE)

    local top = y + 40
    RenderText:renderUtf8Text(bb, x + 40, top,
        Font:getFace("cfont", 24),
        string.format("БОНУС! Жизней: %d   Выигрыш: $%d", self.bonus_lives, self.bonus_total_win),
        false, false, WIN_TEXT)

    local margin = Screen:scaleBySize(40)
    local sector_w = Screen:scaleBySize(55)
    local sector_h = Screen:scaleBySize(55)
    local gap = Screen:scaleBySize(4)

    local positions = {}
    local i
    for i = 1, 7 do
        positions[#positions+1] = { x = margin + (i-1)*(sector_w+gap), y = top + 40 }
    end
    for i = 1, 6 do
        positions[#positions+1] = { x = w - margin - sector_w, y = top + 40 + i*(sector_h+gap) }
    end
    for i = 1, 7 do
        positions[#positions+1] = { x = w - margin - sector_w - (i-1)*(sector_w+gap), y = top + 40 + 6*(sector_h+gap) + sector_h + gap }
    end
    for i = 1, 6 do
        positions[#positions+1] = { x = margin, y = top + 40 + (6-i)*(sector_h+gap) + sector_h + gap }
    end

    for i = 1, math.min(26, #positions) do
        local p = positions[i]
        local sector = self.bonus_sectors[i]
        local sym = sector and sector.sym or "?"
        local is_marker = (i == self.bonus_marker)

        if is_marker then
            bb:paintRect(p.x-3, p.y-3, sector_w+6, sector_h+6, WIN_TEXT)
        end
        self:renderSymbolWithDim(bb, p.x, p.y, sector_w, sector_h, sym, false, false)
    end

    local center_y = top + 40 + 3*(sector_h+gap) + sector_h
    local center_w = Screen:scaleBySize(80)
    local center_h = Screen:scaleBySize(80)
    local total_cw = 3 * center_w + 2 * gap
    local center_x = x + (w - total_cw) / 2

    for i = 1, 3 do
        local cx = center_x + (i-1)*(center_w+gap)
        local sym = self.bonus_center[i] or "?"
        self:renderSymbolWithDim(bb, cx, center_y, center_w, center_h, sym, false, false)
    end

    local status_y = center_y + center_h + 30
    local sw = RenderText:sizeUtf8Text(0, w, status_font, self.status).x
    RenderText:renderUtf8Text(bb, x + (w - sw)/2, status_y,
        status_font, self.status, false, false, WIN_TEXT)
end

return FruitSlots