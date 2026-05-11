#!/usr/bin/env bash
# xray-test-suite — automatic configuration setup
#
# Bootstraps config.json + ~/.claude/.xray-credentials.json from the bundled
# .sample.json files, then writes any provided values into them.
#
# USAGE
#   bash scripts/xray-setup.sh                                            # interactive (terminal only)
#   bash scripts/xray-setup.sh --cloud-id X --project-key Y ...           # non-interactive (CI / Claude)
#   XRAY_CLOUD_ID=X XRAY_PROJECT_KEY=Y bash scripts/xray-setup.sh         # env-var driven
#   bash scripts/xray-setup.sh --force                                    # overwrite existing files
#
# All env-var inputs use the XRAY_ prefix (XRAY_CLOUD_ID, XRAY_USERNAME, XRAY_PROJECT_KEY,
# XRAY_PROJECT_NAME, XRAY_IMPORT_URL, XRAY_API_TOKEN, XRAY_CLIENT_ID, XRAY_CLIENT_SECRET).
# This avoids collisions with system env vars like USERNAME (Windows) or PROJECT_KEY (some CIs).
#
# EXIT CODES
#   0  Fully configured (no placeholders remain).
#   1  Hard error (sample files missing — plugin not installed correctly).
#   2  Files staged but placeholders remain (user input still needed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REFS="$PLUGIN_ROOT/skills/xray-test-suite/references"
CONFIG="$REFS/config.json"
CONFIG_SAMPLE="$REFS/config.sample.json"
CREDS="${HOME}/.claude/.xray-credentials.json"
CREDS_SAMPLE="$REFS/credentials.sample.json"

[ -f "$CONFIG_SAMPLE" ] || { echo "ERROR: $CONFIG_SAMPLE not found — is the plugin installed correctly?" >&2; exit 1; }
[ -f "$CREDS_SAMPLE"  ] || { echo "ERROR: $CREDS_SAMPLE not found — is the plugin installed correctly?" >&2; exit 1; }

CLOUD_ID="${XRAY_CLOUD_ID:-}"
USERNAME="${XRAY_USERNAME:-}"
PROJECT_KEY="${XRAY_PROJECT_KEY:-}"
PROJECT_NAME="${XRAY_PROJECT_NAME:-}"
IMPORT_URL="${XRAY_IMPORT_URL:-}"
API_TOKEN="${XRAY_API_TOKEN:-}"
XRAY_CLIENT_ID="${XRAY_CLIENT_ID:-}"
XRAY_CLIENT_SECRET="${XRAY_CLIENT_SECRET:-}"
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --cloud-id)           CLOUD_ID="$2"; shift 2 ;;
    --username)           USERNAME="$2"; shift 2 ;;
    --project-key)        PROJECT_KEY="$2"; shift 2 ;;
    --project-name)       PROJECT_NAME="$2"; shift 2 ;;
    --xray-import-url)    IMPORT_URL="$2"; shift 2 ;;
    --api-token)          API_TOKEN="$2"; shift 2 ;;
    --xray-client-id)     XRAY_CLIENT_ID="$2"; shift 2 ;;
    --xray-client-secret) XRAY_CLIENT_SECRET="$2"; shift 2 ;;
    --force)              FORCE=1; shift ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [ ! -f "$CONFIG" ] || [ "$FORCE" -eq 1 ]; then
  cp "$CONFIG_SAMPLE" "$CONFIG"
  echo "Created: $CONFIG"
fi

mkdir -p "$(dirname "$CREDS")"
if [ ! -f "$CREDS" ] || [ "$FORCE" -eq 1 ]; then
  cp "$CREDS_SAMPLE" "$CREDS"
  chmod 600 "$CREDS" 2>/dev/null || true
  echo "Created: $CREDS"
fi

prompt() {
  local var="$1" msg="$2" default="${3:-}"
  if [ -t 0 ] && [ -z "${!var}" ]; then
    if [ -n "$default" ]; then
      read -rp "$msg [$default]: " input
      eval "$var=\"\${input:-$default}\""
    else
      read -rp "$msg: " input
      eval "$var=\"\$input\""
    fi
  fi
}
prompt_secret() {
  local var="$1" msg="$2"
  if [ -t 0 ] && [ -z "${!var}" ]; then
    read -rsp "$msg: " input
    echo
    eval "$var=\"\$input\""
  fi
}

