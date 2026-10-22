#!/usr/bin/env bash
# 빌드 중 en.lproj, ko.lproj 를 제외한 나머지 언어팩(*.lproj)을 삭제합니다.
# (Base.lproj 는 xib/storyboard 가 들어 있을 수 있어 안전을 위해 유지합니다.)
#
# 사용법:
#   prune_localizations.sh <폴더|.deb 파일> [<폴더|.deb 파일> ...]
#   - 폴더  : 폴더 안의 불필요한 *.lproj 를 바로 삭제
#   - .deb  : 풀어서 삭제한 뒤 같은 이름으로 다시 패키징 (gzip, root:root)

set -euo pipefail

PRUNED=0

# 폴더 하나를 정리하고 삭제 개수를 PRUNED 에 저장
prune_dir() {
    local root="$1"
    local expr=(-type d -name '*.lproj' ! -name en.lproj ! -name ko.lproj ! -name Base.lproj)

    PRUNED=$(find "$root" -name .git -prune -o \( "${expr[@]}" \) -print | wc -l | tr -d ' ')
    if [ "$PRUNED" -gt 0 ]; then
        find "$root" -name .git -prune -o \( "${expr[@]}" \) -prune -exec rm -rf {} +
    fi
}

prune_deb() {
    local deb="$1"
    local tmp
    tmp="$(mktemp -d)"

    if ! command -v dpkg-deb >/dev/null 2>&1; then
        brew install dpkg
    fi

    dpkg-deb -R "$deb" "$tmp"
    prune_dir "$tmp"

    if [ "$PRUNED" -gt 0 ]; then
        dpkg-deb --root-owner-group -Zgzip -b "$tmp" "$deb.pruned" >/dev/null
        mv -f "$deb.pruned" "$deb"
    fi
    rm -rf "$tmp"
}

if [ "$#" -eq 0 ]; then
    echo "사용법: $0 <폴더|.deb> ..." >&2
    exit 1
fi

for target in "$@"; do
    if [ -d "$target" ]; then
        prune_dir "$target"
    elif [ -f "$target" ] && [[ "$target" == *.deb ]]; then
        prune_deb "$target"
    else
        echo "prune_localizations: 폴더 또는 .deb 가 아닙니다: $target" >&2
        exit 1
    fi
    echo "prune_localizations: $target - 언어팩 ${PRUNED}개 삭제 (유지: en, ko, Base)"
done
