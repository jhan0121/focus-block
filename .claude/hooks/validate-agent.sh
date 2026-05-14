#!/bin/bash
# Agent 도구 서브에이전트 호출 제어 훅
# 근거: AGENTS.md 9항 "Claude Code가 이 저장소의 메인 수정 작업자"
# 서브에이전트는 내 작업 완료 후 이중검증 단계에서만 허용

export LANG=ko_KR.UTF-8
export LC_ALL=ko_KR.UTF-8
export PYTHONUTF8=1
export PYTHONIOENCODING=UTF-8

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | python -c "
import sys, json
d = json.load(sys.stdin)
tool_input = d.get('tool_input', {})
print(tool_input.get('subagent_type', tool_input.get('description', '')))
")

# 허용된 서브에이전트 호출 조건을 stdout JSON으로 사용자 확인 요청
python -c "
import json
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': (
            '★★★ AGENT 도구 차단 — 서브에이전트 호출을 시도했다 ★★★\n\n'
            '왜 이 호출이 차단됐는가:\n'
            '  AGENTS.md 규칙: 서브에이전트는 메인 작업 완료 후 이중검증 목적에만 허용된다.\n'
            '  작업 중 서브에이전트 호출은 T6(미지시 방법 탐색) 위반이다.\n'
            '  Grep/Glob/Read로 직접 찾을 수 있는 것에 서브에이전트를 쓰는 것은 금지된 우회다.\n\n'
            '허용 조건 (모두 충족해야 한다):\n'
            '  1. Claude Code가 메인 작업을 이미 완료한 상태\n'
            '  2. 이중검증(코드 리뷰, 불일치 검출) 목적임이 명확한 상태\n'
            '  3. 사용자가 명시적으로 허락한 상태\n\n'
            '절대 금지된 호출 패턴:\n'
            '  ✗ 코드 탐색·파일 검색 → Grep/Glob/Read 도구로 직접 수행\n'
            '  ✗ 문서 조회 → WebFetch 도구로 직접 수행\n'
            '  ✗ 작업 계획·맥락 파악 단계 → 직접 파일을 읽어서 수행\n'
            '  ✗ "빠를 것 같아서" → T7 효율고려 위반\n\n'
            '현재 이 Agent 호출이 이중검증 목적임을 확인할 수 있는가?'
        )
    }
}
print(json.dumps(output, ensure_ascii=False))
"
exit 1
