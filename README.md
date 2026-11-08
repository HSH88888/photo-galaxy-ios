# 🌌 Photo Galaxy for iPhone / iPad (iOS)

아이폰·아이패드의 사진 보관함(`PHPhotoLibrary`)을 **폴더(앨범)별 · 연·월별 · 일별** 방사형 은하계(Balloon Tree + Phyllotaxis Spiral)로 탐색하는 네이티브 iOS 앱입니다.

## ✨ 주요 기능
- **분류 기준 전환**: `폴더별(아이폰 앨범)` · `연·월별` · `일별` 실시간 전환
- **15,000장+ 대형 사진첩 고속 렌더링**: 화면 내 노출 사진 수(`🖼️ 130장` 기본, `20~500장` 설정 가능) 임계값 제어 및 `PHCachingImageManager` 고속 썸네일 로딩
- **원형 길게 누르기 옵션**: 폴더/그룹 원이나 사진을 길게 눌러 **대표 사진 변경(원형 썸네일 선택기)** 및 **표시 이름 변경**
- **아이폰 다이내믹 아일랜드 / 노치 회피 하단 도크 UI**: 모든 조작 버튼을 하단 도크에 배치하고 대형 뷰어 버튼(`📂 원본 열기`, `⭐ 대표사진 지정`, `✕ 닫기`) 제공

---

## 📲 아이폰에 설치하는 방법 (윈도우 PC 기준)

GitHub Actions(macOS 클라우드 서버)가 자동으로 빌드한 **[PhotoGalaxy.ipa](https://github.com/HSH88888/photo-galaxy-ios/raw/main/PhotoGalaxy.ipa)** 파일을 이용해 아래 방법으로 설치할 수 있습니다.

### 방법 1: Sideloadly 사용 (윈도우 PC에서 무료 설치 · 가장 간편)
1. 윈도우 PC에 **iTunes**(마이크로소프트 스토어 버전이 아닌 애플 공식 설치판)와 **iCloud**를 설치합니다.
2. [Sideloadly 공식 사이트](https://sideloadly.io/)에서 **Sideloadly**를 다운로드해 실행합니다.
3. 아이폰을 케이블로 PC에 연결하고 아이폰 화면에서 **'이 컴퓨터 신뢰'**를 누릅니다.
4. Sideloadly의 **IPA 아이콘**에 `PhotoGalaxy.ipa` 파일을 드래그 앤 드롭하고, 본인 **Apple ID(이메일)**를 입력한 뒤 **Start**를 누릅니다.
5. 설치가 완료되면 아이폰 **설정 › 일반 › VPN 및 기기 관리**에서 본인 이메일을 눌러 **'신뢰'**를 탭합니다.
6. iOS 16 이상인 경우 **설정 › 개인정보 보호 및 보안 › 개발자 모드**를 켜고 재부팅하면 바로 실행됩니다!

### 방법 2: Mac / Xcode로 빌드 또는 앱스토어(App Store) 업로드
```bash
brew install xcodegen
xcodegen generate
open PhotoGalaxy.xcodeproj
```
Xcode에서 **Signing & Capabilities** 탭의 **Team**을 본인 Apple 계정에 연결한 뒤 아이폰에 직접 빌드(▶)하거나 **Product › Archive**로 앱스토어(TestFlight)에 업로드할 수 있습니다.
