<p align="center">
  <img src="LangSwitcher/Assets/AppIcon/logo.png" width="150" alt="LangSwitcher Logo">
</p>

<h1 align="center">🌐 LangSwitcher v0.9.5</h1>

<p align="center">
  <strong>A lightweight macOS menu bar app for faster, smarter, and more predictable input source switching.</strong>
  <br>
  macOS에서 입력 언어 전환을 더 빠르고 정확하게 만들어 주는 경량 메뉴바 앱입니다.
</p>

<p align="center">
  <a href="https://github.com/sponsors/peepworks">
    <img src="https://img.shields.io/badge/Sponsor-GitHub%20Sponsors-ea4aaa?logo=github-sponsors&logoColor=white" alt="Sponsor">
  </a>
</p>

<p align="center">
  <a href="#english">English</a>
  ·
  <a href="#한국어">한국어</a>
</p>

---

# English

## What's New in v0.9.5

### ⚡ Interactive Inline Token Editor

v0.9.5 introduces a visual macro-template engine for text expansion. Instead of editing raw placeholder syntax only, snippet elements are rendered as highlighted interactive **Tokens** in a high-performance AppKit-based editor.

- **Interactive tokens**: Click or double-click a blue token to open its property inspector.
- **Context actions**: Right-click a token to duplicate or delete it inline.
- **Readable metadata**: Snippet options are stored as readable plain text rather than percent-encoded URL-style blocks.
- **External-edit friendly**: Spaces, Korean text, and other native-language values remain clean and editable in exported backup files.

### 🧩 Interactive Form Fields and Advanced Layouts

Create dynamic dialog-based templates that ask for missing values immediately before a snippet expands.

Supported form elements:

- Single-line input: `input`
- Multi-line input: `textarea`
- Dropdown menu: `select`
- Checkbox toggle: `checkbox`
- Radio buttons: `radio`
- Date picker: `datepicker`
- Optional content block: `optional`

#### Smart Field Synchronization

Use the **same Field Name** in multiple form tokens to synchronize their values automatically. This is useful for long forms where a customer name, project name, ID, or date must appear in several locations.

---

## v0.9.0 Highlights

### 🗂️ Profile Support

Create and switch between separate LangSwitcher configurations for different workflows, such as development, writing, work, or personal use.

### 🔒 Stability and Performance Improvements

- Reclaims Unix file descriptors used by helper utilities such as `hidutil` and `plutil`.
- Anchors Accessibility Event Observers (`AXObserver`) to the macOS Main RunLoop for improved long-running stability.
- Uses an \(O(1)\) append-based activity logging architecture instead of row-shifting \(O(n)\) operations.
- Releases high-resolution `NSImage` caches when configuration rows leave the visible area or preference tabs change.

---

## Why LangSwitcher?

Switching between apps, browser tabs, Spotlight, Terminal, messengers, and code editors often leads to typing with the wrong input source. LangSwitcher reduces these interruptions through system-wide shortcuts, app-aware rules, browser tab memory, typo conversion, and advanced text expansion.

## Core Features

- Direct input source switching with custom shortcuts
- Profile support for separate LangSwitcher configurations
- App-specific keyboard rules that switch input sources automatically
- Browser Tab Memory for Chrome, Safari, Edge, and Brave
- English ↔ Korean typo correction
- Custom text expansion with a visual inline Token Editor
- Interactive form fields: textarea, dropdown, checkbox, radio, date picker, and optional blocks
- Name-based form field synchronization across templates
- Dynamic snippet variables for date, time, weekday, clipboard, selected text, and cursor placement
- Hyper Key mapping for Caps Lock (`⌃⌥⇧⌘`)
- Single-modifier toggle key support, including Right Command and Right Option
- App launch shortcuts to launch or focus apps instantly
- Native HUD feedback for input source changes and rule tests
- JSON-based backup and restore

---

## Custom Text Expansion Guide

LangSwitcher lets you turn short abbreviations (**Triggers**) into email templates, code snippets, clipboard content, and interactive input forms.

