# Завантаження FreePunto

## Пряме завантаження DMG

[Завантажити FreePunto-0.3.0.dmg](https://github.com/VedicV/FreePunto/releases/download/v0.3.0/FreePunto-0.3.0.dmg)

Це посилання веде на файл DMG у GitHub Releases. Воно почне працювати після публікації релізу `v0.3.0` і завантаження asset-файлу `FreePunto-0.3.0.dmg`.

## Встановлення

1. Завантажте DMG.
2. Відкрийте `FreePunto-0.3.0.dmg`.
3. Перетягніть `FreePunto.app` до `Applications`.
4. Запустіть FreePunto з `Applications`.

Для глобальних гарячих клавіш, читання і заміни тексту macOS може вимагати дозволи Accessibility та Input Monitoring.

## Оновлення

Для поточних ad-hoc збірок macOS може вимагати повторно видати дозволи після заміни `FreePunto.app`.

1. Закрийте FreePunto через меню.
2. У `System Settings -> Privacy & Security -> Accessibility` видаліть старий FreePunto зі списку кнопкою `-`.
3. У `System Settings -> Privacy & Security -> Input Monitoring` також видаліть старий FreePunto, якщо він там є.
4. Замініть застосунок новою версією з DMG.
5. Запустіть FreePunto і додайте його назад до потрібних списків дозволів.
6. Знову закрийте FreePunto.
7. Запустіть FreePunto ще раз з `Applications`.

Детальніше: [INSTALL_USAGE.md](INSTALL_USAGE.md#оновлення-на-нову-версію).

## Локальне збирання DMG

Якщо потрібно зібрати DMG локально:

```bash
./scripts/build_dmg.sh
```

Після збирання файл буде тут:

```text
dist/FreePunto-0.3.0.dmg
```
