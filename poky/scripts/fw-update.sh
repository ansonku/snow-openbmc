#!/usr/bin/env bash
# Simulate PLDM firmware update flow:
#   1. Create metadata JSON
#   2. Generate random fw binary
#   3. Build .pkg with pldm_fwup_pkg_creator
#   4. SCP package to BMC
#   5. Query current fw version via Redfish
#   6. Trigger update via Redfish
#   7. Poll progress every 3 s
#   8. Restart pldmd on BMC after completion
#   9. Query updated fw version via Redfish

set -euo pipefail

# ── Default parameters ────────────────────────────────────────────────────────
HOST="127.0.0.1"
HTTPS_PORT="10443"
SSH_PORT="10022"
USER="root"
PASS="0penBmc"
INTERVAL=1

METADATA="/tmp/sim_metadata.json"
FW_BIN="/tmp/sim_fw_v2.bin"
PKG="/tmp/jm1000_sim_v2.pkg"
PLDM_TOOL="/home/anson/working/snow/snow-openbmc/build/ast2700-a1/tmp/work/cortexa35-openbmc-linux/pldm/1.0+git/sources/pldm-1.0+git/tools/fw-update/pldm_fwup_pkg_creator.py"

BASE_URL="https://${HOST}:${HTTPS_PORT}"
CURL=(curl -k -s -u "${USER}:${PASS}")
SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$SSH_PORT")

# ── Step 1: Create metadata JSON ──────────────────────────────────────────────
echo "==> [1/9] 建立 ${METADATA}"
cat > "$METADATA" <<'EOF'
{
  "PackageHeaderInformation": {
    "PackageHeaderIdentifier": "F018878CCB7D49439800A02F059ACA02",
    "PackageHeaderFormatVersion": 1,
    "PackageVersionString": "2.0.0"
  },
  "FirmwareDeviceIdentificationArea": [
    {
      "DeviceUpdateOptionFlags": [
        0
      ],
      "ComponentImageSetVersionString": "2.0.0",
      "ApplicableComponents": [
        0
      ],
      "Descriptors": [
        {
          "DescriptorType": 0,
          "DescriptorData": "7B19"
        }
      ]
    }
  ],
  "ComponentImageInformationArea": [
    {
      "ComponentClassification": 10,
      "ComponentIdentifier": 1,
      "ComponentOptions": [
        0
      ],
      "RequestedComponentActivationMethod": [
        1
      ],
      "ComponentVersionString": "2.0.0"
    }
  ]
}
EOF
echo "    完成：${METADATA}"

# ── Step 2: Generate random fw binary ────────────────────────────────────────
echo ""
read -rp "==> [2/9] 請輸入 fw image 大小 (MB，可含小數，e.g. 1.5): " MB_INPUT

# Convert MB to bytes, then compute dd count (512-byte blocks)
# Use awk for floating-point math
BYTE_COUNT=$(awk "BEGIN { printf \"%d\", ${MB_INPUT} * 1024 * 1024 + 0.5 }")
BLOCK_COUNT=$(awk "BEGIN { printf \"%d\", ${MB_INPUT} * 2048 + 0.5 }")  # 1 MB = 2048 blocks of 512 B

echo "    產生 ${MB_INPUT} MB (${BYTE_COUNT} bytes, ${BLOCK_COUNT} blocks × 512 B) → ${FW_BIN}"
dd if=/dev/urandom of="$FW_BIN" bs=512 count="$BLOCK_COUNT" 2>&1 | grep -v '^$' | sed 's/^/    /'
echo "    完成：${FW_BIN}  ($(du -sh "$FW_BIN" | cut -f1))"

# ── Step 3: Build PLDM package ────────────────────────────────────────────────
echo ""
echo "==> [3/9] 建立 PLDM 套件 ${PKG}"
if [[ ! -f "$PLDM_TOOL" ]]; then
    echo "    Error: pldm_fwup_pkg_creator.py 不存在：${PLDM_TOOL}" >&2
    exit 1
fi
python3 "$PLDM_TOOL" "$PKG" "$METADATA" "$FW_BIN"
echo "    完成：${PKG}  ($(du -sh "$PKG" | cut -f1))"

# ── Step 4: Query current fw version ─────────────────────────────────────────
echo ""
echo "==> [4/8] 查詢 BMC 目前韌體版本"
FW_INV=$("${CURL[@]}" "${BASE_URL}/redfish/v1/UpdateService/FirmwareInventory" 2>/dev/null || true)
MEMBERS=$(echo "$FW_INV" | grep -o '"@odata.id"[[:space:]]*:[[:space:]]*"[^"]*FirmwareInventory/[^"]*"' \
    | grep -o '/redfish/[^"]*' || true)

if [[ -z "$MEMBERS" ]]; then
    echo "    (無法取得 FirmwareInventory，略過)"
