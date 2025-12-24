#!/usr/bin/env bash
set -e

for file in docs/*.md; do
  filename=$(basename "$file")
  title=$(echo "${filename%.*}" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')

  echo "Publishing $file → $title"

  pandoc "$file" -f markdown -t html -o page.html

  API_URL="${CONFLUENCE_BASE_URL}/wiki/rest/api/content?title=${title}&spaceKey=${CONFLUENCE_SPACE_KEY}"
  RESPONSE=$(curl -s -u "$CONFLUENCE_USER:$CONFLUENCE_API_TOKEN" "$API_URL")

  PAGE_ID=$(echo "$RESPONSE" | jq -r '.results[0].id // empty')
  PAGE_VERSION=$(echo "$RESPONSE" | jq -r '.results[0].version.number // 0')

  if [ -z "$PAGE_ID" ]; then
    echo "Creating page: $title"

    jq -n \
      --arg title "$title" \
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
    echo "Updating page: $title"

    NEXT_VERSION=$((PAGE_VERSION + 1))

    jq -n \
      --arg title "$title" \
      --arg parent "$PARENT_PAGE_ID" \
      --argjson version "$NEXT_VERSION" \
      --rawfile body page.html \
      --argjson id "$PAGE_ID" \
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
