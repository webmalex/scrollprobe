# ScrollProbe

`ScrollProbe.app` содержит два независимых режима работы:

- `Protection`: постоянно удаляет доказанно патологические scroll events без
  окна, JSONL и downstream tap;
- `Diagnostics`: опциональное окно для парных host/guest измерений и
  экспериментальных режимов.

ScrollProbe никогда не синтезирует события и не изменяет delta/phase существующих
событий.

## Protection

После первого запуска в menu bar появляется shield icon. Protection можно
включить из этого меню или кнопкой `Enable Protection` в Diagnostics:

1. Явно включить Protection и один раз выдать Accessibility.
2. Убедиться, что статус стал `Protection: Active`.
3. Закрыть Diagnostics window. Приложение и filter продолжат работать в menu bar.
4. Для временного отключения выбрать `Pause Protection`.

Protection сохраняет явный выбор пользователя и автоматически включается при
следующем запуске приложения. Checkbox `Launch at Login` в menu bar регистрирует
основной app через `SMAppService.mainApp`; после входа пользователя agent
запускается без Diagnostics window. Если macOS требует повторного согласия, menu
показывает отдельный переход в System Settings > General > Login Items.

Production filter имеет один active `kCGHIDEventTap + headInsert + default` и
удаляет только события без delta на всех трёх axes с
`scrollPhase=changed` и без momentum phase. Begin/end/cancel, momentum и любое
реальное перемещение всегда пропускаются. Callback ведёт только лёгкие счётчики
в памяти; Protection не записывает input data или diagnostic logs и не делает
network requests. Приложение сохраняет boolean preference в `UserDefaults` и
создаёт пустой lock file в `~/Library/Caches/dev.scrollprobe.ScrollProbe`, чтобы
второй экземпляр не мог установить конкурирующий tap.

Первая строка menu bar показывает version/build. Ниже видны время работы
текущего tap, его generation и число восстановлений. Пока menu открыто, counters
и active time обновляются раз в секунду; при закрытии единственный UI timer
сразу удаляется. `Copy Status` помещает в clipboard обезличенный lifecycle
snapshot с версией, состоянием permission/login item, counters и последней
ошибкой; отчет не содержит hostname, user paths или input data. Если tap нельзя
повторно включить после disable/fault, Protection делает не более трех попыток
пересоздания с задержками 0, 0.5 и 1 секунду, затем явно переходит в `Failed`.

## Diagnostics

Diagnostics открывается через `Open Diagnostics...` в menu bar. Оно измеряет
scroll-события в двух точках:

- ingress: `kCGHIDEventTap + headInsert + default`, принимает решение pass/drop;
- downstream: `kCGAnnotatedSessionEventTap + tailAppend + listenOnly`.

Diagnostic modes:

- `Monitor only`: пропускает все события и только измеряет их.
- `Drop zero-delta changed events`: удаляет только события без любой delta с
  `scrollPhase=changed` и без momentum phase. Begin/end/cancel, momentum и все
  события с реальным перемещением сохраняются.
- `Drop all`: удаляет все scroll events в течение 10 секунд после установки
  taps, затем автоматически продолжает в monitor-only режиме.

Экспериментальные drop-режимы доступны только для guest profiles и только когда
background Protection поставлен на паузу. Во время diagnostic run состояние
Protection заморожено, чтобы tap ordering и смысл лога не менялись на ходу.

## Сборка

Требования: macOS 15+, Xcode Command Line Tools и принятая лицензия Xcode.

```sh
make test
make app
make package
```

Готовое приложение: `dist/ScrollProbe.app`. Команда `make package` создает
переносимый архив `dist/ScrollProbe-macos-arm64.zip`.

Текущий v0.5.1 build 9 archive:

```text
SHA-256  6254e5f0e6f3ce2e914dd4e5666b0f9743ca5c61c0861df8af35bfee9320b5e8
```

Сборка подписывается ad-hoc со стабильным локальным designated requirement по
bundle ID. Обычная ad-hoc подпись привязана к `cdhash`, из-за чего macOS считает
каждую пересборку новым приложением и старая запись Accessibility перестает
работать. После перехода на стабильное requirement старую запись нужно один раз
удалить и выдать право заново. Последующие локальные пересборки сохраняют то же
requirement.

Identifier-only requirement подходит только для локального диагностического
инструмента. Для распространения нужна настоящая Developer ID подпись.

## Разрешения

1. Запустить `dist/ScrollProbe.app`.
2. Нажать `Enable Protection` или `Request Accessibility` и включить ScrollProbe
   в System Settings.
3. Protection автоматически повторит запуск после выдачи права. Если macOS не
   применил его сразу, перезапустить приложение.

Отдельный Input Monitoring не требуется. Accessibility уже разрешает активный
HID tap, а downstream listen-only tap подтвержденно работает с тем же доступом.
На macOS 15 `CGRequestListenEventAccess()` также может не добавить приложение в
таблицу Input Monitoring, даже когда tap успешно создан, поэтому отдельного
permission flow в приложении нет.

