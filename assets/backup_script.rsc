/system script
remove [find name=back-up]
add name=back-up dont-require-permissions=yes source={
    /export file=1;
    /system backup save name=1 password=
}

/system scheduler
remove [find name=backupMK]
add name=backupMK interval=1d start-time=00:05:00 on-event="/system script run back-up" policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon
