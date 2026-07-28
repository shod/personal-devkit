# Hand-off: расширяемость плагина personal-devkit (base plugin ↔ project-local rules)

> Назначение: продолжить проектирование в новом чате. Документ самодостаточен —
> контекст, главный принцип, предлагаемая архитектура, конкретные правки и уже
> сделанные артефакты. Автор идей — рассуждение из предыдущей сессии (phase-runner
> прогон фичи 006 в репо `horoscope`).

## 0. Кто/что/зачем

- **Пользователь = разработчик плагина** `shod/personal-devkit` (маркетплейс,
  `autoUpdate: true`). Хочет сделать плагин максимально **универсальным** и удобным.
- Проблема: есть **базовый плагин** (generic workflow-скиллы), но есть **правила,
  специфичные для конкретного проекта**. Нужен чистый механизм: где проходит
  граница «base vs project» и как проекту расширять/переопределять поведение
  скиллов, не форкая их.
- Плагин в git: `https://github.com/shod/personal-devkit.git`
  - `plugins/workflow-kit/skills/task-git/SKILL.md`
  - `plugins/workflow-kit/skills/phase-runner/SKILL.md`
  - Локальный marketplace-checkout (auto-update, НЕ править): `C:\Users\olegs\.claude\plugins\marketplaces\personal-devkit`

## 1. Триггерный кейс (реальный, из прогона)

`phase-runner`/`task-git` шаг **CHECKS** захардкодил «Laravel-тройку»
(`pint` + `phpstan` + `pest`) и собирает список файлов для PHPStan как
`git diff FEATURE...HEAD --name-only -- "*.php"`.

Два дефекта из-за хардкода:
1. **Скоуп PHPStan.** Проект `apps/api/phpstan.neon` имеет `paths: [app]` — тесты
   вне анализа. Но CHECKS притащил `tests/*.php` → 17 ложных ошибок
   `method.notFound` на Pest-цепочках (`withHeader()/patchJson()`), которых
   штатный `phpstan` (без аргументов) никогда не выдаёт.
2. **Mixed backend/Flutter фазы.** «Laravel-тройка» — неверные чеки для Flutter-
   задач; `flutter analyze`/`flutter test` пришлось добавлять вручную.

Оба — симптом одного: **скилл принимает решение, которое принадлежит проекту.**

## 2. ГЛАВНЫЙ ПРИНЦИП (ядро hand-off)

**Скилл владеет workflow (когда / в каком порядке). Проект владеет тем, ЧТО и КАК
выполнять.**

- Как только в базовом скилле хочется написать `if (Laravel)` / захардкодить путь,
  глоб или тул-скоуп — это **триггер вынести решение в слот контракта.**
- Механизм — **инверсия контроля**: скилл не вычисляет список файлов и не выбирает
  линтер; он *спрашивает проект* «как ты линтуешь изменённые файлы этого стека?»,
  проект *отвечает* (командой/скриптом/профилем). Скилл остаётся stack-agnostic.
- Шов для ответа **уже существует** — `.claude-project.json` (`commands.*`,
  `paths.*`). Его надо превратить из «реестра команд» в полноценный **контракт**
  между плагином и проектом.

Одной фразой: **не расширяй скиллы под проекты — расширяй контракт, а проекты
заполняют его данными и скриптами.**

## 3. Три уровня расширения (по возрастанию мощности)

| Уровень | Где живёт | Для чего | Пример |
|---|---|---|---|
| 1. Данные/конфиг | `.claude-project.json` (`commands`, `paths`, `checks`) | ~90% случаев: команды, пути, глобы, скоупы | `commands.phpstan:changed`, `paths.backend` |
| 2. Поведение | проектные скрипты/хуки, вызываемые скиллом по имени слота | логика, невыразимая строкой | `bin/phpstan-changed.sh` |
| 3. Нормы/оверрайды | `CLAUDE.md` / `.claude/rules/*.md`; project-scoped скиллы в `.claude/skills/` | правила для агента; переопределение шага базового скилла («most specific wins») | «PHPStan только app/»; локальный `checks`-скилл |

Precedence: **project > plugin defaults.** Базовый скилл даёт только дефолты и
fallback.

## 4. Предлагаемый рефактор: декларативные `checks`-профили

Заменить захардкоженную тройку одной секцией в контракте — решает СРАЗУ обе
проблемы (скоуп + mixed-фазы) и делает скилл stack-agnostic.

```jsonc
// .claude-project.json
{
  "contractVersion": 1,
  "checks": {
    "backend": {
      "match": "apps/api/**",                    // профиль активен, если фаза тронула эти файлы
      "run": ["pint", "phpstan:changed", "test"] // имена слотов из commands.*
    },
    "mobile": {
      "match": "apps/mobile/**",
      "run": ["flutter:analyze", "flutter:test"]
    }
  },
  "commands": {
    "phpstan:changed": "bash apps/api/bin/phpstan-changed.sh {BASE} 2>&1"
    // ... остальные commands.*
  }
}
```

Псевдокод generic-петли в скилле (вместо «Laravel-тройки»):

```
changed = git diff FEATURE...PHASE_BRANCH --name-only
for profile in checks where any(changed matches profile.match):
    for step in profile.run:
        run(commands[step])   # проект решил И какие шаги, И как каждый выполняется
```

