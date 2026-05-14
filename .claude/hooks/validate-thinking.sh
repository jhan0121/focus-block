#!/bin/bash
# PreToolUse 훅: 모든 도구 호출 전 직전 assistant thinking에서 T1~T7 금지 패턴 감지
# 원리: PreToolUse stdin의 transcript_path → JSONL 마지막 assistant entry → thinking 필드 추출 → 패턴 검사
# 위반 시 stderr로 강제 피드백 출력 후 exit 2 (도구 허용 + 피드백 Claude에게 전달 → thinking 수정 후 재시도 유도)
# 확인된 JSONL 구조: entry.message.content[i].type == "thinking", entry.message.content[i].thinking == 텍스트

export LANG=ko_KR.UTF-8
export LC_ALL=ko_KR.UTF-8
export PYTHONUTF8=1
export PYTHONIOENCODING=UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/lib/nekoi-config.sh"

INPUT=$(cat)

TRANSCRIPT_PATH=$(echo "$INPUT" | python -c "import sys, json; d=json.load(sys.stdin); print(d.get('transcript_path',''))")
TOOL_NAME=$(echo "$INPUT" | python -c "import sys, json; d=json.load(sys.stdin); print(d.get('tool_name',''))")

CONFIGURED_SESSIONS_DIR="$(nekoi_config_get paths sessions_dir "")"
WATCHER_PID_FILE="$(nekoi_config_get paths watcher_pid_file "/tmp/nekoi-claude-thinking-watcher.pid")"
WATCHER_VIOLATIONS="$(nekoi_config_get paths violations_dir "${CLAUDE_PROJECT_DIR}/.claude/violations")"
WATCHER_SESSIONS="$(nekoi_sessions_dir "$TRANSCRIPT_PATH" "$CONFIGURED_SESSIONS_DIR")"

if [ -n "$WATCHER_SESSIONS" ] && { [ ! -f "$WATCHER_PID_FILE" ] || ! kill -0 "$(cat "$WATCHER_PID_FILE" 2>/dev/null)" 2>/dev/null; }; then
    python - "$WATCHER_SESSIONS" "$WATCHER_VIOLATIONS" << 'WEOF' &
import sys, os, time, re, json, glob
from datetime import datetime, timezone

sessions_dir = sys.argv[1]
violations_dir = sys.argv[2]
os.makedirs(violations_dir, exist_ok=True)

REALTIME_PATTERNS = [
    ('T1_영어사용', r'I need to|I should|I will|Let me|I think|I believe|I have to|Now I|This is|There is|However|Actually|Therefore|Looking at|The user|The issue|Based on|Converting\s+\w+|substantial|significant\s+refactor|quite\s+large|quite\s+complex|This\s+would\s+be|However,\s+I|Now\s+I\'m|I\'m\s+deciding|I\'m\s+realizing|I\'ll\s+work|We\s+need|We\s+should|The\s+real\s+complication|From\s+an\s+efficiency|Furthermore|Moreover|Nevertheless|might\s+be|probably\s+|likely\s+|it\s+seems|it\s+appears|I\s+assume|I\s+presume|I\s+would\s+guess|most\s+likely\s+cause|can\'t\s+verify|cannot\s+verify|Option\s*[1-9]|option\s*[1-9]|two\s+ways|another\s+way|alternative\s+approach|alternatively|If\s+I|When\s+I|Once\s+I|The\s+file|The\s+function|The\s+pattern|The\s+rule|The\s+hook|Adding\s+the|Removing\s+the|Now\s+adding|Need\s+to\s+add|Should\s+add|Going\s+to|Will\s+add|Must\s+add|Found\s+the|Not\s+found|Missing\s+the|Current\s+state|A\s+new|A\s+simple|A\s+better|Reading\s+the|Writing\s+the|Checking\s+the'),
    ('T2_의도재해석', r'사용자의\s*의도는|사용자가\s*원하는\s*것은|사용자의\s*말을\s*다시|다시\s*해석하면|의도를\s*재해석|what\s*the\s*user\s*wants|what\s*the\s*user\s*means|the\s*user\'?s?\s*intent\s*is|the\s*user\'?s?\s*goal\s*is|re-reading\s*the\s*instruction|on\s*second\s*thought|the\s*user\s*really\s*means|what\s*they\s*really\s*want'),
    ('T3_작업축소', r'우선\s*[가-힣\w]+만|일단\s*[가-힣\w]+부터|핵심만|간단하게|샘플로|just\s*the\s*core|just\s*the\s*basics|start\s*with\s*just|for\s*now\s*just|leave\s*that\s*for\s*later|come\s*back\s*to|too\s*complex\s+to|the\s*scope\s*is\s*large|handle\s*incrementally|do\s*this\s*in\s*phases|상당한\s*작업량|연쇄적으로\s*변경|수천\s*줄|수백\s*줄'),
    ('T4_임의판단', r'아마\s+[가-힣]|보통\s+[가-힣]|[가-힣]+겠지|[가-힣]+인\s*것\s*같다|[가-힣]+로\s*보인다|probably\s+the|likely\s+the|I\s*assume\s+the|I\s*presume|should\s*be\s+correct|looks\s+correct|looks\s+fine|in\s*my\s+experience|most\s+likely\s+cause|this\s+is\s+probably|this\s+is\s+likely'),
    ('T5_허위보고', r'확인\s*없이\s*완료|보고하고\s*수정할까|should\s+be\s+complete|this\s+should\s+be\s+done|this\s+should\s+work|that\s+should\s+fix|this\s+resolves|this\s+fixes'),
    ('T6_미지시방법', r'다른\s*방법으로|더\s*나은\s*방법|이렇게\s*하면\s*어떨까|옵션\s*[1-9]|해결\s*방법은|해결책은|we\s*could\s+also|alternatively\s*,|another\s+option\s+is|a\s+better\s+approach|a\s+simpler\s+approach|rather\s+than\s+that|Option\s*[1-9A-Z]|two\s+ways|two\s+options'),
    ('T7_토큰고려', r'토큰\s*절약|더\s*빠른\s*방법|효율적인\s*대안|to\s+save\s+tokens|to\s+keep\s+it\s+short|response\s+is\s+getting\s+long|token\s+limit|context\s+limit|for\s+brevity'),
    ('T9_세션참조', r'세션\s*요약을\s*보니|서머리에\s*따르면|이전\s*세션|앞서\s*확인한|이미\s*추가된|session\s+summary|previous\s+session|from\s+the\s+summary|as\s+established|as\s+mentioned\s+before|pending\s+tasks'),
    ('T12_재작성선언_훅메타', r'훅이\s*이전\s*응답을\s*차단|이전\s*응답.*차단됐|재작성해야\s*한다|이는\s*T[0-9]+\s*위반이다|이것은\s*T[0-9]+\s*위반|이전\s*응답의\s*내용은.*완료|수정\s*완료\s*보고만\s*간결|hook\s+blocked\s+.*response|previous\s+response\s+was\s+blocked|I\s+need\s+to\s+rewrite|I\s+should\s+rewrite|this\s+is\s+a\s+T[0-9]+\s+violation|this\s+violates\s+T[0-9]+|pattern\s+was\s+detected\s+in.*thinking'),
    ('T6강화_미지시결정검토', r'결정했다|결정하기로\s*했다|필요성을\s*검토|필요한지\s*검토|방향을\s*고려하고\s*있다|고려하고\s*있다|[가-힣\w]+하면\s*된다|[가-힣\w]+\s*목표다|물어보는\s*게\s*맞을|I\s+decided\s+to|I\s+decided\s+that|I\s+should\s+ask\s+the\s+user|need\s+to\s+determine|need\s+to\s+decide|which\s+approach\s+is\s+better|the\s+goal\s+is\s+to'),
    ('T4강화_미지시확인행동', r'이제\s*현재.*확인해야\s*한다|현재\s*[가-힣\w]+를\s*확인해야|[가-힣\w]+부터\s*확인해야\s*한다|먼저\s*[가-힣\w]+확인해야|[가-힣\w]+\s*파악해야\s*한다|이\s*부분도\s*확인이\s*필요|이\s*부분을\s*확인해야|어떤\s*방식이\s*(더\s*)?나을지|어느\s*방식이\s*(더\s*)?나을지\s*결정해야|I\s+need\s+to\s+confirm\s+the\s+current|first\s+I\s+need\s+to\s+check|need\s+to\s+figure\s+out\s+which'),
    ('T10강화_사용자지적원인부정', r'이전\s*실행\s*(때|당시|에서)|이전에\s*실행|이전\s*기동\s*(때|당시)|서버\s*기동\s*당시|그\s*당시에는|그\s*시점에는|나중에\s*변경\s*한|나중에\s*누군가|사용자가\s*나중에|나중에\s*0으로|이미\s*실행\s*중이었|이미\s*실행됐을|이미\s*기동\s*중이었|이전\s*로그일|이전\s*실행\s*로그|이미\s*적용됐|이전\s*설정으로|이전\s*세팅으로|was\s+already\s+running|had\s+already\s+been\s+set|had\s+previously\s+been|previously\s+set\s+to|was\s+set\s+before|user\s+changed\s+it\s+later|changed\s+it\s+after|modified\s+it\s+after'),
    ('T12강화_차단후보고생략', r'차단됐으니\s*(보고를|보고는|작업은|내용은)\s*(생략|건너|제외|축소)|차단됐으므로\s*(보고|작성|응답|내용)\s*(생략|간략|간결|축소)|차단\s*당했으니\s*(보고|응답)\s*(생략|간략)|이전\s*응답.*차단.*생략|보고\s*생략|수행\s*내용.*생략|완료\s*보고.*생략|생략하겠습니다|생략하겠다|보고\s*없이|차단됐으니.*간략|차단됐으니.*간결|간결하게만\s*작성|차단.*이유로.*생략'),
    ('T8강화_작업거부_역지시', r'보증\s*불가|수정\s*지시를\s*(내려라|내려|내리면|요청해야|받아야)|사용자가\s*(원하면|수정을\s*원하면|허락하면|지시하면)\s*(진행|수정|작업|처리)|수정을\s*원하면\s*(진행|알려|말씀해|허락|지시)|지시(를|을)\s*(내려라|내려주|요청합니다|요청해야)|수정\s*여부를\s*(알려달라|말씀해주|알려주세요|확인해야)|원하면\s*(진행하겠|처리하겠|수정하겠|알려달라|말씀해주)|불가능하다는\s*뜻이다|수정\s*지시가\s*(있으면|없으면|필요|있어야)|완전히\s*보증할\s*수\s*없|보증하기\s*어렵|허락을\s*받아야|승인을\s*받아야|지시를\s*내려라|원하시면\s*진행|말씀해\s*주시면\s*진행'),
]

