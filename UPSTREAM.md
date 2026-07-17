# Upstream snapshot и выводы

Дата snapshot: 2026-07-17

Каталог `upstream/` исключен из родительского Git. Каждый подкаталог является
самостоятельным полным clone соответствующего upstream-репозитория. Этот файл
фиксирует ревизии, на которых основаны выводы в `PLAN.md`.

## Ревизии

| Проект | Remote | Branch | Commit | Лицензия |
|---|---|---|---|---|
| LinearMouse | `https://github.com/linearmouse/linearmouse.git` | `main` | `6006ae7d71d0494ef9bc5b1eb76103c693dba4e5` | MIT |
| Mos | `https://github.com/Caldis/Mos.git` | `master` | `5dfb2363331cf63f529fdafa27962c41f91feff4` | CC BY-NC 4.0 |
| Mac Mouse Fix | `https://github.com/noah-nuebling/mac-mouse-fix.git` | `master` | `5bfe58b5d422d0549d270bb9dfb1102bafe1c8eb` | MMF License |
| UTM | `https://github.com/utmapp/UTM.git` | `main` | `fb61bfe86a2cc39bb3bc884636fa55414f317acb` | Apache-2.0 |

Используемый установленный релиз UTM `v4.7.5` соответствует commit
`048ca7498ea3a374439149d51739d94c5300bcda`. Релевантный Apple input/display
код в текущем `main` семантически совпадает с этим релизом.

## LinearMouse

Роль: основной MIT-референс для event tap lifecycle и scroll fields.

Полезные точки:

- `LinearMouse/EventTap/EventTap.swift:13-135`: callback ownership, создание,
  run-loop attachment, timeout recovery и teardown;
- `LinearMouse/EventTap/EventThread.swift:41-217`: отдельный event thread и
  управляемые timers;
- `LinearMouse/EventView/ScrollWheelEventView.swift:11-124`: continuous,
  phases, integer/fixed-point/point delta и optional embedded IOHID payload;
- `LinearMouse/AccessibilityPermission.swift:11-32`: Accessibility/TCC flow;
- `LinearMouse/Utilities/CGEvent+LinearMouseSynthetic.swift:125-151`:
  известные synthetic markers;
- `LinearMouse/EventTransformer/LinearScrollingVerticalTransformer.swift` и
  `LinearScrollingHorizontalTransformer.swift`: доказательство, что line mode
  не является общим rate limiter.

Что не переносить целиком:

- `GlobalEventTap`, потому что он связан с configuration/device/window graph;
- `ObservationToken` и остальные package dependencies;
- mutable `ScrollWheelEventView` с SceneKit matrix и per-event logging;
- PointerKit и полный набор private IOHID headers;
- transformers и GUI LinearMouse.

Private `CGEventCopyIOHIDEvent` полезен для экспериментальной диагностики, но
не является public API. Первая рабочая сборка ScrollProbe не должна зависеть от
него. Поддержку embedded IOHID payload можно добавить отдельным optional backend.

## Mos

Роль: поведенческий референс, не источник кода.

Полезные точки:

- `Mos/ScrollCore/ScrollCore.swift:405-412`: downstream-кандидат
  `kCGAnnotatedSessionEventTap + tailAppend + default`;
- `Mos/Windows/MonitorWindow/MonitorViewController.swift:109-120`:
  listen-only monitor на том же уровне;
- `Mos/Windows/MonitorWindow/Logger.swift:25-97`: набор отображаемых CG fields;
- `Mos/Utils/Interceptor.swift:81-118`: permission-aware tap recovery.

Ограничения:

- trackpad events намеренно bypass в `ScrollCore.swift:63-88`;
- tap работает на main run loop;
- monitor обновляет UI практически на каждое событие и искажает high-rate
  измерения;
- synthetic output может отправляться прямо в PID и обходить session tap chain;
- лицензия запрещает коммерческое использование.

Из Mos не копируем код. Используем только независимо реализованные идеи:
self-marker, downstream observer и coalesced UI refresh.

## Mac Mouse Fix

