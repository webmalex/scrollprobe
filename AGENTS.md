# AGENTS.md — общий контекст по задаче VDI

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
