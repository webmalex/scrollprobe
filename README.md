# ScrollProbe

`ScrollProbe.app` измеряет и экспериментально фильтрует scroll-события macOS в
двух точках системной цепочки:

- ingress: `kCGHIDEventTap + headInsert + default`, принимает решение pass/drop;
- downstream: `kCGAnnotatedSessionEventTap + tailAppend + listenOnly`.

ScrollProbe никогда не синтезирует события и не изменяет delta/phase существующих
событий.

## Режимы

- `Monitor only`: пропускает все события и только измеряет их.
- `Drop zero-delta changed events`: удаляет только события без любой delta с
  `scrollPhase=changed` и без momentum phase. Begin/end/cancel, momentum и все
  события с реальным перемещением сохраняются.
- `Drop all`: удаляет все scroll events в течение 10 секунд после установки
  taps, затем автоматически продолжает в monitor-only режиме.

Экспериментальные drop-режимы доступны только для guest-профилей. Выбранный и
фактически активный mode записывается соответственно в `run-start` и каждую
`metrics`-запись.

## Сборка

Требования: macOS 15+, Xcode Command Line Tools и принятая лицензия Xcode.

```sh
make test
make app
make package
```

Готовое приложение: `dist/ScrollProbe.app`. Команда `make package` создает
переносимый архив `dist/ScrollProbe-macos-arm64.zip`.

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
2. Нажать `Request Accessibility` и включить ScrollProbe в System Settings.
3. Перезапустить приложение, если macOS не применил разрешение сразу.

Отдельный Input Monitoring не требуется. Accessibility уже разрешает активный
HID tap, а downstream listen-only tap подтвержденно работает с тем же доступом.
На macOS 15 `CGRequestListenEventAccess()` также может не добавить приложение в
таблицу Input Monitoring, даже когда tap успешно создан, поэтому отдельного
permission flow в приложении нет.

Работоспособность определяется не текстом permission label, а фактом, что после
`Start` растет `ingress.totalObserved`. В monitor mode должен также расти
`downstream.totalObserved`; в drop-all он намеренно остается неизменным.

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

Если macOS сохранила quarantine attribute и продолжает блокировать локальный
диагностический bundle, удалить его уже после копирования в `~/Applications`:

```sh
xattr -dr com.apple.quarantine "$HOME/Applications/ScrollProbe.app"
```

## Логи

Каждый запуск создает JSONL. Каталог по умолчанию:

```text
~/Library/Logs/ScrollProbe/scrollprobe-<UTC>-<RUN_ID>.jsonl
```

Кнопка `Choose log folder...` позволяет выбрать и сохранить другой каталог,
включая доступный из guest shared-каталог репозитория `logs/`. Если запись в
выбранный каталог перестает работать, run завершается с ошибкой вместо тихой
потери данных.

Типы записей:

- `run-start`: версия app, ОС, host, PID, profile, mode и конфигурация taps;
- `tap-inventory`: зарегистрированные taps и процессы;
- `metrics`: секундные агрегаты и фактически активный mode;
- `mode-change`: автоматическое завершение временного drop-all;
- `run-stop` или `error`.

`CGGetEventTapList` сбрасывает min/max latency counters системных taps, поэтому
inventory нужно делать только в заранее отмеченных точках эксперимента.

## Первый baseline

Для каждого сценария используется отдельный run. Profile выбирается из списка,
а UI показывает paired profile и порядок действий. Сценарии, направленные в
guest, записываются одновременно двумя экземплярами ScrollProbe:

| Действие | Scenario на host | Scenario в guest |
|---|---|---|
| Нативное приложение host, trackpad | `host-native-trackpad` | - |
| Horizon напрямую на host, trackpad | `host-horizon-trackpad` | - |
| Нативное приложение guest, trackpad | `host-to-guest-native-trackpad` | `guest-native-trackpad` |
| Ubuntu Horizon в guest, trackpad | `host-to-guest-horizon-ubuntu-trackpad` | `guest-horizon-ubuntu-trackpad` |
| Windows Horizon в guest, trackpad | `host-to-guest-horizon-windows-trackpad` | `guest-horizon-windows-trackpad` |
| Ubuntu Horizon в guest, mouse | `host-to-guest-horizon-ubuntu-mouse` | `guest-horizon-ubuntu-mouse` |
| Windows Horizon в guest, mouse | `host-to-guest-horizon-windows-mouse` | `guest-horizon-windows-mouse` |

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

Для первого raw baseline в guest нужно завершить LinearMouse. Отдельные прогоны
с LinearMouse выполняются позднее с дополнительным суффиксом scenario, например
`guest-horizon-ubuntu-trackpad-linearmouse`.

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
- Два парных monitor baseline уже подтвердили amplification. Следующий
  эксперимент выполняется с targeted zero-delta filter, а drop-all остается
  отдельной проверкой того, что Horizon не обходит ingress tap.
