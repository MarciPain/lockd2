# Lockd2 Mobile App

A Flutter application for controlling remote locks. This app communicates with the `lockd-go` backend to manage security and access.

## Features
- **Remote Control**: Open or toggle locks from your phone.
- **ACL Support**: Only shows the locks you have permission to access.
- **Battery Status**: View the battery levels of your connected locks.

## Automatic Builds
This repository is configured with **GitHub Actions**. Every time you push code to the `main` branch, a new Android APK is automatically built.

You can find the compiled APKs in the **Actions** tab of the GitHub repository under the latest successful "Build Android" run.

## Setup
1. Install [Flutter](https://docs.flutter.dev/get-started/install).
2. Run `flutter pub get` to install dependencies.
3. Configure your API key and server address in the app settings.

---
Built with Flutter.
