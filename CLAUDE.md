# SlipNote - Claude Code Context

## 프로젝트 개요
macOS 메뉴바 기반 빠른 메모 앱 (Swift/SwiftUI)

## 기술 스택
- Swift 5.9, SwiftUI
- macOS 12.0+ (Universal Binary)
- GRDB.swift (SQLite 데이터베이스)
- HotKey (글로벌 단축키)

## 주요 구조
```
SlipNote/
├── Models/          # 데이터 모델 (Slip, Category, Settings)
├── Views/           # SwiftUI 뷰
│   ├── InputWindow/ # 빠른 입력 창
│   ├── Browser/     # 메모 브라우저
│   ├── ViewMode/    # 상세 보기/편집
│   └── Settings/    # 설정 화면
├── Services/        # 데이터베이스, 백업 등
└── Resources/       # 에셋, 로컬라이제이션
```

## 라이선스
- **SlipNote**: Source Available (Proprietary) - 개인 사용 허용, 상업적 사용/재배포 금지
- **의존성**: GRDB.swift (MIT), HotKey (MIT)

## 향후 계획
- App Store 판매 예정

## 연락처
gamzabi@me.com