### 1. Basic Text Expansion

| Item | Description |
|---|---|
| **Trigger** | A short abbreviation you type, such as `;em`. Using a prefix like `;` helps prevent accidental expansion. |
| **Replacement Text** | The text inserted when the trigger is expanded, such as `my.email@gmail.com`. |

Example:

```text
Trigger: ;em
Replacement: my.email@gmail.com
```

### 2. Dynamic Variables

Insert dynamic values through the **[⊕ Insert Element]** interface.

| Variable | Description | Example output |
|---|---|---|
| `{{date:yyyy-MM-dd}}` | Current date | `2026-07-12` |
| `{{time:HH:mm}}` | Current time | `14:30` |
| `{{clipboard}}` | Most recently copied text | Clipboard content |
| `${selectedText}` | Currently selected text | Selected content |
| `{{cursor}}` | Final cursor location after expansion | Cursor position |

### 3. Interactive Form Template Example

```text
Hello {{input:CustomerName}},

Thank you for selecting our platform. Your account ID is
{{input:AccountID|1000&size=120&required=true}}.

We will review your inquiry by
{{datepicker:Deadline|yyyy-MM-dd}}.

Best regards,
{{cursor}}
```

When this snippet runs, LangSwitcher requests any missing form values before inserting the final completed text.

> **Tip:** Reuse the same field name, such as `CustomerName`, anywhere in a template to keep values synchronized automatically.

---

## Screenshots

<p align="center">
  <img src="images/screen_menu_v0.9.0.png" width="300" alt="LangSwitcher Menu">
</p>

<p align="center">
  <img src="images/screen_v0.9.0.png" width="700" alt="LangSwitcher Settings">
</p>

---

## System Requirements

| Item | Requirement |
|---|---|
| OS | macOS 13.5 or later |
| Architecture | Apple Silicon only: M1, M2, M3, or M4 |

---

## Installation

> [!WARNING]
> LangSwitcher is a free open-source project and is not signed with a paid Apple Developer account. macOS may show an “unidentified developer” warning on first launch.

1. Go to the [Releases](../../releases) page.
2. Download the latest `LangSwitcher_v0.9.5.zip`.
3. Extract the ZIP file.
4. Move `LangSwitcher.app` to `/Applications`.
5. Right-click the app and select **Open**.

### If macOS Says the App Is Damaged

Run the following command in Terminal:

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LangSwitcher.app
```

---

## Permissions

### 1. Accessibility Permission — Required

Accessibility permission is required for:

- Global shortcut detection
- Typo correction
- Input source control
- Text expansion and automated keyboard input

Enable it here:

```text
System Settings
→ Privacy & Security
→ Accessibility
→ Enable LangSwitcher
```

### 2. Automation Permission — Optional

Automation permission is required for **Browser Tab Memory**.

Supported browsers:

- Google Chrome
- Safari
- Microsoft Edge
- Brave

Enable it here:

```text
System Settings
→ Privacy & Security
→ Automation
→ Enable supported browsers under LangSwitcher
```

---

## Update Notes

If shortcuts stop working after an update, remove LangSwitcher from Accessibility permissions and add it again. This can resolve macOS permission-cache issues.

```text
System Settings
→ Privacy & Security
→ Accessibility
→ Select LangSwitcher
→ Remove (−)
→ Add (+) LangSwitcher again
```

---

## Quick Start

1. Launch LangSwitcher from the menu bar.
2. Open **Preferences**.
3. Configure startup behavior, HUD, Hyper Key, toggle key, profiles, and text expansion rules.
4. Enable Window Focus Management and Browser Tab Memory if needed.
5. Add custom input-source shortcuts.
6. Add app-specific keyboard rules.
7. Add app launch shortcuts.
8. Create text expansion snippets and interactive templates.

---

## Support LangSwitcher

LangSwitcher is a free open-source project maintained by a solo developer. If it improves your workflow, please consider supporting continued development.

### GitHub Sponsors

[👉 Sponsor on GitHub](https://github.com/sponsors/peepworks)

### Cryptocurrency Donations

| Cryptocurrency | Wallet Address |
|---|---|
| Bitcoin (BTC) | `14eZvFmfSnste92o66DcFq9ns7JqWepu1s` |
| Dogecoin (DOGE) | `D9sGuU6wXVCSnAPTESQsy1QcsxmTHt6VDW` |

---

## Contributing

Contributions are welcome.

You can help by submitting:

- Bug reports
- Feature requests
- Pull requests
- Translations
- Documentation improvements

---

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE) (`GPL-3.0`).

---

# 🇰🇷 한국어

<details>
<summary><strong>클릭해서 한국어 버전 보기</strong></summary>

<br>

## v0.9.5 업데이트

### ⚡ 비주얼 인라인 토큰 에디터

v0.9.5에서는 텍스트 대치 기능을 위한 시각적 매크로 템플릿 엔진을 도입했습니다. 이제 단순한 제어 문자열만 편집하는 방식이 아니라, AppKit 기반 편집기에서 각 요소가 강조 표시된 인터랙티브 **토큰(Token)** 으로 표시됩니다.

- **토큰 편집**: 파란색 토큰을 클릭하거나 더블 클릭하면 해당 요소의 속성 설정창이 열립니다.
- **컨텍스트 메뉴**: 토큰을 우클릭하여 인라인 복제 또는 삭제를 실행할 수 있습니다.
- **읽기 쉬운 메타데이터**: 퍼센트 인코딩된 URL 형식 대신 일반 텍스트 기반의 읽기 쉬운 옵션 포맷을 사용합니다.
- **외부 편집 호환성**: 한국어, 공백, 특수문자가 포함된 설정도 백업 파일이나 외부 편집기에서 깔끔하게 유지됩니다.

### 🧩 인터랙티브 폼 필드와 고급 레이아웃

스니펫 실행 직전에 부족한 값을 입력받는 동적 다이얼로그 기반 템플릿을 만들 수 있습니다.

지원하는 입력 요소:

- 한 줄 입력: `input`
- 여러 줄 입력: `textarea`
- 드롭다운 메뉴: `select`
- 체크박스: `checkbox`
- 라디오 버튼: `radio`
- 날짜 선택기: `datepicker`
- 선택형 블록: `optional`

#### 동일 이름 필드 동기화

하나의 템플릿 안에서 동일한 **필드 이름(Field Name)** 을 사용하면 입력값이 자동으로 동기화됩니다. 고객명, 프로젝트명, 식별 번호처럼 여러 위치에 반복해서 넣어야 하는 값에 유용합니다.

---

## v0.9.0 주요 기능

### 🗂️ 프로필 지원

개발, 문서 작성, 업무, 개인 작업 등 용도별로 LangSwitcher 설정을 분리하고 빠르게 전환할 수 있습니다.

### 🔒 안정성 및 성능 개선

- `hidutil`, `plutil` 등 보조 유틸리티가 사용하는 Unix 파일 디스크립터를 회수합니다.
- 접근성 감시자(`AXObserver`)를 macOS Main RunLoop에 연결하여 장시간 실행 안정성을 높였습니다.
- 활동 통계를 기존 행 이동 방식의 \(O(n)\) 구조에서 \(O(1)\) append 구조로 개선했습니다.
- 목록이 화면 밖으로 이동하거나 설정 탭이 전환되면 고해상도 `NSImage` 캐시를 정리합니다.

---

## LangSwitcher 소개

LangSwitcher는 앱, 브라우저 탭, Spotlight, Terminal, 메신저, 코드 에디터를 빠르게 오가는 환경에서 발생하는 입력 언어 전환 스트레스를 줄여 주는 macOS 메뉴바 앱입니다.

입력 소스 단축키, 앱별 자동 규칙, 브라우저 탭 언어 기억, 한영 오타 변환, 텍스트 대치, 앱 실행 단축키를 하나의 네이티브 앱에서 제공합니다.

## 핵심 기능

- 사용자 지정 단축키로 입력 소스 직접 전환
- 작업 환경별 설정을 분리하는 프로필 기능
- 특정 앱 활성화 시 입력 언어를 자동으로 바꾸는 앱별 규칙
- Chrome, Safari, Edge, Brave 브라우저 탭별 언어 기억
- 영문 ↔ 한글 오타 자동 변환
- 비주얼 인라인 토큰 에디터 기반 텍스트 대치
- 텍스트 영역, 드롭다운, 체크박스, 라디오, 날짜 선택기, 선택형 블록 지원
- 동일 필드명 기반 입력값 동기화
- 날짜, 시간, 요일, 클립보드, 선택 텍스트, 커서 위치 변수 지원
- Caps Lock을 Hyper Key(`⌃⌥⇧⌘`)로 매핑
- Right Command, Right Option 같은 단일 수식 키 전환
- 앱을 즉시 실행하거나 앞으로 가져오는 앱 실행 단축키
- 입력 언어 변경과 규칙 테스트 결과를 보여 주는 네이티브 HUD
- JSON 기반 설정 백업 및 복원

---

## 커스텀 텍스트 대치 가이드

텍스트 대치 기능을 사용하면 자주 작성하는 이메일, 상용구, 코드 조각, 동적 시스템 데이터를 짧은 트리거 입력만으로 빠르게 완성할 수 있습니다.

### 1. 기본 텍스트 대치

| 항목 | 설명 |
|---|---|
| **트리거(Trigger)** | 사용자가 입력할 짧은 약어입니다. 예: `;em` |
| **변환 텍스트(Replacement Text)** | 트리거 실행 시 삽입될 최종 텍스트입니다. 예: `my.email@gmail.com` |

실수로 일반 입력 중 트리거가 실행되지 않도록 `;` 같은 접두사를 사용하는 것을 권장합니다.

```text
트리거: ;em
변환 텍스트: my.email@gmail.com
```

### 2. 동적 변수

템플릿 작성 화면의 **[⊕ 요소 삽입]** 기능을 통해 현재 시스템 데이터를 삽입할 수 있습니다.

| 변수 | 설명 | 출력 예시 |
|---|---|---|
| `{{date:yyyy-MM-dd}}` | 현재 날짜 | `2026-07-12` |
| `{{time:HH:mm}}` | 현재 시간 | `14:30` |
| `{{clipboard}}` | 마지막으로 복사한 텍스트 | 클립보드 내용 |
| `${selectedText}` | 현재 선택된 텍스트 | 선택 영역 내용 |
| `{{cursor}}` | 대치 완료 후 최종 커서 위치 | 커서 위치 |

### 3. 대화형 폼 템플릿 예시

```text
안녕하세요 {{input:고객명}}님,

저희 서비스를 이용해 주셔서 감사합니다.
회원님의 고유 식별 코드는
{{input:고객ID|1000&size=120&required=true}} 입니다.

요청하신 사안은
{{datepicker:마감일|yyyy-MM-dd}}까지 검토를 완료하겠습니다.

감사합니다.
{{cursor}}
```

스니펫을 실행하면 LangSwitcher가 비어 있는 입력 항목을 찾아 다이얼로그로 값을 요청한 뒤, 완성된 텍스트를 삽입합니다.

> **팁:** 템플릿 안에서 같은 필드명(예: `고객명`)을 반복해 사용하면 한 번 입력한 값이 모든 위치에 자동으로 동기화됩니다.

---

## 스크린샷

<p align="center">
  <img src="images/screen_menu_v0.9.0.png" width="300" alt="LangSwitcher Menu">
</p>

<p align="center">
  <img src="images/screen_v0.9.0.png" width="700" alt="LangSwitcher Settings">
</p>

---

## 시스템 요구사항

| 항목 | 요구사항 |
|---|---|
| 운영체제 | macOS 13.5 이상 |
| 아키텍처 | Apple Silicon 전용: M1, M2, M3, M4 |

---

## 설치 방법

> [!WARNING]
> LangSwitcher는 무료 오픈소스 프로젝트이며 유료 Apple Developer 계정으로 서명되지 않았습니다. 최초 실행 시 macOS에서 “확인되지 않은 개발자” 경고가 표시될 수 있습니다.

1. [Releases](../../releases) 페이지로 이동합니다.
2. 최신 `LangSwitcher_v0.9.5.zip` 파일을 다운로드합니다.
3. ZIP 압축을 해제합니다.
4. `LangSwitcher.app`을 `/Applications` 폴더로 이동합니다.
5. 앱을 우클릭한 뒤 **열기(Open)** 를 선택합니다.

### macOS에서 앱이 손상되었다고 표시될 때

Terminal에서 아래 명령을 실행하세요.

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LangSwitcher.app
```

