# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

**Focus Block** — Windows 11 집중/휴식 타이머 앱.
Windows 11 시계 앱의 집중 세션 기능을 대체하며, 세밀한 시간 설정과 명확한 상태 구분을 제공한다.

## 기술 스택

| 영역 | 기술 |
|------|------|
| 런타임 | Electron 39 |
| UI | React 19 + TypeScript |
| 빌드 | electron-vite 5 |
| 패키징 | electron-builder 26 |
| 스타일 | Tailwind CSS v4 |
| 애니메이션 | Framer Motion |
| 아이콘 | Lucide React |

## 디렉터리 구조

```
src/
  main/index.ts         — Electron 메인 프로세스 (타이머 엔진, IPC 핸들러)
  preload/index.ts      — contextBridge로 window.electron, window.api 노출
  preload/index.d.ts    — Window 전역 타입 선언
  renderer/
    index.html          — 렌더러 HTML 진입점
    src/
      main.tsx          — React DOM 렌더링 진입점
      App.tsx           — 루트 컴포넌트
      components/       — UI 컴포넌트
      assets/           — CSS, SVG 리소스

resources/              — 앱 아이콘 등 (asar 언팩 대상)
build/                  — electron-builder 빌드 리소스 (entitlements, 아이콘)
out/                    — electron-vite 빌드 출력 (커밋 제외)
dist/                   — electron-builder 패키징 출력 (커밋 제외)
```

## 아키텍처

### IPC 구조

- **타이머 엔진**: Main 프로세스에서 `setInterval` 기반 1초 단위 tick
- **IPC 채널**: Main ↔ Renderer 간 타이머 상태와 제어 명령 전달
- **contextBridge**: `window.electron` (ElectronAPI), `window.api` (커스텀 API) 노출

### 설정 영구 저장

- `app.getPath('userData')` 경로의 JSON 파일
- 저장 항목: 집중/짧은 휴식/긴 휴식 시간, 긴 휴식 주기, 알림음 on/off
- 앱 시작 시 자동 로드, 변경 시 즉시 저장

## 핵심 기능

### 세션 설정

| 항목 | 범위 | 기본값 |
|------|------|--------|
| 집중 시간 | 1 ~ 120분 | 25분 |
| 짧은 휴식 | 1 ~ 60분 | 5분 |
| 긴 휴식 | 1 ~ 60분 | 15분 |
| 긴 휴식 주기 | 2 ~ 10회 | 4회 |

### 세션 수 입력 방식 (3가지 중 택1)

1. **총 수행 시간 입력** → 세션 횟수, 휴식 횟수, 예상 종료 시각 자동 계산
2. **세션 횟수 입력** → 총 소요 시간, 휴식 횟수, 예상 종료 시각 자동 계산
3. **휴식 횟수 입력** → 세션 횟수, 총 소요 시간, 예상 종료 시각 자동 계산

### 화면 구성

| 화면 | 역할 |
|------|------|
| 설정 화면 | 시간 설정 + 세션 수 입력 방식 선택 + 세션 구성 미리보기 |
| 진행 화면 | 타이머 + 현재 상태 표시 + 세션 맵 + 제어 버튼 |
| 설정 패널 | 기본값 저장, 알림 설정 |

### 타이머 제어

| 기능 | 설명 |
|------|------|
| 시작 | 설정 화면 → 진행 화면 전환 |
| 일시정지 / 재개 | 현재 세션 시간 정지 및 이어서 진행 |
| 다음 세션으로 | 현재 세션 건너뛰고 다음 단계로 즉시 전환 |
| 처음으로 | 전체 세션 초기화 후 설정 화면 복귀 |

### 알림

- 세션 전환 시 알림음 재생 (집중↔휴식)
- 앱 백그라운드 시 Windows 토스트 알림
- 알림음 on/off 설정

## 주요 명령어

```bash
npm run dev          # 개발 모드 (HMR)
npm run build        # 타입 체크 후 전체 빌드
npm run build:win    # Windows 패키징
npm run typecheck    # TypeScript 타입 검사
npm run lint         # ESLint
npm run format       # Prettier 포맷
```

## 설정 파일

| 파일 | 역할 |
|------|------|
| `electron.vite.config.ts` | electron-vite 빌드 설정 (출력: `out/`) |
| `electron-builder.yml` | 패키징 설정 (출력: `dist/`) |
| `tsconfig.json` | TypeScript 루트 설정 |
| `tsconfig.node.json` | Main/Preload 프로세스 TypeScript 설정 |
| `tsconfig.web.json` | Renderer 프로세스 TypeScript 설정 |
| `eslint.config.mjs` | ESLint 설정 |
| `.prettierrc.yaml` | Prettier 설정 |
