#Backup Script

A simple backup script utilising OpenSSL, tar and rsync, written in bash.

##Script Features

* Incremental backup retention
* Backups are encrypted with AES256-cbc with SHA1 message-digest
* The backup script can store a copy both locally and on a remote device/server
* Backups are sent over SSH
* Currently supports GNU/Linux and FreeBSD

##Backup Retention

By default:

* Daily backups are retained for the past week
* Weekly backups from Mondays are retained for the past month
* Monthly backups from the first Monday of each month are retained for the past six months

The retention lengths are adjustable in backup.cfg:

If desired, the backup deletion can be run seperately:
* To delete local backups, run "deleteoldbackups.sh"
* To delete remote backups, run "deleteoldbackups.sh --remote"

##Arguments
backup.sh:

* --config [filename] : Specify a different configuration file (or location)

deleteoldbackups.sh:

* --config [filename] : Specify a different configuration file (or location)
* --remote : Delete remote backups (local backups are deleted by default)

Note that deleteoldbackups.sh is run both locally and remotely by backup.sh by default.

##Use With cron

If you're running this script from cron, make sure you add the following line to the top of your crontab:
`PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin`
