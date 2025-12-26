#!/usr/bin/env bash
set -euo pipefail

echo "=== Docs-as-Code publish started ==="

MAP_FILE="docs/.confluence-map.json"

if [[ ! -f "$MAP_FILE" ]]; then
  echo "ERROR: Missing $MAP_FILE"
  exit 1
fi

shopt -s nullglob
FILES=(docs/*.md)

for file in "${FILES[@]}"; do
  filename=$(basename "$file")

  PAGE_ID=$(jq -r --arg f "$filename" '.[$f] // empty' "$MAP_FILE")
  if [[ -z "$PAGE_ID" ]]; then
    echo "Skipping $filename (no page ID mapping)"
    continue
  fi

  TITLE=$(echo "${filename%.md}" \
    | sed 's/-/ /g' \
    | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

  echo "Updating $TITLE (ID: $PAGE_ID)"

  pandoc "$file" -f markdown -t html -o page.html

  # 🔒 FORCE A CONTENT CHANGE (THIS IS THE KEY)
  echo "<!-- Published by CI at $(date -u) -->" >> page.html

  PAGE_RESPONSE=$(curl -s \
    -u "$CONFLUENCE_USER:$CONFLUENCE_API_TOKEN" \
    "$CONFLUENCE_BASE_URL/wiki/rest/api/content/$PAGE_ID?expand=version")

  VERSION=$(echo "$PAGE_RESPONSE" | jq -r '.version.number')
  NEXT_VERSION=$((VERSION + 1))

  jq -n \
    --arg id "$PAGE_ID" \
    --arg title "$TITLE" \
    --arg parent "$PARENT_PAGE_ID" \
    --argjson version "$NEXT_VERSION" \
    --rawfile body page.html \
    '{
      id: $id,
      type: "page",
      title: $title,
      ancestors: [ { id: $parent } ],
      version: { number: $version },
      body: {
        storage: {
          value: $body,
          representation: "storage"
        }
      }
    }' > payload.json

  curl -s \
    -u "$CONFLUENCE_USER:$CONFLUENCE_API_TOKEN" \
    -X PUT \
    -H "Content-Type: application/json" \
    "$CONFLUENCE_BASE_URL/wiki/rest/api/content/$PAGE_ID" \
    --data @payload.json

done

echo "=== Docs-as-Code publish completed ==="