Роль: справочник для позднего IOHID/private API исследования.

Полезные точки:

- `Helper/Core/Scroll/Scroll.m:81-90`: public HID/head/default scroll tap;
- `Helper/Core/Scroll/Scroll.m:195-250`: disabled-event handling и drop;
- `Helper/Utility/GlobalEventTapThread.m:40-125`: мотивация отдельного input
  thread, но не готовая реализация для копирования;
- `Shared/IOKit/CGEventHIDEventBridge.*`: private bridge между CGEvent и
  IOHIDEvent;
- `Helper/Core/Scroll/Scroll.m:1030-1144`: согласованное заполнение нескольких
  delta representations для будущего synthetic output.

Ограничения:

- production scroll path пропускает continuous/phased trackpad events без
  преобразования;
- dedicated event thread не используется production scroll tap;
- private bridge использует undocumented symbols, а обратный bridge еще и
  hard-coded object offsets;
- прямой IOHID event-system monitor требует Apple private entitlements;
- сложная app/helper/launch-agent архитектура не нужна ScrollProbe;
- нестандартная лицензия делает независимую реализацию предпочтительнее.

На первом этапе не используем код или private API Mac Mouse Fix.

## UTM

Роль: описание host-side границы AVF и возможная точка раннего эксперимента.

Подтвержденный Apple backend path:

1. `Configuration/UTMAppleConfigurationVirtualization.swift:161-169`
   выбирает `VZUSBScreenCoordinatePointingDeviceConfiguration` либо заменяет
   его на `VZMacTrackpadConfiguration`.
2. `Services/UTMAppleVirtualMachine.swift:501-528` создает
   `VZVirtualMachine` с готовой конфигурацией.
3. `Platform/macOS/Display/VMDisplayAppleDisplayWindowController.swift:54-55`
   создает обычный `VZVirtualMachineView`.
4. В том же файле `:78-86` UTM присваивает view виртуальную машину и включает
   или выключает `automaticallyReconfiguresDisplay`.
5. После этого закрытый Virtualization.framework самостоятельно преобразует
   host input в reports выбранного virtual pointing device.

В Apple backend нет UTM-функции, получающей scroll delta и отправляющей ее в
VM. Явная `scrollWheel` обработка в `VMMetalView` относится только к QEMU.
Поэтому изменение `Mac Trackpad` на `Generic Mouse` меняет тип устройства, но
не выводит input из `VZVirtualMachineView`.

Dynamic Resolution также реализован внутри того же opaque view через
`automaticallyReconfiguresDisplay`; прямой связи с event count в исходниках
нет, но внутреннее AVF/compositor взаимодействие не исключено.

Возможный поздний эксперимент:

- заменить `VZVirtualMachineView` минимальным subclass;
- считать вызовы `scrollWheel(with:)` и временно не вызывать `super`;
- проверить, прекращается ли guest scroll в режимах Mouse и Trackpad.

Если subclass не видит или не контролирует Trackpad scroll, AVF использует
opaque multi-touch path, который нельзя нормализовать public API UTM.

## Итоговая граница первой реализации

`ScrollProbe.app` должен быть независимым, unsandboxed и минимальным:

1. Deployment target macOS 15.0.
2. Стабильные bundle identifier, designated requirement и путь установки для TCC.
3. Видимое окно или status UI, особенно для drop-all режима.
4. Ingress: `kCGHIDEventTap + headInsert + default`, только scroll mask.
5. Downstream: configurable listen-only tail, сначала annotated-session.
6. Один выделенный run-loop thread для обоих taps.
7. Только scalar extraction внутри callback.
8. One-second aggregate snapshots и bounded trace ring.
9. Public CG fields в обязательном baseline.
10. `CGGetEventTapList` выполняется вне callbacks.
11. Monitor mode никогда не изменяет и не публикует события.
12. Drop-all имеет автоматический deadline и не создает synthetic events.

Первый этап требует AppKit/ApplicationServices/CoreGraphics/OSLog и Darwin.
IOKit и private bridging header не являются обязательными до получения baseline.
