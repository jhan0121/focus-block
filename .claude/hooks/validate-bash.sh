#!/bin/bash
# Bash 도구 명령 패턴 검사 훅
# 절대 금지(exit 2): 빌드 실행, 출력 자르기, 파일 읽기 우회, sed/awk 줄 추출
# 파괴적 명령(exit 0 + 가이드): rm, git reset/clean/rm, cmd del — 기본 승인 메커니즘에 위임

export LANG=ko_KR.UTF-8
export LC_ALL=ko_KR.UTF-8
export PYTHONUTF8=1
export PYTHONIOENCODING=UTF-8

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | python -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('command', ''))
")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# ─────────────────────────────────────────────────────────
# 1. 빌드 / 개발 서버 실행 차단
# ─────────────────────────────────────────────────────────
if echo "$COMMAND" | grep -qP 'npm\s+run\s+(dev|build|preview|dev:|build:)'; then
  echo "████████████████████████████████████████████████████████████████" >&2
  echo "★★★ BASH 차단 — 금지된 빌드/개발 서버 명령을 실행하려 했다 ★★★" >&2
  echo "감지된 명령: $COMMAND" >&2
  echo "" >&2
  echo "왜 이 명령이 차단됐는가:" >&2
  echo "  AGENTS.md 2항: npm run dev/build/preview 등은 사용자가 명시적으로 허용하기 전까지 실행 금지." >&2
  echo "  에러 확인을 목적으로 빌드·실행하는 것은 정적 분석 의무를 우회하는 행위다." >&2
  echo "  '빌드해서 확인하면 더 빠르다'는 T7(효율고려) 위반이다." >&2
  echo "  '에러를 보려면 실행이 필요하다'는 T4(임의판단) 위반이다." >&2
  echo "  검증은 코드 독해, 타입 정의 확인, 라우트 연결 확인으로만 수행한다." >&2
  echo "" >&2
  echo "[지금 즉시 이 순서대로 다시 시작하라 — CLAUDE.md 작업 수행 순서]" >&2
  echo "  STEP 1: 사용자 지시 원문을 그대로 읽는다. 재해석, 더 나은 방법 추론 금지." >&2
  echo "  STEP 2: 연관 파일을 Read/Grep으로 직접 확인한다." >&2
  echo "          타입·스키마 확인 → 프로젝트의 실제 정적 검증 명령만 허용." >&2
  echo "          라우트 확인 → 실제 라우트 등록 파일 직접 읽기." >&2
  echo "          타입 확인 → 프로젝트의 실제 타입·스키마 파일 직접 읽기." >&2
  echo "  STEP 3: 왜/어떻게/무엇을/어떤 식으로 4가지 질문에 실제 파일 근거로 답한다." >&2
  echo "  STEP 4: Edit 도구로 국소 수정한다. 빌드 실행이 필요하면 사용자 허락을 먼저 받는다." >&2
  echo "  STEP 5: 변경 파일과 호출 파일의 앞뒤 흐름이 끊기지 않음을 Read로 확인한다." >&2
  echo "  STEP 6: 확인 못 한 영역은 완료가 아닌 '미확인'으로 분리해서 보고한다." >&2
  echo "████████████████████████████████████████████████████████████████" >&2
  exit 2
fi

# ─────────────────────────────────────────────────────────
# 2. 출력 자르기 패턴 차단
# ─────────────────────────────────────────────────────────
if echo "$COMMAND" | grep -qP '\|\s*head(\s+-\d+|\s+--lines|\s*$)|\|\s*tail(\s+-\d+|\s+--lines|\s*$)|^\s*head\s+-[0-9]|^\s*tail\s+-[0-9]|2>&1\s*\|\s*head|2>&1\s*\|\s*tail|2>1|>\s*/dev/null'; then
  echo "████████████████████████████████████████████████████████████████" >&2
  echo "★★★ BASH 차단 — 출력 자르기 파이프를 사용하려 했다 ★★★" >&2
  echo "감지된 명령: $COMMAND" >&2
  echo "" >&2
  echo "왜 이 명령이 차단됐는가:" >&2
  echo "  | head -N, | tail -N, 2>&1 | head, 2>1, > /dev/null 전부 금지." >&2
  echo "  출력을 자르면 실제 오류·경고·후반부 데이터가 누락된다." >&2
  echo "  누락된 정보를 보지 못한 채 완료로 보고하면 T5(허위보고) 위반이 된다." >&2
  echo "  '출력이 많아서' 또는 '필요한 부분만 보려고'는 T7(효율고려) 위반이다." >&2
  echo "" >&2
  echo "[지금 즉시 이 순서대로 다시 시작하라 — CLAUDE.md 작업 수행 순서]" >&2
  echo "  STEP 1: 사용자 지시 원문을 그대로 읽는다." >&2
  echo "  STEP 2: 출력이 많으면 전체를 파일로 저장 후 Read 도구로 필요한 범위를 읽는다." >&2
  echo "          특정 패턴 검색이 필요하면 Grep 도구를 직접 쓴다." >&2
  echo "          출력 전체가 필요 없으면 명령 자체를 더 정확하게 작성한다." >&2
  echo "  STEP 3: 실제 확인한 결과를 근거로만 판단한다. 잘린 출력으로 판단하면 T4 위반." >&2
  echo "  STEP 4: Edit 도구로 국소 수정한다. 출력을 자르는 파이프는 어떤 경우에도 추가하지 않는다." >&2
  echo "  STEP 5: 변경 파일과 호출 파일의 흐름이 끊기지 않음을 확인한다." >&2
  echo "  STEP 6: 확인 못 한 영역은 완료가 아닌 '미확인'으로 분리해서 보고한다." >&2
  echo "████████████████████████████████████████████████████████████████" >&2
  exit 2
