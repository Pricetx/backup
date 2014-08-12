#!/usr/local/bin/bash

### CONFIGURATION STUFF ###
# ALL directories MUST have a trailing / (except for rsync)
# To generate the private key: 'openssl genrsa -out [nameofkey].key -aes256 4096'
# To generate the X509 certificate: 'openssl req -out [nameofkey].crt -new -key [nameofkey].key -x509'
# To decrypt backups: 'openssl smime -decrypt -in [nameofbackup].tgz.enc -inform DER -inkey [nameofkey].key -out [nameofbackup].tgz'
# KEEP THE PRIVATE KEY SAFE. It does not need to be kept on the server. If you lose it, you will NOT be able to unencrypt backups

# Directory to store backups
LOCALDIR="/root/backups/"

# Temporary directory used during backup creation
TEMPDIR="/root/backups/temp/"

# File to log the outcome of backups
LOGFILE="/root/backups/backup.log"

# The X509 certificate to encrypt the backup
CRTFILE="/root/NAME_OF_CERT.crt"

# The time (in minutes) to store local backups for
LOCALAGE="10080"

# The time (in minutes) to store remote backups for
REMOTEAGE="10080"

# IP / hostname of the server to store remote backups
REMOTESERVER="REMOTE_SERVER_HERE"

# SSH port of remote server
REMOTEPORT=22

# User to use with SSH (public key needs to be installed remotely)
REMOTEUSER="REMOTE_USER_HERE"

# Path to store the remote backups
REMOTEDIR="/BACKUP/PATH/ON/REMOTE/SYSTEM/"

# OPTIONAL: If MySQL is being backed up, enter the root password below
ROOTMYSQL=""


# Files and directories to backup
# To add new entries, just increment the number in brackets
BACKUP[0]="/root/backup.sh"
BACKUP[1]="/etc/"

# Files and directories to exclude from backup
# To add new entries, just increment the number in brackets
EXCLUDE[0]="/etc/master.passwd"


# Directories to rsync - these MUST NOT have a trailing /
# To add new entries, just increment the number in brackets
RSYNCDIR[0]="/home/pricetx"



### END OF CONFIGURATION ###
### DO NOT EDIT BELOW THIS LINE ###

log() {
        #log to screen and to logfile
        echo $1
        echo `date -u +%Y-%m-%d-%H%M` $1 >> ${LOGFILE}
}


# Check that all the required stuff exists
if [ ! -e $LOCALDIR ]; then
        log "${LOCALDIR} does not exist. Create it or fix the LOCALDIR variable"
        exit
elif [ ! -e $TEMPDIR ]; then
        log "${TEMPDIR} does not exist. Create it or fix the TEMPDIR variable"
        exit
elif [ ! -f /usr/bin/openssl ]; then
        log "openssl is not installed. Install it and try again"
        exit
elif [ ! -e ${CRTFILE} ]; then
        log "X509 certificate not found. Create one or fix the CRTFILE variable."
        exit
elif [ ! -f /usr/local/bin/rsync ]; then
        log "rsync is not intalled. Install it and try again"
        exit
fi



### VARIABLES - DO NOT EDIT ###
BACKUPDATE=`date -u +%Y-%m-%d-%H%M`
STARTTIME=`date +%s`
TARFILE="${LOCALDIR}`hostname`-${BACKUPDATE}.tgz"
SQLFILE="${TEMPDIR}mysql_${BACKUPDATE}.sql"

cd ${LOCALDIR}



### MYSQL BACKUP ###
if [ -f /usr/local/bin/mysql ]; then
        log "Starting MySQL dump dated ${BACKUPDATE}"
        /usr/local/bin/mysqldump -u root -p${ROOTMYSQL} --all-databases > ${SQLFILE}
        log "MySQL dump complete"

        #Add MySQL backup to BACKUP list
        BACKUP=(${BACKUP[*]} ${SQLFILE})
else
        log "MySQL not found, not backing up MySQL!"
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
/usr/bin/tar ${TARCMD}

# Encrypt tar file
#log "Encrypting backup"
/usr/bin/openssl smime -encrypt -aes256 -binary -in ${TARFILE} -out ${TARFILE}.enc -outform DER -stream ${CRTFILE}
log "Encryption completed"

# Delete unencrypted tar
rm ${TARFILE}

log "Tar backup complete. Filesize: `du -h ${TARFILE}.enc | cut -f1`"

log "Tranferring tar backup to remote server"
scp -P ${REMOTEPORT} ${TARFILE}.enc ${REMOTEUSER}@${REMOTESERVER}:${REMOTEDIR}
log "File transfer completed"

if [ -f /usr/local/bin/mysql ]; then
        log "Deleting temporary MySQL backup"
        rm ${SQLFILE}
fi
### END OF TAR BACKUP ###



### RSYNC BACKUP ###
log "Starting rsync backups"
for i in ${RSYNCDIR[@]}; do
        /usr/local/bin/rsync -avz --no-links --progress --delete --relative -e"ssh -p ${REMOTEPORT}" $i ${REMOTEUSER}@${REMOTESERVER}:${REMOTEDIR}
done
log "rsync backups complete"
### END OF RSYNC BACKUP



log "Deleting old local backups"
# Deletes backups older than 1 week
/usr/bin/find ${LOCALDIR} -name "*.tgz.enc" -mmin +${LOCALAGE} -exec rm {} \;

log "Deleting old remote backups"
/usr/bin/ssh -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTESERVER} "/usr/bin/find ${REMOTEDIR} -name \"*tgz.enc\" -mmin +${REMOTEAGE} -exec rm {} \;"

ENDTIME=`date +%s`
DURATION=$((ENDTIME - STARTTIME))
log "All done. Backup and transter completed in ${DURATION} seconds"
