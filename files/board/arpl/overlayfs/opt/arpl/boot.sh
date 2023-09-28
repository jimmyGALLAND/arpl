#!/usr/bin/env bash

set -e

. /opt/arpl/include/functions.sh

# Sanity check
loaderIsConfigured || die "$(TEXT "Loader is not configured!")"

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0

LOADER_DISK="$(blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1)"
BUS=$(udevadm info --query property --name ${LOADER_DISK} | grep ID_BUS | cut -d= -f2)
[ "${BUS}" = "ata" ] && BUS="sata"

# Print text centralized
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="$(printf "$(TEXT "Welcome to %s")" "${ARPL_TITLE}")"
printf "\033[1;44m%*s\n" ${COLUMNS} ""
printf "\033[1;44m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;32m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
printf "\033[1;44m%*s\033[0m\n" ${COLUMNS} ""
TITLE="$(TEXT "BOOTING...")"
[ -d "/sys/firmware/efi" ] && TITLE+=" [UEFI]" || TITLE+=" [BIOS]"
[ "${BUS}" = "usb" ] && TITLE+=" [USB flashdisk]" || TITLE+=" [SATA DoM]"
printf "\033[1;33m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"

DSMLOGO="$(readConfigKey "dsmlogo" "${USER_CONFIG_FILE}")"
if [ "${DSMLOGO}" = "true" -a -c "/dev/fb0" -a -f "${CACHE_PATH}/logo.png" ]; then
  echo | fbv -acuf "${CACHE_PATH}/logo.png" >/dev/null 2>/dev/null || true
fi

# Check if DSM zImage changed, patch it if necessary
ZIMAGE_HASH="$(readConfigKey "zimage-hash" "${USER_CONFIG_FILE}")"
if [ "$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print$1}')" != "${ZIMAGE_HASH}" ]; then
  echo -e "\033[1;43m$(TEXT "DSM zImage changed")\033[0m"
  /opt/arpl/zimage-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --title "$(TEXT "Error")" \
      --msgbox "$(TEXT "zImage not patched:\n")$(<"${LOG_FILE}")" 12 70
    exit 1
  fi
fi

# Check if DSM ramdisk changed, patch it if necessary
RAMDISK_HASH="$(readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}")"
RAMDISK_HASH_CUR="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')"
if [ "${RAMDISK_HASH_CUR}" != "${RAMDISK_HASH}" ]; then
  echo -e "\033[1;43m$(TEXT "DSM Ramdisk changed")\033[0m"
  /opt/arpl/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --title "$(TEXT "Error")" \
      --msgbox "$(TEXT "Ramdisk not patched:\n")$(<"${LOG_FILE}")" 12 70
    exit 1
  fi
  writeConfigKey "ramdisk-hash" "${RAMDISK_HASH_CUR}" "${USER_CONFIG_FILE}"
fi

# Load necessary variables
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
BPN="$(dmidecode -s 'baseboard-product-name' | sed 's/Default string//')"
SPN="$(dmidecode -s 'system-product-name' | sed 's/Default string//')"
DMI="$(dmesg | grep -i "DMI:" | sed 's/\[.*\] DMI: //i')"
CPU="$(echo $(cat /proc/cpuinfo | grep 'model name' | uniq | awk -F':' '{print $2}'))"
MEM="$(free -m | grep -i mem | awk '{print$2}') MB"

echo -e "$(TEXT "Model:") \033[1;36m${MODEL}\033[0m"
echo -e "$(TEXT "Build:") \033[1;36m${PRODUCTVER}(${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))\033[0m"
echo -e "$(TEXT "LKM:  ") \033[1;36m${LKM}\033[0m"
if [ -n "${BPN}" ]; then
  echo -e "$(TEXT "BPN:  ") \033[1;36m${BPN}\033[0m"
elif [ -n "${SPN}" ]; then
  echo -e "$(TEXT "SPN:  ") \033[1;36m${SPN}\033[0m"
else
  echo -e "$(TEXT "MBN:  ") \033[1;36mUnknown\033[0m"
fi
echo -e "$(TEXT "DMI:  ") \033[1;36m${DMI}\033[0m"
echo -e "$(TEXT "CPU:  ") \033[1;36m${CPU}\033[0m"
echo -e "$(TEXT "MEM:  ") \033[1;36m${MEM}\033[0m"

if [ ! -f "${MODEL_CONFIG_PATH}/${MODEL}.yml" ] || [ -z "$(readConfigKey "productvers.[${PRODUCTVER}]" "${MODEL_CONFIG_PATH}/${MODEL}.yml")" ]; then
  echo -e "\033[1;33m*** $(printf "$(TEXT "The current version of arpl does not support booting %s-%s, please rebuild.")" "${MODEL}" "${PRODUCTVER}") ***\033[0m"
  exit 1
