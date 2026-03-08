<div align="center">
  <img src="Sources/KTXCalendar/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="160" alt="KTX2Cal App Icon" style="border-radius: 36px;"/>
  
  <h1>KTX2Cal</h1>
  
  <p><b>KTX 열차 예약을 iPhone 캘린더에 자동으로 등록하는 iOS 앱</b></p>

  <img src="https://img.shields.io/badge/iOS-16.0+-blue?logo=apple" alt="iOS 16+"/>
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9"/>
  <img src="https://img.shields.io/badge/Xcode-15+-blue?logo=xcode" alt="Xcode 15+"/>
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License"/>
</div>

---

## 📌 개요

**KTX2Cal**은 코레일 KTX 앱의 승차권 정보를 **Share Extension**으로 받아, 출발역·도착역·시간을 자동 파싱하여 iPhone 기본 캘린더에 일정을 즉시 생성하는 iOS 앱입니다.

> 더 이상 KTX 예약 내역을 보면서 직접 캘린더에 입력할 필요가 없습니다.

---

## ✨ 주요 기능

### 🚄 1. KTX 앱 → 캘린더 1-tap 등록
- 코레일 KTX 앱 승차권 화면에서 **공유 버튼 탭 → KTX2Cal 공유** 선택
- Share Extension이 예약 텍스트를 즉시 파싱
- 아래 정보가 캘린더 이벤트로 자동 생성됨:

| 캘린더 필드 | 내용 |
|------------|------|
| **제목** | `[KTX] 서울 → 부산` |
| **시작 시간** | 출발 시각 |
| **종료 시간** | 도착 시각 |
| **위치** | 출발역명 |

### 📅 2. KTX 일정 목록 관리
- 앱을 열면 iPhone 캘린더에 등록된 **모든 KTX 일정 목록** 표시
- 열차 번호, 출발역→도착역, 날짜·시간 한눈에 확인
- 앱 실행 시 **다음 예정 열차로 자동 스크롤**

### 🕹 3. 지난 열차 시각적 구분
- 탑승 시간이 지난 열차는 **흑백 grayscale + 반투명 처리**로 자동 dimming
- 예정된 열차와 지난 열차를 스크롤 없이 즉각 구분 가능

### 🗑 4. 캘린더 일정 삭제
- 목록에서 **× 버튼** → 확인 팝업 → 캘린더에서 일정 삭제
- 실수 방지를 위한 삭제 전 확인 단계 포함

---

## 🛠 아키텍처

```
KTX2Cal
├── Sources/
│   ├── KTXCalendar/              # 메인 앱 타겟
│   │   ├── App/
│   │   │   └── KTXCalendarApp.swift    # 앱 진입점 (@main)
│   │   ├── Views/
│   │   │   └── ContentView.swift       # 메인 UI (SwiftUI)
│   │   └── Assets.xcassets/            # 앱 아이콘 등 리소스
│   └── ShareExtension/           # Share Extension 타겟
│       ├── ShareViewController.swift   # NSExtensionRequestHandling
│       └── ShareTicketView.swift       # 공유 시 확인 UI
│
├── Shared/                        # 양 타겟 공용 코드
│   ├── Models/
│   │   └── KTXTicket.swift        # 승차권 데이터 모델
│   └── Services/
│       ├── KTXParser.swift        # 예약 텍스트 파싱 로직
│       ├── CalendarService.swift  # EventKit 캘린더 CRUD
│       ├── TicketStore.swift      # 이벤트 목록 관리 (ObservableObject)
│       └── OCRService.swift       # (예비) OCR 연동
│
├── Resources/                     # Info.plist, Entitlements
├── project.yml                    # xcodegen 프로젝트 정의
└── sideload.sh                    # 사이드로딩 스크립트
```

### 기술 스택

| 구성 요소 | 기술 |
|----------|------|
| UI 프레임워크 | SwiftUI |
| 캘린더 통합 | EventKit |
| 앱 간 데이터 수신 | App Extension (Share Extension) |
| 프로젝트 생성 | [xcodegen](https://github.com/yonaskolb/XcodeGen) |
| 최소 iOS 버전 | iOS 16.0 |

---

## 🔍 파싱 로직

코레일 KTX 앱이 공유하는 텍스트 형식을 파싱합니다:

```
승차권번호 | 서울 → 부산
KTX 123 | 2025.10.08 09:00 → 11:40
```

- `\r\n` / `\r` 줄바꿈을 `\n`으로 정규화 후 파싱 (CR 문자 방어 처리)
- 출발역/도착역에서 `역` 접미사 자동 제거
- 정규식 기반 시각 추출 (HH:mm 형식)

---

## 📲 설치 방법

### 사전 요구사항
- macOS (Apple Silicon / Intel)
- Xcode 15.0 이상
- [xcodegen](https://github.com/yonaskolb/XcodeGen) 설치

```bash
brew install xcodegen
```

### 빌드 및 설치

```bash
# 1. 저장소 클론
git clone https://github.com/yalkongs/KTX2Cal_i.git
cd KTX2Cal_i

# 2. xcodeproj 생성
xcodegen generate

# 3. Xcode로 열기
open KTXCalendar.xcodeproj
```

4. Xcode에서 iPhone 연결 후 **⌘R** 실행
5. **Signing & Capabilities** → 본인 Apple ID 팀으로 변경

> **Personal Team 사이드로딩**: 무료 Apple 개발자 계정으로도 설치 가능  
> 단, 7일마다 재서명 필요

---

## 📖 사용 방법

```
1. KTX2Cal 앱 최초 실행 → 캘린더 접근 권한 허용

2. 코레일 앱에서 승차권 화면 열기

3. 공유 버튼 탭

4. 공유 메뉴에서 "KTX2Cal 공유" 선택

5. 미리보기 확인 후 "캘린더에 추가" 탭

6. KTX2Cal 앱을 열어 등록 확인
```

---

## ⚙️ 권한

| 권한 | 용도 |
|------|------|
| `NSCalendarsUsageDescription` | KTX 일정 생성 및 조회 |
| `NSCalendarsWriteOnlyAccessUsageDescription` | 일정 추가 전용 접근 |
| App Groups | 메인 앱 ↔ Share Extension 간 데이터 공유 |

---

## 🔮 향후 개발 예정

- [ ] **위젯** — 다음 KTX 탑승 정보를 홈 화면 위젯으로 표시
- [ ] **알림** — 출발 30분/10분 전 자동 푸시 알림
- [ ] **노선도** — 출발역~도착역 간 경로 지도 표시
- [ ] **PDF/이미지 OCR** — 승차권 이미지에서 정보 자동 인식
- [ ] **여러 캘린더 선택** — 등록 대상 캘린더 지정 기능
- [ ] **iCloud 동기화** — 여러 기기 간 KTX 일정 동기화

---

## 📄 라이선스

```
MIT License

Copyright (c) 2025 yalkongs

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction...
```

---

## 🙋 기여 / 문의

Issues와 Pull Requests 환영합니다.  
버그 신고나 기능 제안은 [GitHub Issues](https://github.com/yalkongs/KTX2Cal_i/issues)를 이용해 주세요.
