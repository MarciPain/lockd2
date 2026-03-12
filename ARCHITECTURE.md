# Project Architecture - lockd2 (Mobile App)

## Current State
`lockd2` is a mobile application developed with the Flutter framework that connects to the `lockd-go2` backend. The app allows viewing and controlling lock states (open/close/trigger).

## Functionality
- **Dynamic UI**: Control interface automatically generated based on the ACL and lock type sent by the backend.
- **API Key Management**: Secret key for authentication can be provided during initial setup or in settings.
- **Localization**: Support for Hungarian and English languages.
- **Automated Build**: Android APK automatically generated after every push using GitHub Actions.

## File List and Functions
- [lib/main.dart](./lib/main.dart): Entry point of the application and the complete UI logic (single-file implementation for easier management).
- [assets/](./assets): Image resources and icons.
- [.github/workflows/](./.github/workflows): CI/CD processes (Android build).

## Related Projects
- [lockd-go2 Backend](https://github.com/MarciPain/lockd-go2): Server-side logic.
- [hass-lockd2-addon](https://github.com/MarciPain/hass-lockd2-addon): Home Assistant integration.

---

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Donate-orange.svg)](https://buymeacoffee.com/marcipain)

---

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Donate-orange.svg)](https://buymeacoffee.com/marcipain)
