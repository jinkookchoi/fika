#!/bin/bash
# 이 레포의 안전장치: gh / git push 가 반드시 개인 계정으로만 나가게 강제한다.
# (전역 gh 활성 계정이 회사 계정일 때 실수로 public 레포·릴리즈를 회사로 올리는 사고 방지)
#
# PreToolUse(Bash) 훅으로 등록. 활성 gh 계정이 허용 계정이 아니면 exit 2 로 차단한다.
# 'gh auth ...'(계정 전환·로그인 등)는 해결 수단이므로 검사에서 제외한다.
set -uo pipefail

ALLOWED="jinkookchoi"   # 허용(개인) GitHub 로그인

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)

# gh 호출 또는 git push 가 들어간 명령만 대상. 단 'gh auth' 는 제외(전환 명령을 막으면 안 됨).
if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])gh([[:space:]]|$)|git[[:space:]].*push'; then
  if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])gh[[:space:]]+auth'; then
    exit 0
  fi

  # 활성 gh 계정 추출 (오프라인: gh auth status 파싱)
  active=$(gh auth status 2>/dev/null | awk '
    /Logged in to .* account /{ for(i=1;i<=NF;i++) if($i=="account") a=$(i+1) }
    /Active account: true/{ print a; exit }')

  if [ "${active:-}" != "$ALLOWED" ]; then
    echo "🚫 gh 활성 계정이 '${active:-unknown}' 입니다." >&2
    echo "   이 레포(fika)는 개인 계정 '$ALLOWED' 로만 push/create/release 해야 합니다." >&2
    echo "   먼저 실행:  gh auth switch --user $ALLOWED" >&2
    exit 2
  fi
fi
exit 0