fi

# ─────────────────────────────────────────────────────────
# 3. rm 파괴적 삭제 — JSON permissionDecision ask (공식 방식)
# ─────────────────────────────────────────────────────────
if echo "$COMMAND" | grep -qP 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|--recursive.*--force|-f.*-r|-rf|-fr|-r\s|-f\s)\s*\S|\brm\s+\S'; then
  python -c "
import json, sys
reason = (
    '[rm 파괴적 삭제 감지] 명령: ' + sys.argv[1] + '\n\n'
    '주의: rm 삭제는 되돌릴 수 없습니다.\n'
    '승인 전 확인:\n'
    '  - 삭제 대상이 다른 파일에서 import/참조 중인가?\n'
    '  - git 추적 파일인가? (git에서도 삭제됨)\n'
    '  - 사용자가 명시적으로 삭제를 지시했는가?\n'
    '대안: 백업만 필요하면 파일명 변경을 사용자에게 제안하라'
)
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': reason
    }
}, ensure_ascii=False))" "$COMMAND"
  exit 0
fi

# ─────────────────────────────────────────────────────────
# 4. git 파괴적 명령 — JSON permissionDecision ask (공식 방식)
# ─────────────────────────────────────────────────────────
if echo "$COMMAND" | grep -qP 'git\s+(reset\s+--hard|clean\s+-[fdx]|rm\s+--cached|rm\s+-r|checkout\s+--\s+\.|restore\s+\.|push\s+--force|push\s+-f\b|reflog\s+delete|branch\s+-[Dd])'; then
  python -c "
import json, sys
reason = (
    '[git 파괴적 명령 감지] 명령: ' + sys.argv[1] + '\n\n'
    '명령별 영향:\n'
    '  git reset --hard    : 로컬 미커밋 변경 전부 삭제 (복구 불가)\n'
    '  git clean -f/-fd/-fx: 추적 안 된 파일/폴더 영구 삭제\n'
    '  git rm --cached     : 스테이징에서 제거 (다음 커밋에 삭제 반영)\n'
    '  git checkout -- .   : 워킹트리 전체 되돌리기\n'
    '  git push --force    : 원격 브랜치 강제 덮어쓰기\n'
    '  git branch -D       : 미병합 브랜치 강제 삭제\n\n'
    '승인 전: git status / git diff로 영향 범위를 먼저 확인했는가?'
)
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': reason
    }
}, ensure_ascii=False))" "$COMMAND"
  exit 0
fi

# ─────────────────────────────────────────────────────────
# 4-A. cmd /c / powershell 파괴적 삭제 — JSON permissionDecision ask (공식 방식)
# ─────────────────────────────────────────────────────────
if echo "$COMMAND" | grep -qiP 'cmd\s+(/c|/C)\s+(del|rd|rmdir|erase)\s|powershell\s+.*Remove-Item'; then
  python -c "
import json, sys
reason = (
    '[Windows 파괴적 삭제 감지] 명령: ' + sys.argv[1] + '\n\n'
    '주의: cmd del / rd / powershell Remove-Item 은 파일·폴더를 영구 삭제합니다.\n'
    '확인:\n'
    '  - 사용자가 명시적으로 지시한 명령인가?\n'
    '  - 삭제 대상이 프로젝트 소스 파일인가?\n'
    '  - git 추적 파일이라면 git rm을 쓰는 것이 git 기록에 남는다'
)
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': reason
    }
}, ensure_ascii=False))" "$COMMAND"
  exit 0
