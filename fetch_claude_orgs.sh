#!/bin/bash

# Check if claude-sessionkey.txt exists
if [ ! -f claude-sessionkey.txt ]; then
    echo "Error: claude-sessionkey.txt file not found."
    exit 1
fi

# Prepare CSV header
echo "\"SessionKey\",\"Name\",\"Capabilities\""

# Read session keys from claude-sessionkey.txt
while read -r sessionKey; do
    # Skip empty lines
    if [ -z "$sessionKey" ]; then
        continue
    fi

    # Output debug info
    echo "Processing session key: $sessionKey" >&2

    # Make curl request with the session key
    response=$(curl -s 'https://api.claude.ai/api/organizations' \
      -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8' \
      -H 'accept-language: en-US,en;q=0.9' \
      -H 'cache-control: max-age=0' \
      -H "cookie: sessionKey=$sessionKey" \
      -H 'user-agent: Mozilla/5.0 (X11; Linux x86_64)' \
      -H 'sec-fetch-mode: navigate' \
      -H 'sec-fetch-site: none' \
      --compressed)

    # Output debug info
    echo "Response: $response" >&2

    # Remove newlines and spaces from response
    response=$(echo "$response" | tr -d '\n\t ')

    # Check if response is valid
    if echo "$response" | grep -i -q 'unauthorized'; then
        echo "Invalid session key: $sessionKey" >&2
        continue
    fi

    # Check if response is empty
    if [ -z "$response" ]; then
        echo "No response for session key: $sessionKey" >&2
        continue
    fi

    # Remove surrounding square brackets
    objects=$(echo "$response" | sed 's/^\[\(.*\)\]$/\1/')

    # Split objects at '},{' by replacing '},{' with '}\n{'
    objects=$(echo "$objects" | sed 's/},{/}\n{/g')

    # Process each JSON object
    echo "$objects" | while read -r object; do
        # Extract 'name' field
        name=$(echo "$object" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
        # Extract 'capabilities' field
        capabilities=$(echo "$object" | sed -n 's/.*"capabilities":\[\([^]]*\)\].*/\1/p')

        # Skip if name not found
        if [ -z "$name" ]; then
            echo "Name not found in response for session key: $sessionKey" >&2
            continue
        fi

        # Format capabilities
        capabilities=$(echo "$capabilities" | tr -d '"' | tr ',' ';')

        # Escape double quotes in name and capabilities
        name=$(echo "$name" | sed 's/"/""/g')
        capabilities=$(echo "$capabilities" | sed 's/"/""/g')

        # Output CSV line
        echo "\"$sessionKey\",\"$name\",\"$capabilities\""
    done

done < claude-sessionkey.txt
