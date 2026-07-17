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

## Терминология input path

Нельзя смешивать физическое устройство и выбранное виртуальное устройство UTM:

- `physical input`: встроенный trackpad или внешняя mouse;
- `UTM pointer`: `Mac Trackpad` (`VZMacTrackpadConfiguration`) или
  `Generic Mouse` (`VZUSBScreenCoordinatePointingDeviceConfiguration`);
- `target`: guest native app, Ubuntu Horizon или Windows Horizon.

Ранние scenario с суффиксом `mouse` были выбраны осознанно и означали UTM
`Generic Mouse`, хотя физический scroll выполнялся trackpad. Новые diagnostics
metadata должны хранить эти измерения отдельными полями вместо одного имени.

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
11. Парные runs доказали amplification между host и guest ingress. В зависимости
    от gesture и UTM pointer один host trackpad stream превращался в 25-112 раз
    больше guest scroll events, почти полностью zero-delta
    `scrollPhase=changed`.
12. LinearMouse исключен как источник amplification: burst одинаково появляется
    при полностью завершенном процессе и отсутствующем event tap LinearMouse.
13. Targeted filter, удаляющий только zero-delta `scrollPhase=changed` без
    momentum, устраняет freeze в Ubuntu и Windows Horizon при UTM `Generic Mouse`
    и `Mac Trackpad`.
14. Stress runs с десятками тысяч событий не вызвали freeze или disable/timeout
    ScrollProbe taps. Downstream peak после фильтра остался не выше примерно
    97 events/s.

## Что пока не доказано

1. Не локализован точный генератор amplification внутри закрытого пути
   Virtualization.framework -> guest input stack.
2. Не доказан точный внутренний механизм freeze в Horizon и последующей сетевой
   деградации. Доказано только, что удаление патологических событий до Horizon
   устраняет наблюдаемый freeze в тестовой топологии.
3. Не снят численный stable control с физической Bluetooth-мышью при включенном
   filter.
4. Не выполнены working-day soak, sleep/wake, VM suspend/resume, login item и
   update/TCC migration tests.
5. Нет независимого подтверждения на других версиях macOS, UTM и Horizon.

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
host -> guest; известны похожие UTM/AVF freeze. Два парных run показали, что
обычные host `scrollPhase=changed` events превращаются в тысячи почти полностью
zero-delta changed events уже на guest HID ingress.

Против: `Generic Mouse` не устранил симптом, хотя должен менять тип виртуального
устройства.

### H2. Слишком высокая частота или амплификация событий

AVF, guest WindowServer или другой компонент может превращать один физический
gesture в чрезмерное число `scrollWheel` events.

За: два парных trackpad run показали 155 -> 4750 и 162 -> 5269 событий между
host и guest ingress. Амплификация воспроизводится с включенным и полностью
завершенным LinearMouse. Точный виновник внутри host -> AVF -> guest цепочки еще
не локализован, но сам факт амплификации доказан.

Против: пока измерен только проблемный путь trackpad через guest Horizon;
стабильный mouse control численно не снят.

### H3. LinearMouse меняет delta, но не снижает event rate

Дискретизация каждого микро-события может оставлять прежнюю частоту или даже
усиливать фактическую прокрутку, превращая малую дробную delta в отдельный line
step. Нужен отдельный accumulator/rate limiter, а не только line translation.

Первый парный run подтверждает эту часть гипотезы: guest ingress увидел 4750
событий, а downstream после LinearMouse 4647. LinearMouse удалил 103 momentum
events, но пропустил 4646 scroll-phase events, из которых 4645 имели нулевую
delta. Второй run без процесса и tap LinearMouse всё равно дал 5269 ingress
events. Следовательно, LinearMouse не создает amplification, а его line/no
inertia mode только удаляет полезные momentum events, не ограничивая основной
zero-delta burst.

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
| ScrollProbe monitor | Реализован, host smoke test пройден |
| Переносимый guest bundle | Готов, `dist/ScrollProbe-macos-arm64.zip` |
| Парные host/guest runs | Два run, amplification 155 -> 4750 и 162 -> 5269 |
| Drop-all bypass mode | Реализован, не нужен для рабочего workaround |
| Zero-delta changed filter | Подтверждённый workaround, Ubuntu/Windows без freeze |
| Menu-bar protection agent | Следующий этап для ежедневной работы |
| Throttling filter | Не требуется при текущем targeted workaround |
| IOHID/DriverKit | Не требуется при работающем CGEventTap workaround |

## Следующий шаг

Сделать в том же приложении production-like `Protection` service без обязательных
логов и downstream tap. Service должен жить независимо от diagnostics window,
управляться из menu bar, показывать реальное состояние tap и сохранять явный
выбор пользователя. Текущую форму оставить optional diagnostics window.

## Smoke test ScrollProbe 2026-07-17