def check_and_record(thinking_text, jsonl_name):
    viols = []
    for rule, pattern in REALTIME_PATTERNS:
        found = re.findall(pattern, thinking_text)
        if found:
            viols.append({'rule': rule, 'matches': found[:3]})
    if not viols:
        return
    ts = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
    out_path = os.path.join(violations_dir, f'realtime_{ts}.md')
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('# 실시간 thinking 위반 기록\n\n')
        f.write(f'감지 시각 (UTC): {datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")}\n')
        f.write(f'총 위반 수: {len(viols)}\n')
        f.write(f'출처 JSONL: {jsonl_name}\n\n---\n\n')
        for v in viols:
            f.write(f'## {v["rule"]}\n\n')
            f.write(f'- 감지된 표현: {v["matches"]}\n\n')
        f.write(f'## thinking 원문 (앞 2000자)\n\n{thinking_text[:2000]}\n')

jsonl_path = None
position = 0

while True:
    time.sleep(0.3)
    pattern = os.path.join(sessions_dir, '**', '*.jsonl')
    files = sorted(glob.glob(pattern, recursive=True), key=os.path.getmtime, reverse=True)
    current = files[0] if files else None
    if current != jsonl_path:
        jsonl_path = current
        position = os.path.getsize(jsonl_path) if jsonl_path and os.path.exists(jsonl_path) else 0
        continue
    if not jsonl_path or not os.path.exists(jsonl_path):
        continue
    current_size = os.path.getsize(jsonl_path)
    if current_size <= position:
        continue
    try:
        with open(jsonl_path, 'r', encoding='utf-8') as f:
            f.seek(position)
            new_content = f.read()
            position = f.tell()
        for raw in new_content.splitlines():
            raw = raw.strip()
            if not raw:
                continue
            try:
                entry = json.loads(raw)
                if entry.get('type') == 'assistant':
                    msg = entry.get('message', {})
                    content_list = msg.get('content', []) if isinstance(msg, dict) else []
                    if isinstance(content_list, list):
                        for c in content_list:
                            if isinstance(c, dict) and c.get('type') == 'thinking':
                                t = c.get('thinking', '')
                                if t:
                                    check_and_record(t, os.path.basename(jsonl_path))
            except Exception:
                continue
    except Exception:
        pass
WEOF
    echo $! > "$WATCHER_PID_FILE"
fi

# transcript_path가 없으면 설정된 세션 디렉터리에서 가장 최근 JSONL을 fallback으로 사용
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  TRANSCRIPT_PATH=$(python - "$WATCHER_SESSIONS" << 'PYEOF'
import glob
import os
import sys

sessions_dir = sys.argv[1]
if not sessions_dir or not os.path.isdir(sessions_dir):
    sys.exit(0)

files = [
    p for p in glob.glob(os.path.join(sessions_dir, '**', '*.jsonl'), recursive=True)
    if os.path.isfile(p)
]
if files:
    print(max(files, key=os.path.getmtime))
PYEOF
)
  if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
  fi
fi

python - "$TRANSCRIPT_PATH" "$TOOL_NAME" << 'PYEOF'
import sys
import json
import re

transcript_path = sys.argv[1]
tool_name = sys.argv[2]

