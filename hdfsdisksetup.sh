#!/bin/bash
#title          : disksetup.sh
#description    : prepares disks on the system for use on HDFS filesystem.
#                 1) Format the disks as ext4
#                 2) Mounts the disks
#                 3) Update fstab
#                 4) Create dn,nn and YARN directories
#                 5) Set directory ownerships
#author         : Nabeel Moidu <nabeel.moidu@lazada.com>
#date           : 20170531
#version        : 0.1    
#usage          : bash disksetup.sh
#notes          :       
#bash_version   : 4.2.46(1)-release
#============================================================================

# Set options
DISKLIST_FILE="/tmp/disklist"
MOUNT_ROOT="/grid"
FORMAT_CMD="mkfs -t"
FILESYSTEM_TYPE="ext4"
FORMAT_OPTIONS="-F -m 1 -T largefile -O dir_index,extent,sparse_super"
MOUNT_OPTIONS="rw,noatime,nodelalloc"
DISKSETUP_LOG="./disksetup.log"

# First list out options
usage()  {
    echo "Usage: "
    echo "        disksetup.sh : Do a dry run and generate disklist file in /tmp/disklist for review"
    echo "        disksetup.sh -r <filename> : Format disks listed in file provided with ext4 and mount them for HDFS use"
    echo "        disksetup.sh -l <filename> : Use <filename> as log file for current script execution"
}

# Default no arguments is just disk list creation for review.

logMessage() {

  # FORMAT : "DATE | TIME | SEVERITY | MESSAGE"
  local now=`date +%Y-%m-%d\ %H:%M:%S.$(( $(date +%-N) / 1000000 ))`
  local level=$1
  shift
  local logentry="$now $level $*"
  # If log file not writable, redirect output to console
  if [ -w $DISKSETUP_LOG ]; then
    echo $logentry >> $DISKSETUP_LOG
  else
    echo $logentry
  fi

}

isRoot()  {
  local uid
  local amRoot
  uid=$(id -u)
  amRoot=0
  if [ "$uid" -ne 0 ]
  then
    amRoot=1
  fi

  return $amRoot
}

getDiskSize()  {

  # This auto disk detection routine relies on grouping the sizes of all available disks and choosing the largest disk
  # type for HDFS. The actual script execution does not rely on this. The final disk choices are decided 
  # by the disk list file passed on as argument to the -r option when running the script.
  
  disksize=$(fdisk -l | grep ^Disk | grep sectors | cut -d " " -f 5 | sort -n | uniq |tail -1)
}

