#!/usr/bin/env bash
#
# Apply the agreed text fixes in the WordPress database with WP-CLI.
# Sukh Mantra Ayurveda (tracker: UPD-041). The wording matches the "Content Fixes" sheet.
#
# Usage (run on STAGING first, from a shell where the "wp" command works):
#   bash tools/apply_content_fixes.sh                        # dry run: shows what WOULD change, changes nothing
#   bash tools/apply_content_fixes.sh --include-approved     # dry run including the fixes that need client approval
#   bash tools/apply_content_fixes.sh --apply                # make the safe changes (asks you to confirm)
#   bash tools/apply_content_fixes.sh --apply --include-approved --yes
#
# Options:
#   --apply             make the changes. Without it nothing is ever changed.
#   --include-approved  also include the fixes that need the client's OK. Only use after the client approves them.
#   --yes               do not ask for confirmation before applying.
#   --path DIR          WordPress folder, if you are not already inside it.
#   -h, --help          show this help.
#
# Safety:
#   - Default is a dry run. Read the counts before applying anything.
#   - Before applying it saves a database backup in ./backups/ (SQL files are ignored by Git).
#   - Each fix is a plain text swap, so check the dry-run counts first. Expect a small number of matches
#     per fix (the "PITA" heading, for example, should match once or twice). A very large number means
#     the text is appearing somewhere unexpected: stop and check.
#   - The health-related Dosha Test question is NOT included. It needs the client and a legal adviser.
#   - Do not run this on the live site until it has been tried on staging.

set -euo pipefail

APPLY=0
INCLUDE_APPROVED=0
ASSUME_YES=0
WP_PATH=""

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1 ;;
        --include-approved) INCLUDE_APPROVED=1 ;;
        --yes) ASSUME_YES=1 ;;
        --path)
            [ $# -ge 2 ] || { echo "--path needs a folder" >&2; exit 2; }
            WP_PATH="$2"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if ! command -v wp > /dev/null 2>&1; then
    echo "WP-CLI (the \"wp\" command) was not found." >&2
    echo "Ask the host to enable it, or use the Better Search Replace plugin with the pairs on the Content Fixes sheet." >&2
    exit 1
fi

WP=(wp)
if [ -n "$WP_PATH" ]; then
    WP+=("--path=$WP_PATH")
fi

# Fixes that are safe to apply without asking: "old|new|tracker item".
SAFE=(
    "PITA|PITTA|UPD-004"
    "Ayurvedic Ayurvedic|Ayurvedic|UPD-005"
)

# Fixes that need the client's OK first: "old|new|tracker item".
NEEDS_OK=(
    "We treatments remove|Our treatments cannot remove|UPD-006"
    "lasts 69 minutes|lasts 90 minutes|UPD-002"
    "Prishtabhyanga|Prishta Abhyanga|UPD-007"
    "Prishtha|Prishta|UPD-007"
    "Sukhmantra Ayurveda|Sukh Mantra Ayurveda|UPD-028"
    "natural nature|natural constitution|UPD-025"
)

PAIRS=("${SAFE[@]}")
if [ "$INCLUDE_APPROVED" -eq 1 ]; then
    PAIRS+=("${NEEDS_OK[@]}")
fi

if [ "$APPLY" -eq 1 ]; then
    MODE="APPLY (changes the database)"
else
    MODE="DRY RUN (changes nothing)"
fi
echo "Site:  $("${WP[@]}" option get siteurl)"
echo "Mode:  $MODE"
echo "Fixes: ${#PAIRS[@]} ($([ "$INCLUDE_APPROVED" -eq 1 ] && echo "including those that need client approval" || echo "safe fixes only"))"
echo

if [ "$APPLY" -eq 1 ]; then
    if [ "$ASSUME_YES" -ne 1 ]; then
        read -r -p "Apply these ${#PAIRS[@]} fixes to the site above? Type yes to continue: " answer
        if [ "$answer" != "yes" ]; then
            echo "Cancelled. Nothing was changed."
            exit 0
        fi
    fi
    mkdir -p backups
    BACKUP="backups/before-content-fixes-$(date +%Y%m%d-%H%M%S).sql"
    echo "Saving a database backup to $BACKUP ..."
    "${WP[@]}" db export "$BACKUP"
    echo
fi

for pair in "${PAIRS[@]}"; do
    IFS='|' read -r old new item <<< "$pair"
    echo "--- $item: \"$old\" -> \"$new\""
    ARGS=(search-replace "$old" "$new" --all-tables --skip-columns=guid --precise --report-changed-only)
    if [ "$APPLY" -ne 1 ]; then
        ARGS+=(--dry-run)
    fi
    "${WP[@]}" "${ARGS[@]}"
    echo
done

if [ "$APPLY" -eq 1 ]; then
    echo "Refreshing Elementor styles and the object cache ..."
    "${WP[@]}" elementor flush-css || echo "(Elementor's flush-css command was not available: use Elementor > Tools > Regenerate CSS.)"
    "${WP[@]}" cache flush || true
    echo "Done. Clear any page-cache plugin too, then look at the pages and re-run tools/qa_smoke_test.py."
else
    echo "Dry run finished. Nothing was changed. Add --apply when the counts look right."
fi
