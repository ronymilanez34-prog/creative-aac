#!/usr/bin/env bash
# שומר תוכן של שיחה (עם Claude או כל מקור אחר) בתוך הפרויקט,
# תחת docs/conversations/<תאריך>-<שם>.md, ומבצע commit.
#
# שימוש:
#   scripts/save_conversation.sh <שם> < conversation.md      # מקובץ / stdin
#   pbpaste | scripts/save_conversation.sh hackathon-pitch    # מהלוח (mac)
#   scripts/save_conversation.sh <שם> path/to/file.md         # מקובץ בנתיב
#
# דגלים:
#   --push    גם דוחף לענף הנוכחי אחרי ה-commit
set -euo pipefail

push=0
args=()
for a in "$@"; do
  case "$a" in
    --push) push=1 ;;
    *) args+=("$a") ;;
  esac
done

if [ "${#args[@]}" -lt 1 ]; then
  echo "usage: $0 [--push] <name> [file.md]  (or pipe content on stdin)" >&2
  exit 1
fi

name="${args[0]}"
src="${args[1]:-/dev/stdin}"

repo_root="$(git rev-parse --show-toplevel)"
out_dir="$repo_root/docs/conversations"
mkdir -p "$out_dir"

date="$(date +%Y-%m-%d)"
slug="$(printf '%s' "$name" | tr '[:upper:] ' '[:lower:]-' | tr -cd '[:alnum:]_-')"
out="$out_dir/$date-$slug.md"

{
  printf '# שיחה · %s\n\n' "$name"
  printf '> נשמר ב-%s באמצעות `scripts/save_conversation.sh`.\n\n---\n\n' "$date"
  cat "$src"
} > "$out"

echo "saved: ${out#$repo_root/}"

cd "$repo_root"
git add "$out"
git commit -q -m "docs: save conversation '$name' ($date)"
echo "committed on branch $(git branch --show-current)"

if [ "$push" -eq 1 ]; then
  git push -u origin "$(git branch --show-current)"
fi