fi

VID="$(readConfigKey "vid" "${USER_CONFIG_FILE}")"
PID="$(readConfigKey "pid" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
MAC1="$(readConfigKey "mac1" "${USER_CONFIG_FILE}")"

declare -A CMDLINE

# Fixed values
# Automatic values
CMDLINE['syno_hw_version']="${MODEL}"
[ -z "${VID}" ] && VID="0x46f4" # Sanity check
[ -z "${PID}" ] && PID="0x0001" # Sanity check
CMDLINE['vid']="${VID}"
CMDLINE['pid']="${PID}"
CMDLINE['sn']="${SN}"
CMDLINE['netif_num']=1

# Read cmdline
while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")

KVER=$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")

if [ ! "${BUS}" = "usb" ]; then
  LOADER_DEVICE_NAME=$(echo ${LOADER_DISK} | sed 's|/dev/||')
  SIZE=$(($(cat /sys/block/${LOADER_DEVICE_NAME}/size) / 2048 + 10))
  # Read SATADoM type
  DOM="$(readModelKey "${MODEL}" "dom")"
fi

# Validate netif_num
NETIF_NUM=${CMDLINE["netif_num"]}
MACS=0
for N in $(seq 1 9); do
  [ -n "${CMDLINE["mac${N}"]}" ] && MACS=$((${MACS} + 1))
done
if [ ${NETIF_NUM} -ne ${MACS} ]; then
  echo -e "\033[1;33m*** $(printf "$(TEXT "netif_num is not equal to macX amount, set netif_num to %s")" "${MACS}") ***\033[0m"
  CMDLINE["netif_num"]=${MACS}
fi

# Prepare command line
CMDLINE_LINE=""
grep -q "force_junior" /proc/cmdline && CMDLINE_LINE+="force_junior "
[ ${EFI} -eq 1 ] && CMDLINE_LINE+="withefi " || CMDLINE_LINE+="noefi "
[ ! "${BUS}" = "usb" ] && CMDLINE_LINE+="synoboot_satadom=${DOM} dom_szmax=${SIZE} "
CMDLINE_LINE+="console=ttyS0,115200n8 earlyprintk earlycon=uart8250,io,0x3f8,115200n8 root=/dev/md0 loglevel=15 log_buf_len=32M"
CMDLINE_DIRECT="${CMDLINE_LINE}"
for KEY in ${!CMDLINE[@]}; do
  VALUE="${CMDLINE[${KEY}]}"
  CMDLINE_LINE+=" ${KEY}"
  [ -n "${VALUE}" ] && CMDLINE_LINE+="=${VALUE}"
done
# Escape special chars
echo -e "$(TEXT "Cmdline:\n")\033[1;36m${CMDLINE_LINE}\033[0m"

# Wait for an IP
COUNT=0
echo -n "$(TEXT "IP")"
while true; do
  IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}')
  if [ -n "${IP}" ]; then
    echo -e ": \033[1;32m${IP}\033[0m"
    break
  elif [ ${COUNT} -eq 8 ]; then
    echo -e ": \033[1;31mERROR\033[0m"
    break
  fi
  COUNT=$((${COUNT} + 1))
  sleep 1
  echo -n "."
done

DIRECT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
if [ "${DIRECT}" = "true" ]; then
  CMDLINE_DIRECT=$(echo ${CMDLINE_LINE} | sed 's/>/\\\\>/g') # Escape special chars
  grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
  echo -e "\033[1;33m$(TEXT "Reboot to boot directly in DSM")\033[0m"
  grub-editenv ${GRUB_PATH}/grubenv set next_entry="direct"
  reboot
  exit 0

else

  echo -en "\r$(printf "%$((${#MSG} * 2))s" " ")\n"

  echo -e "\033[1;37m$(TEXT "Loading DSM kernel...")\033[0m"

  if [ "${KVER:0:1}" = "3" -a ${EFI} -eq 1 ]; then
    echo -e "\033[1;33m$(TEXT "Warning, running kexec with --noefi param, strange things will happen!!")\033[0m"
    kexec --noefi -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
  else
    kexec -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
  fi
  echo -e "\033[1;37m$(TEXT "Booting...")\033[0m"
  for T in $(w | grep -v "TTY" | awk -F' ' '{print $2}'); do
    echo -e "\n\033[1;43m$(TEXT "[This interface will not be operational. Please use the http://find.synology.com/ find DSM and connect.]")\033[0m\n" >"/dev/${T}" 2>/dev/null || true
  done
  KERNELWAY="$(readConfigKey "kernelway" "${USER_CONFIG_FILE}")"
  [ "${KERNELWAY}" = "kexec" ] && kexec -f -e || poweroff
  exit 0

fi
