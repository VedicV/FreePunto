# Завантаження FreePunto

## Завантаження з GitHub Releases

[Завантажити FreePunto (GitHub Releases)](https://github.com/VedicV/FreePunto/releases)

Файли DMG для встановлення доступні на сторінці [Releases](https://github.com/VedicV/FreePunto/releases).

## Встановлення

1. Завантажте DMG.
2. Відкрийте `FreePunto-0.3.0.dmg`.
3. Перетягніть `FreePunto.app` до `Applications`.
4. Запустіть FreePunto з `Applications`.

Для глобальних гарячих клавіш, читання і заміни тексту macOS може вимагати дозволи Accessibility та Input Monitoring.

### Якщо macOS не дозволяє відкрити FreePunto

Під час першого запуску macOS може показати вікно **“FreePunto” Not Opened** з повідомленням, що Apple не може перевірити застосунок. У такому разі:

1. У вікні попередження натисніть **Done**. Не натискайте **Move to Trash**.
2. Відкрийте **System Settings → Privacy & Security**.
3. Прокрутіть сторінку вниз до розділу **Security**.
4. Біля повідомлення про заблокований FreePunto натисніть **Open Anyway**.
5. Підтвердьте дію паролем або Touch ID, а потім натисніть **Open**.
6. Коли FreePunto запуститься, відкрийте **Privacy & Security → Accessibility** і увімкніть доступ для FreePunto. Якщо гарячі клавіші не працюють, також увімкніть FreePunto в **Input Monitoring**.

Назви кнопок залежать від мови macOS: **Open Anyway** може називатися **«Відкрити однаково»** або **«Все одно відкрити»**.

#### Альтернатива через Термінал

Якщо кнопка **Open Anyway** не з'явилася, відкрийте застосунок **Terminal**, по черзі виконайте дві команди:

```bash
xattr -dr com.apple.quarantine /Applications/FreePunto.app
open /Applications/FreePunto.app
```

Перша команда знімає карантинну позначку лише з FreePunto, друга — запускає застосунок. Не додавайте `sudo` і не застосовуйте `xattr` до всієї папки `/Applications`.

> [!IMPORTANT]
> Дозволяйте запуск лише тоді, коли ви завантажили FreePunto з [офіційної сторінки GitHub Releases](https://github.com/VedicV/FreePunto/releases). Не вимикайте Gatekeeper та інші механізми захисту macOS повністю.

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
