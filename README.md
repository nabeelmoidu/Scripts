# Scripts
The hdfsdisksetup.sh script will do the following :

1) Identify the max size of disks on the node
2) Set that as the disk type for the HDFS filesystem (Local OS systems are of SSD type typically, of much smaller size, and formatted as RAID 1 )
3) List disks of that size from fdisk
4) Filter out disks already formatted and mounted from that list
5) Format remaining disks as ext4 with the options mentioned above
6) Mount the disks with options mentioned above in the /grid/N pattern mount directories
7) Update fstab with entries for the disks using the UUIDs
8) Create directories for HDFS and Yarn in the mount locations
9) Set file ownership for these directories to the HDFS / YARN user and Hadoop group
10) Log all actions above in a log file.

When executed as part of initial provisioning the script can be placed in /root and executed as root user with following syntax:

{code:bash}
/root/disksetup.sh && /root/disksetup.sh -r /tmp/disklist
{code}

The initial run without arguments generates the file /tmp/diskslist with the disks to be formatted  listed therein. The second run will do the 10 steps mentioned earlier. It's done intentionally this way to avoid accidental execution of the script which can cause data loss by formatting the disks.


