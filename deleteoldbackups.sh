#!/bin/bash

#Ensure that all possible binary paths are checked
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

#Directory the script is in (for later use)
SCRIPTNAME="${BASH_SOURCE[0]}"
SCRIPTDIR="$( cd "$( dirname "${SCRIPTNAME}" )" && pwd )"


log() {
    echo "$1"
    echo "$(date -u +%Y-%m-%d-%H%M)" "$1" >> "deleted.log"
}


getFileDate() {
    unset FILEHOSTNAME FILEYEAR FILEMONTH FILEDAY FILETIME
    FILEHOSTNAME=$(echo "$1" | cut -d - -f 1)
    FILEYEAR=$(echo "$1" | cut -d - -f 2)
    FILEMONTH=$(echo "$1" | cut -d - -f 3)
    FILEDAY=$(echo "$1" | cut -d - -f 4)
    FILETIME=$(echo "$1" | cut -d - -f 5)

    #Approximate a 30-day month and 365-day year
    FILEDAYS=$(( $((10#${FILEYEAR}*365)) + $((10#${FILEMONTH}*30)) + $((10#${FILEDAY})) ))
    FILEAGE=$(( 10#${DAYS} - 10#${FILEDAYS} ))

    if [ "${BACKUPHOSTNAME}" == "${FILEHOSTNAME}" ]; then
        if [[ "${FILEYEAR}" && "${FILEMONTH}" && "${FILEDAY}" && "${FILETIME}" ]]; then
            return 0
        fi
    fi

    return 1 #File isn't a backup archive
}


deleteBackups() {
    #Get current time
    #Be careful when using time - GNU and BSD use different flags in many cases!
    DAY=$(date +%d)
    MONTH=$(date +%m)
    YEAR=$(date +%C%y)

    #Approximate a 30-day month and 365-day year
    DAYS=$(( $((10#${YEAR}*365)) + $((10#${MONTH}*30)) + $((10#${DAY})) ))


    cd "${BACKUPDIR}"
    log "Checking for backups to delete"

    #Iterate over all .tgz.enc files
    for f in *.tgz*; do
        getFileDate "$f"
        KEEPFILE="NO"

        if [ $? == 0 ]; then
            #It's a valid backup file and has the correct hostname

            #Delete all old monthlies
            if [[ ${FILEAGE} -gt ${AGEMONTHLIES} ]]; then
                #Do nothing - leave $KEEPFILE as NO
                log "$f DELETED - was over ${AGEMONTHLIES} days old"

            #Clean up old weeklies to monthlies (made on the 1st only)
            elif [[ ${FILEAGE} -gt ${AGEWEEKLIES} ]]; then
                if [ "${FILEDAY}" == 01 ]; then
                    #Mark to be kept
                    KEEPFILE="YES"
                    log "$f held back as monthly backup"
                fi

            #Clean up old dailies to weeklies (made on the 1st, 8th, 15th, 22nd, 29th)
            elif [[ ${FILEAGE} -gt ${AGEDAILIES} ]]; then
                for i in 01 08 15 22 29; do
                    if [ "${FILEDAY}" == $i ]; then 
                        #Mark to be kept
                        KEEPFILE="YES"
                        log "$f held back as weekly backup"
                    fi
                done

            #File is too new, don't delete
            else
                KEEPFILE="YES"
                log "$f held back as daily backup"
            fi


            #Delete the file if it's still not marked to be kept
            if [ ${KEEPFILE} == "NO" ]; then
                rm -f "$f"
                log "$f DELETED - pruned for granular backup"
            fi

        fi
    done

    log "Finished deleting old backups"
}


if [ "$1" == "--remote" ]; then
    #Send the config and this script to the remote server to be run
    source "${SCRIPTDIR}"/backup.cfg
    echo "BACKUPHOSTNAME=$(hostname)" > /tmp/hostname
    cat "${SCRIPTDIR}"/backup.cfg /tmp/hostname "${SCRIPTDIR}"/"${SCRIPTNAME}" | ssh -T -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTESERVER} "/usr/bin/env/bash"

elif [ $# == 0 ]; then
    #Check if config is already loaded
    if [ "${BACKUPHOSTNAME}" ]; then
        #We're running on the remote server - config already loaded
        BACKUPDIR=${REMOTEDIR}
        AGEDAILIES=${REMOTEAGEDAILIES}
        AGEWEEKLIES=${REMOTEAGEWEEKLIES}
        AGEMONTHLIES=${REMOTEAGEMONTHLIES}
    else
        #We're running locally - load the config
        source $(dirname $(realpath $0))/backup.cfg
        BACKUPDIR=${LOCALDIR}
        AGEDAILIES=${LOCALAGEDAILIES}
        AGEWEEKLIES=${LOCALAGEWEEKLIES}
        AGEMONTHLIES=${LOCALAGEMONTHLIES}
        BACKUPHOSTNAME=${HOSTNAME}
    fi

    #Everything hereon is run irrespective of whether we're on the local or remote machine
    deleteBackups
else
    #Script has been called with invalid flags
    echo "Usage: $0 [--remote]"
    exit
fi
