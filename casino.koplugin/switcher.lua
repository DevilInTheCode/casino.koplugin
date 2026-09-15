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

local Switcher = InputContainer:extend{
    height = Screen:scaleBySize(60),
    balance = 1000,
    on_start = nil,
    on_close = nil,
    on_balance_reset = nil,   -- НОВОЕ
    offset_y = 0,
    root_layout = nil,
    clock_timer = nil,
}

function Switcher:init()
end

function Switcher:refresh()
    if self.root_layout then
        UIManager:setDirty(self.root_layout, "ui")
    else
        UIManager:setDirty(self, "ui")
    end
end

function Switcher:updateBalance(v)
    if v == self.balance then return end
    self.balance = v
    self:refresh()
end

function Switcher:startClock()
    if self.clock_timer then
        UIManager:unschedule(self.clock_timer)
    end
    self.clock_timer = function()
        self:refresh()
        self.clock_timer = nil
        self:startClock()
    end
    UIManager:scheduleIn(60, self.clock_timer)
end

function Switcher:stopClock()
    if self.clock_timer then
        UIManager:unschedule(self.clock_timer)
        self.clock_timer = nil
    end
end

function Switcher:onTap(ges)
    local pos = ges.pos
    local h = Screen:scaleBySize(60)
    local w = Screen:getWidth()

    if pos.y < self.offset_y or pos.y > self.offset_y + h then
        return false
    end

    -- Кнопка Пуск слева
    local start_w = Screen:scaleBySize(140)
    if pos.x < start_w then
        if self.on_start then self.on_start() end
        return true
    end

    -- Баланс (нажатие = сброс до 1000)
    local bal_zone_x = w - Screen:scaleBySize(120) - Screen:scaleBySize(120)
    local bal_zone_w = Screen:scaleBySize(120)
    if pos.x >= bal_zone_x and pos.x <= bal_zone_x + bal_zone_w then
        if self.on_balance_reset then self.on_balance_reset() end
        return true
    end

    return false
end

function Switcher:paintTo(bb, x, y)
    local w = bb:getWidth()
    local h = Screen:scaleBySize(60)

    self.offset_y = y
    self.width = w
    self.height = h

    bb:paintRect(x, y, w, h, WIN_FACE)

    bb:paintRect(x, y, w, 2, WIN_LIGHT)
    bb:paintRect(x, y + h - 2, w, 2, WIN_SHADOW)

    -- Кнопка Пуск
    local start_w = Screen:scaleBySize(140)
    local start_h = h - Screen:scaleBySize(10)
    local sx = x + Screen:scaleBySize(5)
    local sy = y + Screen:scaleBySize(5)

    bb:paintRect(sx, sy, start_w, start_h, WIN_FACE)
    bb:paintRect(sx, sy, start_w, 2, WIN_LIGHT)
    bb:paintRect(sx, sy, 2, start_h, WIN_LIGHT)
    bb:paintRect(sx, sy + start_h - 2, start_w, 2, WIN_SHADOW)
    bb:paintRect(sx + start_w - 2, sy, 2, start_h, WIN_SHADOW)

    local start_font = Font:getFace("cfont", 20)
    local label = "◰ Пуск"   -- НОВЫЙ СИМВОЛ
    local lw = RenderText:sizeUtf8Text(0, start_w, start_font, label).x
    RenderText:renderUtf8Text(bb,
        sx + (start_w - lw) / 2,
        sy + start_h / 2 + 7,
        start_font,
        label,
        false, false, WIN_TEXT)

    local info_font = Font:getFace("cfont", 18)

    -- Баланс
    local bal_text = string.format("$%d", self.balance)
    local bw = RenderText:sizeUtf8Text(0, w, info_font, bal_text).x
    RenderText:renderUtf8Text(bb,
        x + w - bw - Screen:scaleBySize(120),
        y + h / 2 + 6,
        info_font,
        bal_text,
        false, false, WIN_TEXT)

    -- Часы
    local time_text = os.date("%H:%M")
    local tw = RenderText:sizeUtf8Text(0, w, info_font, time_text).x
    RenderText:renderUtf8Text(bb,
        x + w - tw - Screen:scaleBySize(15),
        y + h / 2 + 6,
        info_font,
        time_text,
        false, false, WIN_TEXT)
end

return Switcher