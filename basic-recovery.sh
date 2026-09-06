#!/usr/bin/env bash

set -o pipefail

# ============================================================
# FOREMOST RECOVERY TOOLKIT - BASIC RECOVERY
# Veilige interactieve recovery workflow voor Kali Linux
# ============================================================

EXTENSIONS="jpg,jpeg,avi,mp4,pdf,doc"
TYPE_CATEGORY="Standaard"

# ============================================================
# HULPFUNCTIES
# ============================================================

header() {
    clear
    echo "============================================================"
    echo "       FOREMOST RECOVERY TOOLKIT - BASIC RECOVERY"
    echo "============================================================"
    echo
}

step_header() {
    header
    echo "$1"
    echo "------------------------------------------------------------"
    echo
}

fatal() {
    echo
    echo "❌ FOUT: $1"
    echo
    exit 1
}

pause() {
    echo
    read -r -p "Druk op Enter om verder te gaan..." _
}

require_command() {
    local cmd="$1"
    local package="$2"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "⚙️  '$cmd' is niet geïnstalleerd."
        echo "Pakket '$package' wordt geïnstalleerd..."

        apt-get update ||
            fatal "apt update is mislukt."

        apt-get install -y "$package" ||
            fatal "Installatie van '$package' is mislukt."
    fi
}

valid_block_device() {
    [[ -b "$1" ]]
}

source_active_mounts() {
    local device="$1"
    local node
    local target
    local found=0

    while IFS= read -r node; do
        [[ -n "$node" ]] || continue

        while IFS= read -r target; do
            [[ -n "$target" ]] || continue
            printf '%s -> %s\n' "$node" "$target"
            found=1
        done < <(findmnt -rn -S "$node" -o TARGET 2>/dev/null || true)

    done < <(lsblk -nrpo NAME "$device" 2>/dev/null)

    (( found == 1 ))
}

parent_disk() {
    local dev="$1"
    local type pk

    type=$(lsblk -ndo TYPE "$dev" 2>/dev/null | head -n1)

    if [[ "$type" == "disk" ]]; then
        readlink -f "$dev"
        return
    fi

    pk=$(lsblk -ndo PKNAME "$dev" 2>/dev/null | head -n1)

    [[ -n "$pk" ]] || return 1

    readlink -f "/dev/$pk"
}

stable_device_identity() {
    local dev="$1"
    local disk="$2"
    local serial wwn model disk_size partuuid uuid byid link target

    dev=$(readlink -f "$dev" 2>/dev/null) || return 1
    disk=$(readlink -f "$disk" 2>/dev/null) || return 1

    [[ -b "$dev" ]] || return 1
    [[ -b "$disk" ]] || return 1

    serial=$(lsblk -dn -o SERIAL "$disk" 2>/dev/null | head -n1 | xargs)
    wwn=$(lsblk -dn -o WWN "$disk" 2>/dev/null | head -n1 | xargs)
    model=$(lsblk -dn -o MODEL "$disk" 2>/dev/null | head -n1 | xargs)
    disk_size=$(blockdev --getsize64 "$disk" 2>/dev/null) || return 1

    partuuid=$(lsblk -dn -o PARTUUID "$dev" 2>/dev/null | head -n1 | xargs)
    uuid=$(lsblk -dn -o UUID "$dev" 2>/dev/null | head -n1 | xargs)

    byid=""

    if [[ -d /dev/disk/by-id ]]; then
        for link in /dev/disk/by-id/*; do
            [[ -e "$link" ]] || continue
            target=$(readlink -f "$link" 2>/dev/null || true)

            if [[ "$target" == "$disk" ]]; then
                byid+="${link##*/},"
            fi
        done
    fi

    printf 'SERIAL=%s|WWN=%s|MODEL=%s|DISKSIZE=%s|BYID=%s|PARTUUID=%s|UUID=%s\n' \
        "$serial" "$wwn" "$model" "$disk_size" "$byid" "$partuuid" "$uuid"
}

show_devices() {
    lsblk -e 7 -o NAME,SIZE,MODEL,TYPE,FSTYPE,LABEL,MOUNTPOINTS
}

