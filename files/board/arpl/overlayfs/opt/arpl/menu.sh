#!/usr/bin/env bash

. /opt/arpl/include/functions.sh
. /opt/arpl/include/addons.sh
. /opt/arpl/include/modules.sh

# Check partition 3 space, if < 2GiB is necessary clean cache folder
CLEARCACHE=0
LOADER_DISK="$(blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1)"
LOADER_DEVICE_NAME=$(echo ${LOADER_DISK} | sed 's|/dev/||')
if [ $(cat /sys/block/${LOADER_DEVICE_NAME}/${LOADER_DEVICE_NAME}3/size) -lt 4194304 ]; then
  CLEARCACHE=1
fi

# Get actual IP
IP=$(ip route 2>/dev/null | sed -n 's/.* via .* dev \(.*\)  src \(.*\)  metric .*/\1: \2 /p' | head -1)

# Dirty flag
DIRTY=0

MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
DSMLOGO="$(readConfigKey "dsmlogo" "${USER_CONFIG_FILE}")"
DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
PRERELEASE="$(readConfigKey "prerelease" "${USER_CONFIG_FILE}")"
KERNELWAY="$(readConfigKey "kernelway" "${USER_CONFIG_FILE}")"
ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")" # official drivers priorities
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="${ARPL_TITLE}"
  if [ -n "${MODEL}" ]; then
    BACKTITLE+=" ${MODEL}"
  else
    BACKTITLE+=" (no model)"
  fi
  if [ -n "${PRODUCTVER}" ]; then
    BACKTITLE+=" ${PRODUCTVER}"
    if [ -n "${BUILDNUM}" ]; then
      BACKTITLE+="(${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))"
    else
      BACKTITLE+="(no version num)"
    fi
  else
    BACKTITLE+=" (no product version)"
  fi
  if [ -n "${SN}" ]; then
    BACKTITLE+=" ${SN}"
  else
    BACKTITLE+=" (no SN)"
  fi
  if [ -n "${IP}" ]; then
    BACKTITLE+=" ${IP}"
  else
    BACKTITLE+=" (no IP)"
  fi
  if [ -n "${KEYMAP}" ]; then
    BACKTITLE+=" (${LAYOUT}/${KEYMAP})"
  else
    BACKTITLE+=" (qwerty/us)"
  fi
  if [ -d "/sys/firmware/efi" ]; then
    BACKTITLE+=" [UEFI]"
  else
    BACKTITLE+=" [BIOS]"
  fi
  echo ${BACKTITLE}
}

###############################################################################
# Shows available models to user choose one
function modelMenu() {
  if [ -z "${1}" ]; then
    RESTRICT=1
    FLGBETA=0
    dialog --backtitle "$(backtitle)" --title "$(TEXT "Model")" --aspect 18 \
      --infobox "$(TEXT "Reading models")" 0 0

    while read M; do
      Y=$(echo ${M} | tr -cd "[0-9]")
      Y=${Y:0-2}
      echo "${M} ${Y}" >>"${TMP_PATH}/modellist"
    done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sed 's/.*\///; s/\.yml//')

    while true; do
      echo "" >"${TMP_PATH}/menu"
      FLGNEX=0
      while read M Y; do
        PLATFORM=$(readModelKey "${M}" "platform")
        DT="$(readModelKey "${M}" "dt")"
        BETA="$(readModelKey "${M}" "beta")"
        Added a menu to try recovery info from installed DSM
        [ "${BETA}" = "true" -a ${FLGBETA} -eq 0 ] && continue
        # Check id model is compatible with CPU
        COMPATIBLE=1
        if [ ${RESTRICT} -eq 1 ]; then
          format
          for F in $(readModelArray "${M}" "flags"); do
            Added a menu to try recovery info from installed DSM
            if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
              COMPATIBLE=0
              FLGNEX=1
              break
            fi
          done
        fi
        [ "${DT}" = "true" ] && DT="DT" || DT=""
        [ ${COMPATIBLE} -eq 1 ] && echo "${M} \"$(printf "\Zb%-12s\Zn \Z4%-2s\Zn" "${PLATFORM}" "${DT}")\" " >>"${TMP_PATH}/menu"
      done < <(cat "${TMP_PATH}/modellist" | sort -r -n -k 2)
      [ ${FLGNEX} -eq 1 ] && echo "f \"\Z1$(TEXT "Disable flags restriction")\Zn\"" >>"${TMP_PATH}/menu"
      [ ${FLGBETA} -eq 0 ] && echo "b \"\Z1$(TEXT "Show beta models")\Zn\"" >>"${TMP_PATH}/menu"
      dialog --backtitle "$(backtitle)" --colors --menu "$(TEXT "Choose the model")" 0 0 0 \
        --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      resp=$(<${TMP_PATH}/resp)
      [ -z "${resp}" ] && return
      if [ "${resp}" = "f" ]; then
        RESTRICT=0
        continue
      fi
      if [ "${resp}" = "b" ]; then
        FLGBETA=1
        continue
      fi
      break
    done
  else
    resp="${1}"
  fi
  # If user change model, clean buildnumber and S/N
  if [ "${MODEL}" != "${resp}" ]; then
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    PRODUCTVER=""
    BUILDNUM=""
    SMALLNUM=""
    writeConfigKey "productver" "" "${USER_CONFIG_FILE}"
    writeConfigKey "buildnum" "" "${USER_CONFIG_FILE}"
    writeConfigKey "smallnum" "" "${USER_CONFIG_FILE}"
    writeConfigKey "paturl" "" "${USER_CONFIG_FILE}"
    writeConfigKey "patsum" "" "${USER_CONFIG_FILE}"
    SN=$(generateSerial "${MODEL}")
    writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
    # Delete old files
    //rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
    DIRTY=1
  fi
}

