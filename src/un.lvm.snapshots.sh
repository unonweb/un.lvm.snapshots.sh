#!/bin/bash

# Script location variables
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE}")"
SCRIPT_DIR=$(dirname -- "$(readlink -f "${BASH_SOURCE}")")
SCRIPT_NAME=$(basename -- "$(readlink -f "${BASH_SOURCE}")")

ESC=$(printf "\e")
BOLD="${ESC}[1m"
RESET="${ESC}[0m"
RED="${ESC}[31m"
GREEN="${ESC}[32m"
BLUE="${ESC}[34m"
UNDERLINE="${ESC}[4m"

# IMPORTS
source "${SCRIPT_DIR}/lib/printHighestNumFromArr.sh"
source "${SCRIPT_DIR}/lib/trim.sh"

ORIGIN=""
MOUNT_POINT_SNAP=""
MOUNT_POINT_ORIGIN=""
DEV_PATH_VG="/dev/os"
declare -A IS_MOUNTED=()

function getSnapshots() {
  # CAN'T CALL THIS FROM ANOTHER FUNCTION IF THE NAMEREF FROM THE OTHER FUNCTION ITSELF IS A LOCAL VARIABLE
  # ONLY WORKS WITH GLOBAL VARIABLES WHEN CALLING FROM ANOTHER FUNCTION

  local -n result=$1
  local snapshots=()
  
  mapfile -t snapshots < <(sudo lvs -o lv_name | grep snap) # --> MAPFILE

  for ((i = 0; i < ${#snapshots[@]}; i++)); do
    snapshots[$i]=$(trim ${snapshots[$i]})
  done

  result=("${snapshots[@]}")

  #for res in "${result[@]}"; do
  #  echo "result: ${res}"
  #done
}

function selectSnapshot() {
  # ARGS:
  # --mounted
  local prompt="${1:-Select snapshot}"
  local option
  local snapshots
  local tmp

  # get snapshots
  case "$*" in
    *--mounted*)
      mapfile -t snapshots < <(findmnt --list --output TARGET | grep /mnt/debian)
      ;;
    *)
      mapfile -t snapshots < <(sudo lvs -o lv_name | grep snap) 
      ;;
  esac
  
  for ((i = 0; i < ${#snapshots[@]}; i++)); do
    # findmnt output
    snapshots[$i]=${snapshots[$i]#/mnt/}
    # for lvs output
    snapshots[$i]=$(trim ${snapshots[$i]})
  done

  # check if snapshots is empty
  if [[ ${#snapshots[@]} -eq 0 ]]; then
    echo "No snapshots found."
    return 1  # Exit the function if no snapshots are found
  fi

  PS3="${RESET}${BOLD}${prompt} >> ${RESET}"
  select option in "${snapshots[@]}"; do
    if [[ $option ]]; then
      #echo "You selected '${option}'."
      #result=${option}

      # result
      SNAPSHOT=${option}
      ORIGIN=$(printSnapshotOrigin)
      MOUNT_POINT_SNAP="/mnt/${SNAPSHOT}"
      MOUNT_POINT_ORIGIN="/mnt/${ORIGIN}"

      break
    else
      echo "Error: Invalid choice '${REPLY}'"
    fi
  done

}

function printNameWithOldestDate() { # ${prefix} arrayOfStringsWithUnixSec
  local prefixToRemove=${1}
  local -n stringsWithUnixSec=${2}
  # Initialize variables to track the oldest date and corresponding string
  local unixSecCurrent=""
  local nameWithOldestDate=""
  local unixSecOldest=""

  # Loop through each string
  for str in "${stringsWithUnixSec[@]}"; do
    unixSecCurrent="${str##*${prefixToRemove}}"  # Remove the prefix
    # Check if this is the first iteration or if the current str is older
    if [[ -z "${unixSecOldest}" || "${unixSecCurrent}" -lt "${unixSecOldest}" ]]; then
      unixSecOldest="${unixSecCurrent}"
      nameWithOldestDate="${str}"
    fi
  done

  # Output the oldest string
  printf '%s' "${nameWithOldestDate}"
}

function createSnapshot() {
  local devPathVG=$1
  local snapshots=()
  local snapshot
  local snapshotNumber
  local snapshotNumbers=()
  local highest
  local max=4
  local next
  local namePrefix="debian-snap"
  local nextName="${namePrefix}-$(date +%s)" # debian-snap-1744664618
  local oldest

  # get snapshots
  mapfile -t snapshots < <(sudo lvs -o lv_name | grep snap)
  for ((i = 0; i < ${#snapshots[@]}; i++)); do
    snapshots[$i]=$(trim ${snapshots[$i]})
  done

  if [[ ${#snapshots[@]} -ge ${max} ]]; then
    oldest=$(printNameWithOldestDate "${namePrefix}-" snapshots)
    #echo "snapshots: ${snapshots[@]}"
    #echo "number of snapshots: ${#snapshots[@]}"
    echo "Reached maximum of ${max} snapshots"
    echo "Oldest snapshot: ${oldest}"
    # remove
    sudo lvremove "${devPathVG}/${oldest}"
    if [[ $? -eq 0 ]]; then
      # create
      echo "Create snapshot ${GREEN}${nextName}${RESET}? (y|n)"
      read -p ">> "
      echo ""
      if [[ $REPLY == "y"  ]]; then
        sudo lvcreate --snapshot --extents 10%ORIGIN --name ${nextName} ${devPathVG}/debian    
      fi
    fi
  else
    # create
    echo "Create snapshot ${GREEN}${nextName}${RESET}? (y|n)"
    read -p ">> "
    echo ""
    if [[ $REPLY == "y"  ]]; then
      sudo lvcreate --snapshot --extents 10%ORIGIN --name ${nextName} ${devPathVG}/debian    
    fi
  fi
}

function createMountPoint() {
  local mountpoint=$1

  # Create mount point if it doesn't exist
  if [ ! -d "${mountpoint}" ]; then
    echo "Creating mountpoint: ${GREEN}${mountpoint}${RESET}"
    sudo mkdir -p "${mountpoint}"
  fi
}

function mountLV() {
  local snapshotPath=$1
  local mountPoint=$2

  createMountPoint ${mountPoint}
  sudo mount ${snapshotPath} ${mountPoint} # mount
}

function printSnapshotOrigin() {
  local snapshotPath=$1
  local origin

  origin=$(sudo lvs -o origin --noheadings ${snapshotPath})
  origin=$(trim $origin)
  printf '%s' "$origin"
}

function main() {

  local operations=(
    "List snapshots"
    "Create snapshot"
    "Remove snapshot"
    "Mount snapshot"
    "Unmount"
    "Diff snapshot"
    "Restore snapshot"
  )
  local isMountedSnap=0
  local isMountedOrigin=0
  local index
  local diffFile="${SCRIPT_DIR}/diff.txt"

  # refresh metadata
  sudo lvchange --refresh ${DEV_PATH_VG}

  # interactive loop
  while true; do
    # header
    echo
    echo "---"
    echo
    # menu
    index=1
    for op in "${operations[@]}"; do
      echo -e "${GREEN}${index}${RESET}) ${op}"
      ((index++))
    done
    # read
    echo
    read -p ">> "
    echo

    case ${REPLY} in
    1)
      # list snapshots
      echo -en "${GREEN}"
      sudo lvs -o lv_name,lv_time,data_percent | grep snap
      echo -en "${RESET}"
      echo
      echo "Mounted:"
      echo -en "${GREEN}"
      findmnt --list --output TARGET | grep /mnt/debian
      echo -en "${RESET}"
      ;;
    2)
      # create snapshot
      createSnapshot "${DEV_PATH_VG}"
      ;;
    3)
      # remove
      selectSnapshot "Select snapshot to remove"
      sudo lvremove "${DEV_PATH_VG}/${SNAPSHOT}"
      ;;
    4)
      # mount
      selectSnapshot "Select snapshot to mount"
      if [[ -n ${MOUNT_POINT_SNAP} ]] && ! mountpoint -q ${MOUNT_POINT_SNAP}; then
        mountLV "${DEV_PATH_VG}/${SNAPSHOT}" ${MOUNT_POINT_SNAP}
      fi
      ;;
    5)
      # unmount
      selectSnapshot "Select snapshot to mount" --mounted
      if [[ -n ${MOUNT_POINT_SNAP} ]] && mountpoint -q ${MOUNT_POINT_SNAP}; then
        echo "Unmounting ${MOUNT_POINT_SNAP} ..."
        sudo umount ${MOUNT_POINT_SNAP} && echo "Successfully unmounted ${MOUNT_POINT_SNAP}"
      fi
      # umount ORIGIN
      if [[ -n ${MOUNT_POINT_ORIGIN} ]] && mountpoint -q ${MOUNT_POINT_ORIGIN}; then
        echo "Unmounting ${MOUNT_POINT_ORIGIN} ..."
        sudo umount ${MOUNT_POINT_ORIGIN} && echo "Successfully unmounted ${MOUNT_POINT_ORIGIN}"
      fi
      ;;
    6)
      # diff
      selectSnapshot "Select snapshot to diff"
      echo
      
      if [[ -n ${SNAPSHOT} ]]; then
        # mount snap
        if [[ -n ${MOUNT_POINT_SNAP} ]] && ! mountpoint -q ${MOUNT_POINT_SNAP}; then
          mountLV "${DEV_PATH_VG}/${SNAPSHOT}" ${MOUNT_POINT_SNAP}
        fi
        # mount origin
        if [[ -n ${MOUNT_POINT_ORIGIN} ]] && ! mountpoint -q ${MOUNT_POINT_ORIGIN}; then
          mountLV "${DEV_PATH_VG}/${ORIGIN}" ${MOUNT_POINT_ORIGIN}
        fi

        echo "Comparing ${GREEN}${MOUNT_POINT_SNAP}/${RESET} with ${GREEN}${MOUNT_POINT_ORIGIN}${RESET} ..."
        sudo rsync --info=nonreg0 --dry-run --recursive --human-readable --delete --size-only --out-format="%n" \
        --exclude mnt \
        --exclude tmp \
        --exclude var/tmp \
        --exclude var/log \
        --exclude var/cache \
        --exclude var/run \
        ${MOUNT_POINT_SNAP}/ ${MOUNT_POINT_ORIGIN} > ${diffFile} && echo "Diff written to: ${GREEN}${diffFile}${RESET}"
      fi
      ;;
    7)
      # restore
      echo "Create a snapshot before restoring? (y|n)"
      read -p ">> "
      echo
      if [[ $REPLY == "y"  ]]; then
        createSnapshot "${DEV_PATH_VG}"
      fi
      echo
      selectSnapshot "Select snapshot to restore"
      echo
      if [[ -n ${SNAPSHOT} ]]; then
        echo "Restoring ${GREEN}${DEV_PATH_VG}/${SNAPSHOT}${RESET} ..."
        sudo lvconvert --merge "${DEV_PATH_VG}/${SNAPSHOT}"
      fi
      ;;
    *)
      echo "Invalid selection"
      sleep 2
      ;;
    esac
  done
}

main