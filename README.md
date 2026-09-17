# Devilsoft Casino

Текстовое казино игровой плагин для KOReader, стилизованное под интерфейс Windows 98.

Only Russian language :) 
Write for kindle paperwhite 4.
 if you need another languages or games inside this plugin put this ai generated lua trash in deepseek and he do it for you.
 
## 🎰 Игры

- **Кости** — ставки на сумму, дубли, диапазоны.
- **21 (Блэкджек)** — классические правила, удвоение.
- **Покер (видео)** — обмен карт, таблица выплат.
- **Покер с ИИ** — упрощённый Техасский Холдем один на один. ИИ блефует и повышает ставки.
- **Дурак** — Подкидной дурак.

## 🖥️ Интерфейс

- Верхняя панель с названием и кнопкой закрытия.
- Нижняя панель задач: кнопка «Пуск» с меню, баланс, часы.
- Меню «Пуск» для переключения между играми.
- Кнопки и панели в стиле Windows 98.

## 💰 Баланс

Баланс сохраняется между сессиями. Нажатие на сумму в нижней панели сбрасывает её до $1000.

## 📦 Установка

1. Скачай папку `casino.koplugin`.
2. Помести её в `koreader/plugins/`.
3. Перезапусти KOReader.
4. Открой меню → инструменты → прочие инструменты → «Казино».

## 📁 Структура

```
casino.koplugin/
├── _meta.lua          # Описание плагина
├── main.lua           # Каркас, меню «Пуск», переключение игр
├── statusbar.lua      # Верхняя панель Win98
├── switcher.lua       # Нижняя панель: Пуск, баланс, часы
└── games/
    ├── dice.lua       # Кости
    ├── blackjack.lua  # 21
    ├── poker.lua      # Видео-покер
    └── poker_ai.lua   # Покер с ИИ
```

## 📸 Скриншоты

<img src="https://github.com/user-attachments/assets/e89e750e-9e03-4a04-85ad-a4405da7c6f1" width="50%">
<img src="https://github.com/user-attachments/assets/ff99db4d-e07d-4b8c-8261-67cd7118746f" width="50%">
<img src="https://github.com/user-attachments/assets/5a5c0b43-f121-40ea-b211-a92843aed4fe" width="50%">


## 📄 Лицензия

MIT