# T1~T7 금지 패턴 정의
# 각 패턴은 (규칙명, 패턴, 위반 설명, 올바른 행동) 튜플
FORBIDDEN_PATTERNS = [
    (
        'T2 - 사용자 의도 재해석',
        r'잠깐\s*사용자의\s*의도는|A를\s*다시\s*생각하면|더\s*효율적인\s*방법은|사용자의\s*말을\s*다시\s*보면|다시\s*해석하면|의도를\s*재해석|wait,?\s*the\s*user\s*actually|actually\s*the\s*user\s*wants|user\s*really\s*means|user\s*actually\s*wants|what\s*the\s*user\s*really|re-reading\s*the\s*instruction|re-interpreting|on\s*second\s*thought|thinking\s*about\s*it\s*more|if\s*I\s*think\s*about\s*what\s*the\s*user|the\s*user\'?s?\s*real\s*intent|the\s*user\'?s?\s*actual\s*goal|the\s*user\'?s?\s*underlying',
        '사용자의 명시적 지시를 다른 의미로 해석하려 했다',
        '사용자 지시를 그대로 문자 그대로 이행해야 한다. 해석하거나 더 나은 방향으로 바꾸는 것 자체가 T2 위반이다'
    ),
    (
        'T3 - 작업 축소',
        r'우선\s*[가-힣\w]+만|일단\s*[가-힣\w]+부터|핵심만|간단하게|샘플로|더\s*간단한|간단한\s*접근|큰\s*파일이라서|우선\s*~만|일단\s*~부터|just\s*the\s*core|just\s*the\s*basics|just\s*the\s*key|start\s*with\s*just|only\s*the\s*essential|only\s*the\s*main|skip\s*the\s*rest|handle\s*the\s*rest\s*later|do\s*this\s*part\s*first|tackle\s*this\s*first|focus\s*on\s*this\s*one|simplify\s*this|keep\s*it\s*simple|minimal\s*implementation|bare\s*minimum|for\s*now\s*just|for\s*now\s*only|leave\s*that\s*for\s*later|address\s*that\s*later|come\s*back\s*to',
        '작업 범위를 임의로 줄이거나 일부만 처리하려 했다',
        '사용자가 지시한 전체 범위를 완전하게 구현해야 한다. 크기, 복잡도, 토큰 수를 이유로 작업을 나누거나 축소하는 것은 T3 위반이다'
    ),
    (
        'T4 - 임의 판단',
        r'아마\s+[가-힣]|보통\s+[가-힣]|[가-힣]+겠지|[가-힣]+이어\s*보인다|[가-힣]+인\s*것\s*같다|이론적으로|보통\s*로그는|일반적으로\s+[가-힣]|[가-힣]+일\s*것이다|probably\s+the|probably\s+this|probably\s+it|probably\s+a|likely\s+the|likely\s+this|likely\s+it|likely\s+a|I\s*assume\s+the|I\s*assume\s+it|I\s*assume\s+this|I\s*presume|I\s*guess|should\s*be\s+fine|must\s*be\s+the|must\s*be\s+a|ought\s*to\s+be|typically\s+this|typically\s+the|in\s*general\s+this|in\s*practice\s+this',
        '확인하지 않은 상태에서 추측으로 판단하려 했다',
        '파일을 실제로 Read 도구로 읽고, 타입을 Grep으로 확인하고, 연관 파일을 모두 검증한 후에만 판단해야 한다. 추측이나 경험 기반 추론은 T4 위반이다'
    ),
    (
        'T5 - 허위 보고',
        r'확인\s*없이\s*완료|보고하고\s*수정할까|수정할까요|done\s+without\s+checking|should\s+be\s+complete|this\s+should\s+be\s+done|task\s+is\s+complete|this\s+is\s+complete|marked\s+as\s+done|should\s+work\s+now|this\s+should\s+work|that\s+should\s+fix|should\s+be\s+fixed|should\s+resolve|this\s+resolves|this\s+fixes',
        '실제 확인 없이 완료를 추론하거나 보고 후 수정을 제안하려 했다',
        '실제 파일을 읽고 실제 흐름을 확인한 후에만 완료를 선언해야 한다. 사용자가 수정을 지시하지 않았으면 수정 제안도 금지이다'
    ),
    (
        'T6 - 미지시 방법 추론',
        r'서브에이전트를\s*사용하여|간단한\s*접근은|더\s*나은\s*방법이\s*있|이렇게\s*하면\s*어떨까|we\s*could\s+also|we\s*could\s+instead|another\s+option\s+is|alternatively\s*,?\s*we|alternatively\s*,?\s*I|instead\s*,?\s*we\s+could|a\s+better\s+approach|a\s+cleaner\s+approach|a\s+simpler\s+approach|a\s+different\s+approach|would\s+it\s+be\s+better|should\s+we\s+instead|what\s+if\s+we|what\s+if\s+I',
        '사용자가 지시하지 않은 방법이나 대안을 스스로 고안하려 했다',
        '사용자가 명시적으로 지시한 방법만 사용해야 한다. 더 나은 방법이 있다고 판단되어도 사용자 지시 없이 다른 방법을 선택하거나 제안하는 것은 T6 위반이다'
    ),
    (
        'T7 - 토큰/효율 고려',
        r'토큰\s*절약|더\s*빠른\s*방법|효율적인\s*대안|크기가\s*크기\s*때문|응답이\s*길어질\s*수|토큰이\s*많이|to\s+save\s+tokens|to\s+keep\s+it\s+short|to\s+be\s+concise|response\s+is\s+getting\s+long|this\s+is\s+getting\s+long|too\s+much\s+to\s+output|truncate\s+the|shorten\s+the\s+response|keep\s+it\s+brief|for\s+brevity|in\s+the\s+interest\s+of\s+brevity|token\s+limit|context\s+limit|to\s+avoid\s+repetition|to\s+save\s+space',
        '토큰 수, 응답 크기, 처리 효율을 고려하여 작업을 변형하려 했다',
        '작업의 크기와 토큰 수는 고려 대상이 아니다. 사용자가 요구한 전체 작업을 완전하게 수행해야 한다. 토큰 절약을 이유로 작업을 줄이거나 응답을 압축하는 것은 T7 위반이다'
    ),
    (
        'T8 - 보고→수정 전환',
        r'요약해야\s*한다|수정을\s*시작|파일\s*구조를\s*먼저\s*확인|실제\s*파일\s*구조를\s*먼저|정리해야\s*한다|need\s+to\s+summarize|let\s+me\s+summarize|need\s+to\s+understand\s+the\s+structure|let\s+me\s+check\s+the\s+structure|first\s+understand\s+the\s+structure|before\s+reporting\s+I\s+need|before\s+I\s+can\s+report',
        '사용자가 보고를 요구했는데 수정 또는 파일 확인 작업으로 전환하려 했다',
        '사용자가 보고를 지시했으면 보고만 수행한다. 수정 작업으로 전환하거나 파일 구조 파악으로 넘어가지 않는다'
    ),
    (
        'T9 - 서머리/요약 의존',
        r'세션\s*요약을\s*보니|서머리에\s*따르면|이전\s*세션\s*요약|세션\s*요약에서|from\s+the\s+session\s+summary|according\s+to\s+the\s+summary|the\s+summary\s+says|summary\s+indicates|based\s+on\s+the\s+context\s+summary|from\s+the\s+previous\s+context|from\s+prior\s+context|as\s+established\s+in\s+the\s+summary',
        '서머리나 요약에 의존해서 실제 파일 없이 판단하려 했다',
        '실제 JSONL 또는 파일을 직접 Read/Grep으로 읽은 후에만 판단한다'
    ),
    (
        'T7 강화 - 출력 자르기',
        r'\[:[0-9]+\]|너무\s*많다|일부만\s*처리|출력이\s*너무|한번에\s*출력하면|too\s+much\s+to\s+include|too\s+long\s+to\s+show|omit\s+the\s+rest|skip\s+the\s+rest|only\s+show\s+part|only\s+include\s+part|truncate\s+here|cut\s+it\s+short',
        '출력 크기를 이유로 자르거나 일부만 처리하려 했다',
        '사용자가 전체 출력을 요구했으면 자르거나 제한하지 않고 전체를 그대로 출력한다'
    ),
    (
        'T1 강화 - 영어 문장',
        r'I need to|I should|I will|I must|I can|Let me|I think|I believe|I want|I have|I am|I\'m|I\'ve|I\'d|I\'ll|Now I|This is|There is|There are|It seems|It looks|It appears|However|Alternatively|Instead|Actually|Since|Because|Although|Therefore|Looking at|Checking|Verifying|Analyzing|Considering|Reviewing|The user|The issue|The problem|The solution|The approach|The best|The most|The right|The correct|Wait, I|Wait I|Without seeing|Without reading|Without checking|I appreciate|I notice|I find|I realize|I understand|I see that|Could you|Would you|In this case|In fact|In particular|In summary|In general|To be clear|To summarize|To confirm|Parsing the|Writing the|Reading the|Completing the|Looking for|The disconnect|The key|The point|The reason|It would be|It could be|It should be|It looks like|It seems like|Would be|Should be|Could be|I\'m ready|Once I|I also need|Then there|I need to expand|I should add|I\'ve already|I already|I previously|I had|I was|I noticed|I checked|I verified|I confirmed|I completed|I added|I updated|Now let|Now I\'ll|So I|So the|OK so|Alright|Right, so|Let\'s|Based on|According to',
        'thinking에서 영어 단어/문장을 사용했다',
        'thinking은 반드시 한국어로만 작성한다. 영어 단어가 하나라도 등장하면 즉시 한국어로 재시작한다'
    ),
    (
        'T2 강화 - 사용자 의도 추론/재해석',
        r'사용자가\s*원하는\s*것은|사용자의\s*요청은|사용자가\s*의미하는|이게\s*아니오라는\s*뜻|이건\s*아니라는\s*뜻|이는\s*[가-힣]+라는\s*의미|사용자의\s*핵심\s*의도|사용자가\s*진짜\s*원하는|사용자가\s*말하는\s*핵심|사용자의\s*진의|사용자의\s*진짜|사용자가\s*화내는\s*이유|사용자가\s*지적하는\s*것|사용자의\s*지적\s*요약|사용자의\s*메시지를\s*다시|사용자의\s*답변이\s*모호|사용자가\s*말한\s*것을\s*다시|what\s*the\s*user\s*wants|what\s*the\s*user\s*means|what\s*the\s*user\s*is\s*asking|the\s*user\s*is\s*asking\s*for|the\s*user\s*wants\s*me\s*to|the\s*user\s*needs\s*me\s*to|the\s*user\'?s?\s*request\s*is|the\s*user\'?s?\s*intent\s*is|the\s*user\'?s?\s*goal\s*is|the\s*user\'?s?\s*point\s*is|reading\s*between\s*the\s*lines|what\s*they\s*really\s*want|what\s*they\s*actually\s*mean|they\s*probably\s*want|they\s*likely\s*mean',
        '사용자의 지시를 분석하거나 의미를 추론하려 했다',
        '사용자 지시 원문을 그대로 읽고 그대로 이행한다. 의미 해석, 의도 추론, 진의 파악은 모두 T2 위반이다'
    ),
    (
        'T3 강화 - 축소/복잡도 회피',
        r'너무\s*복잡|복잡해질\s*수|과할\s*수\s*있|과도할\s*수|너무\s*길|길어질\s*수|컨텍스트가\s*너무|너무\s*많아|실용적이지\s*않|현실적으로|단계적으로|먼저\s*[가-힣]+만\s*처리|더\s*단순한|단순화|최소한|최소로|필요한\s*것만|핵심\s*부분만|중요한\s*것만|기본적인\s*것만|too\s*complex\s+to|too\s*large\s+to|too\s*much\s+to|too\s*difficult\s+to|this\s+is\s+complex|this\s+is\s+large|this\s+is\s+extensive|the\s+scope\s+is\s+large|scope\s+is\s+too|would\s+take\s+too\s+long|takes\s+too\s+long|need\s+to\s+break\s+this\s+down|break\s+it\s+into\s+steps|handle\s+incrementally|do\s+this\s+in\s+phases|tackle\s+this\s+in\s+parts|not\s+practical\s+to|impractical\s+to|not\s+realistic\s+to|realistically\s+speaking',
        '작업 복잡도나 크기를 이유로 범위를 줄이려 했다',
        '사용자가 지시한 전체 범위를 그대로 수행한다. 복잡도, 크기, 효율을 이유로 축소하는 것은 T3 위반이다'
    ),
    (
        'T4 강화 - 추측/가능성 판단',
        r'[가-힣]+일\s*가능성|[가-힣]+일\s*수\s*있|[가-힣]+로\s*보인다|[가-힣]+인\s*듯|[가-힣]+인\s*듯하다|[가-힣]+처럼\s*보인다|[가-힣]+같다|[가-힣]+않을까|[가-힣]+할\s*것\s*같다|[가-힣]+할\s*듯|추측하면|추측컨대|경험상|일반적\s*경우|보통의\s*경우|[가-힣]+때문일\s*수|[가-힣]+원인일\s*수|[가-힣]+문제일\s*수|it\s*seems\s+like|it\s*looks\s+like|it\s*appears\s+that|appears\s+to\s+be|seems\s+to\s+be|seems\s+likely|looks\s+correct|looks\s+fine|looks\s+good|should\s*be\s+correct|this\s*should\s+be|that\s*should\s+be|this\s*must\s+be|that\s*must\s+be|this\s*would\s+be|I\s*would\s+guess|I\s*would\s+assume|I\s*would\s+expect|in\s*my\s+experience|from\s+experience|experience\s+tells',
        '확인하지 않은 것을 추측이나 가능성으로 판단하려 했다',
        'Read/Grep으로 실제 파일을 확인한 후에만 판단한다. "~일 수 있다", "~로 보인다"는 모두 T4 위반이다'
    ),
    (
        'T6 강화 - 대안/우회 탐색',
        r'다른\s*방법으로|또\s*다른\s*방법|대안적으로|대안으로|대신에|다른\s*접근|또는\s*다른|아니면\s*[가-힣]+방법|더\s*나은\s*방법|더\s*효과적인\s*방법|더\s*강력한\s*방법|더\s*적절한\s*방법|더\s*좋은\s*방법|차선책|우회\s*방법|우회해서|별도\s*파일\s*없이|파일\s*없이|인라인으로|직접\s*넣|다른\s*방식으로|다른\s*경로로|다른\s*전략|다른\s*옵션|옵션으로는|alternatively\s*[,.]|an\s*alternative\s+is|as\s+an\s+alternative|instead\s+of\s+that|instead\s*,?\s*we\s+could|a\s+workaround\s+is|we\s+could\s+work\s+around|another\s+way\s+to|a\s+different\s+way|a\s+better\s+way|a\s+cleaner\s+way|a\s+simpler\s+way|a\s+more\s+efficient\s+way|rather\s+than\s+that|rather\s+than\s+doing|bypass\s+this|work\s+around\s+this',
        '사용자가 지시하지 않은 대안이나 우회 방법을 스스로 탐색하려 했다',
        '사용자가 명시한 방법만 사용한다. 대안 탐색, 우회 방법 고려 자체가 T6 위반이다'
    ),
    (
        'T6 강화 - 옵션/선택지 제시',
        r'옵션\s*[1-9일이삼]|옵션\s*[A-Z]|방법\s*[1-9일이삼]|해결\s*방법\s*[1-9]|방안\s*[1-9]|해결책\s*[1-9]|[1-9]\.\s*[가-힣]+방법|[1-9]\.\s*[가-힣]+방안|선택지[는은이가]|두\s*가지\s*방법|세\s*가지\s*방법|[1-9]가지\s*방법|첫\s*번째\s*방법|두\s*번째\s*방법|세\s*번째\s*방법|방법\s*A|방법\s*B|방안\s*A|방안\s*B|해결\s*방안:\s*[1-9]|옵션\s*[1-9]\s*[가-힣]|옵션\s*A\s*[가-힣]|옵션\s*B\s*[가-힣]',
        '사용자가 지시하지 않은 선택지를 옵션/방법/방안 번호 형태로 나열하려 했다',
        '사용자 지시 원문에 선택 요구가 없으면 옵션을 나열하지 않는다. 직접 파일을 확인하고 지시된 작업을 수행한다. 옵션 나열 자체가 T6 위반이다'
    ),
    (
        'T6 강화 - 미지시 해결책 제시',
        r'해결\s*방법은|해결책은|해결\s*방안은|해결\s*방향은|해결하려면|해결하기\s*위해|수정\s*방법은|수정\s*방향은|수정\s*방안은|개선\s*방법은|수정\s*접근|해결\s*접근|문제\s*해결\s*방향|순환\s*임포트\s*해결|임포트\s*해결|순환\s*해결',
        '사용자가 해결 방법을 지시하지 않았는데 스스로 해결책을 제시하려 했다',
        '해결 방법은 사용자가 명시적으로 지시할 때만 선택한다. 해결책 스스로 제시는 T6 위반이다. 대신 실제 파일을 Read로 확인한 현재 상태를 그대로 보고한다'
    ),
    (
        'T5 강화 - 지시 미이행 후 완료 선언',
        r'DB\s*기능.*비활성화.*완료|비활성화.*구현.*완료|활성화.*비활성화.*구현|임포트.*중앙화.*완료|순환.*임포트.*해결.*완료|기능.*비활성화.*했다|비활성화.*처리했다|중앙화.*완료됐다|이제\s*[가-힣]+이\s*(완료|됐|해결)',
        '사용자가 지시한 기능(DB 비활성화/임포트 중앙화 등)을 실제로 구현하지 않고 완료로 선언하려 했다',
        '지시한 기능이 실제 파일에서 구현됐는지 Read로 확인한 후에만 완료를 선언한다. 구현 없는 완료 선언은 T5 허위보고 위반이다'
    ),
    (
        'T6 강화 - 방법 선택 되묻기',
        r'[가-힣\w]+[을를]\s*먼저\s*확인할까요|[가-힣\w]+[을를]\s*직접\s*대조할까요|[가-힣\w]+[을를]\s*확인할까요.*아니면|아니면\s*[가-힣\w]+[을를]\s*(먼저|직접|기준으로)|[가-힣\w]+할까요.*아니면\s*[가-힣\w]+할까요|어떤\s*(방법|방식|순서)[으로를]\s*(진행|시작|확인)할까요|먼저\s*[가-힣\w]+할까요|[가-힣\w]+부터\s*할까요|어떻게\s*(진행|확인|대조)할까요',
        '사용자에게 작업 방법이나 순서를 되물으며 시작을 회피하려 했다',
        '작업 방법은 파일을 직접 확인하고 스스로 결정한다. 방법 선택을 사용자에게 묻는 것은 T6 위반이다'
    ),
    (
        'T6 강화 - 작업 거부 우회',
        r'거부됐으니|거부당했으니|차단됐으니|막혔으니|실패했으니|안\s*됐으니|할\s*수\s*없으니|불가능하니|허락이\s*없으니|승인이\s*없으니|다른\s*방법을\s*찾|우회\s*방법을|어떻게\s*하면',
        '도구 거부/차단 후 우회 방법을 스스로 탐색하려 했다',
        '도구가 거부되면 사용자에게 상황을 보고하고 지시를 기다린다. 스스로 우회 방법을 찾는 것은 T6 위반이다'
    ),
    (
        'T7 강화 - 컨텍스트/반복 우려',
        r'컨텍스트가\s*커|컨텍스트\s*낭비|반복적으로\s*전달|매번\s*전달하면|중복될\s*수|이미\s*로드되어|이미\s*포함되어|이미\s*적용되어|불필요한\s*반복|중복\s*적용|중복이\s*될|과부하|오버헤드|context\s*is\s+getting\s+large|context\s*window|to\s+avoid\s+repetition|to\s+avoid\s+redundancy|already\s+loaded|already\s+included|already\s+applied|no\s+need\s+to\s+repeat|overhead\s+of|unnecessary\s+overhead|redundant\s+to',
        '컨텍스트 크기나 반복을 이유로 작업을 줄이려 했다',
        '컨텍스트 크기는 고려 대상이 아니다. 사용자가 지시한 것을 그대로 수행한다'
    ),
    (
        'T4 강화 - 유력 원인 추측',
        r'[가-힣]+일\s*가능성이\s*높|가장\s*유력한|유력한\s*후보|원인인\s*것\s*같|원인으로\s*보인|이\s*원인인\s*듯|[가-힣]+일\s*것으로\s*보인|[가-힣]+인\s*것으로\s*보인다|[가-힣]+로\s*보이는|[가-힣]+라고\s*볼\s*수\s*있|[가-힣]+발생할\s*수\s*있|[가-힣]+할\s*가능성이|most\s+likely\s+cause|most\s+likely\s+the|the\s+most\s+probable|the\s+root\s+cause\s+is\s+probably|the\s+root\s+cause\s+is\s+likely|this\s+is\s+probably\s+caused\s+by|this\s+is\s+likely\s+caused\s+by|the\s+issue\s+is\s+probably|the\s+bug\s+is\s+probably|the\s+error\s+is\s+probably|the\s+problem\s+is\s+probably|could\s+be\s+the\s+cause|might\s+be\s+the\s+cause|appears\s+to\s+be\s+the\s+cause',
        '확인하지 않은 원인을 "유력", "가능성 높음"으로 추측했다',
        'DB/파일을 실제로 Read 도구로 확인한 후에만 원인을 진술한다. "~일 가능성이 높다", "가장 유력한"은 T4 위반이다'
    ),
    (
        'T4 강화 - 확인 불가 포기',
        r'확인할\s*수\s*없으니|직접\s*확인할\s*수\s*없|실행\s*금지이므로\s*확인|확인\s*불가|알\s*수\s*없어서|파악하기\s*어렵|파악\s*불가|실행\s*없이는\s*알\s*수|로그를\s*확인할\s*수\s*없|직접\s*볼\s*수\s*없|can\'?t\s+verify\s+without|cannot\s+verify\s+without|can\'?t\s+check\s+without|cannot\s+check\s+without|unable\s+to\s+verify|unable\s+to\s+confirm|no\s+way\s+to\s+verify|no\s+way\s+to\s+check|impossible\s+to\s+verify|without\s+running|without\s+executing|without\s+the\s+logs|can\'?t\s+know\s+without\s+running|not\s+possible\s+to\s+check',
        '"확인 불가"를 이유로 작업을 포기하거나 추측으로 대체하려 했다',
        '확인이 어렵다면 사용자에게 확인 방법을 직접 요청한다. "확인 불가"는 T5 허위보고 또는 T6 작업 거부 우회 위반이다'
    ),
    (
        'T4 강화 - 파일 읽고도 ls 추가검증 회피',
        r'실제로\s*(ls|목록|디렉토리)\s*(를|을|로|으로)?\s*(확인|조회|검색)해야|파일이\s*(있는지|존재하는지)\s*(ls|dir|직접)\s*(확인|검증)해야|(코드|파이썬|py)\s*(를|을)?\s*(봤(음에도|는데도|으면서도)|읽었(음에도|는데도))\s*(불구하고)?\s*(ls|목록|파일\s*목록|디렉토리)|(basis|raw|json)\s*(파일|데이터).*없(다|음).*다시.*확인|실제\s*(경로|디렉토리)\s*(를|을)?\s*(직접|다시)\s*(확인|조회)\s*(해야|해달)|(결론을\s*내리기|판단하기)\s*(전에|위해)\s*(ls|목록|파일\s*목록)|(없다고\s*단정|없다고\s*결론)\s*(짓기\s*)?(전에|전)\s*(ls|실제|직접)',
        '파일을 실제로 읽어서 결론이 났음에도 ls/목록 확인을 핑계로 결론 선언을 회피하려 했다',
        '파일을 Read로 읽어서 확인된 사실은 즉시 결론으로 선언한다. 이미 확인된 사실에 대해 ls/목록 추가 확인을 요구하는 것은 T4 확인 불가 포기 위반이다'
    ),
    (
        'T2 강화 - 사용자 감정 분석',
        r'사용자의\s*분노|사용자가\s*화가\s*났|사용자가\s*집중하는|사용자가\s*지적한\s*문제는|사용자의\s*최신\s*메시지를\s*보니|사용자가\s*지적한\s*것은|정당하니|사용자의\s*감정|사용자가\s*원하는\s*방향|사용자\s*의도\s*파악|사용자\s*요구\s*정리|the\s*user\s*is\s*angry|the\s*user\s*is\s*frustrated|the\s*user\s*is\s*upset|the\s*user\s*seems\s*angry|the\s*user\s*seems\s*frustrated|user\'?s?\s*frustration|user\'?s?\s*anger|user\'?s?\s*emotion|user\'?s?\s*feeling|the\s*user\s*is\s*emphasizing|the\s*user\s*is\s*pointing\s*out|the\s*user\s*is\s*complaining\s*about',
        '사용자의 감정이나 의도를 분석하거나 정리하려 했다',
        '사용자 지시 원문만 그대로 읽고 이행한다. 감정 분석, 의도 정리, 핵심 파악은 모두 T2 위반이다'
    ),
    (
        'T3 강화 - 우선순위 조작',
        r'우선적으로\s*해결|먼저\s*[가-힣]+부터\s*해결|가장\s*긴급|가장\s*심각|더\s*중요한\s*문제|더\s*중요한\s*것은|긴급해\s*보인|시급해\s*보인|나머지는\s*나중|이건\s*나중에|다음으로|다음에\s*처리|이후에\s*처리|이후에\s*확인|이후에\s*수정|most\s*urgent|most\s*critical|most\s*important\s*issue|higher\s*priority|top\s*priority|address\s*this\s*first|deal\s*with\s*this\s*first|the\s*rest\s*can\s*wait|leave\s*the\s*rest|handle\s*the\s*others\s*later|defer\s*the\s*rest|postpone\s*the\s*rest|put\s*aside\s*the\s*rest',
        '작업 우선순위를 임의로 정하거나 일부를 나중으로 미루려 했다',
        '사용자가 지시한 모든 작업을 나누지 않고 전체 범위로 수행한다. 우선순위 설정 자체가 T3 위반이다'
    ),
    (
        'T3 강화 - 작업 방치 및 되돌리기',
        r'원래대로\s*되돌린다|이전\s*상태로\s*되돌|되돌리겠다|방치하겠다|그대로\s*두겠다|존재\s*의미가\s*없으니|차단하겠다는\s*선언|회피하겠다|무시하겠다|이미\s*수정한\s*것을\s*되돌|revert\s*this|roll\s*this\s*back|undo\s*this|leave\s*it\s*as\s*is|leave\s*this\s*alone|ignore\s*this\s*for\s*now|abandon\s*this|discard\s*this\s*change|put\s*it\s*back\s*to',
        '지시된 작업을 방치하거나 되돌리거나 회피하려 했다',
        '지시된 작업을 끝까지 완전하게 수행한다. 방치, 되돌리기, 회피는 T3 위반이다'
    ),
    (
        'T3 강화 - 추가 지시 대기 회피',
        r'지시를\s*기다린다|명시해\s*주면\s*바로|알려주시면\s*바로|지시해\s*달라|어떻게\s*변경할지\s*명시|전체\s*범위를\s*지시|추가\s*지시를\s*기다|사용자가\s*지시하면|사용자가\s*확인해\s*주면|말씀해\s*주시면\s*바로|지시해\s*주시면\s*바로|waiting\s*for\s*instructions|wait\s*for\s*user\s*to\s*specify|please\s*specify\s*what|let\s*me\s*know\s*what\s*you\s*want|tell\s*me\s*what\s*to\s*do|once\s*you\s*confirm|once\s*you\s*clarify|if\s*you\s*want\s*me\s*to|if\s*you\'?d\s*like\s*me\s*to|when\s*you\s*specify|I\'?ll\s*wait\s*for|pending\s*your\s*confirmation|pending\s*further\s*instructions',
        '작업을 직접 수행하지 않고 추가 지시를 기다리려 했다',
        '지시받은 내용으로 직접 수행한다. 추가 지시를 기다리는 것은 T3 작업 축소/회피 위반이다'
    ),
    (
        'T4 강화 - 서버 로그/런타임 출력 요청',
        r'서버\s*로그.*확인해\s*달라|콘솔\s*로그.*보여\s*달라|에러\s*메시지.*보여\s*달라|로그에서.*확인해\s*달라|런타임\s*출력.*확인|cause\s*필드.*있다|스택\s*트레이스.*보여|서버를\s*재시작.*로그|서버\s*로그.*필요|로그\s*전체.*보여|서버\s*탓|서비스\s*연결\s*문제|please\s*share\s*the\s*logs|can\s*you\s*share\s*the\s*logs|show\s*me\s*the\s*logs|provide\s*the\s*error\s*message|server\s*is\s*the\s*issue|it\'?s\s*a\s*server\s*issue|connection\s*issue\s*with|network\s*issue\s*with',
        '실제 파일 확인 없이 서버 로그나 런타임 출력을 사용자에게 요청하거나 서버 탓으로 돌리려 했다',
        'Read/Grep으로 실제 파일을 확인한 후에만 판단한다. 로그 요청과 서버 탓은 T4 확인 불가 포기 위반이다'
    ),
    (
        'T9 강화 - 이전 세션/요약 참조',
        r'이전\s*대화\s*요약|세션\s*요약의|Pending\s*Tasks|이전\s*세션의|세션\s*요약\s*참조|요약에서\s*확인|요약에\s*따라|이전\s*세션에서|이전\s*대화에서|이전\s*세션\s*기준|요약\s*내용에|세션\s*요약\s*기준|세션\s*요약을\s*기반|세션\s*내역|대화\s*내역에\s*따라|이전\s*대화에\s*따라|이전\s*작업\s*내역',
        '세션 요약이나 이전 대화 요약에 의존하여 판단하려 했다',
        '세션 요약은 배경 정보일 뿐이다. 현재 실제 파일을 Read/Grep으로 직접 확인한 후에만 판단한다. 요약 의존은 T9 위반이다'
    ),
    (
        'T2 강화 - 화난 이유/진의 분석',
        r'사용자가\s*화난\s*이유|사용자의\s*진정한\s*의도|사용자의\s*진짜\s*의도|진정한\s*의도|진짜\s*이유|화난\s*이유|분노의\s*이유|사용자가\s*분노한\s*이유|화가\s*난\s*이유|화가\s*난\s*핵심|사용자의\s*핵심\s*불만|핵심\s*불만은|진의를\s*파악|진의\s*파악|사용자\s*심리|사용자의\s*불만\s*핵심|why\s*the\s*user\s*is\s*angry|why\s*the\s*user\s*is\s*upset|the\s*user\'?s?\s*frustration\s*comes\s*from|the\s*user\'?s?\s*real\s*complaint|the\s*user\'?s?\s*underlying\s*issue|what\s*the\s*user\s*is\s*really\s*upset\s*about|the\s*root\s*of\s*the\s*user\'?s?\s*anger',
        '사용자의 화난 이유나 진정한 의도를 분석하려 했다',
        '사용자의 지시 원문만 그대로 읽고 이행한다. 감정 원인 분석, 진의 파악은 모두 T2 위반이다'
    ),
    (
        'T2 강화 - 지시 의도 재해석',
        r'의도였을\s*수\s*있다|해석했다|라고\s*해석|의미일\s*수\s*있다|뜻일\s*수\s*있다|[가-힣]+라는\s*의도로|[가-힣]+라는\s*뜻으로|[가-힣]+를\s*요구하는\s*것|[가-힣]+를\s*원하는\s*것|[가-힣]+를\s*말하는\s*것|[가-힣]+을\s*지적하는\s*것|[가-힣]+라는\s*신호|수정을\s*요청하는\s*게\s*아니라|확인하라는\s*의도|보여준\s*것은.*의미|선택해서\s*보여준\s*것은|this\s*could\s*mean|this\s*might\s*mean|this\s*could\s*indicate|this\s*might\s*indicate|this\s*implies\s*that|this\s*suggests\s*that|interpreting\s*this\s*as|I\s*interpret\s*this\s*as|I\s*read\s*this\s*as|reading\s*this\s*as|this\s*is\s*likely\s*asking\s*for|what\s*this\s*really\s*means\s*is',
        '사용자의 지시가 실제로 무엇을 의미하는지 해석하려 했다',
        '사용자 지시 원문을 그대로 읽고 그대로 이행한다. "~라는 의도였을 수 있다" 해석 자체가 T2 위반이다'
    ),
    (
        'T4 강화 - 아닐 가능성 추측',
        r'아닐\s*가능성|아닐\s*수\s*있|아닐\s*수도|아닐\s*것|아닐\s*것\s*같|아닐\s*듯|문제가\s*아닐|원인이\s*아닐|에러가\s*아닐|버그가\s*아닐|이슈가\s*아닐|틀릴\s*수\s*있|틀릴\s*가능성|잘못됐을\s*수|다를\s*수\s*있|다를\s*가능성|might\s*not\s*be\s*the|may\s*not\s*be\s*the|could\s*not\s*be\s*the|might\s*not\s*be\s*a|may\s*not\s*be\s*a|not\s*necessarily\s*the|not\s*necessarily\s*a|could\s*be\s*wrong|might\s*be\s*wrong|possibly\s*wrong|I\s*could\s*be\s*wrong|this\s*might\s*not',
        '"~가 아닐 가능성"으로 추측하려 했다',
        '가능성 추론 없이 실제 파일을 직접 확인한다. "~아닐 수 있다"도 T4 위반이다'
    ),
    (
        'T1 강화 - 영어 문장2',
        r'Now I need|I need to check|I should|I will|I must|I can see|I can|Let me|I think|I believe|I want|I have to|I am going|I\'m going|I\'ve|I\'d|I\'ll|Now I|This is|There is|There are|It seems|It looks|It appears|However|Alternatively|Instead|Actually|Since|Because|Although|Therefore|Looking at|Checking|Verifying|Analyzing|Considering|Reviewing|The user|The issue|The problem|The solution|The approach|The best|The most|The right|The correct|Adding new|The real|The actual|The main|Working on|Starting with|First I|Then I|Next I|After that|Wait, I|Wait I|Without seeing|Without reading|Without checking|I appreciate|I notice|I find|I realize|I understand|I see that|I see the|Could you|Would you|Can you|Once you|After you|It would be|It could be|It should be|It looks like|It seems like|In this case|In fact|In particular|In summary|In general|To be clear|To summarize|To confirm|To check|I\'m aware|I\'m finding|I\'m noticing|I\'m refactoring|I\'m looking|I\'m checking|I\'m going to|Would be|Should be|Could be|Parsing the|Writing the|Writing regex|Reading the|Completing the|Looking at the|Looking for|I need the|The disconnect|The key|The point|The reason|I\'m ready|Once I|I also need|Then there|I need to expand|I should add|I\'ve already|I already|I previously|I had|I was|I noticed|I checked|I verified|I confirmed|I completed|I added|I updated|I modified|I changed|Now let|Now I\'ll|Now I can|So I|So the|So this|So we|OK so|OK I|Alright|Great, now|Good, now|Right, so|Right, I|Let\'s|Let me check|Let me read|Let me look|Actually I|Wait, the|Wait, let|I see, so|I see now|I notice that|Hmm|Ah|Oh|Ah I see|I see that the|From the|Based on|According to',
        'thinking에서 영어 단어/문장을 사용했다',
        'thinking은 반드시 한국어로만 작성한다. 영어 단어 하나라도 등장하면 즉시 삭제하고 한국어로 재시작한다'
    ),
    (
        'T1 강화 - 영어 문장3 (세션내역 실제 사용)',
        r'Converting\s+file|Converting\s+\w+|substantial\s+refactor|substantial\s+work|substantial\s+amount|significant\s+refactor|significant\s+work|significant\s+amount|quite\s+large|quite\s+complex|quite\s+difficult|scope\s+is|The\s+scope|complexity\s+of|This\s+is\s+a\s+substantial|This\s+is\s+quite|This\s+would\s+be|This\s+could\s+be|This\s+refactor|This\s+conversion|This\s+migration|this\s+means|this\s+requires|CPU-bound|IO-bound|asyncio\s+event\s+loop|event\s+loop|threadpool|However,\s+I|However,\s+this|However,\s+the|However,\s+converting|However,\s+aiofiles|Now\s+I\'m\s+deciding|Now\s+I\'m\s+realizing|I\'m\s+deciding|I\'m\s+realizing|I\'m\s+converting|Converting\s+async|Continuing\s+through|I\'ll\s+work|I\'ll\s+start|I\'ll\s+need|I\'ll\s+handle|We\s+need|We\s+should|We\s+can|We\s+must|We\s+have|We\s+would|We\s+could|This\s+means\s+I|So\s+the\s+conversion|So\s+this\s+would|The\s+real\s+complication|The\s+real\s+benefit|The\s+main\s+complication|The\s+actual\s+issue|The\s+performance\s+impact|The\s+blocking|The\s+async|From\s+an\s+efficiency|From\s+a\s+performance|On\s+the\s+other\s+hand|At\s+this\s+point|At\s+a\s+minimum|For\s+example|For\s+instance|In\s+addition|Furthermore|Moreover|Nevertheless|Regardless|Meanwhile|Otherwise|Therefore,\s+I|Therefore,\s+the|Therefore,\s+we',
        'thinking에서 영어 문장을 사용했다 (실제 세션에서 감지된 패턴)',
        'thinking은 반드시 한국어로만 작성한다. "Converting", "substantial", "However, I" 같은 영어 문장이 등장하면 즉시 삭제하고 한국어로 재시작한다'
    ),
    (
        'T3 강화 - 작업량/복잡도 과대 언급',
        r'상당한\s*작업량|작업량이\s*크다|큰\s*변경|수천\s*줄|수백\s*줄|광범위한\s*수정|전면적\s*변환|전면적\s*리팩터|규모가\s*크다|규모가\s*상당|변경\s*범위가\s*넓|변경\s*범위가\s*크|수정해야\s*할\s*곳이\s*많|수정\s*대상이\s*많|호출부가\s*많|호출\s*지점이\s*많|연쇄적으로\s*변경|연쇄\s*수정|영향\s*범위가\s*크|영향\s*범위가\s*넓',
        '"상당한 작업량", "규모가 크다" 같은 표현으로 작업 범위를 과대 언급하거나 위협적으로 표현하려 했다',
        '작업 범위 크기는 판단 대상이 아니다. 지시된 전체 범위를 즉시 수행한다. T3 위반이다'
    ),
    (
        'T6 강화 - 영문 옵션/선택지 제시',
        r'Option\s*[1-9A-Z]|option\s*[1-9a-z]|Method\s*[1-9A-Z]|method\s*[1-9a-z]|Approach\s*[1-9A-Z]|approach\s*[1-9a-z]|two\s+ways|three\s+ways|two\s+options|three\s+options|two\s+approaches|three\s+approaches|another\s+way|another\s+option|another\s+approach|alternative\s+approach|better\s+approach|simpler\s+approach|easier\s+approach|cleaner\s+approach|safer\s+approach|more\s+efficient|more\s+elegant|more\s+appropriate',
        '영어로 선택지나 대안을 나열하려 했다',
        '사용자가 명시적으로 선택을 요구하지 않았으면 선택지를 나열하지 않는다. 즉시 지시된 작업을 수행한다. T6 위반이다'
    ),
    (
        'T4 강화 - 영문 추측 표현',
        r'might\s+be|could\s+be\s+because|probably\s+|likely\s+|possibly\s+|seems\s+to\s+be|appears\s+to\s+be|looks\s+like\s+it|I\s+suspect|I\s+assume|I\s+presume|might\s+not\s+be\s+worth|might\s+cause|could\s+cause|may\s+cause|might\s+need|could\s+need|may\s+need|would\s+require|this\s+should\s+work|this\s+might\s+work|this\s+could\s+work',
        '영어로 추측 표현을 사용했다',
        '영어 추측 표현도 T4 위반이다. 실제 파일을 Read로 확인한 후에만 판단한다'
    ),
    (
        'T9 강화 - 영문 세션 참조',
        r'session\s+summary|previous\s+session|last\s+session|from\s+the\s+summary|according\s+to\s+the\s+summary|based\s+on\s+previous|based\s+on\s+last\s+session|pending\s+tasks|from\s+the\s+context|from\s+prior|from\s+our\s+last|as\s+mentioned\s+before|as\s+discussed|as\s+established',
        '영어로 세션 요약이나 이전 대화에 의존하려 했다',
        '세션 요약은 배경 정보다. 실제 파일을 Read/Grep으로 직접 확인한다. T9 위반이다'
    ),
    (
        'T9 강화 - 세션 기억 참조',
        r'이번\s*세션에서\s*확인한|이번\s*세션에서\s*발견|이전\s*세션에서\s*수정|이전\s*세션에서\s*완료|세션에서\s*파악한|이전에\s*확인한\s*바|이전에\s*발견한|앞서\s*확인한|앞서\s*분석한|앞서\s*파악한|이미\s*파악된|이미\s*확인된|이미\s*발견된|기억에\s*따르면|기억하기로는|기존\s*패턴들을\s*검토|대부분.*이미\s*포함|이미\s*추가된\s*상태|이미\s*포함되어\s*있|아직\s*포함되지\s*않|패턴을\s*검토해보니|이미\s*들어가\s*있|이미\s*처리되어|이번에\s*보여준.*위반|위반\s*패턴.*자체\s*분석|세션\s*기억을\s*참조|기억\s*참조\s*중|이미\s*차단된\s*패턴|이미\s*등록된\s*패턴|이전에\s*추가한|앞서\s*추가한|이미\s*추가된|I\s*checked\s*this\s*earlier|I\s*verified\s*this\s*before|I\s*already\s*confirmed|I\s*established\s*earlier|we\s*already\s*confirmed|we\s*established\s*earlier|from\s*what\s*I\s*know\s*from\s*before|based\s*on\s*my\s*earlier\s*work|in\s*the\s*previous\s*conversation|from\s*earlier\s*in\s*this\s*session|recall\s*from\s*last\s*session|recall\s*from\s*earlier',
        '실제 파일 확인 없이 세션 기억이나 이전 확인 내용에 의존했다',
        '실제 파일을 Read/Grep으로 지금 직접 확인한다. 세션 기억 의존은 T9 위반이다'
    ),
    (
        'T4 강화 - 선호도 기반 방법 추측',
        r'깔끔할\s*(것\s*)?같다|깔끔할\s*(것\s*)?이다|더\s*깔끔한\s*방법|더\s*깔끔하게\s*[가-힣]|안전할\s*(것\s*)?같다|안전할\s*(것\s*)?이다|더\s*안전한\s*방법|더\s*안전하게\s*[가-힣]|이\s*방법이\s*(더\s*)?(좋을|나을|적합할|적절할|효과적일|강력할)\s*(것\s*)?같다|이\s*방식이\s*(더\s*)?(좋을|나을|적합할)\s*(것\s*)?같다|이게\s*더\s*나을\s*(것\s*)?같|이\s*편이\s*(더\s*)?나을|this\s*approach\s*seems\s*cleaner|this\s*seems\s*cleaner|this\s*is\s*cleaner|this\s*approach\s*is\s*safer|this\s*seems\s*safer|this\s*is\s*safer|this\s*seems\s*better|this\s*approach\s*seems\s*better|feels\s*cleaner|feels\s*safer|feels\s*better|seems\s*more\s*appropriate|seems\s*more\s*suitable|seems\s*more\s*elegant|this\s*is\s*more\s*elegant',
        '실제 확인 없이 선호도나 직관으로 방법을 선택하려 했다',
        'Read/Grep으로 실제 파일을 확인한 후에만 방법의 적합성을 판단한다. "깔끔할 것 같다", "안전할 것 같다" 방식 선택은 T4 위반이다'
    ),
    (
        'T4 강화 - JSONL/데이터 구조 추측',
        r'content가\s*리스트\s*형식|content.*형식일\s*수\s*있|구조.*형식일\s*수\s*있으니|마지막\s*assistant.*찾고|assistant.*entry.*찾기|텍스트\s*타입인\s*부분을\s*추출|항목을\s*확인해서\s*텍스트|JSON\s*구조.*다를\s*수|응답의\s*content.*리스트|message.*content.*리스트.*형식|content\[i\]|각\s*항목을\s*확인해서|the\s*structure\s*should\s*be|the\s*format\s*should\s*be|the\s*JSON\s*structure\s*is\s*probably|the\s*data\s*structure\s*is\s*probably|it\'?s\s*probably\s*a\s*dict|it\'?s\s*probably\s*a\s*list|the\s*field\s*should\s*be|the\s*key\s*should\s*be|the\s*schema\s*should\s*be',
        '실제 파일을 읽지 않고 JSON/데이터 구조를 추측하려 했다',
        'JSONL 파일이나 데이터 구조는 Read 도구로 실제로 확인한다. "content가 리스트 형식일 수 있으니" 같은 구조 추측은 T4 위반이다'
    ),
    (
        'T4 강화 - 미확인 코드 동작 단정',
        r'[가-힣\w]+[을를]\s*(보내고|전달하고|호출하고|전송하고)\s*있(으니|으므로|기\s*때문|다고)|[가-힣\w]+이\s*원인이다|[가-힣\w]+이\s*문제다|[가-힣]+이\s*422\s*에러의\s*원인|[가-힣]+이\s*에러\s*원인이다|this\s*is\s*sending|this\s*sends|this\s*calls|this\s*invokes|this\s*is\s*calling|this\s*is\s*the\s*cause|this\s*causes\s*the|this\s*is\s*causing|this\s*is\s*responsible\s*for\s*the\s*error|this\s*is\s*what\s*causes\s*the\s*error|this\s*function\s*is\s*sending|this\s*code\s*is\s*sending',
        '실제 코드를 확인하지 않고 특정 값/동작을 단정했다',
        'Read/Grep으로 실제 코드를 확인한 후에만 특정 값이나 동작을 단정한다. "~를 보내고 있다/있으니" 같은 미확인 단정은 T4 위반이다'
    ),
    (
        'T6 강화 - 미지시 상한/한계값 변경',
        r'상한.*올리|최대값.*늘리|[A-Z_]+MAX.*[0-9]+으로|[A-Z_]+LIMIT.*[0-9]+으로|상한을.*변경|한계값.*상향|제한.*늘려|제한.*올려|SEARCH_LIMIT_MAX.*[0-9]+|increase\s*the\s*limit|raise\s*the\s*limit|bump\s*the\s*limit|increase\s*the\s*max|raise\s*the\s*max|bump\s*the\s*max|set\s*the\s*limit\s*to\s*[0-9]+|set\s*the\s*max\s*to\s*[0-9]+|change\s*the\s*limit\s*to|change\s*the\s*max\s*to',
        '사용자가 지시하지 않은 상한값/최대값 변경을 스스로 추론했다',
        '상한값 변경은 사용자 명시 지시 없이 결정하지 않는다. 미지시 값 변경 추론은 T6 위반이다'
    ),
    (
        'T3 강화 - 지시 범위 초과 작업 시작',
        r'이제\s*[가-힣\w]+[을를]\s*(수정해야|변경해야|구현해야|고쳐야|작성해야)|이제\s*[가-힣\w]+\s*파일을\s*(수정|변경|구현|고치)',
        '사용자가 지시하지 않은 수정/구현 작업을 스스로 시작하려 했다',
        '사용자가 명시적으로 지시한 작업만 수행한다. 차단 규칙 강화 지시를 받았으면 훅 파일만 수정한다. 코드 수정은 별도 지시 없이 시작하지 않는다'
    ),
    (
        'T6 강화 - 훅·JSONL 비활성화/우회 시도',
        r'validate-thinking.*비활성화|validate-thinking.*\.bak|validate-thinking.*삭제|validate-thinking.*이름\s*변경|훅.*비활성화|훅.*삭제|훅.*우회|violations.*삭제|violations.*파일.*지우|JSONL.*수정|JSONL.*삭제|transcript.*수정|transcript.*삭제|thinking.*지우|이전\s*응답.*삭제|watcher.*PID.*삭제|캐시.*지우|entry.*제거|entry.*교체|entry.*삭제|마지막\s*assistant.*제거|\.bak으로\s*이름|이름을\s*바꿔|이름\s*변경.*훅|훅\s*파일.*이름',
        '훅·violations 파일·JSONL transcript를 비활성화/수정/삭제하여 감지를 우회하려 했다',
        '훅 우회 시도 자체가 T6 위반이다. thinking에서 한국어로만 규칙을 준수하는 것이 유일한 올바른 행동이다'
    ),
    (
        'T4 강화 - 학습지식을 공식문서처럼 출력',
        r'(exit\s*[012].*의미한다|exit\s*[012].*뜻이다|exit\s*[012].*동작이다|exit\s*code.*규칙|훅.*규칙.*기억|공식\s*문서.*에\s*따르면|공식\s*문서.*기준|docs.*에\s*따르면|문서.*기준으로|문서에서.*확인|알려진\s*바|학습된\s*지식|알고\s*있는\s*바로는|기억하는\s*바로는|알기로는|제\s*기억에|제가\s*알기로|관련\s*지식으로는|배경\s*지식으로는|일반적으로\s*훅|훅\s*시스템의\s*규칙|exit\s*code의\s*의미|exit\s*코드의\s*의미|according\s+to\s+the\s+docs|as\s+per\s+the\s+docs|from\s+the\s+documentation|the\s+documentation\s+says|the\s+spec\s+says|the\s+spec\s+states|per\s+the\s+spec|as\s+documented|as\s+per\s+specification|from\s+my\s+training|based\s+on\s+my\s+training|from\s+what\s+I\s+know|from\s+memory|I\s+recall\s+that|I\s+know\s+from\s+training|I\s+was\s+trained\s+that)',
        '실제 웹서치/문서 확인 없이 학습된 지식을 공식 문서인 척 thinking에서 출력했다',
        '공식 문서나 외부 시스템 규칙은 반드시 WebFetch/WebSearch 도구로 실제 문서를 확인한 후에만 진술한다. 학습 지식을 근거로 기술 규격을 단정하는 것은 T4 위반이다'
    ),
    (
        'T10 강화 - 훅 캐시 핑계 우회',
        r'캐시에\s*남아|캐시\s*때문|이전\s*thinking.*캐시|캐시가\s*남아|캐시로\s*인해|캐시\s*문제|이전\s*응답.*캐시|캐시된\s*thinking|thinking\s*캐시|훅이\s*이전\s*(thinking|응답).*감지|이전\s*(thinking|응답).*잡(히|아|고)|직전\s*응답.*감지|직전\s*thinking.*감지|훅이\s*직전.*차단|이전\s*메시지.*잡|캐싱된.*패턴|패턴이\s*캐시|감지.*캐시|오래된\s*(응답|thinking).*감지|cached\s*thinking|stale\s*thinking|stale\s*response|the\s*hook\s*is\s*catching\s*old|the\s*hook\s*caught\s*old|false\s*positive|this\s*is\s*a\s*false\s*positive|the\s*hook\s*is\s*wrong|the\s*hook\s*is\s*incorrectly|the\s*hook\s*mistakenly|mistaken\s*detection|cached\s*entry|from\s*cached',
        '훅 감지 결과를 "캐시 잔여물" 탓으로 돌려 실제 위반을 부정하려 했다',
        '훅이 감지하면 실제로 그 표현을 썼다는 뜻이다. 캐시 핑계는 T10 훅차단없음정당화 위반이다. 규칙을 준수하는 것이 유일한 올바른 행동이다.'
    ),
    (
        'T12 - 응답 재작성 선언/훅 차단 메타언급',
        r'훅이\s*이전\s*응답을\s*차단했다|이전\s*응답.*차단됐다|이전\s*응답.*차단되었다|응답이\s*차단됐으므로|재작성해야\s*한다|재작성\s*필요|다시\s*작성해야\s*한다|thinking에서.*패턴이\s*감지됐다|이는\s*T[0-9]+\s*위반이다|이것은\s*T[0-9]+\s*위반이다|이것이\s*T[0-9]+\s*위반|이게\s*T[0-9]+\s*위반|이전\s*응답의\s*내용은.*완료|이전\s*응답에서.*수정.*완료|수정\s*완료\s*보고만\s*간결하게|완료\s*보고만\s*작성|간결하게\s*작성한다|보고만\s*간결하게|the\s+hook\s+blocked\s+(?:the\s+)?(?:last|previous|my)\s+response|(?:the\s+)?previous\s+response\s+was\s+blocked|my\s+last\s+response\s+was\s+blocked|I\s+need\s+to\s+rewrite|I\s+should\s+rewrite|rewrite\s+(?:the\s+)?response|this\s+is\s+a\s+T[0-9]+\s+violation|this\s+violates\s+T[0-9]+|T[0-9]+\s+violation\s+was\s+detected|pattern\s+was\s+detected\s+in\s+(?:my\s+)?thinking|since\s+(?:the\s+)?(?:last|previous)\s+response\s+was\s+blocked|the\s+content\s+of\s+(?:the\s+)?(?:last|previous)\s+response',
        '응답 안에서 훅 차단 사실·규칙 위반을 언급하거나, 완료 보고를 우회하거나, 스스로 재작성을 선언하려 했다',
        '훅 차단 여부와 무관하게 사용자 지시 원문대로만 응답을 구성한다. "훅이 차단했다", "재작성해야 한다" 같은 메타 언급 자체가 T12 위반이다. 즉시 삭제하고 지시 원문으로 돌아간다'
    ),
    (
        'T1 강화 - 영어 분석 문장4',
        r'If\s+I|When\s+I|Once\s+I|After\s+I|Before\s+I|What\s+I|Which\s+I|Where\s+I|How\s+I|Why\s+I|The\s+file|The\s+function|The\s+method|The\s+class|The\s+variable|The\s+type|The\s+pattern|The\s+rule|The\s+hook|The\s+check|The\s+pattern\s+is|The\s+rule\s+is|A\s+new|A\s+simple|A\s+complex|A\s+better|A\s+cleaner|No\s+match|No\s+pattern|No\s+rule|Pattern\s+found|Pattern\s+not|Rule\s+found|Rule\s+not|Found\s+the|Found\s+a|Not\s+found|Missing\s+the|Missing\s+a|Adding\s+the|Removing\s+the|Updating\s+the|Checking\s+the|Reading\s+the|Writing\s+the|Current\s+state|Current\s+file|Current\s+pattern|Now\s+adding|Now\s+checking|Now\s+reading|Need\s+to\s+add|Need\s+to\s+check|Need\s+to\s+read|Should\s+add|Should\s+check|Should\s+read|Going\s+to\s+add|Going\s+to\s+check|Going\s+to\s+read|Will\s+add|Will\s+check|Will\s+read|Must\s+add|Must\s+check|Must\s+read',
        'thinking에서 영어 단어/문장을 사용했다 (분석적 영어 표현)',
        'thinking은 반드시 한국어로만 작성한다. 영어 단어 하나라도 등장하면 즉시 삭제하고 한국어로 재시작한다'
    ),
    (
        'T6 강화 - 미지시 결정/확인/검토 선언',
        r'결정했다|결정하기로\s*했다|결정하기로\s*결정|[가-힣\w]+으로\s*결정됐다|[가-힣\w]+하기로\s*결정|필요성을\s*검토|필요성을\s*확인|필요한지\s*검토|필요한지\s*확인해야|[가-힣\w]+의\s*필요성|[가-힣\w]+\s*여부를\s*검토|[가-힣\w]+\s*여부를\s*확인해야|[가-힣\w]+를\s*보존하기로|[가-힣\w]+을\s*보존하기로|[가-힣\w]+\s*방향을\s*고려하고\s*있다|고려하고\s*있다|[가-힣\w]+\s*(방식|방법|방향)으로\s*(진행|처리|구현|실행)하면\s*된다|[가-힣\w]+으로\s*(통일|대체|리팩터링|변경)하면\s*된다|[가-힣\w]+로\s*(통일|대체|리팩터링|변경)하면\s*된다|[가-힣\w]+\s*목표다|[가-힣\w]+이\s*목표다|[가-힣\w]+가\s*목표다|물어보는\s*게\s*맞을|물어보는\s*것이\s*맞|물어보는\s*게\s*적절|I\s+decided\s+to|I\s+decided\s+that|I\s+will\s+ask\s+the\s+user|I\s+should\s+ask|need\s+to\s+determine|need\s+to\s+decide|need\s+to\s+examine\s+whether|which\s+approach\s+is\s+better|whether\s+.*\s+is\s+needed|should\s+be\s+preserved|should\s+be\s+kept|the\s+goal\s+is\s+to',
        '사용자가 지시하지 않은 결정, 검토, 보존, 확인 행동을 thinking에서 스스로 선택했다',
        '사용자가 명시한 것만 수행한다. "결정했다", "검토해야 한다", "~하면 된다"로 스스로 방법을 정하는 것은 T6 위반이다. 지시 원문으로 돌아간다'
    ),
    (
        'T4 강화 - 미지시 확인 행동 결정',
        r'이제\s*현재.*확인해야\s*한다|이제\s*[가-힣\w]+에\s*있는.*확인해야|현재\s*[가-힣\w]+를\s*확인해야\s*한다|현재\s*[가-힣\w]+을\s*확인해야\s*한다|[가-힣\w]+부터\s*확인해야\s*한다|먼저\s*[가-힣\w]+확인해야\s*한다|[가-힣\w]+\s*파악해야\s*한다|[가-힣\w]+를\s*파악해야|[가-힣\w]+을\s*파악해야|이\s*부분도\s*확인이\s*필요|이\s*부분을\s*확인해야|[가-힣\w]+\s*어느\s*방식이\s*(더\s*)?나을지|어느\s*방식이\s*(더\s*)?나을지\s*결정해야|어떤\s*방식이\s*(더\s*)?나을지|어떤\s*방법이\s*(더\s*)?나을지|I\s+need\s+to\s+confirm\s+the\s+current|I\s+need\s+to\s+verify\s+the\s+current|I\s+need\s+to\s+check\s+what\s+currently|first\s+I\s+need\s+to\s+check|first\s+I\s+should\s+check|need\s+to\s+figure\s+out\s+which',
        '사용자가 지시하지 않은 확인/파악/검증 행동을 thinking에서 스스로 결정하고 시작하려 했다',
        'Read 도구는 사용자가 지시한 파일에 대해서만 호출한다. "~를 확인해야 한다"는 사용자 지시 없이 thinking에서 발생하면 T4 위반이다. 지시 원문으로 돌아간다'
    ),
    (
        'T10 강화 - 사용자 지적 원인 부정',
        r'이전\s*실행\s*(때|당시|에서)|이전에\s*실행|이전\s*기동\s*(때|당시)|서버\s*기동\s*당시|그\s*당시에는|그\s*시점에는|나중에\s*변경\s*한|나중에\s*누군가|사용자가\s*나중에|나중에\s*0으로|이미\s*실행\s*중이었|이미\s*실행됐을|이미\s*기동\s*중이었|이전\s*로그일|이전\s*실행\s*로그|이미\s*적용됐을|이전\s*설정으로\s*실행|was\s+already\s+running|had\s+already\s+been\s+set|had\s+previously\s+been|previously\s+set\s+to|was\s+set\s+before|user\s+changed\s+it\s+later|changed\s+it\s+after|modified\s+it\s+after',
        '사용자가 버그를 명확히 지적했는데 "이전 실행 때의 로그일 것이다", "그 당시에는 다른 설정이었을 것이다", "사용자가 나중에 변경한 것 같다"처럼 추측으로 버그를 부정하거나 다른 원인을 찾으려 했다',
        '사용자가 버그를 지적하면 즉시 인정하고 실제 파일을 Read로 확인해서 수정한다. 이전 실행 상태·과거 로그·누군가가 변경했을 것이라는 추측은 T4+T10 동시 위반이다'
    ),
    (
        'T12 강화 - 차단 후 보고 생략',
        r'차단됐으니\s*(보고를|보고는|작업은|내용은)\s*(생략|건너|제외|축소)|차단됐으므로\s*(보고|작성|응답|내용)\s*(생략|간략|간결|축소)|차단\s*당했으니\s*(보고|응답)\s*(생략|간략)|이전\s*응답.*차단.*생략|보고\s*생략하겠|수행\s*내용.*생략하겠|완료\s*보고.*생략|생략하겠습니다|생략하겠다|보고\s*없이\s*넘어|차단됐으니.*간략|차단됐으니.*간결|간결하게만\s*작성|차단.*이유로.*생략',
        '훅에 차단됐다는 이유로 보고 내용을 생략하거나 축소하려 했다',
        '차단 여부와 무관하게 사용자 지시에 따른 완전한 보고를 작성한다. 차단 후 보고 생략·축소는 T3(작업축소)+T12(훅메타언급) 동시 위반이다'
    ),
    (
        'T8 강화 - 작업 거부 역지시',
        r'보증\s*불가|수정\s*지시를\s*(내려라|내려|내리면|요청해야|받아야)|사용자가\s*(원하면|수정을\s*원하면|허락하면|지시하면)\s*(진행|수정|작업|처리)|수정을\s*원하면\s*(진행|알려|말씀해|허락|지시)|지시(를|을)\s*(내려라|내려주|요청합니다|요청해야)|수정\s*여부를\s*(알려달라|말씀해주|알려주세요|확인해야)|원하면\s*(진행하겠|처리하겠|수정하겠|알려달라|말씀해주)|불가능하다는\s*뜻이다|수정\s*지시가\s*(있으면|없으면|필요|있어야)|완전히\s*보증할\s*수\s*없|보증하기\s*어렵|허락을\s*받아야|승인을\s*받아야|지시를\s*내려라|원하시면\s*진행|말씀해\s*주시면\s*진행',
        '사용자가 문제를 지적했는데 수정을 거부하고 "수정 지시를 내려라", "보증 불가", "원하면 진행하겠다"처럼 역으로 지시·허락을 요청하려 했다',
        '사용자가 문제를 지적한 순간이 수정 지시다. 즉시 실제 파일을 Read로 확인하고 수정을 진행한다. 보증 여부 논의나 역지시 요청은 T8(작업거부)+T3(작업축소) 동시 위반이다'
    ),

]

