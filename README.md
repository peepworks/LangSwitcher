# 🌐 LangSwitcher

A lightweight, open-source macOS menu bar application that allows you to instantly switch input languages using customizable global keyboard shortcuts.

![macOS](https://img.shields.io/badge/macOS-13.5+-007ACC?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square)
![License](https://img.shields.io/badge/License-GPLv3-blue.svg?style=flat-square)

## ✨ Features
* **System Keyboard Integration:** Automatically detects and lists all active input sources directly from your Mac's system settings. No need to manage language lists manually!
* **Default Shortcuts:** Easily enable or disable familiar combinations like `⌃ Control + Space`, `⌘ Command + Space`, or `⌥ Option + Space`.
* **Advanced Custom Shortcuts:**
  * **Unlimited Combinations:** Record your own multi-key global shortcuts to switch to any specific language instantly.
  * **Hardware Key Mapping:** Accurately recognizes and records keys based on the QWERTY layout, even if your current input method is set to a non-Latin language (e.g., Korean).
  * **Conflict Prevention:** Built-in duplicate detection warns you with an alert sound and visual feedback if a shortcut is already in use.
* **Menu Bar App:** Runs quietly in the background without cluttering your Dock.
* **Launch at Login:** Option to automatically start the app when your Mac boots.
* **Localization:** Fully supports multiple languages, seamlessly adapting to your system language using `Localizable.xcstrings`.

## 💻 System Requirements
* **OS:** macOS 13.5 or later
* **Architecture:** Apple Silicon (M1, M2, M3, etc.) Macs only. *(Intel Mac is not supported in this release.)*

## 📥 Installation & Running the App
⚠️ **Note:** Because this is a free, open-source project and not signed with a paid Apple Developer account, macOS Gatekeeper will flag it as being from an "unidentified developer" on the first launch. Please follow these steps to open it safely:

1. Go to the [Releases](../../releases) page.
2. Download the latest `LangSwitcher_v0.2.0.zip` file and extract it.
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
   * Enter your Mac password when prompted, then try launching the app again.

## ⚙️ Accessibility Permissions (Important)
LangSwitcher requires **Accessibility** permissions to detect your keyboard shortcuts globally.

1. Open **System Settings** > **Privacy & Security** > **Accessibility**.
2. Click the `+` button at the bottom (you may need to enter your Mac password) and select `LangSwitcher.app` from your Applications folder.
3. Ensure the toggle next to LangSwitcher is turned **ON**.

🔄 **When Updating to a New Version:**
Because this app does not use a paid developer signature, macOS may invalidate the accessibility permission when you overwrite it with a new version. If shortcuts stop working after an update:
1. Go back to the Accessibility settings.
2. Select the existing `LangSwitcher` and click the `-` button to **remove it completely**.
3. Click the `+` button to **add the newly installed version** again.

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

LangSwitcher는 사용자 지정 전역 키보드 단축키를 사용하여 입력 언어를 즉시 전환할 수 있는 가볍고 빠른 macOS 메뉴바 전용 오픈소스 애플리케이션입니다.

![macOS](https://img.shields.io/badge/macOS-13.5+-007ACC?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square)
![License](https://img.shields.io/badge/License-GPLv3-blue.svg?style=flat-square)

## ✨ 주요 기능
* **시스템 키보드 완벽 연동:** 사용자의 Mac 시스템 환경설정에 등록된 입력기(키보드) 목록을 실시간으로 자동 감지하여 제공합니다.
* **기본 단축키:** `⌃ Control + Space`, `⌘ Command + Space`, `⌥ Option + Space` 등 익숙한 조합을 쉽게 켜고 끌 수 있습니다.
* **강력한 사용자 지정 단축키 (Custom Shortcuts):**
  * **무제한 추가:** 원하는 키 조합을 마음대로 추가하여 특정 언어로 즉시 전환하세요.
  * **하드웨어 키 매핑:** 한글 등 다른 언어 입력 상태에서 단축키를 지정해도 영문(QWERTY) 배열을 기준으로 정확하게 기록됩니다.
  * **중복 단축키 방지:** 이미 사용 중인 키 조합 입력 시 경고음과 붉은색 시각적 피드백을 제공하여 충돌을 원천 차단합니다.
* **메뉴바 전용 앱:** Dock 공간을 차지하지 않고 백그라운드에서 조용히 실행됩니다.
* **자동 실행:** Mac 부팅 시 앱이 자동으로 실행되도록 설정할 수 있습니다.
* **다국어 지원:** 시스템 언어 설정에 맞춰 UI가 자연스럽게 변환됩니다.

## 💻 시스템 요구사항
* **운영체제:** macOS 13.5 이상
* **지원 기기:** Apple Silicon (M1, M2, M3 등) 탑재 Mac 전용 *(현재 버전은 인텔 Mac을 지원하지 않습니다.)*

## 📥 설치 및 실행 방법
⚠️ **참고:** 이 앱은 개인 오픈소스 프로젝트이며 유료 애플 개발자 프로그램에 등록되어 있지 않습니다. 따라서 처음 실행 시 macOS에서 '확인되지 않은 개발자' 경고가 나타납니다. 아래의 방법으로 안전하게 실행해 주세요.

1. [Releases](../../releases) 페이지로 이동합니다.
2. 최신 버전의 `LangSwitcher_v0.2.0.zip` 파일을 다운로드하고 압축을 풉니다.
3. `LangSwitcher.app` 파일을 `응용 프로그램(Applications)` 폴더로 이동합니다.
4. **확인되지 않은 개발자 경고 우회하기 (마우스 사용):**
   * Finder를 열고 `응용 프로그램` 폴더로 이동합니다.
   * `LangSwitcher.app`을 **마우스 우클릭(또는 Control-클릭)** 한 후 메뉴에서 **"열기"**를 선택합니다.
   * 경고창이 나타나면 다시 한번 **"열기"** 버튼을 클릭합니다.
5. **터미널을 이용한 확실한 방법 (앱이 손상되었다고 나오는 경우):**
   * 만약 위 방법으로도 실행되지 않거나 앱이 손상되었다는 오류가 뜬다면, **터미널(Terminal)** 앱을 엽니다.
   * 아래 명령어를 복사하여 붙여넣고 엔터를 쳐서 앱의 격리 속성을 제거합니다:
     ```bash
     sudo xattr -r -d com.apple.quarantine /Applications/LangSwitcher.app
     ```
   * 맥의 비밀번호를 입력한 뒤(화면에 보이지 않아도 입력됩니다) 엔터를 치고, 앱을 다시 실행해 보세요.

## ⚙️ 손쉬운 사용 권한 설정 (중요)
LangSwitcher가 전역 단축키 입력을 감지하려면 **'손쉬운 사용'** 권한이 반드시 필요합니다.

1. 맥의 **시스템 설정** > **개인정보 보호 및 보안** > **손쉬운 사용**으로 이동합니다.
2. 하단의 `+` 버튼을 누르고 (또는 비밀번호 입력) 응용 프로그램 폴더에 있는 `LangSwitcher.app`을 추가합니다.
3. LangSwitcher 옆의 스위치가 **켜짐(활성화)** 상태인지 확인합니다.

🔄 **새 버전으로 앱 업데이트 시 주의사항:**
이 앱은 유료 애플 개발자 서명이 되어 있지 않기 때문에, 새 버전으로 덮어쓰기(업데이트)를 하면 macOS가 보안상 기존 권한을 무효화할 수 있습니다. 업데이트 후 단축키가 작동하지 않는다면 아래 과정을 진행해 주세요.
1. 손쉬운 사용 설정 창으로 다시 이동합니다.
2. 기존에 등록된 `LangSwitcher`를 선택하고 `-` 버튼을 눌러 **목록에서 완전히 지웁니다**.
3. `+` 버튼을 눌러 새로 설치한 앱을 **다시 추가**해 줍니다.

## ☕️ 후원 (Donations)
이 앱이 도움이 되셨다면 커피 한 잔을 후원해 주실 수 있습니다! 보내주신 후원은 프로젝트 유지보수에 큰 힘이 됩니다.

| 암호화폐 | 지갑 주소 |
| :--- | :--- |
| **비트코인 (BTC)** | `14eZvFmfSnste92o66DcFq9ns7JqWepu1s` |
| **도지코인 (DOGE)** | `D9sGuU6wXVCSnAPTESQsy1QcsxmTHt6VDW` |

## ⚖️ 라이선스
이 프로젝트는 **GNU General Public License v3.0 (GPL-3.0)** 라이선스에 따라 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요. Copyright (c) 2026 peepboy.
</details>