###############################################################################
# Shows available buildnumbers from a model to user choose one
function productversMenu() {
  ITEMS="$(readConfigEntriesArray "productvers" "${MODEL_CONFIG_PATH}/${MODEL}.yml" | sort -r)"
  Added a menu to try recovery info from installed DSM
  if [ -z "${1}" ]; then
    moddify bootwait
    dialog --backtitle "$(backtitle)" --colors \
      mod ttyd port to 5000, add NIC check connect
    --no-items --menu "$(TEXT "Choose a product version")" 0 0 0 ${ITEMS} \
      format
    2>${TMP_PATH}/resp
    Added a menu to try recovery info from installed DSM
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
  else
    if ! arrayExistItem "${1}" ${ITEMS}; then return; fi
    resp="${1}"
  fi
  modify mac related
  if [ "${PRODUCTVER}" = "${resp}" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Product Version")" \
      --yesno "$(printf "$(TEXT "The current version has been set to %s. Do you want to reset the version?")" "${PRODUCTVER}")" 0 0
    [ $? -ne 0 ] && return
  fi
  local KVER=$(readModelKey "${MODEL}" "productvers.[${resp}].kver")
  if [ -d "/sys/firmware/efi" -a "${KVER:0:1}" = "3" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Product Version")" \
      --msgbox "$(TEXT "This version does not support UEFI startup, Please select another version or switch the startup mode.")" 0 0
    return
  fi
  if [ ! "usb" = "$(udevadm info --query property --name ${LOADER_DISK} | grep ID_BUS | cut -d= -f2)" -a "${KVER:0:1}" = "5" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Product Version")" \
      --msgbox "$(TEXT "This version only support usb startup, Please select another version or switch the startup mode.")" 0 0
    # return
  fi
  while true; do
    # get online pat data
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Product Version")" \
      --infobox "$(TEXT "Get pat data ..")" 0 0
    idx=0
    while [ ${idx} -le 3 ]; do # Loop 3 times, if successful, break
      fastest=$(_get_fastest "www.synology.com" "www.synology.cn")
      [ "${fastest}" = "www.synology.cn" ] &&
        fastest="https://www.synology.cn/api/support/findDownloadInfo?lang=zh-cn" ||
        fastest="https://www.synology.com/api/support/findDownloadInfo?lang=en-us"
      patdata=$(curl -skL "${fastest}&product=${MODEL/+/%2B}&major=${resp%%.*}&minor=${resp##*.}")
      if [ "$(echo ${patdata} | jq -r '.success' 2>/dev/null)" = "true" ]; then
        if echo ${patdata} | jq -r '.info.system.detail[0].items[0].files[0].label_ext' 2>/dev/null | grep -q 'pat'; then
          paturl=$(echo ${patdata} | jq -r '.info.system.detail[0].items[0].files[0].url')
          patsum=$(echo ${patdata} | jq -r '.info.system.detail[0].items[0].files[0].checksum')
          paturl=${paturl%%\?*}
          break
        fi
      fi
      idx=$((${idx} + 1))
    done
    if [ -z "${paturl}" -o -z "${patsum}" ]; then
      MSG="$(TEXT "Failed to get pat data,\nPlease manually fill in the URL and md5sum of the corresponding version of pat.")"
      paturl=""
      patsum=""
    else
      MSG="$(TEXT "Successfully to get pat data,\nPlease confirm or modify as needed.")"
    fi
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Product Version")" \
      modify mac related
    --extra-button --extra-label "$(TEXT "Retry")" \
      --form "${MSG}" 10 110 2 "URL" 1 1 "${paturl}" 1 5 100 0 "MD5" 2 1 "${patsum}" 2 5 100 0 \
      2>"${TMP_PATH}/resp"
    RET=$?
    [ ${RET} -eq 0 ] && break    # ok-button
    [ ${RET} -eq 3 ] && continue # extra-button
    return                       # 1 or 255  # cancel-button or ESC
  done
  paturl="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
  patsum="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
  [ -z "${paturl}" -o -z "${patsum}" ] && return
  writeConfigKey "paturl" "${paturl}" "${USER_CONFIG_FILE}"
  writeConfigKey "patsum" "${patsum}" "${USER_CONFIG_FILE}"
  PRODUCTVER=${resp}
  writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
  BUILDNUM=""
  SMALLNUM=""
  writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
  writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"
  dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Product Version")" \
    --infobox "$(TEXT "Reconfiguring Synoinfo, Addons and Modules")" 0 0
  # Delete synoinfo and reload model/build synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read KEY VALUE; do
    writeConfigKey "synoinfo.${KEY}" "${VALUE}" "${USER_CONFIG_FILE}"
  done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].synoinfo")
  # Check addons
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"
  while IFS=': ' read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      deleteConfigKey "addons.${ADDON}" "${USER_CONFIG_FILE}"
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Rebuild modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  while read ID DESC; do
    writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
  done < <(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
  # Remove old files
  rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
  DIRTY=1
}

###############################################################################
# Shows menu to user type one or generate randomly
function serialMenu() {
  while true; do
    dialog --clear --backtitle "$(backtitle)" \
      --menu "$(TEXT "Choose a option")" 0 0 0 \
      a "$(TEXT "Generate a random serial number")" \
      m "$(TEXT "Enter a serial number")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "m" ]; then
      while true; do
        dialog --backtitle "$(backtitle)" \
          --inputbox "$(TEXT "Please enter a serial number ")" 0 0 "" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && return
        SERIAL=$(cat ${TMP_PATH}/resp)
        if [ -z "${SERIAL}" ]; then
          return
        elif [ $(validateSerial ${MODEL} ${SERIAL}) -eq 1 ]; then
          break
        fi
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Alert")" \
          --yesno "$(TEXT "Invalid serial, continue?")" 0 0
        [ $? -eq 0 ] && break
      done
      break
    elif [ "${resp}" = "a" ]; then
      SERIAL=$(generateSerial "${MODEL}")
      break
    fi
  done
  SN="${SERIAL}"
  writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
}

###############################################################################
# Manage addons
function addonMenu() {
  # Read 'platform' and kernel version to check if addon exists
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"
  # Read addons from user config
  unset ADDONS
  declare -A ADDONS
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  NEXT="a"
  # Loop menu
  while true; do
    dialog --backtitle "$(backtitle)" --default-item ${NEXT} \
      --menu "$(TEXT "Choose a option")" 0 0 0 \
      a "$(TEXT "Add an addon") $(echo -e $(carArrow))" \
      d "$(TEXT "Delete addon(s)")" \
      s "$(TEXT "Show user addons") $(echo -e $(carArrow))" \
      m "$(TEXT "Show all available addons") $(echo -e $(carArrow))" \
      o "$(TEXT "Download a external addon")" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      NEXT='a'
      rm "${TMP_PATH}/menu"
      while read ADDON DESC; do
        arrayExistItem "${ADDON}" "${!ADDONS[@]}" && continue # Check if addon has already been added
        echo "${ADDON} \"${DESC}\"" >>"${TMP_PATH}/menu"
      done < <(availableAddons "${PLATFORM}" "${KVER}")
      if [ ! -f "${TMP_PATH}/menu" ]; then
        dialog --backtitle "$(backtitle)" --msgbox "$(TEXT "No available addons to add")" 0 0
        NEXT="e"
        continue
      fi
      dialog --backtitle "$(backtitle)" --menu "$(TEXT "Select an addon")" 0 0 0 \
        --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      ADDON="$(<"${TMP_PATH}/resp")"
      [ -z "${ADDON}" ] && continue
      dialog --backtitle "$(backtitle)" --title "$(TEXT "params")" \
        --inputbox "$(TEXT "Type a opcional params to addon")" 0 0 \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      ADDONS[${ADDON}]="$(<"${TMP_PATH}/resp")"
      writeConfigKey "addons.${ADDON}" "${VALUE}" "${USER_CONFIG_FILE}"
      DIRTY=1
      ;;
    d)
      NEXT='d'
      if [ ${#ADDONS[@]} -eq 0 ]; then
        dialog --backtitle "$(backtitle)" --msgbox "$(TEXT "No user addons to remove")" 0 0
        continue
      fi
      ITEMS=""
      for I in "${!ADDONS[@]}"; do
        ITEMS+="${I} ${I} off "
      done
      dialog --backtitle "$(backtitle)" --no-tags \
        --checklist "$(TEXT "Select addon to remove")" 0 0 0 ${ITEMS} \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      ADDON="$(<"${TMP_PATH}/resp")"
      [ -z "${ADDON}" ] && continue
      for I in ${ADDON}; do
        unset ADDONS[${I}]
        deleteConfigKey "addons.${I}" "${USER_CONFIG_FILE}"
      done
      DIRTY=1
      ;;
    s)
      NEXT='s'
      ITEMS=""
      for KEY in ${!ADDONS[@]}; do
        ITEMS+="${KEY}: ${ADDONS[$KEY]}\n"
      done
      dialog --backtitle "$(backtitle)" --title "$(TEXT "User addons")" \
        --msgbox "${ITEMS}" 0 0
      ;;
    m)
      NEXT='m'
      MSG=""
      while read MODULE DESC; do
        if arrayExistItem "${MODULE}" "${!ADDONS[@]}"; then
          MSG+="\Z4${MODULE}\Zn"
        else
          MSG+="${MODULE}"
        fi
        MSG+=": \Z5${DESC}\Zn\n"
      done < <(availableAddons "${PLATFORM}" "${KVER}")
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Available addons")" \
        --colors --msgbox "${MSG}" 0 0
      ;;
    o)
      TEXT="$(TEXT "please enter the complete URL to download.")\n"
      dialog --backtitle "$(backtitle)" --aspect 18 --colors --inputbox "${TEXT}" 0 0 \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      URL="$(<"${TMP_PATH}/resp")"
      [ -z "${URL}" ] && continue
      clear
      echo "$(TEXT "Downloading") ${URL}"
      STATUS=$(curl -k -w "%{http_code}" -L "${URL}" -o "${TMP_PATH}/addon.tgz" --progress-bar)
      if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
        dialog --backtitle "$(backtitle)" --title "Error downloading" --aspect 18 \
          --msgbox "$(TEXT "Check internet, URL or cache disk space")" 0 0
        return 1
      fi
      ADDON="$(untarAddon "${TMP_PATH}/addon.tgz")"
      if [ -n "${ADDON}" ]; then
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Success")" --aspect 18 \
          --msgbox "Addon '${ADDON}' added to loader" 0 0
      else
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Invalid addon")" --aspect 18 \
          --msgbox "$(TEXT "File format not recognized!")" 0 0
      fi
      ;;
    e) return ;;
    esac
  done
}

