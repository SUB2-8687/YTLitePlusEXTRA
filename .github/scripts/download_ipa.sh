#!/usr/bin/env bash
# IPA 다운로드 + 검증 스크립트
#
# 사용법: download_ipa.sh <IPA_URL> [저장파일명(기본 youtube.ipa)]
#
# - Dropbox / Google Drive / GitHub blob 공유 링크를 직접 다운로드 링크로 자동 변환합니다.
# - 받은 파일이 HTML(미리보기·로그인·만료 페이지)이면 원인을 알려주고 실패 처리합니다.
# - 받은 파일이 올바른 IPA(zip + Payload/*.app)인지 확인합니다.
# - URL 은 비밀 값이므로 로그에 출력하지 않습니다.

set -uo pipefail

URL="${1:-}"
OUT="${2:-youtube.ipa}"

fail() {
    echo "::error::$1"
    exit 1
}

# 앞뒤 공백/따옴표/CR 제거
URL="$(printf '%s' "$URL" | tr -d '\r\n' | sed -e 's/^[[:space:]"'\'']*//' -e 's/[[:space:]"'\'']*$//')"

[ -n "$URL" ] || fail "ipa_url 이 비어 있습니다. 복호화된 IPA 의 직접 다운로드 링크를 입력하세요."

case "$URL" in
    http://*|https://*) ;;
    *) fail "ipa_url 은 http:// 또는 https:// 로 시작하는 링크여야 합니다." ;;
esac

# ---------- 공유 링크 -> 직접 다운로드 링크 변환 ----------
if [[ "$URL" =~ ^https?://(www\.)?dropbox\.com/ ]]; then
    # dl=0 -> dl=1 (없으면 추가)
    if [[ "$URL" == *"dl=0"* ]]; then
        URL="${URL//dl=0/dl=1}"
    elif [[ "$URL" != *"dl=1"* && "$URL" != *"raw=1"* ]]; then
        if [[ "$URL" == *"?"* ]]; then URL="${URL}&dl=1"; else URL="${URL}?dl=1"; fi
    fi
    echo "Dropbox 링크를 직접 다운로드 형식으로 변환했습니다."
elif [[ "$URL" =~ ^https?://drive\.google\.com/ ]]; then
    gid=""
    if [[ "$URL" =~ /file/d/([A-Za-z0-9_-]+) ]]; then
        gid="${BASH_REMATCH[1]}"
    elif [[ "$URL" =~ [?\&]id=([A-Za-z0-9_-]+) ]]; then
        gid="${BASH_REMATCH[1]}"
    fi
    if [ -n "$gid" ]; then
        URL="https://drive.usercontent.google.com/download?id=${gid}&export=download&confirm=t"
        echo "Google Drive 링크를 직접 다운로드 형식으로 변환했습니다."
    fi
elif [[ "$URL" =~ ^https?://github\.com/[^/]+/[^/]+/blob/ ]]; then
    URL="${URL/\/blob\//\/raw\/}"
    echo "GitHub blob 링크를 raw 형식으로 변환했습니다."
fi

# ---------- 다운로드 ----------
rm -f "$OUT"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

http_code="$(curl -L --silent --show-error \
    --retry 3 --retry-delay 2 --connect-timeout 30 \
    -A "$UA" \
    -o "$OUT" \
    -w '%{http_code}' \
    "$URL")"
curl_status=$?

if [ "$curl_status" -ne 0 ]; then
    fail "다운로드 실패 (curl 종료 코드 $curl_status). 링크가 올바른지, 외부에서 접근 가능한지 확인하세요."
fi

case "$http_code" in
    2??) ;;
    *) fail "다운로드 실패: 서버가 HTTP $http_code 를 반환했습니다. 링크가 만료되었거나 접근 권한이 없는지 확인하세요." ;;
esac

[ -s "$OUT" ] || fail "다운로드된 파일이 비어 있습니다."

size="$(wc -c < "$OUT" | tr -d ' ')"
file_type="$(file --mime-type -b "$OUT")"
echo "다운로드 완료: ${size} bytes, 형식: ${file_type}"

# ---------- 검증 ----------
if [[ "$file_type" == text/html* ]]; then
    fail "받은 파일이 IPA 가 아니라 웹 페이지(HTML)입니다. 직접 다운로드되는 링크가 필요합니다 (Dropbox 는 dl=1, Google Drive 는 '링크가 있는 모든 사용자' 공유, MediaFire/미리보기/로그인 페이지 링크는 사용 불가)."
fi

if [ "$(head -c 2 "$OUT")" != "PK" ]; then
    fail "받은 파일이 올바른 IPA(zip)가 아닙니다. 감지된 형식: $file_type"
fi

if ! unzip -l "$OUT" 2>/dev/null | grep -Eq 'Payload/[^/]+\.app/'; then
    fail "zip 파일이지만 IPA 구조(Payload/*.app)가 아닙니다. 복호화된 .ipa 파일인지 확인하세요."
fi

echo "IPA 검증 완료."
