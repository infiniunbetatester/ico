[← К ICO](../README_RU.md) &nbsp; · &nbsp; [English](widgets.md) / **Русский**

# Создайте свой остров

Виджеты ICO — небольшие веб-интерфейсы внутри чёлки. Используйте HTML, CSS и JavaScript для оформления и логики, а `window.ico` — для нативных действий на Mac.

## Начните с двух файлов

Откройте папку виджетов из панели **Виджеты**. Создайте каталог `my-widget` внутри `~/.ico/widgets/` и добавьте два файла:

| Файл | Назначение |
| :--- | :--- |
| `~/.ico/widgets/my-widget/widget.json` | Название, SF Symbol, описание и высота виджета |
| `~/.ico/widgets/my-widget/index.html` | Интерфейс, стили и поведение |

### `widget.json`

```json
{
  "name": "Мой виджет",
  "icon": "sparkles",
  "description": "Небольшой инструмент для моего острова",
  "height": 260
}
```

Для `icon` укажите название из [SF Symbols](https://developer.apple.com/sf-symbols/): например, `sparkles`, `cloud.sun.fill`, `timer` или `note.text`.

### `index.html`

```html
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 24px;
      background: transparent;
      color: #f5f5fa;
      font: 14px/1.5 -apple-system, BlinkMacSystemFont, sans-serif;
    }
    main {
      padding: 24px;
      border-radius: 22px;
      background: rgba(179, 161, 255, 0.09);
    }
    h1 { margin: 0 0 8px; font-size: 22px; }
    p { margin: 0 0 20px; color: #a3a6b3; }
    button {
      padding: 10px 16px;
      border: 0;
      border-radius: 12px;
      background: #c0adff;
      color: #17131f;
      font: inherit;
      font-weight: 600;
      cursor: pointer;
    }
  </style>
</head>
<body>
  <main>
    <h1>Привет, остров.</h1>
    <p>Немного места для следующей идеи.</p>
    <button type="button" id="copy">Скопировать напоминание</button>
  </main>
  <script>
    document.querySelector('#copy').addEventListener('click', () => {
      window.ico.copy('Сделай небольшой перерыв.');
      window.ico.toast('Напоминание скопировано', 'checkmark');
    });
  </script>
</body>
</html>
```

Обновите список виджетов в ICO и откройте свой виджет.

## Нативный мост

Объект `window.ico` добавляется при загрузке виджета внутри ICO. В обычном браузере этого моста нет.

| Метод | Действие | Пример |
| :--- | :--- | :--- |
| `ico.toast(text, icon)` | Показать уведомление острова; `icon` — необязательное имя SF Symbol | `ico.toast('Готово', 'checkmark')` |
| `ico.copy(text)` | Скопировать текст в буфер macOS | `ico.copy('Привет из ICO')` |
| `ico.close()` | Свернуть остров | `ico.close()` |
| `ico.openURL(url)` | Открыть URL в стандартном приложении | `ico.openURL('https://example.com')` |
| `ico.notify(title, body)` | Запросить системное уведомление macOS | `ico.notify('Перерыв', 'Немного отдохни.')` |
| `ico.sound(name)` | Воспроизвести системный звук | `ico.sound('Glass')` |
| `ico.storage.set(key, value)` | Сохранить значение, совместимое с JSON | `ico.storage.set('theme', 'dark')` |
| `ico.storage.get(key, fallback)` | Прочитать значение или вернуть значение по умолчанию | `ico.storage.get('theme', 'dark')` |
| `ico.storage.remove(key)` | Удалить сохранённое значение | `ico.storage.remove('theme')` |
| `ico.fetch(url, options)` | Выполнить HTTP-запрос через нативный сетевой мост | `await ico.fetch('https://example.com')` |
| `ico.measure()` | Запустить экранную линейку; вернуть результат замера или `null` при отмене | `const size = await ico.measure()` |
| `ico.onCollapse(callback)` | Выполнить функцию при сворачивании острова | `ico.onCollapse(() => pause())` |
| `ico.onExpand(callback)` | Выполнить функцию при раскрытии острова | `ico.onExpand(() => resume())` |

`ico` в примерах — сокращение от `window.ico`. Доступные системные звуки: `Glass`, `Ping`, `Hero`, `Tink` и `Morse`.

### Сетевые запросы

`ico.fetch()` поддерживает `method`, `headers` и строковый `body`. В ответе доступны `status`, `ok`, `text()` и `json()`.

```js
const response = await window.ico.fetch('https://example.com');
if (!response.ok) throw new Error(`HTTP ${response.status}`);
const html = await response.text();
```

Запрос проходит через нативный `URLSession`, поэтому браузерные правила CORS не применяются. При этом сохраняются требования сервера к авторизации и доступности сети.

### Состояние и жизненный цикл

ICO кеширует веб-представления: при сворачивании и повторном раскрытии виджет не создаётся заново. Приостанавливайте анимации и частые запросы, пока остров свёрнут:

```js
let visible = true;
window.ico.onCollapse(() => { visible = false; });
window.ico.onExpand(() => { visible = true; });

setInterval(() => {
  if (visible) updateDisplay();
}, 1000);
```

Для сохраняемых значений используйте `ico.storage`. Мост читает данные из `localStorage` виджета и дополнительно записывает копию в нативные настройки. Перезагрузка виджета сбрасывает его переменные JavaScript и таймеры.

## Что есть в каталоге

Во встроенном каталоге сейчас доступны **курсы криптовалют**, **погода**, **блокнот**, **чек-лист задач**, **мировое время** и **экранная линейка**. Их можно установить из панели виджетов без ручного создания файлов.

Для собственного виджета попробуйте Pomodoro, панель активности GitHub или небольшой дашборд для нужного вам API. Это идеи для расширения, а не готовые позиции каталога.

---

[К README](../README_RU.md) · [Среда выполнения](../Sources/Views/Components/WidgetWebView.swift) · [Каталог виджетов](../Sources/Model/WidgetManager.swift)
