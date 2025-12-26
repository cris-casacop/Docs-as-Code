#!/usr/bin/env bash
set -euo pipefail

echo "=== Docs-as-Code publish started ==="

# Fail early if docs folder does not exist
if [[ ! -d "docs" ]]; then
  echo "ERROR: docs/ directory not found"
  exit 1
fi

# Ensure at least one Markdown file exists
shopt -s nullglob
FILES=(docs/*.md)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No Markdown files found in docs/"
  exit 0
fi

for file in "${FILES[@]}"; do
  filename=$(basename "$file")

  TITLE=$(echo "${filename%.md}" \
    | sed 's/-/ /g' \
    | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

  echo "Processing: $file → $TITLE"

  pandoc "$file" -f markdown -t html -o page.html

  # Look up page by title
  SEARCH_URL="${CONFLUENCE_BASE_URL}/wiki/rest/api/content?title=${TITLE}&spaceKey=${CONFLUENCE_SPACE_KEY}"

  SEARCH_RESPONSE=$(curl -s \
    -u "$CONFLUENCE_USER:$CONFLUENCE_API_TOKEN" \
    "$SEARCH_URL")

  PAGE_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.results[0].id // empty')
  PAGE_VERSION=$(echo "$SEARCH_RESPONSE" | jq -r '.results[0].version.number // 0')

  if [[ -z "$PAGE_ID" ]]; then
    echo "Creating page: $TITLE"

    jq -n \
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
      }' > payload.json

    curl -s \
      -u "$CONFLUENCE_USER:$CONFLUENCE_API_TOKEN" \
      -X POST \
      -H "Content-Type: application/json" \
      "$CONFLUENCE_BASE_URL/wiki/rest/api/content" \
      --data @payload.json

  else
    NEXT_VERSION=$((PAGE_VERSION + 1))
    echo "Updating page: $TITLE (ID: $PAGE_ID → v$NEXT_VERSION)"

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
  fi
done

echo "=== Docs-as-Code publish completed ==="
