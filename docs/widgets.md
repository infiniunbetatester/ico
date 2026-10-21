[← Back to ICO](../README.md) &nbsp; · &nbsp; **English** / [Русский](widgets.ru.md)

# Build your own island

ICO widgets are small web interfaces that run inside the island. Use HTML, CSS and JavaScript for the UI, then call `window.ico` when you need a native Mac action.

## Start with two files

Open the widgets folder from the **Widgets** panel. Create a folder called `my-widget` inside `~/.ico/widgets/`, then add these files:

| File | Purpose |
| :--- | :--- |
| `~/.ico/widgets/my-widget/widget.json` | Widget name, SF Symbol, description and height |
| `~/.ico/widgets/my-widget/index.html` | Interface, styles and behavior |

### `widget.json`

```json
{
  "name": "My Widget",
  "icon": "sparkles",
  "description": "A small tool for my island",
  "height": 260
}
```

Use an [SF Symbols](https://developer.apple.com/sf-symbols/) name for `icon`, such as `sparkles`, `cloud.sun.fill`, `timer` or `note.text`.

### `index.html`

```html
<!doctype html>
<html lang="en">
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
    <h1>Hello, island.</h1>
    <p>A little space for your next idea.</p>
    <button type="button" id="copy">Copy a reminder</button>
  </main>
  <script>
    document.querySelector('#copy').addEventListener('click', () => {
      window.ico.copy('Make time for a break.');
      window.ico.toast('Reminder copied', 'checkmark');
    });
  </script>
</body>
</html>
```

Refresh the widget list in ICO and open your widget.

## The native bridge

The `window.ico` object is injected when ICO loads the widget. Ordinary browser previews do not include this bridge.

| Method | Action | Example |
| :--- | :--- | :--- |
| `ico.toast(text, icon)` | Show an island toast; `icon` is an optional SF Symbol | `ico.toast('Done', 'checkmark')` |
| `ico.copy(text)` | Copy text to the macOS clipboard | `ico.copy('Hello from ICO')` |
| `ico.close()` | Collapse the island | `ico.close()` |
| `ico.openURL(url)` | Open a URL in the default application | `ico.openURL('https://example.com')` |
| `ico.notify(title, body)` | Request a macOS notification | `ico.notify('Break time', 'Take a moment.')` |
| `ico.sound(name)` | Play a system sound | `ico.sound('Glass')` |
| `ico.storage.set(key, value)` | Save a JSON-compatible value | `ico.storage.set('theme', 'dark')` |
| `ico.storage.get(key, fallback)` | Read a value, or return the fallback | `ico.storage.get('theme', 'dark')` |
| `ico.storage.remove(key)` | Remove a saved value | `ico.storage.remove('theme')` |
| `ico.fetch(url, options)` | Make an HTTP request through the native network bridge | `await ico.fetch('https://example.com')` |
| `ico.measure()` | Start the screen ruler; returns a measurement or `null` if cancelled | `const size = await ico.measure()` |
| `ico.onCollapse(callback)` | Run a callback when the island collapses | `ico.onCollapse(() => pause())` |
| `ico.onExpand(callback)` | Run a callback when the island expands | `ico.onExpand(() => resume())` |

`ico` in the examples is shorthand for `window.ico`. Sound names include `Glass`, `Ping`, `Hero`, `Tink` and `Morse`.

### Network requests

`ico.fetch()` supports `method`, `headers` and a string `body`. Its response exposes `status`, `ok`, `text()` and `json()`.

```js
const response = await window.ico.fetch('https://example.com');
if (!response.ok) throw new Error(`HTTP ${response.status}`);
const html = await response.text();
```

Requests go through native `URLSession`, so browser CORS rules do not apply. Server authentication and network availability still apply.

### State and lifecycle

ICO caches widget web views, so collapsing and reopening the island does not recreate the widget. Pause animation loops or frequent polling while the island is collapsed:

```js
let visible = true;
window.ico.onCollapse(() => { visible = false; });
window.ico.onExpand(() => { visible = true; });

setInterval(() => {
  if (visible) updateDisplay();
}, 1000);
```

Use `ico.storage` for values you want to save. The bridge reads from the widget's `localStorage` and also writes a native preferences copy. A widget reload resets its JavaScript variables and timers.

## What is in the catalog?

The built-in catalog currently includes **crypto prices**, **weather**, **quick notes**, **a task checklist**, **world clocks** and **a screen ruler**. Install these from ICO's Widgets panel without creating files manually.

For your next custom widget, try a Pomodoro timer, a GitHub activity panel or a small dashboard for an API you use. These are ideas for extensions, rather than catalog entries.

---

[Back to the README](../README.md) · [Widget runtime](../Sources/Views/Components/WidgetWebView.swift) · [Widget catalog](../Sources/Model/WidgetManager.swift)