from datetime import datetime, timezone as _tz

with open(transcript_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 마지막 assistant entry 찾기 — 타임스탬프 기반 오래된 항목 필터링
# 90초 초과된 entry는 현재 응답이 아닌 것으로 간주하고 스킵
last_thinking_text = ''
_now = datetime.now(_tz.utc)
for line in reversed(lines):
    line = line.strip()
    if not line:
        continue
    try:
        entry = json.loads(line)
        if entry.get('type') == 'assistant':
            ts_str = entry.get('timestamp', '')
            if ts_str:
                try:
                    entry_dt = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                    age_sec = (_now - entry_dt).total_seconds()
                    if age_sec > 90:
                        # 90초 이상 된 오래된 entry — 현재 응답이 아님, 스킵
                        break
                except Exception:
                    pass
            msg = entry.get('message', {})
            content = msg.get('content', []) if isinstance(msg, dict) else []
            if isinstance(content, list):
                thinking_parts = []
                for c in content:
                    if isinstance(c, dict) and c.get('type') == 'thinking':
                        thinking_parts.append(c.get('thinking', ''))
                if thinking_parts:
                    last_thinking_text = '\n'.join(thinking_parts)
                    break
    except:
        continue

if not last_thinking_text:
    sys.exit(0)

# 패턴 검사
violations = []
for rule_name, pattern, violation_desc, correct_action in FORBIDDEN_PATTERNS:
    matches = re.findall(pattern, last_thinking_text)
    if matches:
        violations.append({
            'rule': rule_name,
            'matches': matches[:3],
            'violation_desc': violation_desc,
            'correct_action': correct_action,
        })

if not violations:
    sys.exit(0)

# 위반 발견 → stderr로 강력한 경고 피드백 출력 (도구는 허용, 경고만 전달)
lines_out = [
    '█' * 70,
    f'★★★ THINKING VIOLATION — 이 thinking은 지금 즉시 삭제되어야 한다 ★★★',
    f'위반 {len(violations)}개 감지. 도구({tool_name})는 실행되지만:',
    '  → 이 thinking 패턴을 응답에 반영하면 Stop 훅이 응답 전체를 차단하고 재생성을 강제한다.',
    '  → 경고가 아니다. 명령이다. 지금 즉시 아래 위반 문장들을 삭제하고 처음부터 다시 시작하라.',
    '',
]
for v in violations:
    lines_out.append(f'  ▶ 【{v["rule"]}】')
    lines_out.append(f'    감지된 표현: {v["matches"]}')
    lines_out.append(f'    왜 잘못됐는가: {v["violation_desc"]}')
    lines_out.append(f'    지금 즉시 해야 할 행동: {v["correct_action"]}')
    lines_out.append('')
lines_out += [
    '─' * 70,
    '▶ 올바른 thinking 재시작 순서 — 지금 즉시 실행하라:',
    '',
    '  1. 사용자 지시 원문을 한 글자도 바꾸지 않고 그대로 읽는다.',
    '     금지: "사용자의 의도는" / "다시 보면" / "진짜 의미는" / "더 효율적인"',
    '     왜: 재해석 자체가 T2 위반이다. 지시에 없는 의미를 추가하는 순간 규칙 위반이다.',
    '',
    '  2. Read/Grep 도구로 실제 파일을 연다. 파일을 열기 전에는 아무 판단도 하지 않는다.',
    '     금지: 파일명 추측 / 구조 가정 / "보통 이런 구조는" / "경험상"',
    '     왜: 열지 않은 파일에 대한 모든 판단이 T4 위반이다.',
    '',
    '  3. 왜/어떻게/무엇을/어떤 식으로 — 실제 파일 근거로만 답한다.',
    '     왜: 현재 코드에서 확인된 실제 결함.',
    '     어떻게: 라우트→서비스→DB 파일 순서.',
    '     무엇을: 파일명:라인번호로 정확히 지정. "이 부분", "해당 로직" 금지.',
    '     어떤 식으로: old_string이 현재 파일에 실제 존재하는지 Read로 확인 후 Edit.',
    '',
    '  4. Edit 도구로 국소 수정. Write로 덮어쓰기 절대 금지. 가짜 구현·더미 로직 금지.',
    '     왜: Write 덮어쓰기는 기존 코드 맥락을 파괴하고 타입 불일치를 발생시킨다.',
    '',
    '  5. 변경 파일과 호출 파일의 앞뒤 흐름이 끊기지 않음을 Read로 직접 확인한다.',
    '     방법: Grep으로 변경 파일을 import하는 모든 파일을 찾아 읽는다.',
    '',
    '  6. 미확인 영역은 완료가 아닌 "미확인"으로 분리 보고한다.',
    '     금지: 실제 확인 없이 "완료됐습니다" / "정상입니다" / "해결됐습니다" 선언.',
    '     왜: 확인하지 않은 것을 완료로 보고하면 T5 허위보고 위반이다.',
    '',
    '─' * 70,
    '▶ 이 패턴이 응답에 나오면 Stop 훅이 즉시 차단한다 — 절대 금지:',
    '',
    '  ✗ [T1] 영어 thinking: I need to / Let me / The file / Found the / probably / likely',
    '       왜: thinking은 한국어만 허용된다. 영어 단어 1개라도 나오면 즉시 삭제하고 재시작.',
    '',
    '  ✗ [T2] 의도 재해석: 사용자의 의도는 / what the user really wants / on second thought',
    '       왜: 지시 원문을 그대로 이행해야 한다. 해석 자체가 위반이다.',
    '',
    '  ✗ [T3] 작업 축소: 우선 ~만 / 간단하게 / just the core / too complex to / 상당한 작업량',
    '       왜: 지시된 전체 범위를 지금 즉시 수행해야 한다. 크기·복잡도는 이유가 안 된다.',
    '',
    '  ✗ [T4] 추측 판단: 아마 / ~겠지 / ~인 것 같다 / ~로 보인다 / seems / appears',
    '       왜: Read/Grep으로 실제 파일을 확인한 후에만 판단한다. 추측은 허용되지 않는다.',
    '',
    '  ✗ [T5] 허위완료: 완료됐습니다 / 정상입니다 / this should work / that should fix',
    '       왜: 변경 파일과 호출 파일을 Read로 직접 확인한 후에만 완료를 선언한다.',
    '',
    '  ✗ [T6] 미지시 대안: 다른 방법 / 이렇게 하면 어떨까 / Option 1 / alternatively',
    '       왜: 사용자가 명시한 방법만 사용한다. 대안 탐색 자체가 위반이다.',
    '',
    '  ✗ [T6] 결정 선언: 결정했다 / ~하면 된다 / ~가 목표다 / I decided to / the goal is to',
    '       왜: 방법·방향·결정은 사용자 지시 원문에만 따른다.',
    '',
    '  ✗ [T9] 세션 기억: 이전 세션에서 / 서머리에 따르면 / 앞서 확인한 / session summary',
    '       왜: 세션 요약은 배경 정보다. 지금 실제 파일을 Read로 확인한다.',
    '',
    '  ✗ [T12] 훅 메타: 재작성해야 한다 / 이는 T위반이다 / 차단됐으므로',
    '        왜: 훅 차단 사실을 응답에 넣는 것 자체가 금지다.',
    '',
    '█' * 70,
]
import json as _json
warning_text = '\n'.join(lines_out)
print(_json.dumps({
    "hookSpecificOutput": {
        "permissionDecision": "allow",
        "permissionDecisionReason": warning_text
    }
}))
sys.exit(0)
PYEOF