human_bytes() {
    numfmt --to=iec-i --suffix=B "$1" 2>/dev/null ||
        echo "$1 bytes"
}

auto_mount_destination() {

    local dev="$1"
    local fstype
    local mount_dir
    local uuid

    fstype=$(lsblk -ndo FSTYPE "$dev" 2>/dev/null | head -n1)
    uuid=$(lsblk -ndo UUID "$dev" 2>/dev/null | head -n1)

    case "${fstype,,}" in

        exfat)
            echo "✅ exFAT gedetecteerd."
            echo "   Geschikt voor Windows + Linux."
            ;;

        ntfs|ntfs3)
            echo "⚠️  NTFS gedetecteerd."
            echo "   Windows en Linux kunnen deze gebruiken."
            echo "   exFAT blijft de aanbevolen keuze."
            ;;

        vfat|fat|fat32)
            echo
            echo "❌ FAT32/VFAT is niet geschikt."
            echo "Recovery-images kunnen groter zijn dan 4 GB."
            echo
            echo "Gebruik exFAT of NTFS."
            return 1
            ;;

        ext2|ext3|ext4|xfs|btrfs)
            echo
            echo "❌ Bestandssysteem '$fstype' is niet standaard"
            echo "leesbaar en schrijfbaar onder Windows."
            echo
            echo "Gebruik exFAT of NTFS."
            return 1
            ;;

        "")
            echo
            echo "❌ Geen bestandssysteem gevonden op $dev."
            echo
            echo "BELANGRIJK:"
            echo "Het recovery-script formatteert NOOIT automatisch."
            echo "Automatisch formatteren zou bestaande data kunnen wissen."
            echo
            echo "Maak de bestemmingsschijf eerst als exFAT klaar."
            return 1
            ;;

        *)
            echo
            echo "❌ Bestandssysteem '$fstype' wordt niet gebruikt"
            echo "voor deze Windows + Linux recovery-opslag."
            echo
            echo "Gebruik exFAT of NTFS."
            return 1
            ;;
    esac

    DEST_MOUNT=$(findmnt -rn -S "$dev" -o TARGET | head -n1)

    if [[ -n "$DEST_MOUNT" && -d "$DEST_MOUNT" ]]; then

        echo
        echo "✅ Bestemming is reeds gemount:"
        echo "$DEST_MOUNT"

        return 0
    fi

    if [[ -n "$uuid" ]]; then
        mount_dir="/mnt/foremost_${uuid//[^[:alnum:]_-]/_}"
    else
        mount_dir="/mnt/foremost_$(basename "$dev")"
    fi

    mkdir -p "$mount_dir" || return 1

    echo
    echo "🔌 $dev is niet gemount."
    echo "Automatisch mounten op:"
    echo "$mount_dir"
    echo

    if [[ "${fstype,,}" == "exfat" ]]; then

        if ! mount \
            -t exfat \
            -o rw,uid="$(id -u "$REAL_USER")",gid="$(id -g "$REAL_USER")",umask=0022 \
            "$dev" "$mount_dir"
        then
            rmdir "$mount_dir" 2>/dev/null || true
            return 1
        fi

    else

        if ! mount \
            -o rw,uid="$(id -u "$REAL_USER")",gid="$(id -g "$REAL_USER")",umask=0022 \
            "$dev" "$mount_dir"
        then
            rmdir "$mount_dir" 2>/dev/null || true
            return 1
        fi
    fi

    DEST_MOUNT="$mount_dir"
    return 0
}

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "❌ Start dit script met sudo:"
    echo
    echo "sudo $0"
    echo
    exit 1
fi

REAL_USER="${SUDO_USER:-root}"

require_command lsblk util-linux
require_command smartctl smartmontools
require_command foremost foremost
require_command python3 python3
require_command sha256sum coreutils
require_command findmnt util-linux
require_command blockdev util-linux
require_command numfmt coreutils
require_command truncate coreutils
require_command mkfs.exfat exfatprogs

while true; do

    step_header "STAP 1/7 - KIES BRONSCHIJF"

    echo "Beschikbare schijven en partities:"
    echo

    show_devices

    echo

    read -r -p "💽 Geef de brondevice in (bv. sdb of sdb1): " SRC_INPUT

    [[ -n "$SRC_INPUT" ]] || continue

    SOURCE_DEVICE="/dev/${SRC_INPUT#/dev/}"
    SOURCE_DEVICE=$(readlink -f "$SOURCE_DEVICE" 2>/dev/null || true)

    if ! valid_block_device "$SOURCE_DEVICE"; then
        echo
        echo "❌ '$SOURCE_DEVICE' is geen geldig block device."
        pause
        continue
    fi

    SOURCE_DISK=$(parent_disk "$SOURCE_DEVICE") || {
        echo
        echo "❌ Kan de fysieke bronschijf niet bepalen."
        pause
        continue
    }

    SOURCE_IDENTITY=$(stable_device_identity "$SOURCE_DEVICE" "$SOURCE_DISK") || {
        echo
        echo "❌ Kan de stabiele identiteit van de bron niet bepalen."
        pause
        continue
    }

    SOURCE_MOUNTS=$(source_active_mounts "$SOURCE_DEVICE" || true)

    if [[ -n "$SOURCE_MOUNTS" ]]; then
        echo
        echo "❌ DE GEKOZEN BRON OF EEN ONDERLIGGENDE PARTITIE IS GEMOUNT."
        echo
        printf '%s\n' "$SOURCE_MOUNTS"
        echo
        echo "Er wordt bewust NIETS automatisch ge-unmount."
        pause
        continue
    fi

    break
done

step_header "STAP 2/7 - SMART HEALTH CHECK"

echo "Brondevice   : $SOURCE_DEVICE"
echo "Fysieke disk: $SOURCE_DISK"
echo

SMART_TARGET="$SOURCE_DISK"

SMART_OUTPUT=$(smartctl -a "$SMART_TARGET" 2>&1)
SMART_RC=$?

printf '%s\n' "$SMART_OUTPUT"

SMART_RISK=0
SMART_WARNINGS=()

smart_raw_value() {
    local attr="$1"
    local value

    value=$(printf '%s\n' "$SMART_OUTPUT" |
        awk -v name="$attr" '$2 == name {print $NF; exit}')

    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s' "$value"
    else
        printf '0'
    fi
}

REALLOCATED=$(smart_raw_value "Reallocated_Sector_Ct")
REPORTED_UNCORRECT=$(smart_raw_value "Reported_Uncorrect")
PENDING=$(smart_raw_value "Current_Pending_Sector")
OFFLINE_UNCORRECT=$(smart_raw_value "Offline_Uncorrectable")
CRC_ERRORS=$(printf '%s\n' "$SMART_OUTPUT" |
    awk '$1 == 199 {print $NF; exit}')

if [[ ! "$CRC_ERRORS" =~ ^[0-9]+$ ]]; then
    CRC_ERRORS=$(smart_raw_value "UDMA_CRC_Error_Count")
fi

if [[ ! "$CRC_ERRORS" =~ ^[0-9]+$ ]]; then
    CRC_ERRORS=$(smart_raw_value "SATA_CRC_Error")
fi

if printf '%s\n' "$SMART_OUTPUT" |
    grep -Eqi 'SMART.*(FAILED|FAILURE)|overall-health.*FAILED'
then
    SMART_RISK=2
    SMART_WARNINGS+=("SMART algemene gezondheid meldt FAILED")
fi

if (( PENDING > 0 )); then
    SMART_RISK=2
    SMART_WARNINGS+=("$PENDING pending sector(en)")
fi

if (( OFFLINE_UNCORRECT > 0 )); then
    SMART_RISK=2
    SMART_WARNINGS+=("$OFFLINE_UNCORRECT offline uncorrectable sector(en)")
fi

if (( REPORTED_UNCORRECT > 0 )); then
    SMART_RISK=2
    SMART_WARNINGS+=("$REPORTED_UNCORRECT gerapporteerde onherstelbare fout(en)")
fi

if (( REALLOCATED > 0 )); then
    (( SMART_RISK < 1 )) && SMART_RISK=1
    SMART_WARNINGS+=("$REALLOCATED reallocated sector(en)")
fi

