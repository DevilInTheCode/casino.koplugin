local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local Font = require("ui/font")
local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local Device = require("device")
local FrontLightWidget = require("ui/widget/frontlightwidget")

local WIN_FACE   = Blitbuffer.Color8(0xC0)
local WIN_SHADOW = Blitbuffer.Color8(0x80)
local WIN_LIGHT  = Blitbuffer.COLOR_WHITE
local WIN_TEXT   = Blitbuffer.COLOR_BLACK

local Switcher = InputContainer:extend{
    height = Screen:scaleBySize(60),
    balance = 1000,
    on_start = nil,
    on_close = nil,
    on_balance_reset = nil,
    offset_y = 0,
    root_layout = nil,
    clock_timer = nil,
    start_active = false,

    -- зоны нажатия
    z_start_x = 0, z_start_y = 0, z_start_w = 0, z_start_h = 0,
    z_balance_x = 0, z_balance_y = 0, z_balance_w = 0, z_balance_h = 0,
    z_bulb_x = 0, z_bulb_y = 0, z_bulb_w = 0, z_bulb_h = 0,
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

function Switcher:setStartActive(v)
    if v == self.start_active then return end
    self.start_active = v
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

    -- Кнопка Пуск
    if pos.x >= self.z_start_x and pos.x <= self.z_start_x + self.z_start_w
       and pos.y >= self.z_start_y and pos.y <= self.z_start_y + self.z_start_h then
        if self.on_start then self.on_start() end
        return true
    end

    -- Баланс (сброс)
    if pos.x >= self.z_balance_x and pos.x <= self.z_balance_x + self.z_balance_w
       and pos.y >= self.z_balance_y and pos.y <= self.z_balance_y + self.z_balance_h then
        if self.on_balance_reset then self.on_balance_reset() end
        return true
    end

    -- Лампочка (яркость)
    if pos.x >= self.z_bulb_x and pos.x <= self.z_bulb_x + self.z_bulb_w
       and pos.y >= self.z_bulb_y and pos.y <= self.z_bulb_y + self.z_bulb_h then
        -- Открываем виджет яркости, если устройство поддерживает
        if Device:hasFrontlight() then
            UIManager:show(FrontLightWidget:new{})
        end
        return true
    end

    return false
end

-- Иконка лампочки (рисуем вручную)
function Switcher:renderBulbIcon(bb, x, y, size)
    local cx = math.floor(x + size / 2)
    local cy = math.floor(y + size / 2)
    local r = math.floor(size / 4)

    -- Круг
    local dy
    for dy = -r, r do
        local dx = math.floor(math.sqrt(r * r - dy * dy))
        bb:paintRect(cx - dx, cy + dy, dx * 2 + 1, 1, WIN_TEXT)
    end

    -- Лучи (8 направлений)
    local angle
    for angle = 0, 315, 45 do
        local rad = math.rad(angle)
        local lx = math.floor(cx + math.cos(rad) * (r + 4))
        local ly = math.floor(cy + math.sin(rad) * (r + 4))
        bb:paintRect(lx, ly, 2, 2, WIN_TEXT)
    end
end

function Switcher:paintTo(bb, x, y)
    local w = bb:getWidth()
    local h = Screen:scaleBySize(60)

    self.offset_y = y
    self.width = w
    self.height = h

    -- Фон панели
    bb:paintRect(x, y, w, h, WIN_FACE)

    -- Верхняя светлая грань
    bb:paintRect(x, y, w, 2, WIN_LIGHT)
    -- Нижняя тёмная грань
    bb:paintRect(x, y + h - 2, w, 2, WIN_SHADOW)

    -- ===== Кнопка Пуск =====
    local start_w = Screen:scaleBySize(140)
    local start_h = h - Screen:scaleBySize(10)
    local sx = x + Screen:scaleBySize(5)
    local sy = y + Screen:scaleBySize(5)

    self.z_start_x = sx
    self.z_start_y = sy
    self.z_start_w = start_w
    self.z_start_h = start_h

    bb:paintRect(sx, sy, start_w, start_h, WIN_FACE)

    if self.start_active then
        -- Вдавленная: тёмная сверху/слева, светлая снизу/справа
        bb:paintRect(sx, sy, start_w, 2, WIN_SHADOW)
        bb:paintRect(sx, sy, 2, start_h, WIN_SHADOW)
        bb:paintRect(sx, sy + start_h - 2, start_w, 2, WIN_LIGHT)
        bb:paintRect(sx + start_w - 2, sy, 2, start_h, WIN_LIGHT)
    else
        -- Обычная: светлая сверху/слева, тёмная снизу/справа
        bb:paintRect(sx, sy, start_w, 2, WIN_LIGHT)
        bb:paintRect(sx, sy, 2, start_h, WIN_LIGHT)
        bb:paintRect(sx, sy + start_h - 2, start_w, 2, WIN_SHADOW)
        bb:paintRect(sx + start_w - 2, sy, 2, start_h, WIN_SHADOW)
    end

    local start_font = Font:getFace("cfont", 20)
    local label = "◰ Пуск"
    local lw = RenderText:sizeUtf8Text(0, start_w, start_font, label).x
    -- Сдвиг текста при вдавливании
    local text_offset = self.start_active and 1 or 0
    RenderText:renderUtf8Text(bb,
        sx + (start_w - lw) / 2 + text_offset,
        sy + start_h / 2 + 7 + text_offset,
        start_font,
        label,
        false, false, WIN_TEXT)

    -- ===== Баланс (слева от утопленной панели) =====
    local info_font = Font:getFace("cfont", 18)
    local bal_text = string.format("$%d", self.balance)
    local bal_w = RenderText:sizeUtf8Text(0, w, info_font, bal_text).x

    -- Позиция: правее кнопки Пуск, но левее утопленной панели
    -- Утопленная панель: справа, ширина ~200 px
    local panel_w = Screen:scaleBySize(120)
    local panel_x = x + w - panel_w - Screen:scaleBySize(8)
    local bal_x = panel_x - bal_w - Screen:scaleBySize(15)

    self.z_balance_x = bal_x - 5
    self.z_balance_y = y + Screen:scaleBySize(15)
    self.z_balance_w = bal_w + 10
    self.z_balance_h = Screen:scaleBySize(30)

    RenderText:renderUtf8Text(bb,
        bal_x,
        y + h / 2 + 6,
        info_font,
        bal_text,
        false, false, WIN_TEXT)

    -- ===== Утопленная панель с лампочкой и часами =====
    local panel_h = h - Screen:scaleBySize(14)
    local panel_y = y + Screen:scaleBySize(7)

    bb:paintRect(panel_x, panel_y, panel_w, panel_h, WIN_FACE)
    -- Вдавленная рамка: тёмная сверху/слева, светлая снизу/справа
    bb:paintRect(panel_x, panel_y, panel_w, 2, WIN_SHADOW)
    bb:paintRect(panel_x, panel_y, 2, panel_h, WIN_SHADOW)
    bb:paintRect(panel_x, panel_y + panel_h - 2, panel_w, 2, WIN_LIGHT)
    bb:paintRect(panel_x + panel_w - 2, panel_y, 2, panel_h, WIN_LIGHT)

    -- Иконка лампочки внутри панели
    local bulb_size = Screen:scaleBySize(22)
    local bulb_x = panel_x + Screen:scaleBySize(10)
    local bulb_y = panel_y + (panel_h - bulb_size) / 2

    self.z_bulb_x = bulb_x - 5
    self.z_bulb_y = bulb_y - 5
    self.z_bulb_w = bulb_size + 10
    self.z_bulb_h = bulb_size + 10

    self:renderBulbIcon(bb, bulb_x, bulb_y, bulb_size)

    -- Часы внутри панели (справа от лампочки)
    local time_text = os.date("%H:%M")
    local time_w = RenderText:sizeUtf8Text(0, panel_w, info_font, time_text).x
    local time_x = panel_x + panel_w - time_w - Screen:scaleBySize(12)

    RenderText:renderUtf8Text(bb,
        time_x,
        panel_y + panel_h / 2 + 6,
        info_font,
        time_text,
        false, false, WIN_TEXT)
end

return Switcher