else
    echo "    ┌─ Firmware Inventory ──────────────────────────────────"
    while IFS= read -r uri; do
        ITEM=$("${CURL[@]}" "${BASE_URL}${uri}" 2>/dev/null || true)
        NAME=$(echo "$ITEM"    | grep -o '"Name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | grep -o '"[^"]*"$' | tr -d '"')
        VERSION=$(echo "$ITEM" | grep -o '"Version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | grep -o '"[^"]*"$' | tr -d '"')
        printf "    │  %-40s  %s\n" "${NAME:-$(basename "$uri")}" "${VERSION:-(unknown)}"
    done <<< "$MEMBERS"
    echo "    └───────────────────────────────────────────────────────"
fi

# ── Step 6: Trigger Redfish update ───────────────────────────────────────────
echo ""
echo "==> [5/8] 呼叫 Redfish 觸發韌體更新"
RESPONSE=$("${CURL[@]}" -X POST \
    "${BASE_URL}/redfish/v1/UpdateService/update-multipart" \
    -F 'UpdateParameters={"@Redfish.OperationApplyTime":"Immediate"};type=application/json' \
    -F "UpdateFile=@${PKG};type=application/octet-stream" \
    -w "\n%{http_code}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" != "202" ]]; then
    echo "    Error: 更新請求失敗 (HTTP ${HTTP_CODE})" >&2
    echo "$BODY" >&2
    exit 1
fi

TASK_URI=$(echo "$BODY" | grep -o '"@odata.id"[[:space:]]*:[[:space:]]*"[^"]*Tasks/[0-9]*"' \
    | head -n1 | grep -o '/redfish/[^"]*' | tr -d '"')

if [[ -z "$TASK_URI" ]]; then
    echo "    Error: 無法從回應中解析 task URI" >&2
    echo "$BODY" >&2
    exit 1
fi

TASK_ID=$(basename "$TASK_URI")
echo "    Task ID: ${TASK_ID}  (${BASE_URL}${TASK_URI})"

# ── Step 7: Poll progress ────────────────────────────────────────────────────
echo ""
echo "==> [6/8] 輪詢更新進度（每 ${INTERVAL} 秒）..."

while true; do
    TASK_JSON=$("${CURL[@]}" "${BASE_URL}${TASK_URI}")

    PERCENT=$(echo "$TASK_JSON" | grep -o '"PercentComplete"[[:space:]]*:[[:space:]]*[0-9]*' \
        | grep -o '[0-9]*$' || echo "?")
    STATE=$(echo "$TASK_JSON"  | grep -o '"TaskState"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | grep -o '"[^"]*"$' | tr -d '"' || echo "Unknown")
    STATUS=$(echo "$TASK_JSON" | grep -o '"TaskStatus"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | grep -o '"[^"]*"$' | tr -d '"' || echo "Unknown")

    printf "    [%s] State: %-12s  Status: %-8s  Progress: %s%%\n" \
        "$(date '+%H:%M:%S')" "$STATE" "$STATUS" "$PERCENT"

    case "$STATE" in
        Completed)
            echo "    更新成功完成！"
            break
            ;;
        Exception|Killed|Cancelled)
            echo "    Error: 更新結束，狀態為 ${STATE}" >&2
            echo "$TASK_JSON" | grep -o '"Message"[[:space:]]*:[[:space:]]*"[^"]*"' \
                | grep -o '"[^"]*"$' | tr -d '"' | while IFS= read -r msg; do
                    echo "    $msg" >&2
                done
            exit 1
            ;;
    esac

    sleep "$INTERVAL"
done

# ── Step 8: Restart pldmd on BMC ─────────────────────────────────────────────
echo ""
echo "==> [7/8] SSH 進入 BMC 重啟 pldmd"
ssh "${SSH_OPTS[@]}" "${USER}@${HOST}" "systemctl restart pldmd && echo '    pldmd 重啟成功'"

# ── Step 9: Query updated fw version ─────────────────────────────────────────
echo ""
echo "==> [8/8] 查詢更新後韌體版本"
sleep 3   # 等 pldmd 重啟後穩定

FW_INV=$("${CURL[@]}" "${BASE_URL}/redfish/v1/UpdateService/FirmwareInventory" 2>/dev/null || true)
MEMBERS=$(echo "$FW_INV" | grep -o '"@odata.id"[[:space:]]*:[[:space:]]*"[^"]*FirmwareInventory/[^"]*"' \
    | grep -o '/redfish/[^"]*' || true)

if [[ -z "$MEMBERS" ]]; then
    echo "    (無法取得 FirmwareInventory)"
else
    echo "    ┌─ Firmware Inventory (更新後) ────────────────────────"
    while IFS= read -r uri; do
        ITEM=$("${CURL[@]}" "${BASE_URL}${uri}" 2>/dev/null || true)
        NAME=$(echo "$ITEM"    | grep -o '"Name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | grep -o '"[^"]*"$' | tr -d '"')
        VERSION=$(echo "$ITEM" | grep -o '"Version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | grep -o '"[^"]*"$' | tr -d '"')
        printf "    │  %-40s  %s\n" "${NAME:-$(basename "$uri")}" "${VERSION:-(unknown)}"
    done <<< "$MEMBERS"
    echo "    └───────────────────────────────────────────────────────"
fi

echo ""
echo "==> 完成！全部流程執行結束。"
