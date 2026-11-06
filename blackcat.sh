#!/usr/bin/env bash

# Author: Haitham Aouati
# GitHub: github.com/haithamaouati

# Colors
nc="\e[0m"
bold="\e[1m"
underline="\e[4m"
bold_green="\e[1;32m"
bold_red="\e[1;31m"
bold_yellow="\e[1;33m"

# Function to display help menu
show_help() {
    echo "Usage: $0 [OPTIONS] [URL]"
    echo ""
    echo "Options:"
    echo "  -u, --url <url>    Specify the TikTok video URL"
    echo "  -h, --help         Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 https://www.tiktok.com/@user/video/123456789"
    echo "  $0 -u https://www.tiktok.com/@user/video/123456789"
    exit 0
}

# Parse command-line arguments
URL=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -u|--url)
            URL="$2"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information."
            exit 1
            ;;
        *)
            URL="$1"
            ;;
    esac
    shift
done

# Check if URL is provided
if [[ -z "$URL" ]]; then
    echo "Error: TikTok video URL is required."
    echo "Usage: $0 [-u|--url] <tiktok-video-url> (or use -h for help)"
    exit 1
fi

# Extract username from URL
USERNAME=$(echo "$URL" | grep -o '@[^/?]*' | tr -d '@')
[[ -z "$USERNAME" ]] && USERNAME="unknown"

# 1. Clear screen before displaying the ASCII art banner
clear

# 2. Display ASCII Art Banner
print_banner() {
clear
echo -e "${bold}"
echo -e "    /\\___/\\"
echo -e "    )     ("
echo -e "   =\     /="
echo -e "     )   ("
echo -e "    /     \\   ${bold_green}$0${nc}${bold}"
echo -e "    )     (   ${nc}TikTok User Region Scraper${bold}"
echo -e "   /       \\  ${nc}Author: Haitham Aouati${bold}"
echo -e "   \       /  ${nc}GitHub: ${underline}github.com/haithamaouati${nc}${bold}"
echo -e "    \__ __/"
echo -e "       ))"
echo -e "      //"
echo -e "     (("
echo -e "      \)${nc}"
}

print_banner

# 3. Display message and wait 10 seconds before fetching
echo -e "\nRetrieving the region for user ${bold_green}@$USERNAME${nc}...\n"
sleep 10

CREATOR_REGION=""
VIEWER_REGION=""

# Fetch HTML with full desktop browser headers
HTML=$(curl -s -L \
    -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8" \
    -H "Accept-Language: ar,en-US;q=0.9,en;q=0.8" \
    -H "Sec-Ch-Ua: \"Chromium\";v=\"122\", \"Not(A:Brand\";v=\"8\", \"Google Chrome\";v=\"122\"" \
    -H "Sec-Ch-Ua-Mobile: ?0" \
    -H "Sec-Ch-Ua-Platform: \"Windows\"" \
    -H "Sec-Fetch-Dest: document" \
    -H "Sec-Fetch-Mode: navigate" \
    -H "Sec-Fetch-Site: none" \
    -H "Sec-Fetch-User: ?1" \
    -H "Upgrade-Insecure-Requests: 1" \
    "$URL")

if [[ -n "$HTML" ]]; then
    # 1. Try extracting via jq from script blocks
    while IFS= read -r script_content; do
        [[ -z "$script_content" ]] && continue
        if [[ -z "$CREATOR_REGION" || "$CREATOR_REGION" == "null" ]]; then
            CREATOR_REGION=$(echo "$script_content" | jq -r '.. | objects | select(.locationCreated?) | .locationCreated' 2>/dev/null | head -n 1)
        fi
        if [[ -z "$VIEWER_REGION" || "$VIEWER_REGION" == "null" ]]; then
            VIEWER_REGION=$(echo "$script_content" | jq -r '.. | objects | select(has("webapp.app-context")) | .["webapp.app-context"].region' 2>/dev/null | head -n 1)
        fi
        [[ -n "$CREATOR_REGION" && "$CREATOR_REGION" != "null" && -n "$VIEWER_REGION" && "$VIEWER_REGION" != "null" ]] && break
    done < <(echo "$HTML" | grep -o '<script[^>]*>.*?</script>' | sed 's/<script[^>]*>//;s/<\/script>//')

    # 2. Robust Regex Fallback directly on HTML source
    if [[ -z "$CREATOR_REGION" || "$CREATOR_REGION" == "null" ]]; then
        CREATOR_REGION=$(echo "$HTML" | grep -o '"locationCreated"[[:space:]]*:[[:space:]]*"[A-Za-z]\{2\}"' | head -n 1 | cut -d'"' -f4)
    fi

    if [[ -z "$VIEWER_REGION" || "$VIEWER_REGION" == "null" ]]; then
        VIEWER_REGION=$(echo "$HTML" | grep -o '"region"[[:space:]]*:[[:space:]]*"[A-Za-z]\{2\}"' | head -n 1 | cut -d'"' -f4)
    fi
fi

# Fallback defaults
[[ -z "$CREATOR_REGION" || "$CREATOR_REGION" == "null" ]] && CREATOR_REGION="N/A"
[[ -z "$VIEWER_REGION" || "$VIEWER_REGION" == "null" ]] && VIEWER_REGION="N/A"

# Function to look up country name dynamically using strictly countries.json[span_0](start_span)[span_0](end_span)
get_country_name() {
    local code="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
    if [[ "$code" == "N/A" || -z "$code" ]]; then
        echo "N/A"
        return
    fi

    if [[ -f "countries.json" ]]; then
        local country_name=$(jq -r --arg c "$code" '.[] | select(.code == $c) | .name' countries.json 2>/dev/null)
        if [[ -n "$country_name" && "$country_name" != "null" ]]; then
            echo "$country_name"
            return
        fi
    fi

    echo "$code"
}

CREATOR_COUNTRY=$(get_country_name "$CREATOR_REGION")
VIEWER_COUNTRY=$(get_country_name "$VIEWER_REGION")

# Output formatting using column
printf "Type\tCode\tCountry\nCreator Region\t%s\t%s\nViewer Region\t%s\t%s\n" \
    "$CREATOR_REGION" "$CREATOR_COUNTRY" \
    "$VIEWER_REGION" "$VIEWER_COUNTRY" | column -t -s $'\t'
echo
