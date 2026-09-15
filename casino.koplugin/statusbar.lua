local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local Font = require("ui/font")
local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")

local WIN_FACE   = Blitbuffer.Color8(0xC0)  -- #C0C0C0
local WIN_SHADOW = Blitbuffer.Color8(0x80)  -- #808080
local WIN_LIGHT  = Blitbuffer.COLOR_WHITE
local WIN_TEXT   = Blitbuffer.COLOR_BLACK

local StatusBar = InputContainer:extend{
    height = Screen:scaleBySize(50),
    balance = 1000,
    bet = 10,
    on_close = nil,
    on_balance_reset = nil,
    offset_y = 0,
    root_layout = nil,
}

function StatusBar:init()
end

function StatusBar:refresh()
    if self.root_layout then
        UIManager:setDirty(self.root_layout, "ui")
    else
        UIManager:setDirty(self, "ui")
    end
end

function StatusBar:updateBalance(v)
    if v == self.balance then return end
    self.balance = v
    self:refresh()
end

function StatusBar:updateBet(v)
    if v == self.bet then return end
    self.bet = v
    self:refresh()
end

function StatusBar:onTap(ges)
    local pos = ges.pos
    local h = Screen:scaleBySize(50)
    local w = Screen:getWidth()

    if pos.y < self.offset_y or pos.y > self.offset_y + h then
        return false
    end

    -- Крестик закрытия справа
    if pos.x > w - Screen:scaleBySize(60) then
        if self.on_close then self.on_close() end
        return true
    end

    return false
end

function StatusBar:paintTo(bb, x, y)
    local w = bb:getWidth()
    local h = Screen:scaleBySize(50)

    self.offset_y = y
    self.width = w
    self.height = h

    -- Фон панели
    bb:paintRect(x, y, w, h, WIN_FACE)

    -- Верхняя светлая грань
    bb:paintRect(x, y, w, 2, WIN_LIGHT)
    -- Нижняя тёмная грань
    bb:paintRect(x, y + h - 2, w, 2, WIN_SHADOW)

    -- Название
    local title_font = Font:getFace("cfont", 20)
    RenderText:renderUtf8Text(bb,
        x + Screen:scaleBySize(12),
        y + h / 2 + 7,
        title_font,
        "Devilsoft Casino",
        false, false, WIN_TEXT)

    -- Кнопка закрытия (Win98-стиль)
    local close_size = Screen:scaleBySize(34)
    local cx = x + w - close_size - Screen:scaleBySize(8)
    local cy = y + (h - close_size) / 2

    -- Фон кнопки
    bb:paintRect(cx, cy, close_size, close_size, WIN_FACE)
    -- Светлая грань сверху/слева
    bb:paintRect(cx, cy, close_size, 2, WIN_LIGHT)
    bb:paintRect(cx, cy, 2, close_size, WIN_LIGHT)
    -- Тёмная грань снизу/справа
    bb:paintRect(cx, cy + close_size - 2, close_size, 2, WIN_SHADOW)
    bb:paintRect(cx + close_size - 2, cy, 2, close_size, WIN_SHADOW)

    -- Крестик
    local pad = Screen:scaleBySize(10)
    local thick = Screen:scaleBySize(3)
    local i
    for i = 0, 20 do
        local t = i / 20
        local px1 = cx + pad + (close_size - 2 * pad) * t
        local py1 = cy + pad + (close_size - 2 * pad) * t
        local px2 = cx + close_size - pad - (close_size - 2 * pad) * t
        local py2 = cy + pad + (close_size - 2 * pad) * t
        bb:paintRect(px1, py1, thick, thick, WIN_TEXT)
        bb:paintRect(px2, py2, thick, thick, WIN_TEXT)
    end
end

return StatusBar