#!/usr/bin/env bash

#Ensure that all possible binary paths are checked
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin


log() {
    echo -e "$(date -u +%Y-%m-%d-%H%M)" "$1" >> "deleted.log"
    if [ "$2" != "noecho" ]; then
        echo -e "$1"
    fi
}


getFileDate() {
    unset FILEHOSTNAME FILEYEAR FILEMONTH FILEDAY FILETIME FILEDAYS FILEAGE
    FILEHOSTNAME=$(echo "$1" | cut -d - -f 1)
    FILEYEAR=$(echo "$1" | cut -d - -f 2)
    FILEMONTH=$(echo "$1" | cut -d - -f 3)
    FILEDAY=$(echo "$1" | cut -d - -f 4)
    FILETIME=$(echo "$1" | cut -d - -f 5)

    if [ "${BACKUPHOSTNAME}" == "${FILEHOSTNAME}" ]; then
        if [[ "${FILEYEAR}" && "${FILEMONTH}" && "${FILEDAY}" && "${FILETIME}" ]]; then
            #Approximate a 30-day month and 365-day year
            FILEDAYS=$(( $((10#${FILEYEAR}*365)) + $((10#${FILEMONTH}*30)) + $((10#${FILEDAY})) ))
            FILEAGE=$(( 10#${DAYS} - 10#${FILEDAYS} ))
            return 0
        fi
    fi

    return 1 #File isn't a backup archive
}

# Converts bytes to a human readable format
humanReadable() {
    HUMAN=$(echo "$1" | awk '{ split( "B KiB MiB GiB TiB PiB EiB ZiB YiB", s ); n=1; while( $1>1024 ){ $1/=1024; n++ } printf "%.2f %s", $1, s[n] }')
}

deleteBackups() {
    #Get current time
    #Be careful when using time - GNU and BSD use different flags in many cases!
    DAY=$(date +%d)
    MONTH=$(date +%m)
    YEAR=$(date +%C%y)

    #Approximate a 30-day month and 365-day year
    DAYS=$(( $((10#${YEAR}*365)) + $((10#${MONTH}*30)) + $((10#${DAY})) ))

    # Count how many backups have been deleted/kept, and how much space has been saved/used
    NDELETED=0
    NKEPT=0
    SPACEFREED=0
    SPACEUSED=0

    cd "${BACKUPDIR}" || exit

    #Iterate over all .enc files
    for f in *.enc; do
        KEEPFILE="NO"
        getFileDate "$f"

        if [ $? == 0 ]; then
            #It's a valid backup file and has the correct hostname

            #Delete all old monthlies
            if [[ ${FILEAGE} -gt ${AGEMONTHLIES} ]]; then
                : #Delete it - leave $KEEPFILE as NO

            #Clean up old weeklies to monthlies (made on the 1st only)
            elif [[ ${FILEAGE} -gt ${AGEWEEKLIES} ]]; then
                if [ "${FILEDAY}" == 01 ]; then
                    #Mark to be kept
                    KEEPFILE="YES"
                    log "$f held back as monthly backup" "noecho"

                    NKEPT=$(( 10#${NKEPT} + 1 ))
                    #Slightly dirty way of getting filesize, but it's the most portable (wc is slow)
                    LS=($(ls -l "$f"))
                    SPACEUSED=$(( 10#${SPACEUSED} + 10#${LS[4]} ))
                fi

            #Clean up old dailies to weeklies (made on the 1st, 8th, 15th, 22nd, 29th)
            elif [[ ${FILEAGE} -gt ${AGEDAILIES} ]]; then
                for i in 01 08 15 22 29; do
                    if [ "${FILEDAY}" == $i ]; then
                        #Mark to be kept
                        KEEPFILE="YES"
                        log "$f held back as weekly backup" "noecho"

                        NKEPT=$(( 10#${NKEPT} + 1 ))
                        LS=($(ls -l "$f"))
                        SPACEUSED=$(( 10#${SPACEUSED} + 10#${LS[4]} ))
                    fi
                done

            #File is too new, don't delete
            else
                KEEPFILE="YES"
                log "$f held back as daily backup" "noecho"

                NKEPT=$(( 10#${NKEPT} + 1 ))
                LS=($(ls -l "$f"))
                SPACEUSED=$(( 10#${SPACEUSED} + 10#${LS[4]} ))
            fi


            if [ ${KEEPFILE} == "NO" ]; then
                # Actually delete them
                NDELETED=$(( 10#${NDELETED} + 1 ))
                LS=($(ls -l "$f"))
                SPACEFREED=$(( 10#${SPACEFREED} + 10#${LS[4]} ))

                #Disable deletion for testing
                #rm -f "$f"
                log "$f DELETED"
            fi

        fi
    done

    # Output stats
    humanReadable ${SPACEFREED}; log "Deleted ${NDELETED} backups, freeing ${HUMAN}"
    humanReadable ${SPACEUSED}; log "${NKEPT} backups remain, taking up ${HUMAN}"
}

getAbsoluteConfig() {
    # Gets the absolute path of the config file
    if [ ! -e "${CONFIG}" ]; then
        echo "Couldn't find config file: ${CONFIG}"
        exit
    fi

    CONFIG=$( realpath "${CONFIG}" )
}

runLocally() {
    #Check if config is already loaded
    if [ "${BACKUPHOSTNAME}" ]; then
        # We're running on the remote server - config already loaded
        BACKUPDIR=${REMOTEDIR}
        AGEDAILIES=${REMOTEAGEDAILIES}
        AGEWEEKLIES=${REMOTEAGEWEEKLIES}
        AGEMONTHLIES=${REMOTEAGEMONTHLIES}
    else
        # We're running locally - load the config
        getAbsoluteConfig
        source "${CONFIG}"
        
        BACKUPDIR=${LOCALDIR}
        AGEDAILIES=${LOCALAGEDAILIES}
        AGEWEEKLIES=${LOCALAGEWEEKLIES}
        AGEMONTHLIES=${LOCALAGEMONTHLIES}
        BACKUPHOSTNAME=${HOSTNAME}
    fi

    #Everything hereon is run irrespective of whether we're on the local or remote machine
    deleteBackups
}

runRemotely() {
    #Send the config and this script to the remote server to be run
    getAbsoluteConfig
    source "${CONFIG}"
    
    echo "BACKUPHOSTNAME=$(hostname)" > /tmp/hostname
    cat "${CONFIG}" /tmp/hostname "${SCRIPTDIR}"/deleteoldbackups.sh | ssh -T -p "${REMOTEPORT}" "${REMOTEUSER}"@"${REMOTESERVER}" "/usr/bin/env bash"
    rm /tmp/hostname
}

showUsage() {
    echo "Usage: $0 [--remote] [--config filename]"
}

# START OF SCRIPT

# Directory the script is in (for later use)
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default config location
CONFIG="${SCRIPTDIR}"/backup.cfg


# Check arguments
if [ $# == 1 ] && [ "$1" == "--remote" ]; then
    runRemotely

elif [ $# == 2 ] && [ "$1" == "--config" ]; then
    # Load in config and proceed locally
    CONFIG="$2"
    runLocally

elif [ $# == 3 ]; then
    # 3 args: remote + config. Check which way round they're issued
    if [ "$1" == "--remote" ] && [ "$2" == "--config" ]; then
        CONFIG="$3"
        runRemotely
    elif [ "$1" == "--config" ] && [ "$3" == "--remote" ]; then
        CONFIG="$2"
        runRemotely
    else
        # Invalid args
        showUsage
    fi

elif [ $# == 0 ]; then
    # No args, run locally
    runLocally
else
    # Invalid args
    showUsage
fi
