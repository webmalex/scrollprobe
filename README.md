# ScrollProbe

`ScrollProbe.app` измеряет scroll-события macOS в двух точках системной цепочки:

- ingress: `kCGHIDEventTap + headInsert + default`, событие всегда возвращается;
- downstream: `kCGAnnotatedSessionEventTap + tailAppend + listenOnly`.

Текущая версия работает только в monitor-only режиме. Она не изменяет, не
дропает и не синтезирует события.

## Сборка

Требования: macOS 15+, Xcode Command Line Tools и принятая лицензия Xcode.

```sh
make test
make app
```

Готовое приложение: `dist/ScrollProbe.app`.

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
`Start monitor` растут одновременно `ingress.totalObserved` и
`downstream.totalObserved`.

## Логи

Каждый запуск monitor создает JSONL:

```text
~/Library/Logs/ScrollProbe/scrollprobe-<UTC>-<RUN_ID>.jsonl
```

Типы записей:

- `run-start`: ОС, host, PID, scenario и конфигурация taps;
- `tap-inventory`: зарегистрированные taps и процессы;
- `metrics`: секундные агрегаты;
- `run-stop` или `error`.

`CGGetEventTapList` сбрасывает min/max latency counters системных taps, поэтому
inventory нужно делать только в заранее отмеченных точках эксперимента.

## Первый baseline

Для каждого сценария используется отдельный run и понятное значение `Scenario`:

1. `host-native-trackpad`
2. `host-horizon-trackpad`
3. `guest-native-trackpad`
4. `guest-horizon-ubuntu-trackpad`
5. `guest-horizon-windows-trackpad`
6. `guest-horizon-ubuntu-mouse`
7. `guest-horizon-windows-mouse`

Порядок одного прогона:

1. Нажать `Start monitor`.
2. Подождать две секунды без input.
3. Выполнить один короткий контролируемый scroll gesture.
4. Не касаться устройств до полного завершения momentum.
5. Подождать две секунды.
6. Нажать `Stop`.
7. Сохранить наблюдение о freeze и имя JSONL-файла.

Для первого raw baseline в guest нужно завершить LinearMouse. Отдельные прогоны
с LinearMouse выполняются позднее с дополнительным суффиксом scenario, например
`guest-horizon-ubuntu-trackpad-linearmouse`.

Один и тот же собранный `ScrollProbe.app` следует скопировать с host в guest,
чтобы сравнивать одинаковый код. Accessibility выдается отдельно в каждой ОС.

## Интерпретация

- `returned` означает решение ingress callback, а не доказанную доставку в
  Horizon.
- Небольшое расхождение ingress/downstream внутри одной секундной границы
  допустимо. Сравнивать нужно также cumulative `totalObserved` после окончания
  momentum.
- Совпадение host и guest event count не исключает патологию в phase/delta
  semantics.
- Переход к drop-all или throttling выполняется только после monitor baseline.