genDiskFile()  {

  local disk
  getDiskSize
  FULL_DISK_SET=$(fdisk -l  |grep "${disksize}" | cut -d " " -f2 | tr -d ":")
  if [ ${#FULL_DISK_SET[@]} -ne 0 ]; then
    [ -w $DISKLIST_FILE ] || ( echo $DISKLIST_FILE "Not Writable. Exiting" && exit 1)
    # Clear any existing filecontents
    if [ -f $DISKLIST_FILE ]; then
      logMessage INFO "Emptying contents of file: $DISKLIST_FILE" && truncate -s 0 filename
    fi
    # Echo unpartitioned disks to the disklist file
    for disk in  ${FULL_DISK_SET};
      do has_filesystem "$disk" || (echo "$disk" >> $DISKLIST_FILE) ;
    done
    if [ -s $DISKLIST_FILE ] 
    then 
       logMessage INFO "Generated Disk list file at "$DISKLIST_FILE." Please review and re-run the script with -r <disklist_file> to format disks"
    else
       logMessage INFO "No disks listed in file. Check if disks on host are already formatted with a filesystem."
       logMessage INFO "In this case, manually add the disks to the disklist file"
    fi
  else
     logMessage INFO "No disks detected. Perhaps expected disk name patterns may have changed."
  fi

}

has_filesystem() {
  DEVICE=${1}
  OUTPUT=$(file -L -s "${DEVICE}")
  grep -i filesystem <<< "${OUTPUT}" > /dev/null 2>&1
  return ${?}
}

getDisks() 
{
  DISK_ARRAY=()
  local i=0
  local disk
  while IFS= read -r disk
  do
    DISK_ARRAY[i]="$disk"
    ((i++))
  done < <(grep "^/dev/.*[a-z]$" "$DISKLIST")
  if [ $i -eq 0 ]; then
    echo "No disks found" && exit 1
  fi
}

formatDisks()  {

  getDisks
  local disk
  if [ ${#DISK_ARRAY[@]} -lt 1 ]
    then
       logMessage FATAL "No disks available for HDFS.Exiting" && exit 1
  fi
  echo "=============================================================="
  echo "THIS WILL FORMAT THE DISKS LISTED BELOW. ALL DATA WILL BE LOST"
  echo "=============================================================="
  for disk in "${DISK_ARRAY[@]}"
    do echo "$disk"
  done
  echo "======================================="
  read -p "Confirm? " -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
    then
    for disk in "${DISK_ARRAY[@]}"
      do 
      if [ -b "$disk" ]; then
        if mount | grep "${disk}"
        then
           logMessage WARN "${disk} is already mounted. Will not format ${disk}" && continue
        fi 
        echo "================================================="
        echo "               Formatting $disk                  "
        echo "================================================="
        $FORMAT_CMD $FILESYSTEM_TYPE $FORMAT_OPTIONS $disk
        if [ ${?} -eq 0 ]
        then
          mountDisks $disk
        else
          logMessage ERROR "Disk format failed for $disk"
        fi
      else
        logMessage WARN "No such disk or device : $disk"
      fi  
    done
  else
    logMessage FATAL " Please review input disklist file.Exiting " && exit 1
  fi
  
}

mountDisks() {

  local mount_disk=$1 dir_name dir_num dir_list mount_path

  if [ ! -d $MOUNT_ROOT ];
  then
    mount_path="${MOUNT_ROOT}/0"
  else
    dir_list=`ls -1d ${MOUNT_ROOT}/* 2>&1| sort --version-sort|awk -F\/ '$NF ~ /^[0-9]+$/ { print $NF }'`
    if [ -z "${dir_list[0]}" ];
    then
      if ! mount |grep -q "${MOUNT_ROOT}/0" 
      then
        mount_path="${MOUNT_ROOT}/0"
      else
        mount_path="${MOUNT_ROOT}/$(getMountDir 0)"
      fi
    else
      dir_num=$((${#dir_list[@]}-1))
      # Check if the directory already has a mounted filesystem. If so bump value again till
      # we get a directory which isn't mounted.
      while :
      do
        dir_num=$(( dir_num + 1 ))
        if ! mount|grep "${MOUNT_ROOT}/${dir_num}" 
        then
          mount_path="${MOUNT_ROOT}/${dir_num}" && break
        fi
      done 
    fi
  fi
  
  mkdir -p "${mount_path}"
  logMessage INFO  "======================================================================================"
  logMessage INFO "Mounting ${mount_disk} on ${mount_path} with options ${MOUNT_OPTIONS}"
  logMessage INFO "======================================================================================"
  mount -t ${FILESYSTEM_TYPE} -o ${MOUNT_OPTIONS} ${mount_disk} ${mount_path}
  if [ ${?} -eq 0 ];
  then
    addToEtcFstab "${mount_disk}" "${mount_path}"  
    makeHDFSdirs "${mount_path}"
    makeYarnDirs "${mount_path}"
  else
    rmdir "${mount_path}"
    logMessage ERROR "Mount failed for ${mount_disk} on ${mount_path}"
    exit 1
  fi
}

makeHDFSdirs()  {

    local mount_path=${1}
    logMessage INFO "Creating HDFS directories under $mount_path/hdfs"
    mkdir -p "${mount_path}/hdfs/dn"
    if [ "$mount_path" == "${MOUNT_ROOT}/0" ]; then
      mkdir -p "${mount_path}/hdfs/nn"
      mkdir -p "${mount_path}/hdfs/snn"
      chown -R hdfs:hadoop "${mount_path}/hdfs"
    fi

}

makeYarnDirs()  {

    local mount_path=${1}
    logMessage INFO "Creating YARN directories under ${mount_path}/yarn"
    mkdir -p "${mount_path}/yarn/local"
    mkdir -p "${mount_path}/yarn/logs"
    chown -R yarn:hadoop "${mount_path}/yarn"
}

addToEtcFstab() {

  local disk=${1}
  local mount_path=${2}
  #UUID=`lsblk -bo name,uuid|grep "${disk}" |tr -s " "| cut -d " " -f2`
  UUID=$(blkid -s UUID -o value ${disk})
  GREP_PATTERN=" -e ${disk} -e ${mount_path} "  

  if [ -b "/dev/disk/by-uuid/${UUID}" ];
  then
    GREP_PATTERN="${GREP_PATTERN} -e ${UUID}"
  else 
     logMessage ERROR "Unable to detect valid UUID. Skipping fstab update for disk :${disk} " && return
  fi

  if grep -w "${GREP_PATTERN}" /etc/fstab >/dev/null 2>&1
  then
    logMessage WARN "Not adding ${UUID} ${disk} to fstab again (it's already there!)"
    exit 1
  else
    LINE="UUID=\"${UUID}\"\t${mount_path}\t${FILESYSTEM_TYPE}\t${MOUNT_OPTIONS},data=ordered\t0 0"
    logMessage INFO  "Updating fstab with entry "
    logMessage INFO "${LINE}"
    echo -e "${LINE}" >> /etc/fstab
  fi
}

# main

isRoot
amRoot=$?
if [ $amRoot -ne 0 ]
then
  logMessage FATAL "Cannot execute script as non-root user. Exiting " && exit 1
fi



logMessage INFO "======================================================================================"
logMessage INFO "                 Starting execution of script disksetup.sh "
logMessage INFO "======================================================================================"

# If run without arguments, generate disk list file for review and exit.
if [ $# -lt 1 ]
      then
        genDiskFile
        exit 0
      fi
      
while [ "${1+isset}" ]; do
  case "$1" in
    -r|--run)
      if [ $# -lt 2 ]
      then
        echo "Missing disk list file" 
        logMessage FATAL "Missing disk list file. Exiting" 
        usage
        exit 1;
      fi
      DISKLIST=$2
      shift 2
      ;;
    -l|--log)
      if [ $# -lt 2 ]
      then
        echo "Missing log file argument. Using default value ${DISKSETUP_LOG} "
        logMessage WARN "Missing log file argument. Using default value for DISKSETUP LOG: ${DISKSETUP_LOG} " 
      elif [ -w $2 ] 
        DISKSETUP_LOG=$2
      else
        echo "Log file provided not writable. Using default value ${DISKSETUP_LOG} "
        logMessage WARN "Log file provided not writable. Using default value for DISKSETUP LOG: ${DISKSETUP_LOG} " 
      fi
      shift 2
      ;;
    -\?|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Other functions to mount disks, update fstab, create directories etc. all invoked one after other in nested calls. 
# TODO: bring all function invocations here
formatDisks