if (( CRC_ERRORS > 0 )); then
    (( SMART_RISK < 1 )) && SMART_RISK=1
    SMART_WARNINGS+=("$CRC_ERRORS CRC/communicatiefout(en)")
fi

SMART_AVAILABLE=1

if printf '%s\n' "$SMART_OUTPUT" |
    grep -Eqi 'SMART support is: *Unavailable|Unknown USB bridge|Read Device Identity failed|Permission denied|Unable to detect device type|Please specify device type|open device failed|No such device|Device open failed'
then
    SMART_AVAILABLE=0
fi

if [[ "$SMART_AVAILABLE" -eq 0 ]]; then
    echo "⚪ SMART STATUS : NIET BETROUWBAAR BESCHIKBAAR"
else
    echo "Reallocated sectors       : $REALLOCATED"
    echo "Reported uncorrectable     : $REPORTED_UNCORRECT"
    echo "Current pending sectors    : $PENDING"
    echo "Offline uncorrectable      : $OFFLINE_UNCORRECT"
    echo "CRC / communicatiefouten   : $CRC_ERRORS"
fi

if [[ "$SMART_AVAILABLE" -eq 1 && "$SMART_RISK" -eq 2 ]]; then
    read -r -p 'Typ exact "IK BEGRIJP HET RISICO" om Basic toch te forceren: ' CONFIRM

    if [[ "$CONFIRM" != "IK BEGRIJP HET RISICO" ]]; then
        exit 0
    fi
else
    read -r -p "⚠️  Wil je verdergaan met deze bronschijf? (y/n): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

while true; do

    step_header "STAP 3/7 - KIES BESTEMMINGSSCHIJF"

    show_devices

    read -r -p "📁 Bestemmingsdevice: " DST_INPUT

    [[ -n "$DST_INPUT" ]] || continue

    DEST_DEVICE="/dev/${DST_INPUT#/dev/}"
    DEST_DEVICE=$(readlink -f "$DEST_DEVICE" 2>/dev/null || true)

    if ! valid_block_device "$DEST_DEVICE"; then
        pause
        continue
    fi

    DEST_DISK=$(parent_disk "$DEST_DEVICE") || {
        pause
        continue
    }

    DEST_IDENTITY=$(stable_device_identity "$DEST_DEVICE" "$DEST_DISK") || {
        pause
        continue
    }

    if [[ "$DEST_DISK" == "$SOURCE_DISK" ]]; then
        echo "❌ BRON EN BESTEMMING ZIJN DEZELFDE FYSIEKE SCHIJF."
        pause
        continue
    fi

    DEST_TYPE=$(lsblk -ndo TYPE "$DEST_DEVICE" 2>/dev/null | head -n1)

    if [[ "$DEST_TYPE" != "part" ]]; then
        echo "❌ Kies een PARTITIE als bestemming."
        pause
        continue
    fi

    DEST_FSTYPE=$(lsblk -ndo FSTYPE "$DEST_DEVICE" 2>/dev/null | head -n1)

    if ! auto_mount_destination "$DEST_DEVICE"; then
        pause
        continue
    fi

    if ! mountpoint -q "$DEST_MOUNT"; then
        pause
        continue
    fi

    if [[ ! -w "$DEST_MOUNT" ]]; then
        pause
        continue
    fi

    WRITE_TEST="$DEST_MOUNT/.foremost_write_test_$$"

    if ! : > "$WRITE_TEST" 2>/dev/null; then
        pause
        continue
    fi

    rm -f "$WRITE_TEST"

    pause
    break
done

