# WP-08: hardening и production release gates

Статус: в работе, 2026-07-18. Этот документ не объявляет production release
готовым: он разделяет автоматически доказанные гейты и внешние/device gates.

## Автоматизировано и проверено

- Flutter 3.44.6 зафиксирован в `app/.flutter-version`; Dart-зависимости — в
  `pubspec.lock`, новые Windows shell plugins также имеют exact constraints;
- `flutter analyze` — 0 issues; полный suite — 147/147;
- Windows x64 release и Android release APK собираются;
- `tool/generate_release_metadata.ps1` без сети строит CycloneDX 1.5 SBOM по
  всем 190 Dart/Flutter components и SHA-256 для APK, всего Windows Release
  каталога и SBOM;
- release APK: minSdk 24, targetSdk 36; `INTERNET`/`ACCESS_NETWORK_STATE` отсутствуют;
- app `lintVitalRelease` — no issues; privacy grep не находит content/path logging;
- migrations v1→v2, malicious/truncated backup, path traversal, hash mismatch, media fault
  paths, stale ASR completion и optimistic conflicts покрыты тестами;
- Windows cold start release-артефакта: 352/188/188 ms до `MainWindowHandle`.

Генерация release metadata:

```powershell
Set-Location h:\.pet\potok\app
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\generate_release_metadata.ps1
```

Результат лежит в игнорируемом `build/release-metadata/`; его нужно
публиковать вместе с конкретными артефактами, а не коммитить как постоянный
файл.

## Незакрытые production gates

1. Нет production signing keys, AAB/Play signing, MSIX/MSIX-signing и выбранного update
   channel. Это требует решения владельца и ADR до внедрения.
2. Нет Android device/AVD и Windows 10 host: не пройдены install/upgrade/rollback,
   TalkBack/Narrator, call/headset/background/low-storage и widget/shortcut/share smoke matrix.
3. Нет предыдущей опубликованной production-версии, поэтому upgrade с неё и
   rollback installer пока неприменимы; restore v1 fixture и migration v1→v2 проверены.
4. Full Gradle `lintRelease` падает в `just_audio 0.10.6` library lint (137
   `NewApi` findings при library minSdk 16). App lint чист; долг не скрыт baseline.
5. SBOM сформирован, но vulnerability-feed scan и human license review всего
   транзитивного native graph должны выполняться release pipeline с доступом к
   актуальным feeds.

До закрытия пунктов 1–5 текущие артефакты — release-mode QA builds, а не
production release.