Первые два не стандартизованных запуска на host подтвердили работоспособность
обоих taps и JSONL pipeline:

1. Один run накопил 1577 ingress и 1577 downstream events, peak около 145/s.
2. Второй run накопил 270 ingress и 270 downstream events, peak около 131/s.
3. В активных окнах события были continuous и содержали scroll/momentum phases.
4. Timeout или user-input disable не зарегистрированы.
5. Расхождения отдельных секундных окон компенсировались на следующей границе;
   cumulative totals совпали.
6. Стандартизованный smoke run `host-native-trackpad` накопил 462 ingress и
   462 downstream events с peak около 129/s.

Это только host smoke test без стандартизованного одного gesture. Он не
подтверждает и не опровергает amplification на границе host -> guest.

## Первый парный host/guest run 2026-07-17

Пара сценариев была вручную ошибочно отмечена как
`host-to-guest-horizon-windows-mouse-linearmouse` и
`guest-horizon-windows-mouse-linearmouse`:

1. Host ingress/downstream: 155/155 events, peak около 134/s.
2. Guest ingress: 4750 events, peak около 4679/s, то есть в 30,6 раза больше
   cumulative и примерно в 35 раз больше по peak rate.
3. Host имел 49 `scrollPhase=changed` events, guest 4643, рост в 94,8 раза.
4. На host только 3 из 155 событий имели нулевую delta. На guest таких событий
   было 4647 из 4750, или 97,8%.
5. Guest LinearMouse сократил downstream только до 4647 events. Он удалил все
   103 momentum events, но пропустил phase burst; downstream содержал всего одно
   ненулевое событие с суммарным `pointDeltaY=8`.
6. Probe tap не получил timeout или disable. В inventory LinearMouse tap имел
   подозрительное latency value около 66,2 миллионов микросекунд; значение пока
   нельзя интерпретировать как длительность конкретного freeze.

Фактически использовался trackpad и наблюдался обычный многосекундный freeze.
Это первое прямое доказательство сильной амплификации между host и guest. Оно
также объясняет, почему отключение momentum в LinearMouse могло улучшать сеть,
но не устранять UI freeze: основной zero-delta phase burst оставался.

## Парный run без LinearMouse 2026-07-17

LinearMouse был завершен через его menu item. Guest `tap-inventory` подтверждает,
что процесса и event tap LinearMouse в момент run не было. Scenario снова был
вручную ошибочно назван как mouse, фактический input был trackpad, а результатом
был стандартный многосекундный freeze.

1. Host ingress/downstream: 162/162 events, peak около 138/s.
2. Guest ingress/downstream: 5269/5269 events, cumulative amplification в 32,5
   раза.
3. Peak guest ingress около 5160/s против 138/s на host, рост в 37,4 раза.
4. Host имел 41 `scrollPhase=changed` event, guest 5147, рост в 125,5 раза.
5. Guest ingress содержал 5151 zero-delta events из 5269, или 97,8%.
6. Все 118 momentum events и суммарные delta совпали между guest ingress и
   downstream. Без LinearMouse ничего намеренно не удалялось.
7. В первую секунду burst guest ingress получил 5152 events, downstream успел
   обработать 4041. В следующую секунду ingress получил 110, а downstream 1221,
   то есть downstream догнал очередь ровно на 1111 events.
8. Средний inter-arrival внутри основного ingress burst был около 52 мкс, minimum
   около 5,5 мкс. Поэтому instantaneous rate внутри плотной части burst заметно
   выше секундного агрегата 5160/s.
9. Timeout или disable taps ScrollProbe не зарегистрированы.

Контроль без LinearMouse исключает его как источник amplification. Burst уже
присутствует в самом раннем доступном guest CGEventTap и создает измеримую очередь
до downstream tap. Наиболее узкий безопасный первый workaround состоит в
удалении тысяч zero-delta changed events при сохранении жизненного цикла gesture
и всех событий, несущих реальную delta.

## Подтверждение targeted workaround 2026-07-17

Физическим input во всех строках был trackpad. Filter работал только в guest;
host оставался monitor-only.

| UTM pointer | Target | Host events | Guest ingress | Dropped | Downstream | Результат |
|---|---|---:|---:|---:|---:|---|
| Generic Mouse | Windows | 369 | 41495 | 41425 | 70 | freeze исчез |
| Mac Trackpad | Windows, one gesture | 192 | 17184 | 17118 | 66 | freeze исчез |
| Mac Trackpad | Ubuntu, stress | 891 | 40615 | 40137 | 472 | freeze отсутствует |
| Mac Trackpad | Windows, stress | 1369 | 35250 | 34311 | 932 | freeze отсутствует |

Дополнительный mixed guest stress run пропустил через ingress 180622 events,
удалил 177530 и оставил около 3 тысяч downstream без freeze. Во всех чистых и
stress runs отсутствовали timeout, disable и error records. Targeted filter
снижает downstream с тысяч событий в секунду до обычных десятков, не удаляя
momentum, lifecycle или события с любой реальной delta.

