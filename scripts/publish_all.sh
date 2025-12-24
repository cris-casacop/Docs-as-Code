#!/usr/bin/env bash
set -euo pipefail

echo "Starting Docs-as-Code publish to Confluence (auto-create enabled)"

MAP_FILE="docs/.confluence-map.json"

for file in docs/*.md; do
  filename=$(basename "$file")

  TITLE=$(sed 's/\.md$//' <<< "$filename" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

  echo "Processing $filename → $TITLE"

  pandoc "$file" -f markdown -t html -o page.html

  PAGE_ID=""

  # Try to read page ID from map if it exists
  if [[ -f "$MAP_FILE" ]]; then
    PAGE_ID=$(jq -r --arg file "$filename" '.[$file] // empty' "$MAP_FILE")
  fi

  if [[ -n "$PAGE_ID" ]]; then
    echo "Updating existing page (ID: $PAGE_ID)"

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

  else
    echo "Creating new page (no mapping found)"

    RESPONSE=$(jq -n \
      --arg title "$TITLE" \
      --arg space "$CONFLUENCE_SPACE_KEY" \
      --arg parent "$PARENT_PAGE_ID" \
      --rawfile body page.html \
      '{
        type: "page",
        title: $title,
        space: { key: $space },
        ancestors: [ { id: $parent } ],
        body: {
          storage: {
            value: $body,
            representation: "storage"
          }
        }
      }' \
      | curl -s \
          -u "$CONFLUENCE_USER:$CONFLUENCE_API_TOKEN" \
          -X POST \
          -H "Content-Type: application/json" \
          "$CONFLUENCE_BASE_URL/wiki/rest/api/content" \
          --data @-)

    NEW_PAGE_ID=$(echo "$RESPONSE" | jq -r '.id')

    echo "Created page '$TITLE' with ID: $NEW_PAGE_ID"
    echo "👉 Optional: add this to docs/.confluence-map.json"

  fi
done

echo "Docs-as-Code publish completed"
