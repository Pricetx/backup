#Backup Script

A simple backup script utilising OpenSSL, tar and rsync, written in bash.

##Script Features

* Incremental backup retention
* Backups are asymmetrically encrypted
* The backup script can store a copy both locally and on a remote device/server
* Backups are sent over SSH
* Currently supports GNU/Linux and FreeBSD

##Backup retention

By default:
* Daily backups are retained for the past week
* Weekly backups from Mondays are retained for the past month
* Monthly backups from the first Monday of each month are retained for the past six months

The retention lengths are adjustable in backup.cfg
<<<<<<< HEAD
||||||| parent of 99a9b5b... Updated readme

\* (currently GNU/Linux only)
=======

Automatic backup deletion requires deleteoldbackups.sh to be located in the same folder as backup.sh and backup.cfg
>>>>>>> 99a9b5b... Updated readme
