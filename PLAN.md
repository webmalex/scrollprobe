# План исследования scroll freeze в VDI

Последнее обновление: 2026-07-17

## Назначение документа

Это живой документ для продолжения работы из новых чистых сессий. Он отделяет
подтвержденные факты от гипотез, фиксирует уже выполненные проверки и указывает
следующий эксперимент. Перед продолжением задачи нужно прочитать `AGENTS.md`,
этот файл, `UPSTREAM.md` и исходные материалы `ai/001.md` - `ai/003.md`.

## Цель

Найти источник тяжелых зависаний при прокрутке трекпадом в VMware Horizon,
запущенном внутри гостевой macOS в UTM, и устранить проблему на самом раннем
доступном уровне без ненужной разработки системного драйвера.

## Топология

```text
Host: macOS 15.7.7, Apple Silicon M1 Max
  -> UTM 4.7.5, Apple Virtualization.framework, bridged network
    -> Guest: macOS 15.7.7
      -> Continent ZTN 4.0.0.5969
        -> VMware Horizon Client 2312.1 (8.12.1)
          -> Ubuntu 20.04.6 LTS, GNOME 3.36
          -> Windows Server 2019
```

## Подтвержденные факты

1. Bluetooth-мышь со стандартным колесом стабильно работает через всю вложенную
   цепочку до обоих VDI.
2. Одно движение двумя пальцами по трекпаду может вызвать тяжелый UI freeze в
   Horizon на десятки секунд.
3. Во время проблемы ухудшается связь именно с VDI: растут задержки и потери
   ping до VDI. Параллельный ping из гостевой macOS к `1.1.1.1` остается
   практически нормальным.
4. При продолжительной проблеме Continent ZTN может уйти в неуспешный reconnect.
5. Симптом одинаково воспроизводится в Ubuntu 20.04.6 и Windows Server 2019.
   Поэтому проблема с высокой вероятностью находится до уровня удаленной ОС:
   в AVF/UTM, гостевой macOS, Horizon Client или их взаимодействии.
6. Если Continent ZTN и Horizon Client запущены прямо на host macOS, тот же
   трекпад работает нормально. Это исключает трекпад сам по себе и существенно
   снижает вероятность общей ошибки Horizon или инфраструктуры VDI.
7. Версии host и guest macOS уже выровнены до 15.7.7. Это не устранило проблему,
   поэтому исходная гипотеза version mismatch из `ai/001.md` опровергнута.
8. Проверены все четыре сочетания UTM `Pointer` и `Dynamic Resolution`:
   `Mac Trackpad`/`Generic Mouse` и `On`/`Off`. Убедительного улучшения нет.
   Влияние `Dynamic Resolution` субъективно и не подтверждено метриками.
9. LinearMouse в guest был настроен на дискретную прокрутку по строкам и без
   инерции. Это улучшило сетевую стабильность, но не устранило UI freeze.
10. Использовался workaround с открытым браузером, который меняет выраженность
    WindowServer/compositing-проблемы, но не устраняет корень.

## Что пока не доказано

1. Не измерено, сколько scroll-событий создается на host и сколько появляется
   в guest.
2. Не доказано, что AVF умножает количество событий.
3. Не доказано, что Horizon получает сотни или тысячи событий. Большое число
   сетевых display frames может быть следствием обработки скролла, а не прямым
   отражением числа input events.
4. Не известно, какие поля события являются триггером: частота, дробные delta,
   `continuous`, gesture phase, momentum phase или IOHID payload.
5. Не известно, получает ли Horizon scroll через обычную CGEvent/NSEvent цепочку,
   собственный `CGEventTap` или прямой IOHID-клиент.
6. Не установлено, возникает ли такой же WindowServer freeze при прокрутке
   обычного приложения внутри guest без запущенного Horizon.

## Уже исследованные upstream-факты

1. В UTM 4.7.5 режим `Mac Trackpad` создает `VZMacTrackpadConfiguration`, а
   `Generic Mouse` создает `VZUSBScreenCoordinatePointingDeviceConfiguration`.
