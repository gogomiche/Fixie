#!/bin/bash
# Builds and runs the editor QA harness (no Xcode needed, Command Line Tools suffice).
# Compares the current converters with those of a base git ref (default: main).
# Usage: Tools/EditorQA/run.sh [base-ref] [report.md]
set -euo pipefail
cd "$(dirname "$0")/../.."

BASE_REF="${1:-main}"
REPORT="${2:-}"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# Previous implementation, renamed so both can be compared side by side.
git show "$BASE_REF:Fixie/Utilities/HTMLToMarkdown.swift" \
  | sed 's/enum HTMLToMarkdown/enum LegacyHTMLToMarkdown/' > "$BUILD/LegacyHTMLToMarkdown.swift"
git show "$BASE_REF:Fixie/Utilities/QuillDeltaParser.swift" \
  | sed 's/enum QuillDeltaParser/enum LegacyQuillDeltaParser/' > "$BUILD/LegacyQuillDeltaParser.swift"

swiftc -O -o "$BUILD/editor-qa" \
  Fixie/Utilities/HTMLToMarkdown.swift \
  Fixie/Utilities/MarkdownToHTML.swift \
  Fixie/Utilities/QuillDeltaParser.swift \
  Fixie/Utilities/AppClassifier.swift \
  Fixie/Utilities/ClipboardManager.swift \
  "$BUILD/LegacyHTMLToMarkdown.swift" \
  "$BUILD/LegacyQuillDeltaParser.swift" \
  Tools/EditorQA/main.swift

"$BUILD/editor-qa" "Tools/EditorQA/pages" ${REPORT:+"$REPORT"}
