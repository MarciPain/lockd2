# Projekt Architektúra - lockd2 (Mobilapp)

## Aktuális állapot
A `lockd2` egy Flutter keretrendszerben fejlesztett mobilalkalmazás, amely a `lockd-go2` backendhez csatlakozik. Az alkalmazás lehetővé teszi a zárak állapotának megtekintését és vezérlését (nyitás/zárás/trigger).

## Funkcionalitás
- **Dinamikus UI**: A backend által küldött ACL és zártípus alapján automatikusan generált vezérlőfelület.
- **API Kulcskezelés**: Kezdeti beállításkor vagy a beállításokban megadható titkos kulcs a hitelesítéshez.
- **Lokalizáció**: Magyar és angol nyelv támogatása.
- **Automatizált Build**: GitHub Actions segítségével automatikusan generált APK minden push után.

## Fájllista és funkciók
- [lib/main.dart](./lib/main.dart): Az alkalmazás belépési pontja és a teljes UI logika (egy fájlas implementáció a könnyebb kezelhetőség érdekében).
- [assets/](./assets): Képi erőforrások és ikonok.
- [.github/workflows/](./.github/workflows): CI/CD folyamatok (Android build).

## Kapcsolódó Projektek
- [lockd-go2 Backend](https://github.com/MarciPain/lockd-go2): A kiszolgáló oldali logika.
- [hass-lockd2-addon](https://github.com/MarciPain/hass-lockd2-addon): Home Assistant integráció.