---

## 권한 설정

### 1. 손쉬운 사용 권한 — 필수

다음 기능을 사용하려면 손쉬운 사용 권한이 필요합니다.

- 글로벌 단축키 감지
- 한영 오타 변환
- 입력 소스 제어
- 텍스트 대치 및 자동 키보드 입력

설정 위치:

```text
시스템 설정
→ 개인정보 보호 및 보안
→ 손쉬운 사용
→ LangSwitcher 활성화
```

### 2. 자동화 권한 — 선택

**브라우저 탭별 언어 기억** 기능을 사용하려면 자동화 권한이 필요합니다.

지원 브라우저:

- Google Chrome
- Safari
- Microsoft Edge
- Brave

설정 위치:

```text
시스템 설정
→ 개인정보 보호 및 보안
→ 자동화
→ LangSwitcher 하위 브라우저 활성화
```

---

## 업데이트 후 단축키가 동작하지 않을 때

앱 업데이트 후 단축키가 동작하지 않으면 손쉬운 사용 권한에서 LangSwitcher를 제거한 뒤 다시 추가하세요. macOS 권한 캐시 문제를 해결하는 데 도움이 됩니다.

```text
시스템 설정
→ 개인정보 보호 및 보안
→ 손쉬운 사용
→ LangSwitcher 선택
→ 제거 (−)
→ 추가 (+) 후 LangSwitcher 다시 등록
```

---

## 빠른 시작

1. 메뉴바에서 LangSwitcher를 실행합니다.
2. **환경설정(Preferences)** 을 엽니다.
3. 자동 실행, HUD, Hyper Key, 입력 전환 키, 프로필, 텍스트 대치 규칙을 설정합니다.
4. 필요한 경우 창 포커스 관리와 브라우저 탭 기억 기능을 활성화합니다.
5. 사용자 지정 입력 소스 단축키를 등록합니다.
6. 앱별 키보드 규칙을 설정합니다.
7. 앱 실행 단축키를 등록합니다.
8. 텍스트 대치 스니펫과 대화형 템플릿을 작성합니다.

---

## LangSwitcher 후원하기

LangSwitcher는 1인 개발자가 유지하는 무료 오픈소스 프로젝트입니다. 작업 흐름 개선에 도움이 되었다면 지속적인 개발을 후원해 주세요.

### GitHub Sponsors

[👉 GitHub Sponsors로 후원하기](https://github.com/sponsors/peepworks)

### 암호화폐 후원

| 암호화폐 | 지갑 주소 |
|---|---|
| 비트코인 (BTC) | `14eZvFmfSnste92o66DcFq9ns7JqWepu1s` |
| 도지코인 (DOGE) | `D9sGuU6wXVCSnAPTESQsy1QcsxmTHt6VDW` |

---

## 기여

버그 제보, 기능 제안, Pull Request, 번역, 문서 개선 등 다양한 기여를 환영합니다.

---

## 라이선스

이 프로젝트는 [GNU General Public License v3.0](LICENSE) (`GPL-3.0`) 라이선스를 따릅니다.