Работоспособность background filter определяется фактическим статусом
`Protection: Active` и ростом menu-bar counters. Для Diagnostics после `Start`
должен расти `ingress.totalObserved`; в monitor mode также растёт downstream.

## Перенос в guest

Собирать приложение в guest не нужно. Host и guest используют Apple Silicon и
macOS 15, поэтому в обеих системах запускается один и тот же собранный bundle.

1. Скопировать `dist/ScrollProbe.app` из UTM shared directory в
   `~/Applications` или `/Applications`. Прямое копирование bundle достаточно.
2. Первый раз запустить через Finder командой `Open` из контекстного меню.
3. Выдать Accessibility внутри guest и при необходимости перезапустить app.

TCC-базы host и guest независимы, поэтому право выдается один раз в каждой ОС.
Xcode, Swift и остальные инструменты сборки в guest не требуются. ZIP от
`make package` является только запасным способом переноса для файловых систем,
которые повреждают структуру bundle или executable attributes.

Перед заменой уже установленного bundle нужно выбрать `Quit ScrollProbe` в menu
bar. Новый экземпляр намеренно завершится, пока старый процесс с тем же bundle ID
ещё работает.

Если macOS сохранила quarantine attribute и продолжает блокировать локальный
диагностический bundle, удалить его уже после копирования в `~/Applications`:

```sh
xattr -dr com.apple.quarantine "$HOME/Applications/ScrollProbe.app"
```

## Diagnostic Logs

Только явный запуск Diagnostics создаёт JSONL. Background Protection ничего не
пишет. Каталог по умолчанию:

```text
~/Library/Logs/ScrollProbe/scrollprobe-<UTC>-<RUN_ID>.jsonl
```

Кнопка `Choose log folder...` позволяет выбрать и сохранить другой каталог,
включая доступный из guest shared-каталог репозитория `logs/`. Если запись в
выбранный каталог перестает работать, run завершается с ошибкой вместо тихой
потери данных.

Типы записей:

- `run-start`: версия app, ОС, host, PID, profile, physical input, UTM pointer,
  mode, background Protection и конфигурация taps;
- `tap-inventory`: зарегистрированные taps и процессы;
- `metrics`: секундные агрегаты и фактически активный mode;
- `mode-change`: автоматическое завершение временного drop-all;
- `protection-state` и `protection-recovery`: изменения background tap во время
  diagnostics;
- `run-stop` или `error`.

`CGGetEventTapList` сбрасывает min/max latency counters системных taps, поэтому
inventory нужно делать только в заранее отмеченных точках эксперимента.

## Diagnostics Protocol

Для каждого сценария используется отдельный run. Profile выбирается из списка,
а UI показывает paired profile и порядок действий. Сценарии, направленные в
guest, записываются одновременно двумя экземплярами ScrollProbe:

| Действие | Scenario на host | Scenario в guest |
|---|---|---|
| Нативное приложение host | `host-native` | - |
| Horizon напрямую на host | `host-horizon` | - |
| Нативное приложение guest | `host-to-guest-native` | `guest-native` |
| Ubuntu Horizon в guest | `host-to-guest-horizon-ubuntu` | `guest-horizon-ubuntu` |
| Windows Horizon в guest | `host-to-guest-horizon-windows` | `guest-horizon-windows` |

`Physical input` (`Trackpad`/`Mouse`) и UTM pointer (`Mac Trackpad`/`Generic
Mouse`) выбираются независимо и записываются отдельными metadata fields.

Порядок одного прогона:

1. Для guest-сценария нажать `Start monitor` сначала на host, затем в guest.
2. Подождать две секунды без input после запуска обоих probes.
3. Выполнить один короткий контролируемый scroll gesture.
4. Не касаться устройств до полного завершения momentum.
5. Подождать две секунды.
6. Для guest-сценария нажать `Stop` сначала в guest, затем на host.
7. Сохранить наблюдение о freeze и имя JSONL-файла.

Один gesture означает одно непрерывное вертикальное движение двумя пальцами с
последующим отпусканием, без повторного касания и смены направления. Для mouse
control используется один дискретный шаг колеса. Обычное перемещение указателя
не попадает в эти логи, но случайная или продолжительная прокрутка непригодна
для численного сравнения сценариев.

Для raw baseline в guest нужно завершить LinearMouse. Его состояние при
необходимости фиксируется отдельно в наблюдениях эксперимента.

Один и тот же собранный bundle следует использовать на host и guest, чтобы
сравнивать одинаковый код. До завершения baseline его не следует пересобирать.

## Интерпретация

- `returned` означает решение ingress callback, а не доказанную доставку в
  Horizon.
- Небольшое расхождение ingress/downstream внутри одной секундной границы
  допустимо. Сравнивать нужно также cumulative `totalObserved` после окончания
  momentum.
- Совпадение host и guest event count не исключает патологию в phase/delta
  semantics.
- Парные runs подтвердили amplification до десятков тысяч zero-delta events.
  Targeted filter снизил downstream до обычных десятков events/s и устранил
  freeze в Ubuntu и Windows при обоих UTM pointer devices.
