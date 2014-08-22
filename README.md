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

The retention lengths can be adjusted by editing the *'localage'* variables in the shell script.