В Windows иногда визуально не реагирует первый scroll после переключения. Лог
показывает, что первый gesture не удаляется полностью: в одном run downstream
получил сначала 30, затем 36 событий с ненулевой суммарной delta. Поэтому текущая
гипотеза для этого малого эффекта - focus/warm-up Horizon или Windows, а не stuck
filter. Наблюдение нужно сохранить для soak test, но оно не блокирует workaround.

## UX ScrollProbe v0.2.0

Перед следующими ручными экспериментами реализовано:

1. Свободный ввод scenario заменен списком преднастроенных host/guest profiles.
2. Version/build показывается в окне и записывается в `run-start`.
3. UI показывает роль host/guest, paired profile, номер Start step и полный
   порядок одного controlled gesture.
4. Добавлен выбираемый и сохраняемый каталог логов. Ошибка записи завершает run,
   а не оставляет тихо поврежденный JSONL.
5. Drop-режимы разрешены только для guest profiles. Drop-all автоматически
   возвращается в monitor mode через 10 секунд; effective mode есть в каждой
   metrics-записи.
6. Приложение не требует перезагрузки VM/VPN между прогонами, если изменяемый
   фактор этого не требует.

Полная автоматическая синхронизация двух приложений между host и guest пока не
реализована. Для текущего targeted теста достаточно статических paired
инструкций; отдельный shared-state wizard имеет смысл только если ручных
сценариев снова станет много.

## Путь от probe к продукту

Принято направление: не создавать второе приложение. Один app bundle и один
bundle ID означают одну Accessibility/TCC запись, один updater и невозможность
конфликта двух active HID taps. Внутри одного приложения operational filter и
diagnostics разделяются на независимые services.

### Phase 0. Рабочий workaround сейчас

ScrollProbe v0.2.0 можно оставить запущенным в guest в targeted filter mode.
Недостатки: открытое окно, обязательный diagnostics logger и отсутствие
автозапуска protection после reboot.

### Phase 1. Work Agent

1. Перенести ownership active filter tap из window controller в app coordinator.
2. Добавить menu-bar status item: `Protected`, `Paused`, `Needs Accessibility`,
   `Failed`.
3. Добавить `Enable/Pause Protection`, `Open Diagnostics`, `Settings`, `Quit`.
4. Protection path использует только active HID tap и минимальный classifier, не
   создает JSONL и downstream tap.
5. Закрытие diagnostics window не завершает приложение и не выключает protection.
6. Сохранять только явный `protectionEnabled`; никогда не сохранять drop-all.
7. При permission loss или неизвестной ошибке fail open и честно показывать
   `Failed`, не блокируя scroll.

### Phase 2. Always-on reliability

1. Добавить opt-in `Launch at Login` через `SMAppService.mainApp`.
2. Проверить reboot/login, sleep/wake, lock/unlock, VM suspend/resume и TCC revoke.
3. Реализовать bounded tap recreate/re-enable и working-day soak.
4. Diagnostics errors не должны останавливать production protection service.

### Phase 3. Private beta

1. Выбрать окончательные product name и bundle ID до внешней раздачи.
2. Подписывать Developer ID с hardened runtime, timestamp, notarization и staple.
3. Добавить MIT license, privacy statement, uninstall и Accessibility onboarding.
4. Protection mode ничего не пишет на диск и не использует сеть. Diagnostics
   opt-in, bounded и экспортируется с удалением hostname, user paths и inventory
   посторонних security/VPN приложений.
5. Проверить физическую mouse, horizontal scroll, momentum, slow/reverse gestures
   и обновление beta поверх предыдущей версии с сохранением TCC/login state.

### Phase 4. Public release

Публиковать как experimental workaround для воспроизведенной патологии
UTM/Apple Virtualization в явно перечисленной топологии, а не как универсальное
исправление Horizon. Для Reddit приложить numbers, checksums, known limitations и
исходный код; telemetry в первой публичной версии не добавлять.

## TCC и локальная подпись

Лицензия Xcode на host принята, сборка работает. Изначальная ad-hoc подпись
создавала designated requirement на основе `cdhash`, поэтому после каждой
пересборки старая запись Accessibility выглядела включенной, но не подходила
новому бинарнику. Сборка переведена на стабильное локальное identifier-only
requirement `dev.scrollprobe.ScrollProbe`. После однократного удаления старой
TCC-записи и повторной выдачи последующие локальные сборки должны сохранять
совместимость разрешения.

Отдельный Input Monitoring не нужен: оба taps и metrics работают с выданным
Accessibility. `CGRequestListenEventAccess()` удален из UI, поскольку на macOS 15
он может не регистрировать приложение в таблице даже при успешно работающем tap.