###############################################################################
function cmdlineMenu() {
  unset CMDLINE
  declare -A CMDLINE
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
  done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
  echo "a \"$(TEXT "Add/edit a cmdline item")\"" >"${TMP_PATH}/menu"
  echo "d \"$(TEXT "Delete cmdline item(s)")\"" >>"${TMP_PATH}/menu"
  echo "c \"$(TEXT "Define a custom MAC")\"" >>"${TMP_PATH}/menu"
  echo "s \"$(TEXT "Show user cmdline")\"" >>"${TMP_PATH}/menu"
  echo "m \"$(TEXT "Show model/version cmdline")\"" >>"${TMP_PATH}/menu"
  echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"
  # Loop menu
  while true; do
    dialog --backtitle "$(backtitle)" --menu "$(TEXT "Choose a option")" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      dialog --backtitle "$(backtitle)" --title "$(TEXT "User cmdline")" \
        --inputbox "$(TEXT "Type a name of cmdline")" 0 0 \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      NAME="$(sed 's/://g' <"${TMP_PATH}/resp")"
      [ -z "${NAME}" ] && continue
      dialog --backtitle "$(backtitle)" --title "$(TEXT "User cmdline")" \
        --inputbox "$(printf "$(TEXT "Type a value of '%s' cmdline")" "${NAME}")" 0 0 "${CMDLINE[${NAME}]}" \ 
      2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      VALUE="$(<"${TMP_PATH}/resp")"
      CMDLINE[${NAME}]="${VALUE}"
      writeConfigKey "cmdline.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
      ;;
    d)
      if [ ${#CMDLINE[@]} -eq 0 ]; then
        dialog --backtitle "$(backtitle)" --msgbox "$(TEXT "No user cmdline to remove")" 0 0
        continue
      fi
      ITEMS=""
      for I in "${!CMDLINE[@]}"; do
        [ -z "${CMDLINE[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${CMDLINE[${I}]} off "
      done
      dialog --backtitle "$(backtitle)" \
        --checklist "$(TEXT "Select cmdline to remove")" 0 0 0 ${ITEMS} \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      RESP=$(<"${TMP_PATH}/resp")
      [ -z "${RESP}" ] && continue
      for I in ${RESP}; do
        unset CMDLINE[${I}]
        deleteConfigKey "cmdline.${I}" "${USER_CONFIG_FILE}"
      done
      ;;
    c)
      while true; do
        dialog --backtitle "$(backtitle)" --title "$(TEXT "User cmdline")" \
          --inputbox "Type a custom MAC address" 0 0 "${CMDLINE['mac1']}" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && break
        MAC="$(<"${TMP_PATH}/resp")"
        [ -z "${MAC}" ] && MAC="$(readConfigKey "original-mac" "${USER_CONFIG_FILE}")"
        MAC1="$(echo "${MAC}" | sed 's/://g')"
        [ ${#MAC1} -eq 12 ] && break
        dialog --backtitle "$(backtitle)" --title "$(TEXT "User cmdline")" --msgbox "$(TEXT "Invalid MAC")" 0 0
      done
      CMDLINE["mac1"]="${MAC1}"
      CMDLINE["netif_num"]=1
      writeConfigKey "cmdline.mac1" "${MAC1}" "${USER_CONFIG_FILE}"
      writeConfigKey "cmdline.netif_num" "1" "${USER_CONFIG_FILE}"
      MAC="${MAC1:0:2}:${MAC1:2:2}:${MAC1:4:2}:${MAC1:6:2}:${MAC1:8:2}:${MAC1:10:2}"
      ip link set dev eth0 address ${MAC} 2>&1 | dialog --backtitle "$(backtitle)" \
        --title "User cmdline" --progressbox "$(TEXT "Changing mac")" 20 70
      /etc/init.d/S41dhcpcd restart 2>&1 | dialog --backtitle "$(backtitle)" \
        --title "User cmdline" --progressbox "$(TEXT "Renewing IP")" 20 70
      IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print$7}')
      ;;
    s)
      ITEMS=""
      for KEY in ${!CMDLINE[@]}; do
        ITEMS+="${KEY}: ${CMDLINE[$KEY]}\n"
      done
      dialog --backtitle "$(backtitle)" --title "$(TEXT "User cmdline")" \
        --aspect 18 --msgbox "${ITEMS}" 0 0
      ;;
    m)
      ITEMS=""
      while IFS=': ' read KEY VALUE; do
        ITEMS+="${KEY}: ${VALUE}\n"
      done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Model cmdline")" \
        --aspect 18 --msgbox "${ITEMS}" 0 0
      ;;
    e) return ;;
    esac
  done
}