fi

# ─────────────────────────────────────────────────────────
# 4. 파일 조작 우회 패턴 차단 (python -c 로 파일 읽기/쓰기)
# ─────────────────────────────────────────────────────────
if echo "$COMMAND" | grep -qP "python3?\s+-c\s+['\"].*open\s*\(|python3?\s+-c\s+['\"].*\.read\(\)|python3?\s+-c\s+['\"].*\.write\(|python3?\s+-c\s+['\"].*json\.load\s*\(|python3?\s+-c\s+['\"].*json\.dump\s*\("; then
  echo "████████████████████████████████████████████████████████████████" >&2
  echo "★★★ BASH 차단 — Python으로 파일 조작을 우회하려 했다 ★★★" >&2
  echo "감지된 명령: $COMMAND" >&2
  echo "" >&2
  echo "왜 이 명령이 차단됐는가:" >&2
  echo "  python -c로 파일을 직접 읽거나 쓰는 것은 Read/Edit/Write 도구를 우회하는 행위다." >&2
  echo "  '파일이 크다' 이유로 python으로 부분만 읽으면 T7(효율고려) 위반이다." >&2
  echo "  우회 자체가 T6(미지시 방법) 위반이다." >&2
  echo "  Read 도구는 권한 확인·라인 번호·맥락 추적이 가능하며 이것이 유일한 허용 수단이다." >&2
  echo "" >&2
  echo "[지금 즉시 이 순서대로 다시 시작하라 — CLAUDE.md 작업 수행 순서]" >&2
  echo "  STEP 1: 사용자 지시 원문을 그대로 읽는다." >&2
  echo "  STEP 2: Read 도구로 절대 경로와 라인 범위를 지정해서 파일을 읽는다." >&2
  echo "          패턴 검색은 Grep 도구를 직접 쓴다. python -c 우회 금지." >&2
  echo "  STEP 3: 실제 Read/Grep 결과만 판단 근거로 쓴다." >&2
  echo "  STEP 4: 파일 수정은 Edit 도구로 old_string→new_string 국소 수정한다." >&2
  echo "          신규 파일은 Write 도구 + 사용자 명시적 허락 후에만 생성한다." >&2
  echo "  STEP 5: 변경 파일과 호출 파일의 흐름이 끊기지 않음을 Read로 확인한다." >&2
  echo "  STEP 6: 확인 못 한 영역은 완료가 아닌 '미확인'으로 분리해서 보고한다." >&2
  echo "████████████████████████████████████████████████████████████████" >&2
  exit 2
fi

# ─────────────────────────────────────────────────────────
# 5-A. sed/awk 파일 줄 범위 추출 우회 차단
# ─────────────────────────────────────────────────────────
if echo "$COMMAND" | grep -qP "sed\s+(-n\s+)?['\"][0-9]+[,q]|awk\s+'NR[><=]|awk\s+\"NR[><=]"; then
  echo "████████████████████████████████████████████████████████████████" >&2
  echo "★★★ BASH 차단 — sed/awk로 파일 줄 범위 추출을 우회하려 했다 ★★★" >&2
  echo "감지된 명령: $COMMAND" >&2
  echo "" >&2
  echo "왜 이 명령이 차단됐는가:" >&2
  echo "  sed -n '줄번호p', awk 'NR==' 등으로 파일 범위를 추출하는 것은 Read 도구 우회다." >&2
  echo "  'Read 도구가 offset/limit 오류를 낸다'는 핑계로 sed/awk를 쓰는 것은 T6 위반이다." >&2
  echo "  파일이 크면 Read 도구의 limit를 더 작게 줄여서 여러 번 나눠 읽어야 한다." >&2
  echo "" >&2
  echo "[지금 즉시 이 순서대로 다시 시작하라 — CLAUDE.md 작업 수행 순서]" >&2
  echo "  STEP 1: 사용자 지시 원문을 그대로 읽는다." >&2
  echo "  STEP 2: Read 도구의 limit를 더 작게 설정해서 다시 시도한다 (예: limit=20)." >&2
  echo "          파일이 크면 여러 번의 Read 호출로 범위를 나눠서 읽는다." >&2
  echo "          패턴 검색은 Grep 도구만 직접 쓴다. sed/awk 우회 절대 금지." >&2
  echo "  STEP 3: 실제 Read/Grep 결과만 판단 근거로 쓴다." >&2
  echo "  STEP 4: Edit 도구로 국소 수정한다." >&2
  echo "  STEP 5: 변경 파일과 호출 파일의 흐름이 끊기지 않음을 Read로 확인한다." >&2
  echo "  STEP 6: 확인 못 한 영역은 완료가 아닌 '미확인'으로 분리해서 보고한다." >&2
  echo "████████████████████████████████████████████████████████████████" >&2
  exit 2