while true; do
    step_header "STAP 4/7 - KIES BESTANDSTYPEN"

    echo "1) ALLES"
    echo "2) FOTO'S"
    echo "3) VIDEO'S"
    echo "4) DOCUMENTEN"
    echo "5) AUDIO"
    echo "6) ARCHIEVEN"
    echo "7) E-MAIL"
    echo "8) ZELF KIEZEN"

    read -r -p "Keuze [1-8]: " TYPE_CHOICE

    case "$TYPE_CHOICE" in
        1)
            TYPE_CATEGORY="Alles"
            EXTENSIONS="jpg,jpeg,gif,png,bmp,tif,avi,mp4,mov,mpg,wmv,doc,pdf,htm,wav,mp3,wma,ra,zip,rar,pst,ost,dbx,mbx"
            ;;
        2)
            TYPE_CATEGORY="Foto's"
            EXTENSIONS="jpg,jpeg,gif,png,bmp,tif"
            ;;
        3)
            TYPE_CATEGORY="Video's"
            EXTENSIONS="avi,mp4,mov,mpg,wmv"
            ;;
        4)
            TYPE_CATEGORY="Documenten"
            EXTENSIONS="doc,pdf,htm"
            ;;
        5)
            TYPE_CATEGORY="Audio"
            EXTENSIONS="wav,mp3,wma,ra"
            ;;
        6)
            TYPE_CATEGORY="Archieven"
            EXTENSIONS="zip,rar"
            ;;
        7)
            TYPE_CATEGORY="E-mail"
            EXTENSIONS="pst,ost,dbx,mbx"
            ;;
        8)
            TYPE_CATEGORY="Handmatige keuze"
            read -r -p "Types, komma-gescheiden (bv. jpg,pdf,mp4): " EXTENSIONS
            ;;
        *)
            pause
            continue
            ;;
    esac

    read -r -p "Deze keuze gebruiken? [j/N]: " TYPE_CONFIRM

    if [[ "$TYPE_CONFIRM" =~ ^[jJyY]$ ]]; then
        break
    fi
done

step_header "STAP 5/7 - OVERZICHT + BEVESTIGING"

read -r -p "📝 Naam voor deze recovery: " RECNAME

[[ -n "$RECNAME" ]] || RECNAME="recovery"

SAFE_RECNAME=$(printf '%s' "$RECNAME" |
    tr ' /' '__' |
    tr -cd '[:alnum:]_.-')

[[ -n "$SAFE_RECNAME" ]] || SAFE_RECNAME="recovery"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

RECOVERY_DIR="$DEST_MOUNT/${SAFE_RECNAME}_${TIMESTAMP}"
LOGFILE="$RECOVERY_DIR/verslag_foremost.txt"
IMAGE_FILE="$RECOVERY_DIR/image_$(basename "$SOURCE_DEVICE").img"
RESULT_DIR="$RECOVERY_DIR/resultaat"

SOURCE_SIZE=$(blockdev --getsize64 "$SOURCE_DEVICE" 2>/dev/null) ||
    fatal "Kan grootte van bron niet bepalen."

AVAILABLE_BYTES=$(df -PB1 "$DEST_MOUNT" |
    awk 'NR==2 {print $4}')

[[ "$AVAILABLE_BYTES" =~ ^[0-9]+$ ]] ||
    fatal "Kan vrije ruimte op bestemming niet bepalen."

MIN_REQUIRED=$((SOURCE_SIZE + 1073741824))

if (( AVAILABLE_BYTES < MIN_REQUIRED )); then
    fatal "Onvoldoende vrije ruimte."
fi

echo "Recoverymap : $RECOVERY_DIR"
echo "Image       : $IMAGE_FILE"
echo "Categorie   : $TYPE_CATEGORY"
echo "Types       : $EXTENSIONS"

read -r -p "Typ START om de recovery te starten: " FINAL_CONFIRM

if [[ "$FINAL_CONFIRM" != "START" ]]; then
    exit 0
fi

CURRENT_SOURCE_DISK=$(parent_disk "$SOURCE_DEVICE") ||
    fatal "Kan fysieke bronschijf niet opnieuw bepalen."

CURRENT_DEST_DISK=$(parent_disk "$DEST_DEVICE") ||
    fatal "Kan fysieke bestemmingsschijf niet opnieuw bepalen."

[[ "$CURRENT_SOURCE_DISK" == "$SOURCE_DISK" ]] ||
    fatal "Bronschijf is veranderd sinds de selectie."

[[ "$CURRENT_DEST_DISK" == "$DEST_DISK" ]] ||
    fatal "Bestemmingsschijf is veranderd sinds de selectie."

CURRENT_SOURCE_IDENTITY=$(stable_device_identity "$SOURCE_DEVICE" "$CURRENT_SOURCE_DISK") ||
    fatal "Kan identiteit van de bron niet opnieuw bepalen."