###############################################################################
function synoinfoMenu() {
  # Read synoinfo from user config
  unset SYNOINFO
  declare -A SYNOINFO
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
  done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

  echo "a \""$(TEXT "Add/edit a synoinfo item")"\"" >"${TMP_PATH}/menu"
  echo "d \""$(TEXT "Delete synoinfo item(s)")"\"" >>"${TMP_PATH}/menu"
  echo "s \""$(TEXT "Show synoinfo entries")"\"" >>"${TMP_PATH}/menu"
  echo "e \""$(TEXT "Exit")"\"" >>"${TMP_PATH}/menu"

  # menu loop
  while true; do
    dialog --backtitle "$(backtitle)" --menu "$(TEXT "Choose a option")" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Synoinfo entries")" \
        --inputbox "$(TEXT "Type a name of synoinfo entry")" 0 0 \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      NAME="$(<"${TMP_PATH}/resp")"
      [ -z "${NAME}" ] && continue
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Synoinfo entries")" \
        --inputbox "$(printf "$(TEXT "Type a value of '${NAME}' entry")" "${NAME}")" 0 0 "${SYNOINFO[${NAME}]}" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      VALUE="$(<"${TMP_PATH}/resp")"
      SYNOINFO[${NAME}]="${VALUE}"
      writeConfigKey "synoinfo.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
      DIRTY=1
      ;;
    d)
      if [ ${#SYNOINFO[@]} -eq 0 ]; then
        dialog --backtitle "$(backtitle)" --msgbox "$(TEXT "No synoinfo entries to remove")" 0 0
        continue
      fi
      ITEMS=""
      for I in "${!SYNOINFO[@]}"; do
        [ -z "${SYNOINFO[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${SYNOINFO[${I}]} off "
      done
      dialog --backtitle "$(backtitle)" \
        --checklist "$(TEXT "Select synoinfo entry to remove")" 0 0 0 ${ITEMS} \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      RESP=$(<"${TMP_PATH}/resp")
      [ -z "${RESP}" ] && continue
      for I in ${RESP}; do
        unset SYNOINFO[${I}]
        deleteConfigKey "synoinfo.${I}" "${USER_CONFIG_FILE}"
      done
      DIRTY=1
      ;;
    s)
      ITEMS=""
      for KEY in ${!SYNOINFO[@]}; do
        ITEMS+="${KEY}: ${SYNOINFO[$KEY]}\n"
      done
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Synoinfo entries")" \
        --aspect 18 --msgbox "${ITEMS}" 0 0
      ;;
    e) return ;;
    esac
  done
}

###############################################################################
# Extract linux and ramdisk files from the DSM .pat
function extractDsmFiles() {
  PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"

  SPACELEFT=$(df --block-size=1 | awk '/'${LOADER_DEVICE_NAME}'3/{print $4}') # Check disk space left

  PAT_FILE="${MODEL}-${PRODUCTVER}.pat"
  PAT_PATH="${CACHE_PATH}/dl/${PAT_FILE}"
  EXTRACTOR_PATH="${CACHE_PATH}/extractor"
  EXTRACTOR_BIN="syno_extract_system_patch"
  OLDPAT_URL="https://global.download.synology.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"

  if [ -f "${PAT_PATH}" ]; then
    echo "$(printf "$(TEXT "%s cached.")" "${PAT_FILE}")"
  else
    # If we have little disk space, clean cache folder
    if [ ${CLEARCACHE} -eq 1 ]; then
      echo "Cleaning cache"
      rm -rf "${CACHE_PATH}/dl"
    fi
    mkdir -p "${CACHE_PATH}/dl"

    fastest=$(_get_fastest "global.synologydownload.com" "global.download.synology.com" "cndl.synology.cn")
    mirror="$(echo ${PATURL} | sed 's|^http[s]*://\([^/]*\).*|\1|')"
    if echo "${mirrors[@]}" | grep -wq "${mirror}" && [ "${mirror}" != "${fastest}" ]; then
      echo "$(printf "$(TEXT "Based on the current network situation, switch to %s mirror to downloading.")" "${fastest}")"
      PATURL="$(echo ${PATURL} | sed "s/${mirror}/${fastest}/")"
      OLDPATURL="https://${fastest}/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
    fi
    echo "$(printf "$(TEXT "Downloading %s")" "${PAT_FILE}")"
    # Discover remote file size
    FILESIZE=$(curl -k -sLI "${PAT_URL}" | grep -i Content-Length | awk '{print$2}')
    if [ 0${FILESIZE} -ge ${SPACELEFT} ]; then
      # No disk space to download, change it to RAMDISK
      PAT_PATH="${TMP_PATH}/${PAT_FILE}"
    fi
    STATUS=$(curl -k -w "%{http_code}" -L "${PAT_URL}" -o "${PAT_PATH}" --progress-bar)
    if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
      rm "${PAT_PATH}"
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Error downloading")" --aspect 18 \
        --msgbox "$(TEXT "Check internet or cache disk space")" 0 0
      return 1
    fi
  fi

  echo -n "Checking hash of ${PAT_FILE}: "
  if [ "$(md5sum ${PAT_PATH} | awk '{print $1}')" != "${PATSUM}" ]; then
    dialog --backtitle "$(backtitle)" --title "$(TEXT "Error")" --aspect 18 \
      --msgbox "$(TEXT "md5 Hash of pat not match, try again!")" 0 0
    rm -f ${PAT_PATH}
    return 1
  fi
  echo "OK"

  rm -rf "${UNTAR_PAT_PATH}"
  mkdir "${UNTAR_PAT_PATH}"
  echo -n "Disassembling ${PAT_FILE}: "

  header="$(od -bcN2 ${PAT_PATH} | head -1 | awk '{print $3}')"
  case ${header} in
  105)
    echo "Uncompressed tar"
    isencrypted="no"
    ;;
  213)
    echo "Compressed tar"
    isencrypted="no"
    ;;
  255)
    echo "Encrypted"
    isencrypted="yes"
    ;;
  *)
    dialog --backtitle "$(backtitle)" --title "$(TEXT "Error")" --aspect 18 \
      --msgbox "$(TEXT "Could not determine if pat file is encrypted or not, maybe corrupted, try again!")" \
      0 0
    return 1
    ;;
  esac

  SPACELEFT=$(df --block-size=1 | awk '/'${LOADER_DEVICE_NAME}'3/{print$4}') # Check disk space left

  if [ "${isencrypted}" = "yes" ]; then
    # Check existance of extractor
    if [ -f "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" ]; then
      echo "Extractor cached."
    else
      # Extractor not exists, get it.
      mkdir -p "${EXTRACTOR_PATH}"
      # Check if old pat already downloaded
      OLDPAT_PATH="${CACHE_PATH}/dl/DS3622xs+-42218.pat"
      if [ ! -f "${OLDPAT_PATH}" ]; then
        echo "$(TEXT "Downloading old pat to extract synology .pat extractor...")"
        # Discover remote file size
        FILESIZE=$(curl -k -sLI "${OLDPAT_URL}" | grep -i Content-Length | awk '{print$2}')
        if [ 0${FILESIZE} -ge ${SPACELEFT} ]; then
          # No disk space to download, change it to RAMDISK
          OLDPAT_PATH="${TMP_PATH}/DS3622xs+-42218.pat"
        fi
        STATUS=$(curl -k -w "%{http_code}" -L "${OLDPAT_URL}" -o "${OLDPAT_PATH}" --progress-bar)
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          rm "${OLDPAT_PATH}"
          dialog --backtitle "$(backtitle)" --title "$(TEXT "Error downloading")" --aspect 18 \
            --msgbox "$(TEXT "Check internet or cache disk space")" 0 0
          return 1
        fi
      fi
      # Extract DSM ramdisk file from PAT
      rm -rf "${RAMDISK_PATH}"
      mkdir -p "${RAMDISK_PATH}"
      tar -xf "${OLDPAT_PATH}" -C "${RAMDISK_PATH}" rd.gz >"${LOG_FILE}" 2>&1
      if [ $? -ne 0 ]; then
        rm -f "${OLDPAT_PATH}"
        rm -rf "${RAMDISK_PATH}"
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Error extracting")" --textbox "${LOG_FILE}" 0 0
        return 1
      fi
      [ ${CLEARCACHE} -eq 1 ] && rm -f "${OLDPAT_PATH}"
      # Extract all files from rd.gz
      (
        cd "${RAMDISK_PATH}"
        xz -dc <rd.gz | cpio -idm
      ) >/dev/null 2>&1 || true
      # Copy only necessary files
      for f in libcurl.so.4 libmbedcrypto.so.5 libmbedtls.so.13 libmbedx509.so.1 libmsgpackc.so.2 libsodium.so libsynocodesign-ng-virtual-junior-wins.so.7; do
        cp "${RAMDISK_PATH}/usr/lib/${f}" "${EXTRACTOR_PATH}"
      done
      cp "${RAMDISK_PATH}/usr/syno/bin/scemd" "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}"
      rm -rf "${RAMDISK_PATH}"
    fi
    # Uses the extractor to untar pat file
    echo "$(TEXT "Extracting...")"
    LD_LIBRARY_PATH=${EXTRACTOR_PATH} "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" "${PAT_PATH}" "${UNTAR_PAT_PATH}" || true
  else
    echo "$(TEXT "Extracting...")"
    tar -xf "${PAT_PATH}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
    if [ $? -ne 0 ]; then
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Error extracting")" --textbox "${LOG_FILE}" 0 0
    fi
  fi

  echo -n "$(TEXT "Checking hash of zImage: ")"
  if [ ! -f ${UNTAR_PAT_PATH}/grub_cksum.syno ] ||
    [ ! -f ${UNTAR_PAT_PATH}/GRUB_VER ] ||
    [ ! -f ${UNTAR_PAT_PATH}/zImage ] ||
    [ ! -f ${UNTAR_PAT_PATH}/rd.gz ]; then
    dialog --backtitle "$(backtitle)" --title "$(TEXT "Error")" --aspect 18 \
      --msgbox "$(TEXT "pat Invalid, try again!")" 0 0
    return 1
  fi

  echo -n "$(TEXT "Setting hash: ")"
  ZIMAGE_HASH="$(sha256sum ${UNTAR_PAT_PATH}/zImage | awk '{print $1}')"
  writeConfigKey "zimage-hash" "${ZIMAGE_HASH}" "${USER_CONFIG_FILE}"

  RAMDISK_HASH="$(sha256sum ${UNTAR_PAT_PATH}/rd.gz | awk '{print $1}')"
  writeConfigKey "ramdisk-hash" "${RAMDISK_HASH}" "${USER_CONFIG_FILE}"

  echo "$(TEXT "OK")"

  echo -n "$(TEXT "Copying files: ")"
  cp "${UNTAR_PAT_PATH}/grub_cksum.syno" "${BOOTLOADER_PATH}"
  cp "${UNTAR_PAT_PATH}/GRUB_VER" "${BOOTLOADER_PATH}"
  cp "${UNTAR_PAT_PATH}/grub_cksum.syno" "${SLPART_PATH}"
  cp "${UNTAR_PAT_PATH}/GRUB_VER" "${SLPART_PATH}"
  cp "${UNTAR_PAT_PATH}/zImage" "${ORI_ZIMAGE_FILE}"
  cp "${UNTAR_PAT_PATH}/rd.gz" "${ORI_RDGZ_FILE}"
  rm -rf "${UNTAR_PAT_PATH}"
  echo "OK"
}