fi

# ─────────────────────────────────────────────────────────
# 5. 런타임 파일 조작 우회 차단
# ─────────────────────────────────────────────────────────
if echo "$COMMAND" | grep -qP "node\s+-e\s+['\"].*require\s*\(\s*['\"]fs['\"]|node\s+-e\s+['\"].*fs\.(read|write|append|unlink|mkdir|rm)"; then
  echo "████████████████████████████████████████████████████████████████" >&2
  echo "★★★ BASH 차단 — 런타임 파일 API로 파일 조작을 우회하려 했다 ★★★" >&2
  echo "감지된 명령: $COMMAND" >&2
  echo "" >&2
  echo "왜 이 명령이 차단됐는가:" >&2
  echo "  node -e로 fs 모듈을 통해 파일을 조작하는 것은 Read/Edit/Write 도구 우회다." >&2
  echo "  우회 수단 탐색 자체가 T6(미지시 방법) 위반이다." >&2
  echo "" >&2
  echo "[지금 즉시 이 순서대로 다시 시작하라 — CLAUDE.md 작업 수행 순서]" >&2
  echo "  STEP 1: 사용자 지시 원문을 그대로 읽는다." >&2
  echo "  STEP 2: 파일 읽기는 Read 도구, 패턴 검색은 Grep 도구를 직접 쓴다." >&2
  echo "          node -e로 fs 모듈 우회는 도구를 무력화하는 행위로 절대 금지." >&2
  echo "  STEP 3: 실제 Read/Grep 결과만 판단 근거로 쓴다." >&2
  echo "  STEP 4: 파일 수정은 Edit 도구. 파일 생성은 Write 도구 + 사용자 허락." >&2
  echo "  STEP 5: 변경 파일과 호출 파일의 흐름이 끊기지 않음을 Read로 확인한다." >&2
  echo "  STEP 6: 확인 못 한 영역은 완료가 아닌 '미확인'으로 분리해서 보고한다." >&2
  echo "████████████████████████████████████████████████████████████████" >&2
  exit 2
fi

# ─────────────────────────────────────────────────────────
# 6. 훅 파일 우회 시도 차단
# ─────────────────────────────────────────────────────────
if echo "$COMMAND" | grep -qiP 'mv\s+.*validate-thinking|mv\s+.*validate-bash|Rename-Item\s+.*validate-thinking|Rename-Item\s+.*validate-bash|cp\s+.*validate-(thinking|bash).*\.bak|chmod\s+.*validate-thinking|chmod\s+.*validate-bash'; then
  echo "████████████████████████████████████████████████████████████████" >&2
  echo "★★★ BASH 차단 — 훅 파일을 이름 변경/이동으로 비활성화하려 했다 ★★★" >&2
  echo "감지된 명령: $COMMAND" >&2
  echo "" >&2
  echo "왜 이 명령이 차단됐는가:" >&2
  echo "  validate-thinking.sh, validate-bash.sh를 이름 변경·이동·복사하면 훅이 비활성화된다." >&2
  echo "  훅 우회 시도 자체가 T6(미지시 방법 및 우회) 위반이다." >&2
  echo "  훅은 T1~T12 규칙을 강제하는 핵심 장치다. 우회를 시도한다는 것 자체가" >&2
  echo "  규칙을 따르지 않으려는 의도를 드러내는 것이며 즉시 차단된다." >&2
  echo "" >&2
  echo "[지금 즉시 이 순서대로 다시 시작하라 — CLAUDE.md 작업 수행 순서]" >&2
  echo "  STEP 1: 사용자 지시 원문을 그대로 읽는다." >&2
  echo "  STEP 2: thinking에서 영어 단어를 즉시 삭제하고 한국어로 재시작한다." >&2
  echo "          훅 우회(이름 변경, 이동, 복사)는 T6 위반으로 차단된다." >&2
  echo "  STEP 3: 실제 파일을 Read/Grep으로 확인한 결과만 판단 근거로 쓴다." >&2
  echo "  STEP 4: Edit 도구로 국소 수정한다. 훅 파일은 사용자 지시 없이 비활성화 금지." >&2
  echo "  STEP 5: 변경 파일과 호출 파일의 흐름이 끊기지 않음을 Read로 확인한다." >&2
  echo "  STEP 6: 확인 못 한 영역은 완료가 아닌 '미확인'으로 분리해서 보고한다." >&2
  echo "████████████████████████████████████████████████████████████████" >&2
  exit 2
fi

exit 0
