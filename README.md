# Devilsoft Casino

Текстовое казино игровой плагин для KOReader, стилизованное под интерфейс Windows 98.
Only Russian language :) 
Write for kindle paperwhite 4

## 🎰 Игры

- **Кости** — ставки на сумму, дубли, диапазоны.
- **21 (Блэкджек)** — классические правила, удвоение.
- **Покер (видео)** — обмен карт, таблица выплат.
- **Покер с ИИ** — упрощённый Техасский Холдем один на один. ИИ блефует и повышает ставки.

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

<img src="https://github.com/user-attachments/assets/dc2150fb-c267-4adf-af33-4b75bec7a578" width="50%">

<img src="https://github.com/user-attachments/assets/92459f43-5621-4521-99af-1576baa2bf9b" width="50%">

<img src="https://github.com/user-attachments/assets/cd624cc3-7479-4198-9656-c7b86d437dac" width="50%">

<img src="https://github.com/user-attachments/assets/daadadda-a957-4d68-8af6-fee6c9da2ced" width="50%">


## 📄 Лицензия

MIT
