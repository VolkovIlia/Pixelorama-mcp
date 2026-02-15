# Pixelorama MCP

MCP-сервер и GDScript bridge-расширение для автоматизации Pixelorama через Claude Code (или другие MCP-клиенты). Работает поверх штатного Pixelorama без форка -- расширение поднимает TCP bridge, MCP-сервер общается с ним по stdio.

## Возможности

107 инструментов, сгруппированных по категориям:

| Категория | Примеры операций |
|-----------|-----------------|
| Проект | create, open, save, export, import sequence/spritesheet |
| Слои | add, remove, rename, move, группы, свойства |
| Кадры | add, remove, duplicate, move |
| Рисование | line, rect, ellipse, text, gradient, erase |
| Пиксели | get, set, set_many, get_region, set_region, replace_color |
| Холст | fill, clear, resize, crop |
| Выделение | rect, ellipse, lasso, invert, move, export_mask |
| Палитра | list, select, create, delete, import, export |
| Кисти | list, add, remove, stamp, stroke (jitter, spray, blend modes) |
| Тайлмап | tileset CRUD, cell get/set/clear, fill_rect, random_fill |
| Эффекты | effect layers, шейдеры (apply, list, inspect, schema) |
| Анимация | tags, playback, fps, frame_duration, loop |
| 3D | object list/add/remove/update |
| Пакетное выполнение | batch.exec |
| Конвертация | image.to_pixelart -- фото в пиксельарт |

## Установка

### Зависимости

- Python 3.9+ (рекомендуется 3.12+)
- Pixelorama (Flatpak или нативная сборка)

### Установка сервера

```bash
cd server
pip install Pillow
```

Или полная установка через pip:

```bash
cd server
pip install -e .
```

## Настройка Pixelorama (Flatpak)

### 1. Разрешить сетевой доступ

Flatpak-версия по умолчанию не имеет доступа к сети. Bridge использует локальный TCP, поэтому:

```bash
flatpak override --user --share=network com.orama_interactive.Pixelorama
```

### 2. Собрать расширение

```bash
python3 extension/build_extension_zip.py
```

Результат: `extension/dist/PixeloramaMCP.zip`

### 3. Установить расширение

Распаковать zip в каталог расширений Pixelorama:

```bash
mkdir -p ~/.var/app/com.orama_interactive.Pixelorama/data/pixelorama/extensions/PixeloramaMCP
unzip extension/dist/PixeloramaMCP.zip \
  -d ~/.var/app/com.orama_interactive.Pixelorama/data/pixelorama/extensions/PixeloramaMCP/
```

### 4. Включить расширение

1. Перезапустить Pixelorama
2. Открыть Extension Manager
3. Включить **Pixelorama MCP Bridge**

После включения TCP bridge запустится на `127.0.0.1:8123`.

## Интеграция с Claude Code

Добавить в `.mcp.json` (в корне проекта или в `~/.claude/`):

```json
{
  "mcpServers": {
    "pixelorama": {
      "command": "python3",
      "args": ["-m", "pixelorama_mcp"],
      "cwd": "/path/to/Pixelorama-mcp/server",
      "env": {
        "PYTHONPATH": "/path/to/Pixelorama-mcp/server"
      }
    }
  }
}
```

Заменить `/path/to/Pixelorama-mcp` на реальный путь к репозиторию.

## Переменные окружения

| Переменная | По умолчанию | Описание |
|-----------|-------------|----------|
| `PIXELORAMA_BRIDGE_HOST` | `127.0.0.1` | Адрес bridge |
| `PIXELORAMA_BRIDGE_PORT` | `8123` | Порт bridge |
| `PIXELORAMA_BRIDGE_PORTS` | -- | Список портов через запятую (напр. `8123,8124`) |
| `PIXELORAMA_BRIDGE_PORT_RANGE` | -- | Диапазон портов (напр. `8123-8133`) |
| `PIXELORAMA_BRIDGE_TOKEN` | -- | Токен авторизации (опционально) |

Если задан `PIXELORAMA_BRIDGE_TOKEN`, тот же токен должен быть установлен и при запуске Pixelorama.

## image.to_pixelart -- конвертация фото в пиксельарт

Серверный инструмент, не требующий bridge. Принимает фото (base64 или путь к файлу), уменьшает до целевого размера, сокращает палитру и импортирует результат в Pixelorama.

### Параметры

| Параметр | Тип | По умолчанию | Описание |
|----------|-----|-------------|----------|
| `image_data` | string | -- | Base64-кодированное изображение (PNG/JPEG) |
| `image_path` | string | -- | Путь к файлу изображения |
| `width` | int | 64 | Целевая ширина в пикселях |
| `height` | int | 64 | Целевая высота в пикселях |
| `colors` | int | 0 | Макс. количество цветов (0 = без ограничений) |
| `dither` | bool | false | Применить дизеринг при сокращении палитры |
| `keep_aspect` | bool | true | Сохранять пропорции (вписать в width x height) |
| `project_name` | string | "pixelart" | Имя нового проекта |

Нужен один из `image_data` или `image_path`.

### Пример в Claude Code

> Открой фото cat.png и конвертируй в пиксельарт 64x64 с палитрой 16 цветов

## Демо

Домик с анимированными птицами -- нарисован и экспортирован целиком через MCP-инструменты:

![House with birds animation](demo/house_birds.gif)

## Примеры использования в Claude Code

- "Создай проект 32x32, нарисуй красный круг и экспортируй в PNG"
- "Открой cat.png, конвертируй в пиксельарт 48x48 с 8 цветами"
- "Добавь 3 кадра анимации и экспортируй как GIF"
- "Создай тайлсет из 4 тайлов и заполни слой случайным паттерном"
- "Примени шейдер outline к текущему слою"

## Проверка работы

Убедиться, что bridge запущен:

```bash
ss -tlnp | grep 8123
```

Пинг bridge из командной строки:

```bash
cd server
python3 -m pixelorama_mcp.bridge_client bridge.ping
```

## Документация

- Bridge-протокол: [`docs/bridge-protocol.md`](docs/bridge-protocol.md)
- Полный список возможностей: [`docs/capabilities.md`](docs/capabilities.md)
- Дорожная карта: [`docs/mcp-roadmap.md`](docs/mcp-roadmap.md)
- Пошаговая настройка: [`docs/setup.md`](docs/setup.md)
