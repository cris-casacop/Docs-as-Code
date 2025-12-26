#!/usr/bin/env bash
set -euo pipefail

echo "=== Docs-as-Code publish started (label-based) ==="

# Ensure docs directory exists
if [[ ! -d "docs" ]]; then
  echo "ERROR: docs/ directory not found"
  exit 1
fi

shopt -s nullglob
FILES=(docs/*.md)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No Markdown files found. Nothing to publish."
  exit 0
fi

for file in "${FILES[@]}"; do
  filename=$(basename "$file")

  TITLE=$(echo "${filename%.md}" \
    | sed 's/-/ /g' \
    | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

  LABEL="docs-${filename%.md}"

  echo "Processing $file → $TITLE (label: $LABEL)"

  pandoc "$file" -f markdown -t html -o page.html

  # 🔍 Look up page by label (NOT title)
  SEARCH=$(curl -s \
    -u "$CONFLUENCE_USER:$CONFLUENCE_API_TOKEN" \
    "$CONFLUENCE_BASE_URL/wiki/rest/api/content/search?cql=label=${LABEL}")

  PAGE_ID=$(echo "$SEARCH" | jq -r '.results[0].id // empty')

  if [[ -z "$PAGE_ID" ]]; then
    echo "Creating page: $TITLE"

    jq -n \
      --arg title "$TITLE" \
      --arg space "$CONFLUENCE_SPACE_KEY" \
      --arg parent "$PARENT_PAGE_ID" \
      --arg label "$LABEL" \
      --rawfile body page.html \
      '{
        type: "page",
        title: $title,
        space: { key: $space },
        ancestors: [ { id: $parent } ],
        metadata: {
          labels: [
            { prefix: "global", name: $label }
          ]
        },
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
    echo "Updating page: $TITLE (ID: $PAGE_ID)"

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
  fi
done

echo "=== Docs-as-Code publish completed ==="