# 1 - model
function getLogo() {
  rm -f "${CACHE_PATH}/logo.png"
  fix something
  if [ "${DSMLOGO}" = "true" ]; then
    optimize
    fastest=$(_get_fastest "www.synology.com" "www.synology.cn")
    STATUS=$(curl -skL -w "%{http_code}" "https://${fastest}/api/products/getPhoto?product=${MODEL/+/%2B}&type=img_s&sort=0" -o "${CACHE_PATH}/logo.png")
    fix something
    if [ $? -ne 0 -o ${STATUS} -ne 200 -o -f "${CACHE_PATH}/logo.png" ]; then
      convert -rotate 180 "${CACHE_PATH}/logo.png" "${CACHE_PATH}/logo.png" 2>/dev/null
      magick montage "${CACHE_PATH}/logo.png" -background 'none' -tile '3x3' -geometry '350x210' "${CACHE_PATH}/logo.png" 2>/dev/null
      convert -rotate 180 "${CACHE_PATH}/logo.png" "${CACHE_PATH}/logo.png" 2>/dev/null
    fi
    optimize somethings
  fi
}

###############################################################################
# Where the magic happens!
function make() {
  clear
  # get logo.png
  getLogo "${MODEL}"

  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"

  # Check if all addon exists
  while IFS=': ' read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}"; then
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Error")" --aspect 18 \
        --msgbox "$(printf "$(TEXT "Addon %s not found!")" "${ADDON}")" 0 0
      return 1
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

  [ ! -f "${ORI_ZIMAGE_FILE}" -o ! -f "${ORI_RDGZ_FILE}" ] && extractDsmFiles

  /opt/arpl/zimage-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --title "$(TEXT "Error")" --aspect 18 \
      --msgbox "$(TEXT "zImage not patched:")\n$(<"${LOG_FILE}")" 0 0
    return 1
  fi

  /opt/arpl/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --title "$(TEXT "Error")" --aspect 18 \
      --msgbox "$(TEXT "Ramdisk not patched:")\n$(<"${LOG_FILE}")" 0 0
    return 1
  fi

  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
  SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"

  echo "$(TEXT "Cleaning")"
  rm -rf "${UNTAR_PAT_PATH}"

  echo "$(TEXT "Ready!")"
  sleep 3
  DIRTY=0
  return 0
}

