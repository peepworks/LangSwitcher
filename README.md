# 🌐 LangSwitcher

A lightweight, open-source macOS menu bar application that allows you to instantly switch input languages using customizable global keyboard shortcuts and app-specific profiles.

![macOS](https://img.shields.io/badge/macOS-13.5+-007ACC?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square)
![Version](https://img.shields.io/badge/Version-v0.3.0-success?style=flat-square)
![License](https://img.shields.io/badge/License-GPLv3-blue.svg?style=flat-square)

## ✨ Features
* **App-Specific Keyboards (New in v0.3.0!):** Automatically switch to your preferred language when a specific application (e.g., Google Chrome, Terminal) becomes active.
* **Modern Native UI:** A beautifully redesigned settings window using macOS native sidebar navigation, matching the modern System Settings experience.
* **Auto-Update Checker:** Built-in background updater checks the GitHub releases every 24 hours to keep your app up to date silently.
* **Modifier Key Tap Support:** Switch languages simply by tapping a single modifier key (e.g., `Left ⌘`, `Right ⌥`, `⇪ Caps Lock`) or a combination of modifiers (e.g., `⌘ + ⌥`). 
* **System Keyboard Integration:** Automatically detects and lists all active input sources directly from your Mac's system settings.
* **Advanced Custom Shortcuts:** Record unlimited multi-key global shortcuts. Hardware key mapping (QWERTY) accurately recognizes and records special keys like F1-F20, Arrows, Esc, and Return.
* **Conflict Prevention:** Built-in duplicate detection warns you with an alert sound and visual feedback if a shortcut is already in use.

## 💻 System Requirements
* **OS:** macOS 13.5 or later
* **Architecture:** Apple Silicon (M1, M2, M3, etc.) Macs only. *(Intel Mac is not supported in this release.)*

## 📥 Installation & Running the App
⚠️ **Note:** Because this is a free, open-source project and not signed with a paid Apple Developer account, macOS Gatekeeper will flag it as being from an "unidentified developer" on the first launch. Please follow these steps to open it safely:

1. Go to the [Releases](https://github.com/peepworks/LangSwitcher/releases) page.
2. Download the latest `LangSwitcher_v0.3.0.zip` file and extract it.
3. Move `LangSwitcher.app` to your `Applications` folder.
4. **Bypassing the Gatekeeper warning (GUI Method):**
   * Open Finder and go to the `Applications` folder.
   * **Right-click (or Control-click)** on `LangSwitcher.app` and select **"Open"**.
   * A warning dialog will appear. Click the **"Open"** button to confirm.
5. **Advanced Terminal Method (If the app says it is "damaged"):**
   * If macOS blocks the app entirely, open the **Terminal** app.
   * Paste and run the following command to remove the quarantine flag:
     ```bash
     sudo xattr -r -d com.apple.quarantine /Applications/LangSwitcher.app
     ```

## ⚙️ Accessibility Permissions (Important)
LangSwitcher requires **Accessibility** permissions to detect your keyboard shortcuts globally.

1. Open **System Settings** > **Privacy & Security** > **Accessibility**.
2. Click the `+` button at the bottom and select `LangSwitcher.app` from your Applications folder.
3. Ensure the toggle next to LangSwitcher is turned **ON**.

🔄 **When Updating:** If shortcuts stop working after replacing an old version, go to the Accessibility settings, select `LangSwitcher`, click `-` to remove it, and click `+` to add the new version again.

## ☕️ Donations
If you find this app helpful, consider buying me a coffee! Your support is greatly appreciated and helps maintain this project.

| Cryptocurrency | Wallet Address |
| :--- | :--- |
| **Bitcoin (BTC)** | `14eZvFmfSnste92o66DcFq9ns7JqWepu1s` |
| **Dogecoin (DOGE)** | `D9sGuU6wXVCSnAPTESQsy1QcsxmTHt6VDW` |

## ⚖️ License
This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)** - see the [LICENSE](LICENSE) file for details. Copyright (c) 2026 peepboy.

<br>

---

<details>
<summary><strong>🇰🇷 한국어 버전 보기 (Click to view Korean version)</strong></summary>

# 🌐 LangSwitcher

LangSwitcher는 전역 단축키와 앱별 자동 프로필을 통해 입력 언어를 즉시 전환할 수 있는 강력한 macOS 메뉴바 전용 오픈소스 애플리케이션입니다.

![macOS](https://img.shields.io/badge/macOS-13.5+-007ACC?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square)
![Version](https://img.shields.io/badge/Version-v0.3.0-success?style=flat-square)
![License](https://img.shields.io/badge/License-GPLv3-blue.svg?style=flat-square)

## ✨ 주요 기능
* **앱별 키보드 자동 전환 (v0.3.0 신규):** 특정 앱(예: 구글 크롬, 터미널)이 활성화될 때마다 사용자가 지정한 언어로 즉시 자동 전환됩니다.
* **모던 네이티브 UI:** macOS 최신 시스템 설정과 동일한 사이드바 디자인으로 설정 창이 전면 개편되었습니다.
* **자동 업데이트 알림:** 백그라운드에서 24시간마다 GitHub 릴리즈를 확인하여 새로운 버전이 있을 때만 알림을 제공합니다.
* **수식어 키 탭(Tap) 전환 지원:** `⌘ Command`, `⌥ Option`, `⇪ Caps Lock` 등 수식어 키 하나만 '짧게 눌렀다 떼는' 동작으로 언어를 전환할 수 있습니다.
* **시스템 키보드 완벽 연동:** 사용자의 Mac 시스템 환경설정에 등록된 입력기(키보드) 목록을 실시간으로 감지합니다.
* **강력한 단축키 설정:** 무제한 조합 추가가 가능하며, F1~F20, 방향키, Esc, Return 등의 특수 키도 완벽하게 화면에 표시됩니다.
* **중복 단축키 방지:** 이미 사용 중인 키 조합 입력 시 경고음과 시각적 피드백으로 충돌을 차단합니다.

## 💻 시스템 요구사항
* **운영체제:** macOS 13.5 이상
* **지원 기기:** Apple Silicon (M1, M2, M3 등) 탑재 Mac 전용 *(현재 인텔 Mac 미지원)*

## 📥 설치 및 실행 방법
⚠️ **참고:** 이 앱은 개인 오픈소스 프로젝트로, 최초 실행 시 '확인되지 않은 개발자' 경고가 나타납니다.

1. [Releases](https://github.com/peepworks/LangSwitcher/releases) 페이지에서 최신 `LangSwitcher_v0.3.0.zip` 파일을 다운로드 및 압축 해제합니다.
2. `LangSwitcher.app`을 `응용 프로그램(Applications)` 폴더로 이동합니다.
3. **확인되지 않은 개발자 경고 우회하기:**
   * Finder에서 `응용 프로그램` 폴더로 이동합니다.
   * `LangSwitcher.app`을 **우클릭(Control-클릭)** 한 후 **"열기"**를 선택합니다. 경고창에서 다시 **"열기"**를 클릭합니다.
4. **앱이 손상되었다고 나오는 경우 (터미널 우회):**
   * 터미널 앱을 열고 아래 명령어를 실행하여 격리 속성을 제거합니다.
     ```bash
     sudo xattr -r -d com.apple.quarantine /Applications/LangSwitcher.app
     ```

## ⚙️ 손쉬운 사용 권한 설정 (중요)
1. **시스템 설정** > **개인정보 보호 및 보안** > **손쉬운 사용**으로 이동합니다.
2. 하단의 `+` 버튼을 눌러 `LangSwitcher.app`을 추가하고 스위치를 켭니다.

🔄 **업데이트 시:** 덮어쓰기 후 단축키가 작동하지 않으면 손쉬운 사용 목록에서 앱을 완전히 삭제(-)한 후 다시 추가(+)해 주세요.

## ☕️ 후원 (Donations)
이 앱이 도움이 되셨다면 커피 한 잔을 후원해 주실 수 있습니다! 보내주신 후원은 프로젝트 유지보수에 큰 힘이 됩니다.

| 암호화폐 | 지갑 주소 |
| :--- | :--- |
| **비트코인 (BTC)** | `14eZvFmfSnste92o66DcFq9ns7JqWepu1s` |
| **도지코인 (DOGE)** | `D9sGuU6wXVCSnAPTESQsy1QcsxmTHt6VDW` |

## ⚖️ 라이선스
이 프로젝트는 **GNU General Public License v3.0 (GPL-3.0)** 라이선스에 따라 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요. Copyright (c) 2026 peepboy.
</details>
