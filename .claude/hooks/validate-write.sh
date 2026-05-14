#!/bin/bash
# Write 도구 기존 파일 덮어쓰기 차단 훅
# 근거: CLAUDE.md "기존 파일 무단 덮어쓰기 완전 금지 (Write Overwrite Ban)"
# 근거: AGENTS.md "기존 파일은 오직 편집만 허용 (Edit/Patch Only)"

export LANG=ko_KR.UTF-8
export LC_ALL=ko_KR.UTF-8
export PYTHONUTF8=1
export PYTHONIOENCODING=UTF-8

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | python -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
")

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if [ -f "$FILE_PATH" ]; then
  echo "████████████████████████████████████████████████████████████████" >&2
  echo "★★★ WRITE OVERWRITE 차단 — 기존 파일을 Write로 덮어쓰려 했다 ★★★" >&2
  echo "대상 파일: $FILE_PATH" >&2
  echo "" >&2
  echo "왜 이 도구 호출이 차단됐는가:" >&2
  echo "  Write 도구는 파일 전체를 덮어쓴다. 기존 코드 맥락, 사용자 변경사항," >&2
  echo "  타입 일관성, 연관 파일과의 연결이 모두 파괴된다." >&2
  echo "  CLAUDE.md는 기존 파일에 대한 Write 덮어쓰기를 절대적으로 금지한다." >&2
  echo "  '파일이 손상됐다' 판단은 T4(임의판단) 위반이다." >&2
  echo "  '크기가 크다/토큰이 많다' 이유는 T7(효율고려) 위반이다." >&2
  echo "  어떤 이유로도 기존 파일을 Write로 덮어쓸 수 없다." >&2
  echo "" >&2
  echo "지금 즉시 이 순서대로 다시 시작하라:" >&2
  echo "  STEP 1: 사용자 지시 원문을 한 글자도 바꾸지 않고 그대로 읽는다." >&2
  echo "          왜: 재해석·의도 분석은 T2 위반이다. 원문 그대로만 이행한다." >&2
  echo "  STEP 2: Read 도구로 대상 파일을 직접 열어서 현재 내용을 확인한다." >&2
  echo "          왜: 확인 없이 판단하면 T4 위반이다. 반드시 파일을 먼저 열어라." >&2
  echo "  STEP 3: 왜/어떻게/무엇을/어떤 식으로 4가지 질문에 실제 파일 근거로 답한다." >&2
  echo "          변경 대상을 파일명:라인번호로 정확히 지정한다." >&2
  echo "  STEP 4: Edit 도구로 old_string → new_string 국소 수정한다." >&2
  echo "          old_string이 현재 파일에 실제 존재하는지 Read로 확인 후 Edit 호출." >&2
  echo "          신규 파일이 필요하면 사용자에게 명시적 허락을 먼저 요청한다." >&2
  echo "  STEP 5: 변경 파일과 호출 파일의 앞뒤 흐름이 끊기지 않음을 Read로 확인한다." >&2
  echo "  STEP 6: 확인하지 못한 영역은 완료가 아닌 '미확인'으로 분리해서 보고한다." >&2
  echo "" >&2
  echo "절대 금지 — 이 이유로 Write를 호출하면 다시 차단된다:" >&2
  echo "  ✗ '파일이 손상/오염됐다' 판단 후 전체 재작성 → T4 임의판단 위반" >&2
  echo "  ✗ '크기가 크다/토큰이 많다' 이유로 새 파일로 교체 → T7 효율고려 위반" >&2
  echo "  ✗ 현재 내용을 Read로 확인하지 않고 Write 호출 → T4 임의판단 위반" >&2
  echo "  ✗ Edit old_string 매칭 실패를 이유로 Write로 전환 → T6 미지시 대안 위반" >&2
  echo "████████████████████████████████████████████████████████████████" >&2
  exit 2
fi

exit 0