prompt CLOUD_ID     "Atlassian cloudId (hostname or UUID)"
prompt USERNAME     "Atlassian username (work email)"
prompt PROJECT_KEY  "Jira project key (e.g. FIFAGEN)"
prompt PROJECT_NAME "Jira project display name" "${PROJECT_KEY:-}"
prompt IMPORT_URL   "Xray Test Case Importer URL"
prompt_secret API_TOKEN "Atlassian API token"
prompt XRAY_CLIENT_ID "Xray Cloud Client ID (optional, press enter to skip)"
[ -n "${XRAY_CLIENT_ID}" ] && prompt_secret XRAY_CLIENT_SECRET "Xray Cloud Client Secret"

PYTHON_CMD="python3"
command -v python3 >/dev/null 2>&1 || PYTHON_CMD="python"
command -v "$PYTHON_CMD" >/dev/null 2>&1 || { echo "ERROR: python/python3 not found in PATH" >&2; exit 1; }

if [ -n "${CLOUD_ID}${USERNAME}${PROJECT_KEY}${PROJECT_NAME}${IMPORT_URL}" ]; then
  CLOUD_ID="$CLOUD_ID" USERNAME="$USERNAME" \
  PROJECT_KEY="$PROJECT_KEY" PROJECT_NAME="$PROJECT_NAME" \
  IMPORT_URL="$IMPORT_URL" CONFIG_FILE="$CONFIG" \
  "$PYTHON_CMD" - <<'PY'
import json, os
p = os.environ["CONFIG_FILE"]
with open(p) as f: c = json.load(f)
def s(d, k, v):
    if not v: return
    keys = k.split(".")
    for kk in keys[:-1]:
        if kk not in d or not isinstance(d[kk], dict):
            d[kk] = {}
        d = d[kk]
    d[keys[-1]] = v
s(c, "atlassian.cloudId",  os.environ.get("CLOUD_ID"))
s(c, "atlassian.username", os.environ.get("USERNAME"))
s(c, "project.key",        os.environ.get("PROJECT_KEY"))
s(c, "project.name",       os.environ.get("PROJECT_NAME"))
s(c, "xrayImport.url",     os.environ.get("IMPORT_URL"))
with open(p, "w") as f:
    json.dump(c, f, indent=2)
    f.write("\n")
PY
  echo "Updated: $CONFIG"
fi

if [ -n "${API_TOKEN}${XRAY_CLIENT_ID}${XRAY_CLIENT_SECRET}" ]; then
  API_TOKEN="$API_TOKEN" XRAY_CLIENT_ID="$XRAY_CLIENT_ID" \
  XRAY_CLIENT_SECRET="$XRAY_CLIENT_SECRET" CREDS_FILE="$CREDS" \
  "$PYTHON_CMD" - <<'PY'
import json, os
p = os.environ["CREDS_FILE"]
with open(p) as f: c = json.load(f)
def s(d, k, v):
    if not v: return
    keys = k.split(".")
    for kk in keys[:-1]:
        if kk not in d or not isinstance(d[kk], dict):
            d[kk] = {}
        d = d[kk]
    d[keys[-1]] = v
s(c, "atlassian.apiToken",       os.environ.get("API_TOKEN"))
s(c, "xrayCloud.clientId",       os.environ.get("XRAY_CLIENT_ID"))
s(c, "xrayCloud.clientSecret",   os.environ.get("XRAY_CLIENT_SECRET"))
with open(p, "w") as f:
    json.dump(c, f, indent=2)
    f.write("\n")
PY
  echo "Updated: $CREDS"
fi

echo
echo "=== Validation ==="
PLACEHOLDERS=0
if grep -q '"<' "$CONFIG"; then
  echo "WARN: $CONFIG still has placeholder <...> values."
  PLACEHOLDERS=1
fi
if grep -q '"<' "$CREDS"; then
  echo "WARN: $CREDS still has placeholder <...> values."
  PLACEHOLDERS=1
fi
if [ "$PLACEHOLDERS" -eq 1 ]; then
  echo
  echo "Re-run with the missing values:"
  echo "  bash $0 --cloud-id <id> --username <email> --project-key <KEY> \\"
  echo "    --xray-import-url <url> --api-token <token> [--xray-client-id <id> --xray-client-secret <secret>]"
  exit 2
fi
echo "OK — config and credentials populated, no placeholders remain."
