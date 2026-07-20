# AGENTS.md — общий контекст по задаче VDI

## Обязательный контекст

Перед любыми исследованиями или изменениями прочитать `PLAN.md`. Это живой
документ со статусом, подтвержденными фактами, гипотезами и следующим шагом.

## Коммиты

* Перед созданием коммита следовать правилам из `CONTRIBUTING.md`.
* Использовать Conventional Commits на английском: `type(scope): summary`.
* Перед коммитом убедиться, что `commit-msg` hook из
  `.pre-commit-config.yaml` проходит.

## Цель
Решить проблему со скролом в VDI

## Топология
* хост macOS 15.7.7
	* UTM 4.7.5 (сеть мостом)
		* гостевая macOS 15.7.7
			* VPN Continent ZTN (ContinentZTNMacos-4.0.0.5969)
				* VMware Horizon Client 2312.1 (8.12.1)
				* VDI: Ubuntu 20.04.6 LTS, GNOME 3.36
				* VDI: Windows Server 2019

## Ключевые факты

* Проблема одинаково воспроизводится в Ubuntu и Windows VDI.
* Horizon, запущенный напрямую на host macOS, нормально работает с трекпадом.
* Bluetooth-мышь стабильно работает через guest Horizon.
* Host и guest уже имеют одинаковую macOS 15.7.7.
* Все сочетания UTM `Mac Trackpad`/`Generic Mouse` и Dynamic Resolution On/Off
  проверены без убедительного улучшения.
* Amplification на границе host -> guest измерен: один host stream превращается
  в десятки тысяч guest events, почти полностью zero-delta
  `scrollPhase=changed`.
* Узкий guest filter, удаляющий только такие changed events без momentum,
  устраняет freeze в Ubuntu и Windows при UTM `Mac Trackpad` и `Generic Mouse`.
* Work Agent v0.3 реализует тот же filter как отдельный menu-bar Protection
  service без JSONL и downstream tap; пользователь подтвердил успешную работу в
  guest. Формальные long-soak и VM lifecycle tests остаются в Phase 2.
* Opt-in `Launch at Login` через `SMAppService.mainApp` реализован в v0.4;
  пользователь подтвердил автозапуск после старта ОС на host и в guest.
