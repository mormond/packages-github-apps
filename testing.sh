#!/usr/bin/env bash
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

set -o pipefail
client_id=$CLIENT_ID # Client ID as first argument

pem=$( cat $1 ) # file path of the private key as second argument

now=$(date +%s)
iat=$((${now} - 60)) # Issues 60 seconds in the past
exp=$((${now} + 600)) # Expires 10 minutes in the future

echo "iat (issued at): $iat ($(date -u -r $iat))"
echo "exp (expires at): $exp ($(date -u -r $exp))"

b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

header_json='{
    "typ":"JWT",
    "alg":"RS256"
}'
# Header encode
header=$( echo -n "${header_json}" | b64enc )

payload_json="{
    \"iat\":${iat},
    \"exp\":${exp},
    \"iss\":\"${client_id}\"
}"
# Payload encode
payload=$( echo -n "${payload_json}" | b64enc )

# Signature
header_payload="${header}"."${payload}"
signature=$(
    openssl dgst -sha256 -sign <(echo -n "${pem}") \
    <(echo -n "${header_payload}") | b64enc
)

# Create JWT
JWT="${header_payload}"."${signature}"
printf '%s\n' "JWT: $JWT"

printf "Authorization: Bearer $JWT"

INST=$(curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $JWT" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/app/installations)

if [ -z "$INST" ]; then
  echo "No installations found or error fetching installations."
  exit 1
fi
echo "Installations fetched successfully."  

INSTALL_ID=$(jq -r '.[].id' <<< "$INST")
echo "Installation ID: $INSTALL_ID"

INSTALLATION_ACCESS_TOKEN=$(curl -X POST \
   -H "Authorization: Bearer $JWT" \
   -H "Accept: application/vnd.github+json" \
   -H "X-GitHub-Api-Version: 2022-11-28" \
   https://api.github.com/app/installations/$INSTALL_ID/access_tokens)

echo $INSTALLATION_ACCESS_TOKEN 
echo $APP_ID

PASS=$(jq -r '.token' <<< "$INSTALLATION_ACCESS_TOKEN")
echo $PASS

echo "$PASS" | docker login -u "$APP_ID" --password-stdin ghcr.io  