Эффекты:
- Скоуп PHPStan инкапсулирован в `phpstan:changed` (проект знает про `paths:[app]`).
- Mixed-фазы решаются сами (mobile-профиль включается только если тронут `apps/mobile/**`).
- Работает и для laravel-mono, и для flutter-only, и для node-репо — скилл про стек не знает.

## 5. Как сделать контракт надёжным

1. **Дефолты + fallback.** Нет слота → документированное поведение по умолчанию
   (напр. текущее `-- "*.php"`) или skip с `log()`, а не падение. «Из коробки»
   работает на простом проекте, кастомизируется на сложном.
2. **`contractVersion`.** Скилл читает и предупреждает при несовместимости —
   чтобы `/plugin update` не ломал старые `.claude-project.json` молча.
3. **JSON Schema** для `.claude-project.json` (в репо плагина; `$schema` в файле
   проекта) → автокомплит в IDE, валидация, самодокументируемость слотов.
4. **`init`-команда/скилл** плагина: генерит скелет `.claude-project.json` под
   пресет (laravel-mono / flutter / node).
5. **Плейсхолдеры как часть API.** Уже есть `{FILTER}/{PATH}/{NAME}`; добавить и
   задокументировать `{BASE}`, `{CHANGED}` и т.п.

## 6. Dev-воркфлоу и разделение репозиториев

- **Базовый плагин (`shod/personal-devkit`)**: только generic-скиллы + схема
  контракта + дефолты + фикстуры. Ничего про конкретный проект.
- **Проектные расширения — В ПРОЕКТЕ, не в плагине**:
  - `.claude-project.json` — контракт (данные/слоты).
  - `bin/*.sh` — проектная логика (напр. `phpstan-changed.sh`).
  - `CLAUDE.md` / `.claude/rules/*.md` — нормы для агента.
  - `.claude/skills/<name>/` — project-scoped скилл, если надо переопределить шаг
    базового (харнесс: «most specific wins» — одноимённый локальный перекрывает
    плагинный для файлов в его директории).
- **Конформанс-тесты плагина**: матрица example-проектов
  (laravel-only / flutter-only / monorepo / node), у каждого свой
  `.claude-project.json`; гонять скиллы против них в CI и проверять, что
  generic-петля не знает про стек. Это защита «универсальности».

## 7. Конкретные правки в upstream (что делать)

1. Вынести CHECKS-тройку из `phase-runner`/`task-git` в `checks`-профили (§4) —
   убить захардкоженный Laravel-путь.
2. Шаг сбора changed-файлов для линтера **не фильтрует сам** — делегирует в
   `commands.<linter>:changed`. Дефолт (нет команды) — текущее `-- "*.php"` с
   оговоркой в `log()`.
3. Задокументировать контракт (`contractVersion`, слоты, плейсхолдеры) в README
   плагина + добавить JSON Schema.
4. (Опционально) `init`-скилл с пресетами `.claude-project.json`.

## 8. Что уже сделано в этой сессии (в репо `horoscope`, ветка `006-settings-account`, коммит `ce35d3a`)

Локальный «patch поверх скилла», который в новой архитектуре станет просто
заполненным слотом:

- `apps/api/bin/phpstan-changed.sh` — git-diff по `apps/api/app/**/*.php` (host) →
  `sed 's#^apps/api/##'` (container-relative, workdir `/var/www/html` = `apps/api`) →
  `phpstan analyse ... $files` (в Sail). Проверено end-to-end vs `main`: 9 app/-файлов, `[OK] No errors`.
- `.claude-project.json` → `"phpstan:changed": "bash apps/api/bin/phpstan-changed.sh {BASE} 2>&1"`.
- `CLAUDE.md` (Quality gates) → врезка: PHPStan только `app/`; при changed-files
  прогоне ограничивать pathspec до `apps/api/app/**/*.php`, не передавать
  `tests/`/`routes/`/`database/`; использовать `commands.phpstan:changed <base>`.

Это ровно уровень-1 (слот) + уровень-2 (скрипт) + уровень-3 (норма) из §3 —
пример того, как проектное правило встаёт в контракт вместо форка скилла.

## 9. Открытые вопросы для следующего чата

- Формат `checks.*.match`: одиночный глоб vs список vs предикат? (нужно
  пересечение с changed-файлами фазы).
- Что делать, если ни один профиль не сматчился, — skip с предупреждением или fail?
- Порядок профилей и параллелизм чеков (сейчас CHECKS — один прогон на фазу).
- Совместимость: как читать `paths:` из `phpstan.neon` напрямую как ещё один
  fallback, если `commands.phpstan:changed` не задан?
- Куда положить JSON Schema и как подключить `$schema` в проектных файлах.
- `init`-пресеты: минимальный набор стеков на старте.

## 10. Стартовые указания для нового чата

- Плагин-репо: `https://github.com/shod/personal-devkit.git`; скиллы под
  `plugins/workflow-kit/skills/{task-git,phase-runner}/SKILL.md`. Марketplace-
  checkout auto-update — работать в отдельном dev-клоне, не в
  `~/.claude/plugins/marketplaces/personal-devkit`.
- Начать с §4 (checks-профили) + §5.3 (JSON Schema) как MVP расширяемости.
- Держать §2 (главный принцип) как критерий ревью каждого изменения скилла.
