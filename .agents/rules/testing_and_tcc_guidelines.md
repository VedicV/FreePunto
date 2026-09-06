# Testing & macOS TCC Permissions Guidelines for FreePunto

## Core Principle: Avoid the TCC Permission Carousel

On macOS, Accessibility (`AXIsProcessTrusted`), Input Monitoring (`ListenEvent`), and Event Posting (`PostEvent`) permissions are managed by Transparency, Consent, and Control (TCC).

Because FreePunto uses ad-hoc code signing (`codesign --sign -`) during local development, macOS generates a Designated Requirement tied directly to the binary's **CDHash** (`cdhash H"..."`). Any change to the compiled binary changes its CDHash.

Follow these strict guidelines during development and testing to prevent broken permissions and unnecessary user friction.

---

## 1. Test 95% of Changes via Pure CLI (PuntoCore)
- **Do not launch the GUI app to test logic changes.**
- All conversion logic, layout mapping, language detection, sequential cycles, and scanner logic live in `PuntoCore`.
- Run tests via `PuntoCoreTestsRunner`:
  ```bash
  swift build -c release --scratch-path .build && .build/release/PuntoCoreTestsRunner
  ```
- This executes in <1 second and requires **zero** Accessibility permissions.

---

## 2. Canonical Path: Always Test from `/Applications/FreePunto.app`
- macOS TCC treats `/Applications/FreePunto.app` and `dist/FreePunto.app` as completely distinct apps.
- If the user grants permission to `/Applications/FreePunto.app`, running `dist/FreePunto.app` will report `AXIsProcessTrusted: false`.
- **Always copy to `/Applications/FreePunto.app` before testing GUI interactions.**

---

## 3. Never Launch Directly from Terminal
- Running `dist/.../FreePunto &` from zsh or bash attributes the event tap to the **terminal process** (Terminal, iTerm2, Antigravity), NOT to `FreePunto.app`.
- FreePunto will not appear in the Accessibility list, and events will not be intercepted.
- **Always launch via LaunchServices**:
  ```bash
  open /Applications/FreePunto.app
  ```

---

## 4. Never Run `tccutil reset` During Routine Testing
- `tccutil reset Accessibility dev.freepunto.FreePunto` wipes the permission database entry completely.
- This forces the user to manually authenticate, click `+`, and navigate Finder on every build.
- When updating the binary, macOS usually retains the entry in the list; the user only needs to toggle the switch off and on, or macOS may retain trust if signed cleanly.

---

## 5. Keep `BUILD_NUMBER` Deterministic
- In `build_app.sh`, never default `BUILD_NUMBER` to `$(date +%Y%m%d%H%M)`.
- Use a stable number (`BUILD_NUMBER="${BUILD_NUMBER:-1}"`).
- Changing `CFBundleVersion` changes `Info.plist`, which forces signature recreation even if no code changed.

---

## 6. Prompt Option for Accessibility Registration
- In `AppDelegate.swift`, always check Accessibility on startup with `prompt: true`:
  ```swift
  Diagnostics.accessibilityTrusted(prompt: true)
  ```
- This instructs macOS to display the system prompt and automatically add `FreePunto` to the Accessibility list in System Settings (preventing the "app not appearing in settings" issue).

---

## 7. Clean Process Lifecycle Before Replacing App Bundle
- Overwriting a running binary corrupts the Mach-O header in memory and breaks WindowServer event taps.
- Always execute:
  ```bash
  pkill -x FreePunto 2>/dev/null || true
  while pgrep -x FreePunto >/dev/null; do sleep 0.2; done
  rm -rf /Applications/FreePunto.app
  cp -R dist/FreePunto.app /Applications/FreePunto.app
  xattr -dr com.apple.quarantine /Applications/FreePunto.app 2>/dev/null || true
  open /Applications/FreePunto.app
  ```

---

## 8. Diagnostic Logging Without Environment Variables
- `open /Applications/FreePunto.app` strips shell environment variables.
- Keep diagnostic logging directed to `/tmp/freepunto_debug.log` by default in debug/development builds so logs can always be inspected via `cat /tmp/freepunto_debug.log`.