2. В UTM есть многолетние отчеты о freeze гостевой macOS при trackpad scroll:
   [#4636](https://github.com/utmapp/UTM/issues/4636),
   [#5254](https://github.com/utmapp/UTM/issues/5254),
   [#6706](https://github.com/utmapp/UTM/issues/6706) и
   [#7531](https://github.com/utmapp/UTM/issues/7531).
3. Workaround `Generic Mouse` помогал другим конфигурациям, но в нашей
   конфигурации не помог.
4. UTM PR [#7573](https://github.com/utmapp/UTM/pull/7573) предлагал одновременно
   создавать trackpad и USB pointing device. PR закрыт без merge из-за прошлых
   проблем такого сочетания на старых guest macOS.
5. Актуальный upstream LinearMouse уже создает активный tap как
   `kCGHIDEventTap + kCGHeadInsertEventTap`. Поэтому это не новый уровень,
   который еще только предстоит попробовать.
6. Линейный режим LinearMouse подавляет momentum events, но для обычного
   trackpad-события может преобразовать каждое входное событие в отдельный
   дискретный шаг. Он не является общим rate limiter.
7. Mos использует `kCGAnnotatedSessionEventTap + tailAppendEventTap` и явно
   пропускает события, распознанные как trackpad. Его лицензия CC BY-NC 4.0.
8. Mac Mouse Fix содержит полезные IOHID/private API наработки, но значительно
   сложнее и использует нестандартную лицензию.
9. В Apple backend UTM не обрабатывает scroll delta собственным кодом. Он
   создает обычный `VZVirtualMachineView`, после чего закрытый
   Virtualization.framework самостоятельно преобразует host input в reports
   виртуального pointing device.
10. `Generic Mouse` меняет класс виртуального устройства, но сохраняет тот же
    opaque `VZVirtualMachineView` input path. Это согласуется с тем, что данный
    workaround не помог в нашей конфигурации.

## Рабочие гипотезы

Гипотезы перечислены в текущем порядке приоритета. Порядок должен меняться по
результатам измерений.

### H1. Проблемная семантика AVF trackpad events

AVF может передавать в guest формально допустимую, но патологическую для
WindowServer/Horizon последовательность continuous/phase/momentum events.
Проблемой может быть не количество, а сочетание полей и фаз.

За: direct host Horizon исправен; проблема появляется только после границы
host -> guest; известны похожие UTM/AVF freeze.

Против: `Generic Mouse` не устранил симптом, хотя должен менять тип виртуального
устройства.

### H2. Слишком высокая частота или амплификация событий

AVF, guest WindowServer или другой компонент может превращать один физический
gesture в чрезмерное число `scrollWheel` events.

За: субъективное поведение и частичное улучшение после отключения инерции.

Против: численные данные пока отсутствуют.

### H3. LinearMouse меняет delta, но не снижает event rate

Дискретизация каждого микро-события может оставлять прежнюю частоту или даже
усиливать фактическую прокрутку, превращая малую дробную delta в отдельный line
step. Нужен отдельный accumulator/rate limiter, а не только line translation.

### H4. Клиентское взаимодействие Horizon и WindowServer

Horizon может синхронно обрабатывать continuous scroll и инициировать слишком
много display updates. Это объясняет одинаковый результат для Ubuntu и Windows
и исправную работу прямого Horizon на host, где input path отличается.

### H5. Обход CGEventTap со стороны Horizon

Horizon может иметь более ранний tap или читать IOHID напрямую. Гипотеза должна
проверяться строгим drop-all экспериментом, а не анализом субъективного эффекта
LinearMouse.

### H6. Display/compositor path усиливает основную проблему

`Dynamic Resolution` и наличие открытого браузера могут менять выраженность
freeze, но текущих данных недостаточно, чтобы считать display path первопричиной.

### H7. VPN и сеть являются вторичным эффектом

Основной сбой input/render path может создавать burst display traffic и очередь
до VDI, после чего деградирует VPN. Стабильный ping к `1.1.1.1` и исправная
Bluetooth-мышь делают общую неисправность сети менее вероятной.

## Принятые решения

1. Полные upstream-репозитории клонированы в игнорируемый каталог `upstream/`:
   LinearMouse, Mos, Mac Mouse Fix и UTM. Ревизии записаны в `UPSTREAM.md`.
2. Считать LinearMouse основным MIT-референсом для CGEventTap и scroll fields.
3. Не начинать с форка большой GUI-утилиты и не писать DriverKit/kext до
   доказательства, что более простой CGEventTap недостаточен.
4. Первый собственный артефакт должен быть минимальным стабильным `.app` bundle
   `ScrollProbe`, чтобы TCC permission не ломался при каждом запуске бинарника.
5. Один и тот же `ScrollProbe` должен запускаться на host и guest для сравнения
   обеих сторон границы виртуализации.
6. Callback event tap не должен синхронно писать каждое событие в файл или
   выполнять дорогие AppKit/Accessibility-вызовы. Это исказит измерения и может
   привести к `tapDisabledByTimeout`.
7. Первая версия ScrollProbe использует только public CGEvent fields. Private
   `CGEventCopyIOHIDEvent` добавляется позднее как optional experimental backend,
   если public baseline окажется недостаточным.
8. Если guest tap окажется слишком поздним, следующий ранний эксперимент -
   минимальный subclass `VZVirtualMachineView` в UTM, считающий и временно
   блокирующий вызовы `scrollWheel(with:)`.

## Архитектура ScrollProbe

### Режим monitor

1. Ingress active/pass-through tap: `kCGHIDEventTap + kCGHeadInsertEventTap`.
2. Downstream listen-only tap: сначала
   `kCGAnnotatedSessionEventTap + kCGTailAppendEventTap`, с возможностью менять
   tap location для сравнительных прогонов.
3. Снимок `CGGetEventTapList` с PID, process path, tap point, options, mask,
   enabled и latency до и после запуска Horizon/LinearMouse.
4. Агрегация раз в секунду вместо постоянного per-event logging.
5. Опциональный короткий bounded trace для анализа отдельных жестов.

Обязательные поля метрик:

- `ingress`, `returned`, `observedDownstream`, `dropped`;
- события в секунду и минимальный/средний/максимальный inter-arrival time;
- integer, fixed-point и point delta по X/Y;
- optional IOHID delta и явный признак доступности private payload;
- сумма и распределение delta;
- `continuous`, scroll phase и momentum phase;
- source PID/userData и признак synthetic event;
- число disable/timeout/re-enable event tap;
- выбранный режим probe и идентификатор тестового прогона.

`returned` означает решение нашего callback, а не гарантированную доставку в
Horizon. Нельзя называть его доказанным `EventOut`.

### Режим drop-all

На ограниченное время возвращать `NULL` для всех scroll events. Режим должен
иметь автоматическое завершение и заметный индикатор состояния.

- Если scroll в VDI прекращается, Horizon не обходит наш CGEventTap.
- Если VDI продолжает scroll, исследовать tap ordering и прямой IOHID path.

### Режим filter

Добавлять только после monitor и drop-all экспериментов:

1. Отдельные X/Y аккумуляторы.
2. Выбор реально используемого delta-поля по результатам trace.
3. Сохранение остатка после квантования вместо полного сброса accumulator.
4. Подавление momentum events.
5. Ограничение максимального output rate независимо от threshold.
6. Согласованная запись integer/fixed-point/point/IOHID полей.
7. Нормализация или очистка gesture phases для дискретного output.
8. Первоначально фильтр действует только когда Horizon является foreground app.

## План экспериментов

### E0. Подготовка исходников

1. Создать `upstream/` и исключить его из родительского Git.
2. Клонировать четыре выбранных проекта полными клонами.
3. Зафиксировать remote URL, branch, commit SHA и лицензию каждого проекта.
4. Найти минимальный набор MIT-кода LinearMouse, который нужен ScrollProbe.

### E1. Monitor-only baseline

Собрать одинаковые временные ряды на host и guest для следующих сценариев:

1. Физический трекпад, обычное приложение host.
2. Физический трекпад, обычное приложение guest.
3. Физический трекпад, Horizon напрямую на host.
4. Физический трекпад, Horizon в guest, Ubuntu VDI.
5. Физический трекпад, Horizon в guest, Windows VDI.
6. Bluetooth-мышь в guest Horizon как стабильный control.

Для каждого прогона синхронно собирать:

- ScrollProbe host/guest;
- CPU и responsiveness `WindowServer` в guest;
- CPU Horizon;
- packet/byte rate на физическом и VPN-интерфейсе;
- ping до VDI и контрольный ping до `1.1.1.1`;
- точные timestamps начала и конца физического gesture.

### E2. Tap inventory и drop-all

1. Снять tap list без Horizon.
2. Снять tap list с Horizon.
3. Снять tap list с Horizon и LinearMouse.
4. Установить наш head tap после запуска Horizon.
5. Провести ограниченный drop-all тест в guest Horizon.

### E3. Изоляция полей

Если CGEventTap контролирует Horizon, последовательно проверить:

1. Только drop momentum.
2. Только ограничение rate без изменения delta semantics.
3. Только accumulator/quantization.
4. Rate limit вместе с accumulator.
5. Очистку continuous/phase при сохранении суммарного расстояния.

За один прогон меняется только один фактор.

### E4. Низкоуровневое исследование

Выполнять только если drop-all CGEventTap не останавливает scroll в VDI:

1. Проверить imports, linked frameworks, symbols и strings бинарников Horizon.
2. Искать `CGEventTapCreate`, `IOHIDManager`, `IOHIDEventSystemClient` и
   регистрации callbacks.
3. Определить виртуальное HID-устройство guest через `ioreg`.
4. Оценить userspace IOHID seize/filter.
5. Рассматривать DriverKit/system extension только после доказательства, что
   public CGEventTap path действительно обходится.

## Критерии результата

Минимально успешный workaround:

1. Trackpad scroll в обоих VDI не блокирует keyboard/mouse input.
2. Нет многосекундных WindowServer/Horizon freeze.
3. Ping до VDI не получает многосекундные задержки и массовые потери.
4. Continent ZTN не уходит в reconnect при длительной прокрутке.
5. Bluetooth-мышь не деградирует.

Для принятия фильтра дополнительно требуется:

1. Измеримое снижение downstream event rate.
2. Предсказуемая суммарная scroll distance без дрейфа остатка.
3. Рабочие вертикальная и горизонтальная прокрутка.
4. Отсутствие stuck gesture/momentum state.
5. Автоматическое восстановление event tap после timeout/disable.

## Текущий статус

| Этап | Статус |
|---|---|
| Выравнивание host/guest macOS | Завершено, не помогло |
| LinearMouse line mode/no inertia | Проверено, недостаточно |
| UTM Pointer x Dynamic Resolution matrix | Завершено, улучшение не подтверждено |
| Upstream source reconnaissance | Завершено, выводы в `UPSTREAM.md` |
| Локальные upstream clones | Завершено, ревизии зафиксированы |
| Архитектура ScrollProbe | Утверждена, public API baseline |
| ScrollProbe monitor | Не начат |
| Drop-all bypass test | Не начат |
| Throttling filter | Не начат, заблокирован измерениями |
| IOHID/DriverKit | Не начат, заблокирован bypass test |

## Следующий шаг

Создать минимальный проект `ScrollProbe.app`, реализовать dedicated event thread,
public-field sample extraction, ingress/downstream taps и one-second aggregate
metrics. До добавления drop-all сначала получить monitor-only baseline.

## Известные организационные блокеры

На host команда `xcrun --show-sdk-path` сообщила, что лицензия Xcode не принята.
До первой сборки потребуется принять лицензию Xcode. Это действие требует
интерактивного подтверждения пользователя и не должно выполняться агентом
автоматически через `sudo`.
