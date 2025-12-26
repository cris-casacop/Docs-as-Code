#!/usr/bin/env bash
set -euo pipefail

echo "Starting Docs-as-Code publish to Confluence"

MAP_FILE="docs/.confluence-map.json"

if [[ ! -f "$MAP_FILE" ]]; then
  echo "ERROR: $MAP_FILE not found"
  exit 1
fi

for file in docs/*.md; do
  filename=$(basename "$file")

  PAGE_ID=$(jq -r --arg file "$filename" '.[$file] // empty' "$MAP_FILE")

  if [[ -z "$PAGE_ID" ]]; then
    echo "Skipping $filename (no page ID mapping)"
    continue
  fi

  TITLE=$(sed 's/\.md$//' <<< "$filename" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

  echo "Publishing $filename → Page ID $PAGE_ID ($TITLE)"

  pandoc "$file" -f markdown -t html -o page.html

  PAGE_RESPONSE=$(curl -s \
    -u "$CONFLUENCE_USER:$CONFLUENCE_API_TOKEN" \
    "$CONFLUENCE_BASE_URL/wiki/rest/api/content/$PAGE_ID?expand=version")

  CURRENT_VERSION=$(echo "$PAGE_RESPONSE" | jq -r '.version.number')
  NEXT_VERSION=$((CURRENT_VERSION + 1))

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

  echo "Updated page $PAGE_ID successfully"
done

echo "Docs-as-Code publish completed"