###############################################################################
# Advanced menu
function advancedMenu() {
  NEXT="l"
  while true; do
    rm "${TMP_PATH}/menu"
    if [ -n "${PRODUCTVER}" ]; then
      echo "l \"$(TEXT "Switch LKM version"): \Z4${LKM}\Zn\"" >>"${TMP_PATH}/menu"
      echo "o \"$(TEXT "Modules") $(carArrow)\"" >>"${TMP_PATH}/menu"
    fi
    if loaderIsConfigured; then
      echo "r \"$(TEXT "Switch direct boot"): \Z4${DIRECTBOOT}\Zn\"" >>"${TMP_PATH}/menu"
    fi
    echo "u \"$(TEXT "Edit user config file manually")\"" >>"${TMP_PATH}/menu"
    echo "t \"$(TEXT "Try to recovery a DSM installed system")\"" >>"${TMP_PATH}/menu"
    echo "s \"$(TEXT "Show SATA(s)) # ports and drives")\"" >>"${TMP_PATH}/menu"
    echo "g \"$(TEXT "Show dsm logo:") \Z4${DSMLOGO}\Zn\"" >>"${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

    dialog --default-item ${NEXT} --backtitle "$(backtitle)" --title "$(TEXT "Advanced")" \
      --colors --menu "$(TEXT "Choose the option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case $(<"${TMP_PATH}/resp") in
    l)
      [ "${LKM}" = "dev" ] && LKM='prod' || LKM='dev'
      writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
      DIRTY=1
      NEXT="o"
      ;;
    o)
      selectModules
      NEXT="r"
      ;;
    r)
      [ "${DIRECTBOOT}" = "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
      writeConfigKey "directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
      NEXT="u"
      ;;
    u)
      editUserConfig
      NEXT="e"
      ;;
    t) tryRecoveryDSM ;;
    s)
      MSG=""
      NUMPORTS=0
      for PCI in $(lspci -d ::106 | awk '{print$1}'); do
        NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
        MSG+="\Zb${NAME}\Zn\nPorts: "
        unset HOSTPORTS
        declare -A HOSTPORTS
        while read LINE; do
          ATAPORT="$(echo ${LINE} | grep -o 'ata[0-9]*')"
          PORT=$(echo ${ATAPORT} | sed 's/ata//')
          HOSTPORTS[${PORT}]=$(echo ${LINE} | grep -o 'host[0-9]*$')
        done < <(ls -l /sys/class/scsi_host | fgrep "${PCI}")
        while read PORT; do
          ls -l /sys/block | fgrep -q "${PCI}/ata${PORT}" && ATTACH=1 || ATTACH=0
          PCMD=$(cat /sys/class/scsi_host/${HOSTPORTS[${PORT}]}/ahci_port_cmd)
          [ "${PCMD}" = "0" ] && DUMMY=1 || DUMMY=0
          [ ${ATTACH} -eq 1 ] && MSG+="\Z2\Zb"
          [ ${DUMMY} -eq 1 ] && MSG+="\Z1"
          MSG+="${PORT}\Zn "
          NUMPORTS=$((${NUMPORTS} + 1))
        done < <(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
        MSG+="\n"
      done
      MSG+="$(printf "$(TEXT "\nTotal of ports: %s\n")" "${NUMPORTS}")"
      MSG+="$(TEXT "\nPorts with color \Z1red\Zn as DUMMY, color \Z2\Zbgreen\Zn has drive connected.")"
      dialog --backtitle "$(backtitle)" --colors --aspect 18 \
        --msgbox "${MSG}" 0 0
      ;;
    e) break ;;
    esac
  done
}

###############################################################################
# Try to recovery a DSM already installed
function tryRecoveryDSM() {
  dialog --backtitle "$(backtitle)" --title "$(TEXT "Try recovery DSM")" --aspect 18 \
    --infobox "$(TEXT "Trying to recovery a DSM installed system")" 0 0
  if findAndMountDSMRoot; then
    MODEL=""
    PRODUCTVER=""
    BUILDNUM=""
    SMALLNUM=""
    if [ -f "${DSMROOT_PATH}/.syno/patch/VERSION" ]; then
      eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep unique)
      eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep majorversion)
      eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep minorversion)
      eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep buildnumber)
      eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep smallfixnumber)
      if [ -n "${unique}" ]; then
        while read F; do
          M="$(basename ${F})"
          M="${M::-4}"
          UNIQUE=$(readModelKey "${M}" "unique")
          [ "${unique}" = "${UNIQUE}" ] || continue
          # Found
          modelMenu "${M}"
        done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
        if [ -n "${MODEL}" ]; then
          productversMenu ${base}
          if [ -n "${PRODUCTVER}" ]; then
            cp "${DSMROOT_PATH}/.syno/patch/zImage" "${SLPART_PATH}"
            cp "${DSMROOT_PATH}/.syno/patch/rd.gz" "${SLPART_PATH}"
            MSG="$(printf "$(TEXT "Found a installation:\nModel: %s\nProductversion: %s")" "${MODEL}" "${PRODUCTVER}")"
            SN=$(_get_conf_kv SN "${DSMROOT_PATH}/etc/synoinfo.conf")
            if [ -n "${SN}" ]; then
              writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
              MSG+="\nSerial: ${SN}"
            fi
            BUILDNUM=${buildnumber}
            SMALLNUM=${smallfixnumber}
            writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
            writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "$(TEXT "Try recovery DSM")" \
              --aspect 18 --msgbox "${MSG}" 0 0
          fi
        fi
      fi
    fi
  else
    dialog --backtitle "$(backtitle)" --title "$(TEXT "Try recovery DSM")" --aspect 18 \
      --msgbox "$(TEXT "Unfortunately I couldn't mount the DSM partition!")" 0 0
  fi
}

###############################################################################
# Permit user select the modules to include
function selectModules() {
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"
  dialog --backtitle "$(backtitle)" --title "Modules" --aspect 18 \
    --infobox "$(TEXT "Reading modules")" 0 0
  ALLMODULES=$(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
  unset USERMODULES
  declare -A USERMODULES
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
  done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
  # menu loop
  while true; do
    dialog --backtitle "$(backtitle)" --menu "$(TEXT "Choose a option")" 0 0 0 \
      s "$(TEXT "Show selected modules") $(echo -e $(carArrow))" \
      a "$(TEXT "Select all modules")" \
      d "$(TEXT "Deselect all modules")" \
      c "$(TEXT "Choose modules to include") $(echo -e $(carArrow))" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case "$(<${TMP_PATH}/resp)" in
    s)
      ITEMS=""
      for KEY in ${!USERMODULES[@]}; do
        ITEMS+="${KEY}: ${USERMODULES[$KEY]}\n"
      done
      dialog --backtitle "$(backtitle)" --title "$(TEXT "User modules")" \
        --msgbox "${ITEMS}" 0 0
      ;;
    a)
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Modules")" \
        --infobox "$(TEXT "Selecting all modules")" 0 0
      unset USERMODULES
      declare -A USERMODULES
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      while read ID DESC; do
        USERMODULES["${ID}"]=""
        writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
      done <<<${ALLMODULES}
      ;;

    d)
      dialog --backtitle "$(backtitle)" --title "Modules" \
        --infobox "$(TEXT "Deselecting all modules")" 0 0
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      unset USERMODULES
      declare -A USERMODULES
      ;;

    c)
      rm -f "${TMP_PATH}/opts"
      while read ID DESC; do
        arrayExistItem "${ID}" "${!USERMODULES[@]}" && ACT="on" || ACT="off"
        echo "${ID} ${DESC} ${ACT}" >>"${TMP_PATH}/opts"
      done <<<${ALLMODULES}
      dialog --backtitle "$(backtitle)" --title "Modules" --aspect 18 \
        --checklist "$(TEXT "Select modules to include")" 0 0 0 \
        --file "${TMP_PATH}/opts" 2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      resp=$(<${TMP_PATH}/resp)
      [ -z "${resp}" ] && continue
      dialog --backtitle "$(backtitle)" --title "Modules" \
        --infobox "$(TEXT "Writing to user config")" 0 0
      unset USERMODULES
      declare -A USERMODULES
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      for ID in ${resp}; do
        USERMODULES["${ID}"]=""
        writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
      done
      ;;

    e)
      break
      ;;
    esac
  done
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    dialog --backtitle "$(backtitle)" --title "Edit with caution" \
      --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return
    mv "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=$(yq eval "${USER_CONFIG_FILE}" 2>&1)
    [ $? -eq 0 ] && break
    dialog --backtitle "$(backtitle)" --title "$(TEXT "Invalid YAML format")" --msgbox "${ERRORS}" 0 0
  done
  OLDMODEL=${MODEL}
  OLDPRODUCTVER=${PRODUCTVER}
  OLDBUILDNUM=${BUILDNUM}
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
  SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"

  if [ "${MODEL}" != "${OLDMODEL}" -o "${PRODUCTVER}" != "${OLDPRODUCTVER}" -o "${BUILDNUM}" != "${OLDBUILDNUM}" ]; then
    # Remove old files
    rm -f "${MOD_ZIMAGE_FILE}"
    rm -f "${MOD_RDGZ_FILE}"
  fi
  DIRTY=1
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  [ ${DIRTY} -eq 1 ] && dialog --backtitle "$(backtitle)" --title "$(TEXT "Alert")" \
    --yesno "$(TEXT "Config changed, would you like to rebuild the loader?")" 0 0
  if [ $? -eq 0 ]; then
    make || return
  fi
  boot.sh
}

###############################################################################
# Shows language to user choose one
function languageMenu() {

  unset ITEMS
  unset ITEMS_KEY
  declare -a ITEMS_KEY

  COUNT=0
  INDEX_DEFAULT=0

  for i in "${!available_locales[@]}"; do
    COUNT=$((COUNT + 1))
    ITEMS=("${ITEMS[@]}" ${COUNT} "${available_locales[$i]//\"/}")
    ITEMS_KEY=("${ITEMS_KEY[@]}" "$i")
    [ "${LC_ALL%.UTF-8}" = "$i" ] && INDEX_DEFAULT=${COUNT}
  done

  cmd=(dialog --backtitle "$(backtitle)" --default-item "${INDEX_DEFAULT}"
  --menu "$(TEXT "Choose a language")" 0 0 0)
  choice=$("${cmd[@]}" "${ITEMS[@]}" 2>&1 >/dev/tty)
  [[ $? -ne 0 ]] && return
  choice=$(($choice - 1))
  export LANGUAGE="${ITEMS_KEY[$choice]}"
  export LC_ALL="${ITEMS_KEY[$choice]}.UTF-8"
  echo ${LC_ALL} >${BOOTLOADER_PATH}/.locale
}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  dialog --backtitle "$(backtitle)" --default-item "${LAYOUT}" --no-items \
    --menu "$(TEXT "Choose a layout")" 0 0 0 "azerty" "bepo" "carpalx" "colemak" \
    "dvorak" "fgGIod" "neo" "olpc" "qwerty" "qwertz" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  LAYOUT="$(<${TMP_PATH}/resp)"
  OPTIONS=""
  while read KM; do
    OPTIONS+="${KM::-7} "
  done < <(
    cd /usr/share/keymaps/i386/${LAYOUT}
    ls *.map.gz
  )
  dialog --backtitle "$(backtitle)" --no-items --default-item "${KEYMAP}" \
    --menu "$(TEXT "Choice a keymap")" 0 0 0 ${OPTIONS} \
    2>/tmp/resp
  [ $? -ne 0 ] && return
  resp=$(cat /tmp/resp 2>/dev/null)
  [ -z "${resp}" ] && return
  KEYMAP=${resp}
  writeConfigKey "layout" "${LAYOUT}" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
  loadkeys /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz
}

###############################################################################
function updateMenu() {
  CUR_ARPL_VER="${ARPL_VERSION:-0}"
  CUR_ADDONS_VER="$(cat "${CACHE_PATH}/addons/VERSION" 2>/dev/null)"
  CUR_MODULES_VER="$(cat "${CACHE_PATH}/modules/VERSION" 2>/dev/null)"
  CUR_LKMS_VER="$(cat "${CACHE_PATH}/lkms/VERSION" 2>/dev/null)"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  while true; do
    dialog --backtitle "$(backtitle)" --menu "$(TEXT "Choose a option")" 0 0 0 \
      a "$(TEXT "Update arpl")" \
      d "$(TEXT "Update addons")" \
      l "$(TEXT "Update LKMs")" \
      m "$(TEXT "Update modules")" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update arpl")" --aspect 18 \
        --infobox "$(TEXT "Checking last version")" 0 0
      ACTUALVERSION="v${ARPL_VERSION}"
      TAG="$(curl -k -s https://api.github.com/repos/jimmyGALLAND/arpl/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
      if [ $? -ne 0 -o -z "${TAG}" ]; then
        dialog --backtitle "$(backtitle)" --title "Update arpl" --aspect 18 \
          --msgbox "$(TEXT "Error checking new version")" 0 0
        continue
      fi
      if [ "${ACTUALVERSION}" = "${TAG}" ]; then
        dialog --backtitle "$(backtitle)" --title "Update arpl" --aspect 18 \
          --yesno "$(printf "$(TEXT "No new version. Actual version is %s\nForce update?")" "${ACTUALVERSION}")" 0 0
        [ $? -ne 0 ] && continue
      fi
      dialog --backtitle "$(backtitle)" --title "Update arpl" --aspect 18 \
        --infobox "$(TEXT "Downloading last version") ${TAG}" 0 0
      # Download update file
      STATUS=$(curl -k -w "%{http_code}" -L \
        "https://github.com/jimmyGALLAND/arpl/releases/download/${TAG}/update.zip" -o /tmp/update.zip)
      if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
        dialog --backtitle "$(backtitle)" --title "Update arpl" --aspect 18 \
          --msgbox "$(TEXT "Error downloading update file")" 0 0
        continue
      fi
      unzip -oq /tmp/update.zip -d /tmp
      if [ $? -ne 0 ]; then
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Update arpl")" --aspect 18 \
          --msgbox "$(TEXT "Error extracting update file")" 0 0
        continue
      fi
      # Check checksums
      (cd /tmp && sha256sum --status -c sha256sum)
      if [ $? -ne 0 ]; then
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Update arpl")" --aspect 18 \
          --msgbox "$(TEXT "Checksum do not match!")" 0 0
        continue
      fi
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update arpl")" --aspect 18 \
        --infobox "$(TEXT "Installing new files")" 0 0
      # Process update-list.yml
      while read F; do
        [ -f "${F}" ] && rm -f "${F}"
        [ -d "${F}" ] && rm -Rf "${F}"
      done < <(readConfigArray "remove" "/tmp/update-list.yml")
      while IFS=': ' read KEY VALUE; do
        if [ "${KEY: -1}" = "/" ]; then
          rm -Rf "${VALUE}"
          mkdir -p "${VALUE}"
          tar -zxf "/tmp/$(basename "${KEY}").tgz" -C "${VALUE}"
        else
          mkdir -p "$(dirname "${VALUE}")"
          mv "/tmp/$(basename "${KEY}")" "${VALUE}"
        fi
      done < <(readConfigMap "replace" "/tmp/update-list.yml")
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update arpl")" --aspect 18 \
        --yesno "$(printf "$(TEXT "Arpl updated with success to %s!\nReboot?")" "${TAG}")" 0 0
      [ $? -ne 0 ] && continue
      arpl-reboot.sh config
      exit
      ;;

    d)
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update addons")" --aspect 18 \
        --infobox "$(TEXT "Checking last version")" 0 0
      TAG=$(curl -k -s https://api.github.com/repos/jimmyGALLAND/arpl-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
      if [ $? -ne 0 -o -z "${TAG}" ]; then
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Update addons")" --aspect 18 \
          --msgbox "$(TEXT "Error checking new version")" 0 0
        continue
      fi
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update addons")" --aspect 18 \
        --infobox "$(TEXT "Downloading last version")" 0 0
      STATUS=$(curl -k -s -w "%{http_code}" -L "https://github.com/jimmyGALLAND/arpl-addons/releases/download/${TAG}/addons.zip" -o /tmp/addons.zip)
      if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Update addons")" --aspect 18 \
          --msgbox "$(TEXT "Error downloading new version")" 0 0
        continue
      fi
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update addons")" --aspect 18 \
        --infobox "$(TEXT "Extracting last version")" 0 0
      rm -rf /tmp/addons
      mkdir -p /tmp/addons
      unzip /tmp/addons.zip -d /tmp/addons >/dev/null 2>&1
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update addons")" --aspect 18 \
        --infobox "$(TEXT "Installing new addons")" 0 0
      rm -Rf "${ADDONS_PATH}/"*
      for PKG in $(ls /tmp/addons/*.addon); do
        ADDON=$(basename ${PKG} | sed 's|.addon||')
        rm -rf "${ADDONS_PATH}/${ADDON}"
        mkdir -p "${ADDONS_PATH}/${ADDON}"
        tar -xaf "${PKG}" -C "${ADDONS_PATH}/${ADDON}" >/dev/null 2>&1
      done
      DIRTY=1
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update addons")" --aspect 18 \
        --msgbox "$(TEXT "Addons updated with success!")" 0 0
      ;;

    l)
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update LKMs")" --aspect 18 \
        --infobox "$(TEXT "Checking last version")" 0 0
      TAG=$(curl -k -s https://api.github.com/repos/jimmyGALLAND/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
      if [ $? -ne 0 -o -z "${TAG}" ]; then
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Update LKMs")" --aspect 18 \
          --msgbox "$(TEXT "Error checking new version")" 0 0
        continue
      fi
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update LKMs")" --aspect 18 \
        --infobox "$(TEXT "Downloading last version")" 0 0
      STATUS=$(curl -k -s -w "%{http_code}" -L "https://github.com/jimmyGALLAND/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o /tmp/rp-lkms.zip)
      if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Update LKMs")" --aspect 18 \
          --msgbox "$(TEXT "Error downloading last version")" 0 0
        continue
      fi
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update LKMs")" --aspect 18 \
        --infobox "$(TEXT "Extracting last version")" 0 0
      rm -rf "${LKM_PATH}/"*
      unzip /tmp/rp-lkms.zip -d "${LKM_PATH}" >/dev/null 2>&1
      DIRTY=1
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update LKMs")" --aspect 18 \
        --msgbox "$(TEXT "LKMs updated with success!")" 0 0
      ;;
    m)
      unset PLATFORMS
      declare -A PLATFORMS
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update Modules")" --aspect 18 \
        --infobox "$(TEXT "Checking last version")" 0 0
      TAG=$(curl -k -s https://api.github.com/repos/jimmyGALLAND/arpl-modules/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
      if [ $? -ne 0 -o -z "${TAG}" ]; then
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Update Modules")" --aspect 18 \
          --msgbox "$(TEXT "Error checking new version")" 0 0
        continue
      fi
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update Modules")" --aspect 18 \
        --infobox "$(TEXT "Downloading modules")" 0 0
      STATUS=$(curl -k -s -w "%{http_code}" -L "https://github.com/jimmyGALLAND/arpl-modules/releases/download/${TAG}/modules.zip" -o "/tmp/modules.zip")
      if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Update Modules")" --aspect 18 \
          --msgbox "$(TEXT "Error downloading ") modules.zip" 0 0
        continue
      fi
      rm -rf "${MODULES_PATH}"
      unzip -o "/tmp/modules.zip" -d "${MODULES_PATH}" >/dev/null 2>&1
      # Rebuild modules if model/buildnumber is selected
      if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        while read ID DESC; do
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        done < <(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
      fi
      DIRTY=1
      dialog --backtitle "$(backtitle)" --title "$(TEXT "Update Modules")" --aspect 18 \
        --msgbox "$(TEXT "Modules updated with success!")" 0 0
      ;;
    e) return ;;
    esac
  done
}

###############################################################################
###############################################################################

if [ "x$1" = "xb" -a -n "${MODEL}" -a -n "${PRODUCTVER}" -a loaderIsConfigured ]; then
  install-addons.sh
  make
  boot && exit 0 || sleep 5
fi
# Main loop
NEXT="m"
while true; do
  echo -e "m \"$(TEXT "Choose a model") $(carArrow)\"" >"${TMP_PATH}/menu"
  if [ -n "${MODEL}" ]; then
    echo -e "n \"$(TEXT "Choose a version") $(carArrow)\"" >>"${TMP_PATH}/menu"
    echo "s \"$(TEXT "Choose a serial number")\"" >>"${TMP_PATH}/menu"
    if [ -n "${PRODUCTVER}" ]; then
      echo -e "a \"$(TEXT "Addons") $(carArrow)\"" >>"${TMP_PATH}/menu"
      echo -e "x \"$(TEXT "Cmdline menu") $(carArrow)\"" >>"${TMP_PATH}/menu"
      echo -e "i \"$(TEXT "Synoinfo menu") $(carArrow)\"" >>"${TMP_PATH}/menu"
    fi
  fi
  echo -e "v \"$(TEXT "Advanced menu") $(carArrow)\"" >>"${TMP_PATH}/menu"
  if [ -n "${MODEL}" ]; then
    if [ -n "${PRODUCTVER}" ]; then
      echo "d \"$(TEXT "Build the loader")\"" >>"${TMP_PATH}/menu"
    fi
  fi
  if loaderIsConfigured; then
    echo "b \"$(TEXT "Boot the loader")\" " >>"${TMP_PATH}/menu"
  fi
  echo -e "l \"$(TEXT "Choose a language") $(carArrow)\"" >>"${TMP_PATH}/menu"
  echo -e "k \"$(TEXT "Choose a keymap") $(carArrow)\"" >>"${TMP_PATH}/menu"
  if [ ${CLEARCACHE} -eq 1 -a -d "${CACHE_PATH}/dl" ]; then
    echo "c \"$(TEXT "Clean disk cache")\"" >>"${TMP_PATH}/menu"
  fi
  echo -e "p \"$(TEXT "Update menu") $(carArrow)\"" >>"${TMP_PATH}/menu"
  echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

  dialog --default-item ${NEXT} --backtitle "$(backtitle)" --no-cancel --colors \
    --menu "$(TEXT "Choose the option")" 0 0 0 --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && break
  case $(<"${TMP_PATH}/resp") in
  m)
    modelMenu
    NEXT="n"
    ;;
  n)
    productversMenu
    NEXT="s"
    ;;
  s)
    serialMenu
    NEXT="a"
    ;;
  a)
    addonMenu
    NEXT="x"
    ;;
  x)
    cmdlineMenu
    NEXT="i"
    ;;
  i)
    synoinfoMenu
    NEXT="v"
    ;;
  v)
    advancedMenu
    NEXT="d"
    ;;
  d)
    make
    NEXT="b"
    ;;
  b) boot && exit 0 || sleep 5 ;;
  l) languageMenu ;;
  k) keymapMenu ;;
  c) dialog --backtitle "$(backtitle)" --title "$(TEXT "Cleaning")" --aspect 18 \
    --prgbox "rm -rfv \"${CACHE_PATH}/dl\"" 0 0 ;;
  p) updateMenu ;;
  e) break ;;
  esac
done
clear
echo -e "$(printf "$(TEXT "Call %s to return to menu")" "\033[1;32mmenu.sh\033[0m")"
