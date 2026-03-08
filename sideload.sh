#!/bin/bash
# KTX캘린더 사이드로딩 스크립트
# 사용법: ./sideload.sh
#
# 필요 사항:
#   - iPhone을 USB로 Mac에 연결
#   - iPhone에서 "이 컴퓨터를 신뢰" 선택
#   - Xcode에 Apple ID 로그인 (Xcode > Settings > Accounts)

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="KTXCalendar"
DEVICE_UDID="00008140-001261E43E93001C"              # xcodebuild -destination 용 (하드웨어 UDID)
DEVICE_CORE_ID="69FB8EEF-CF78-5C20-A5D3-07C35A4DC686"  # xcrun devicectl 용 (CoreDevice UUID)

echo "================================================"
echo "  🚄 KTX캘린더 사이드로딩 시작"
echo "================================================"

# ── Step 1: Team ID 확인 ──────────────────────────────
echo ""
echo "🔑 Team ID 확인 중..."

# 환경변수로 직접 지정된 경우 우선 사용
# 예: TEAM_ID=XXXXXXXXXX ./sideload.sh

# Method 1: keychain에서 추출 (가장 일반적)
if [ -z "$TEAM_ID" ]; then
    TEAM_ID=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -oE '\([A-Z0-9]{10}\)' \
        | tr -d '()' \
        | head -1)
fi

# Method 2: 다운로드된 Provisioning Profile에서 추출
#   (Xcode에서 'Download Manual Profiles' 실행 후 keychain에 미반영된 경우)
if [ -z "$TEAM_ID" ]; then
    PROV_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
    if [ -d "$PROV_DIR" ]; then
        for profile in "$PROV_DIR"/*.mobileprovision; do
            [ -f "$profile" ] || continue
            TID=$(security cms -D -i "$profile" 2>/dev/null \
                | grep -A2 "TeamIdentifier" \
                | grep "<string>" \
                | sed 's/.*<string>\(.*\)<\/string>.*/\1/' \
                | head -1)
            if [ -n "$TID" ]; then
                TEAM_ID="$TID"
                echo "   ℹ️  Provisioning Profile에서 Team ID 발견"
                break
            fi
        done
    fi
fi

if [ -z "$TEAM_ID" ]; then
    echo ""
    echo "❌ Team ID를 찾을 수 없습니다."
    echo ""
    echo "   ▶ 해결 방법 1 - Xcode에서 Download Manual Profiles:"
    echo "   1. open -a Xcode"
    echo "   2. Xcode → Settings (⌘,) → Accounts 탭"
    echo "   3. 계정 선택 후 'Download Manual Profiles' 클릭"
    echo "   4. 이 스크립트 재실행"
    echo ""
    echo "   ▶ 해결 방법 2 - Team ID 직접 지정:"
    echo "   Xcode Settings → Accounts → 팀 이름 옆 Team ID 확인 후:"
    echo "   TEAM_ID=XXXXXXXXXX ./sideload.sh"
    echo ""

    read -p "   지금 Xcode를 열어드릴까요? (y/n): " OPEN_XCODE
    if [ "$OPEN_XCODE" = "y" ] || [ "$OPEN_XCODE" = "Y" ]; then
        open -a Xcode
        echo "   → Apple ID 로그인 후 'Download Manual Profiles' 클릭, 재실행하세요."
    fi
    exit 1
fi

echo "   ✅ Team ID: $TEAM_ID"

# ── Step 2: 기기 확인 ─────────────────────────────────
echo ""
echo "📱 기기 확인 중..."
DEVICE_INFO=$(xcrun devicectl list devices 2>/dev/null | grep "$DEVICE_CORE_ID" || true)
if [ -z "$DEVICE_INFO" ]; then
    echo "❌ iPhone이 연결되지 않았습니다. USB를 연결하고 다시 실행하세요."
    exit 1
fi
echo "   ✅ $(echo "$DEVICE_INFO" | awk '{print $1, $2}')"

# ── Step 3: xcodegen 재생성 ───────────────────────────
echo ""
echo "⚙️  프로젝트 생성 중..."
~/bin/xcodegen generate --spec "$PROJECT_DIR/project.yml" 2>&1 \
    | grep -v "No.*settings found" || true

# ── Step 4: 기기용 빌드 ───────────────────────────────
echo ""
echo "🔨 기기용 빌드 중... (1~3분 소요)"

BUILD_DIR="$PROJECT_DIR/.build/device"
mkdir -p "$BUILD_DIR"

xcodebuild build \
    -project "$PROJECT_DIR/KTXCalendar.xcodeproj" \
    -scheme "$SCHEME" \
    -destination "id=$DEVICE_UDID" \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Apple Development" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    2>&1 | tee /tmp/xcodebuild.log | grep -E "(error:|BUILD FAILED|Build succeeded)" | head -30

echo ""

# ── Step 5: 앱 경로 찾기 ──────────────────────────────
APP_PATH=$(find "$BUILD_DIR" \
    -name "KTXCalendar.app" \
    -not -path "*/Simulator/*" \
    2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ 빌드된 앱 파일을 찾을 수 없습니다. 위 에러를 확인하세요."
    exit 1
fi
echo "✅ 빌드 성공: $APP_PATH"

# ── Step 6: 기기에 설치 ───────────────────────────────
echo ""
echo "📲 iPhone에 설치 중..."

xcrun devicectl device install app \
    --device "$DEVICE_CORE_ID" \
    "$APP_PATH" \
    2>&1 | grep -v "^$" | tail -5

echo ""
echo "================================================"
echo "  ✅ 설치 완료!"
echo ""
echo "  📌 첫 실행 전 iPhone에서:"
echo "  설정 → 일반 → VPN 및 기기 관리"
echo "  → [본인 Apple ID] → '신뢰' 탭"
echo ""
echo "  📌 Share Extension 활성화:"
echo "  앱을 한 번 실행하면 KTX 앱 공유 시트에"
echo "  'KTX캘린더'가 자동으로 나타납니다."
echo "================================================"
