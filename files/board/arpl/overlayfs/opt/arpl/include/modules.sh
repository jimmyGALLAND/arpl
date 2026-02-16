
###############################################################################
# Return list of all modules available
# 1 - Platform
# 2 - Kernel Version
# 3 - Version 7.1/7.2 ...
function getAllModules() {
  PLATFORM=${1}
  KVER=${2}
  DSMVERS=${3}
  # Unzip modules for temporary folder
  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  tar -zxf "${MODULES_PATH}/${PLATFORM}-${DSMVERS}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  # Get list of all modules
  for F in `ls ${TMP_PATH}/modules/*.ko`; do
    X=`basename ${F}`
    M=${X:0:-3}
    DESC=`modinfo ${F} | awk -F':' '/description:/{ print $2}' | awk '{sub(/^[ ]+/,""); print}'`
    [ -z "${DESC}" ] && DESC="${X}"
    echo "${M} \"${DESC}\""
  done
  rm -rf "${TMP_PATH}/modules"
  exit
}
