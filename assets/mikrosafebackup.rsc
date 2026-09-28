/system script
remove [find name=mikrosafe_backup]
add name=mikrosafe_backup dont-require-permissions=yes source={
    /export file=mikrosafebackup;
    /system backup save name=mikrosafebackup password=
}

/system scheduler
remove [find name=mikrosafe_scheduler]
add name=mikrosafe_scheduler interval=1d start-time=00:05:00 on-event="/system script run mikrosafe_backup" policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon
