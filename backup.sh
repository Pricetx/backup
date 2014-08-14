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
if [ ! -w "$LOCALDIR" ]; then
        log "${LOCALDIR} either doesn't exist or isn't writable"
        log "Either fix or replace the LOCALDIR setting"
        exit
elif [ ! -w "$TEMPDIR" ]; then
        log "${TEMPDIR} either doesn't exist or isn't writable"
        log "Either fix or replace the TEMPDIR setting"
        exit
elif [ ! -r "${CRTFILE}" ]; then
        log "${CRTFILE} either doesn't exist or isn't readable"
        log "Either fix or replace the CRTFILE setting"
        exit
fi

# Check that SSH login to remote server is successful
if [ ! "$(ssh -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTESERVER} echo test)" ]; then
        log "Failed to login to ${REMOTEUSER}@${REMOTESERVER}"
        log "Make sure that your public key is in their authorized_keys"
        exit
fi

# Check that remote directory exists and is writeable
if [ $(ssh -p "${REMOTEPORT}" "${REMOTEUSER}"@"${REMOTESERVER}" touch "${REMOTEDIR}"/test) ]; then
        log "Failed to write to ${REMOTEDIR} on ${REMOTESERVER}"
        log "Check file permissions and that ${REMOTEDIR} is correct"
        exit
else
        ssh -p "${REMOTEPORT}" "${REMOTEUSER}"@"${REMOTESERVER}" rm "${REMOTEDIR}"/test
fi

BACKUPDATE=$(date -u +%Y-%m-%d-%H%M)
STARTTIME=$(date +%s)
TARFILE="${LOCALDIR}""$(hostname)"-"${BACKUPDATE}".tgz
SQLFILE="${TEMPDIR}mysql_${BACKUPDATE}.sql"

cd "${LOCALDIR}"

### END OF CHECKS ###

### MYSQL BACKUP ###

if [ ! $(command -v mysqldump) ]; then
        log "mysqldump not found, not backing up MySQL!"
elif [ -z $ROOTMYSQL ]; then
        log "MySQL root password not set, not backing up MySQL!"
else
        log "Starting MySQL dump dated ${BACKUPDATE}"
        mysqldump -u root -p${ROOTMYSQL} --all-databases > ${SQLFILE}
        log "MySQL dump complete"

        #Add MySQL backup to BACKUP list
        BACKUP=(${BACKUP[*]} ${SQLFILE})
fi

### END OF MYSQL BACKUP ###

### TAR BACKUP ###

log "Starting tar backup dated ${BACKUPDATE}"
# Prepare tar command
TARCMD="-zcf ${TARFILE} ${BACKUP[*]}"

# Add exclusions to front of command
for i in ${EXCLUDE[@]}; do
        TARCMD="--exclude $i ${TARCMD}"
done

# Run tar
tar ${TARCMD}

# Encrypt tar file
log "Encrypting backup"
openssl smime -encrypt -aes256 -binary -in ${TARFILE} -out ${TARFILE}.enc -outform DER -stream ${CRTFILE}
log "Encryption completed"

# Delete unencrypted tar
rm "${TARFILE}"

BACKUPSIZE=$(du -h "${TARFILE}".enc | cut -f1)
log "Tar backup complete. Filesize: ${BACKUPSIZE}"

log "Tranferring tar backup to remote server"
scp -P "${REMOTEPORT}" "${TARFILE}".enc "${REMOTEUSER}"@"${REMOTESERVER}":"${REMOTEDIR}"
log "File transfer completed"

if [ ! $(command -v mysqldump) ]; then
        log "Deleting temporary MySQL backup"
        rm ${SQLFILE}
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

log "Deleting old local backups"

#If file is older than 1 week and not created on a monday then delete it
find ${LOCALDIR} -name ".tgz.enc" -type f -mmin +${LOCALAGEDAILIES} -exec sh -c 'test $(date +%a -r $1) = Mon || rm "$1"' -- {} \;

#If the file is older than 28 days and not from first monday of month
find ${LOCALDIR} -name ".tgz.enc" -type f -mtime +${LOCALAGEWEEKLIES} -exec sh -c 'test $(date +%d -r "$1") -le 7 -a $(date +%a -r "$1") = Mon || rm "$1"' -- {} \;

#If file is older than 6 months delete it
find ${LOCALDIR} -name "*.tgz.enc" -type f -mmin +${LOCALAGEMONTHLIES} -exec rm {} \;

log "Deleting old remote backups"

#If file is older than 1 week and not created on a monday then delete it
ssh -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTESERVER} "find ${REMOTEDIR} -name \"*tgz.enc\" -type f -mmin +${REMOTEAGEDAILIES} -exec sh -c 'test $(date +%a -r \"$1\") = Mon || rm \"$1\"' -- {} \;"

#If the file is older than 28 days and not from first monday of month
ssh -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTESERVER} "find ${LOCALDIR} -name \".tgz.enc\" -type f -mtime +${LOCALAGEWEEKLIES} -exec sh -c 'test $(date +%d -r \"$1\") -le 7 -a $(date +%a -r \"$1\") = Mon || rm \"$1\"' -- {} \;"

#If file is older than 6 months delete it
ssh -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTESERVER} "find ${LOCALDIR} -name \"*.tgz.enc\" -type f -mmin +${LOCALAGEMONTHLIES} -exec rm {} \;"

### END OF BACKUP DELETION ###

ENDTIME=$(date +%s)
DURATION=$((ENDTIME - STARTTIME))
log "All done. Backup and transter completed in ${DURATION} seconds"
