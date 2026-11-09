#!/usr/bin/env bash
# IPA 다운로드 + 검증 스크립트 (macOS/Linux 러너 공용)
# 사용법: download_ipa.sh <URL> [출력파일명=youtube.ipa]
#
# 지원: Dropbox(dl=1 자동 변환), Google Drive(확인 페이지 우회), MediaFire(직링크 추출), 일반 직링크
# 받은 파일이 zip(IPA) 이 아니면(HTML 등) 원인 안내와 함께 실패 처리합니다.

set -euo pipefail

URL="${1:-}"
OUT="${2:-youtube.ipa}"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

# 앞뒤 공백/개행/CR 제거
URL="$(printf '%s' "$URL" | tr -d '\r\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

if [ -z "$URL" ]; then
    echo "::error::IPA URL 이 비어 있습니다."
    exit 1
fi

fetch() { # fetch <url> <out>
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 \
        -A "$UA" -H "Accept: */*" -o "$2" "$1"
}

is_zip() { # 파일 앞 2바이트가 PK 인지 확인
    [ -s "$1" ] && [ "$(head -c 2 "$1")" = "PK" ]
}

try_download() {
    local url="$1"
    rm -f "$OUT"
    if fetch "$url" "$OUT" 2>/dev/null && is_zip "$OUT"; then
        return 0
    fi
    return 1
}

OK=0

# ---------- Dropbox ----------
if [[ "$URL" == *dropbox.com* ]]; then
    # dl=0 / raw=1 제거 후 dl=1 지정
    base="$(printf '%s' "$URL" | sed -E 's/[?&](dl|raw)=[^&]*//g')"
    if [[ "$base" == *\?* ]]; then
        direct="${base}&dl=1"
    else
        direct="${base}?dl=1"
    fi
    echo "Dropbox 링크를 직접 다운로드 형식(dl=1)으로 변환했습니다."
    if try_download "$direct"; then
        OK=1
    else
        # 대체: 다운로드 전용 호스트로 재시도
        alt="$(printf '%s' "$direct" | sed -E 's#https?://(www\.)?dropbox\.com#https://dl.dropboxusercontent.com#; s/[?&]dl=1//')"
        echo "대체 호스트로 재시도합니다."
        if try_download "$alt"; then OK=1; fi
    fi

# ---------- Google Drive ----------
elif [[ "$URL" == *drive.google.com* || "$URL" == *docs.google.com* ]]; then
    id="$(printf '%s' "$URL" | sed -nE 's#.*/d/([A-Za-z0-9_-]+).*#\1#p')"
    [ -z "$id" ] && id="$(printf '%s' "$URL" | sed -nE 's#.*[?&]id=([A-Za-z0-9_-]+).*#\1#p')"
    if [ -z "$id" ]; then
        echo "::error::Google Drive 파일 ID 를 찾을 수 없습니다: $URL"
        exit 1
    fi
    echo "Google Drive 링크를 직접 다운로드 형식으로 변환했습니다."
    if try_download "https://drive.usercontent.google.com/download?id=${id}&export=download&confirm=t"; then
        OK=1
    elif try_download "https://drive.google.com/uc?export=download&confirm=t&id=${id}"; then
        OK=1
    fi

# ---------- MediaFire ----------
elif [[ "$URL" == *mediafire.com* ]]; then
    echo "MediaFire 페이지에서 직접 다운로드 링크를 추출합니다."
    page="$(mktemp)"
    if fetch "$URL" "$page" 2>/dev/null; then
        direct="$(grep -oE 'https?://download[0-9]*\.mediafire\.com/[^"'\'' <>]+' "$page" | head -n1 || true)"
        if [ -n "$direct" ] && try_download "$direct"; then OK=1; fi
    fi
    rm -f "$page"

# ---------- 일반 직링크 ----------
else
    if try_download "$URL"; then OK=1; fi
fi

if [ "$OK" -ne 1 ]; then
    type="unknown"
    [ -f "$OUT" ] && type="$(file --mime-type -b "$OUT" 2>/dev/null || echo unknown)"
    echo "::error::받은 파일이 IPA 가 아닙니다 (감지된 형식: $type). 다음을 확인하세요: (1) 링크가 만료/삭제되지 않았는지 (2) Dropbox 는 '링크가 있는 모든 사용자' 공유 + 폴더가 아닌 파일 링크인지 (3) Google Drive 는 '링크가 있는 모든 사용자' 공유인지 (4) 미리보기/로그인 페이지 링크가 아닌 직접 다운로드 링크인지"
    rm -f "$OUT"
    exit 1
fi

# zip 구조 검증 (Payload/*.app 존재 여부)
if ! unzip -l "$OUT" 2>/dev/null | grep -qE 'Payload/[^/]+\.app/'; then
    echo "::error::zip 파일이지만 IPA 구조(Payload/*.app)가 아닙니다. 복호화된 IPA 가 맞는지 확인하세요."
    exit 1
fi

echo "다운로드 완료: $(wc -c < "$OUT" | tr -d ' ') bytes, IPA 검증 통과"