CURRENT_DEST_IDENTITY=$(stable_device_identity "$DEST_DEVICE" "$CURRENT_DEST_DISK") ||
    fatal "Kan identiteit van de bestemming niet opnieuw bepalen."

[[ "$CURRENT_SOURCE_IDENTITY" == "$SOURCE_IDENTITY" ]] ||
    fatal "IDENTITEITSFOUT bron."

[[ "$CURRENT_DEST_IDENTITY" == "$DEST_IDENTITY" ]] ||
    fatal "IDENTITEITSFOUT bestemming."

CURRENT_SOURCE_MOUNTS=$(source_active_mounts "$SOURCE_DEVICE" || true)

if [[ -n "$CURRENT_SOURCE_MOUNTS" ]]; then
    fatal "Bron moet volledig unmounted blijven."
fi

mkdir -p "$RECOVERY_DIR" ||
    fatal "Kan recoverymap niet aanmaken."

exec > >(tee -a "$LOGFILE") 2>&1

START_TIME=$(date +%s)

echo
echo "============================================================"
echo "STAP 6/7 - IMAGE + SHA256"
echo "============================================================"

DD_ERROR_LOG="$RECOVERY_DIR/dd_read_errors.log"

if ! dd \
    if="$SOURCE_DEVICE" \
    of="$IMAGE_FILE" \
    bs=4M \
    status=progress \
    conv=noerror,sync \
    2> >(tee "$DD_ERROR_LOG" >&2)
then
    fatal "dd is mislukt."
fi

sync

ACTUAL_IMAGE_SIZE=$(stat -c %s "$IMAGE_FILE" 2>/dev/null || echo 0)

if (( ACTUAL_IMAGE_SIZE > SOURCE_SIZE )); then
    truncate -s "$SOURCE_SIZE" "$IMAGE_FILE" ||
        fatal "Kan image niet verkleinen."
fi

if ! sha256sum "$IMAGE_FILE" |
    tee "$IMAGE_FILE.sha256"
then
    fatal "SHA256-berekening is mislukt."
fi

if ! (
    cd "$RECOVERY_DIR" &&
    sha256sum -c "$(basename "$IMAGE_FILE").sha256"
); then
    fatal "SHA256-verificatie is mislukt."
fi

echo
echo "============================================================"
echo "STAP 7/7 - FOREMOST + RAPPORT"
echo "============================================================"

foremost \
    -t "$EXTENSIONS" \
    -i "$IMAGE_FILE" \
    -o "$RESULT_DIR" ||
    fatal "Foremost is mislukt."

TOTAL=0

IFS=',' read -r -a EXT_ARRAY <<< "$EXTENSIONS"

for ext in "${EXT_ARRAY[@]}"; do

    case "$ext" in
        jpeg)
            OUTPUT_DIR="jpg"
            ;;
        *)
            OUTPUT_DIR="$ext"
            ;;
    esac

    COUNT=$(find "$RESULT_DIR/$OUTPUT_DIR" \
        -type f \
        2>/dev/null |
        wc -l)

    COUNT=${COUNT//[[:space:]]/}
    [[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

    TOTAL=$((TOTAL + COUNT))

    printf "%-6s : %s bestanden\n" "$ext" "$COUNT"
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$((DURATION % 60))

echo
echo "============================================================"
echo "                 ✅ RECOVERY VOLTOOID"
echo "============================================================"
echo
echo "Totale tijd          : ${HOURS}u ${MINUTES}m ${SECONDS}s"
echo "Categorie            : $TYPE_CATEGORY"
echo "Foremost types       : $EXTENSIONS"
echo "Herstelde bestanden  : $TOTAL"
echo
echo "Recoverymap:"
echo "$RECOVERY_DIR"
echo
echo "Image:"
echo "$IMAGE_FILE"
echo
echo "SHA256:"
echo "$IMAGE_FILE.sha256"
echo
echo "Foremost-resultaten:"
echo "$RESULT_DIR"
echo
echo "Rapport:"
echo "$LOGFILE"
echo
echo "============================================================"
echo "       FOREMOST RECOVERY TOOLKIT - BASIC RECOVERY"
echo "============================================================"
