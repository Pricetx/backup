#!/bin/bash

# Ensure that all possible binary paths are checked
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# Provides the 'log' command to simultaneously log to
# STDOUT and the log file with a single command
log() {
        echo "$1"
        echo "$(date -u +%Y-%m-%d-%H%M)" "$1" >> "${LOGFILE}"
}

# Load the backup settings
source ./backup.cfg

### CHECKS ###

# This section checks for all of the binaries used in the backup
BINARIES=( date find openssl rm rsync scp ssh tar )

# Iterate over the list of binaries, and if one isn't found, abort
for BINARY in "${BINARIES[@]}"; do
        if [ ! "$(command -v $BINARY)" ]; then
                log "$BINARY is not installed. Install it and try again"
                exit
        fi
done

# Check if the backup folders exist and are writeable
# also, check if the OpenSSL X509 certificate exists
if [ ! -w "${LOCALDIR}" ]; then
        log "${LOCALDIR} either doesn't exist or isn't writable"
        log "Either fix or replace the LOCALDIR setting"
        exit
elif [ ! -w "${TEMPDIR}" ]; then
        log "${TEMPDIR} either doesn't exist or isn't writable"
        log "Either fix or replace the TEMPDIR setting"
        exit
elif [ ! -r "${CRTFILE}" ]; then
        log "${CRTFILE} either doesn't exist or isn't readable"
        log "Either fix or replace the CRTFILE setting"
        exit
fi

        fi
fi

### END OF TAR BACKUP ###

### RSYNC BACKUP ###

log "Starting rsync backups"
for i in ${RSYNCDIR[@]}; do
        rsync -avz --no-links --progress --delete --relative -e"ssh -p ${REMOTEPORT}" $i ${REMOTEUSER}@${REMOTESERVER}:${REMOTEDIR}
done
log "rsync backups complete"

### END OF RSYNC BACKUP ###

### BACKUP DELETION ##

if [[ $(uname) == 'FreeBSD' ]]; then

        log "Deleting old local backups"
        # Deletes backups older than 1 week
        find ${LOCALDIR} -name "*.tgz.enc" -mmin +${LOCALAGEDAILIES} -exec rm {} \;

        log "Deleting old remote backups"
        ssh -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTESERVER} "find ${REMOTEDIR} -name \"*tgz.enc\" -mmin +${REMOTEAGEDAILIES} -exec rm {} \;"

elif [[ $(uname) == 'Linux' ]]; then

        log "Deleting old local backups"

        # Local backup deletion

        # If file is older than 1 week and not created on a monday then delete it
        find ${LOCALDIR} -name ".tgz.enc" -type f -mmin +${LOCALAGEDAILIES} -exec sh -c 'test $(date +%a -r $1) = Mon || rm "$1"' -- {} \;

        # If the file is older than 28 days and not from first monday of month
        find ${LOCALDIR} -name ".tgz.enc" -type f -mtime +${LOCALAGEWEEKLIES} -exec sh -c 'test $(date +%d -r "$1") -le 7 -a $(date +%a -r "$1") = Mon || rm "$1"' -- {} \;

        # If file is older than 6 months delete it
        find ${LOCALDIR} -name "*.tgz.enc" -type f -mmin +${LOCALAGEMONTHLIES} -exec rm {} \;

        log "Deleting old remote backups"

        # Remote backup deletion

        # If file is older than 1 week and not created on a monday then delete it
        ssh -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTESERVER} "find ${REMOTEDIR} -name \"*tgz.enc\" -type f -mmin +${REMOTEAGEDAILIES} -exec sh -c 'test $(date +%a -r \"$1\") = Mon || rm \"$1\"' -- {} \;"

        # If the file is older than 28 days and not from first monday of month
        ssh -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTESERVER} "find ${REMOTEDIR} -name \".tgz.enc\" -type f -mtime +${REMOTEAGEWEEKLIES} -exec sh -c 'test $(date +%d -r \"$1\") -le 7 -a $(date +%a -r \"$1\") = Mon || rm \"$1\"' -- {} \;"

        # If file is older than 6 months delete it
        ssh -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTESERVER} "find ${REMOTEDIR} -name \"*.tgz.enc\" -type f -mmin +${REMOTEAGEMONTHLIES} -exec rm {} \;"

fi

### END OF BACKUP DELETION ###

ENDTIME=$(date +%s)
DURATION=$((ENDTIME - STARTTIME))
log "All done. Backup and transter completed in ${DURATION} seconds"
