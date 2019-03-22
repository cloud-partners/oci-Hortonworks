#!/bin/bash
##
## Set the following variable to "1" to enable data tiering.
enable_data_tiering="0"
worker_check=`hostname | grep worker`
worker_chk=`echo -e $?`
if [ "$worker_chk" = 0 ]; then
	is_worker="true"
else
	is_worker="false"
fi
## Give ISCSI time to intiate
iscsi="1"
while [ $iscsi = "1" ]; do 
	if [ -f /tmp/iscsi.lock ]; then
		iscsi="1"
		sleep 1 
	else
		iscsi="0"
	fi
done

## Primary Disk Mounting Function
data_mount () {
	echo -e "Mounting /dev/$disk to /data$dcount"
	sudo mkdir -p /data$dcount
	sudo mount -o noatime,barrier=1 -t ext4 /dev/$disk /data$dcount
	UUID=`sudo lsblk -no UUID /dev/$disk`
	echo "UUID=$UUID   /data$dcount    ext4   defaults,noatime,discard,barrier=0 0 1" | sudo tee -a /etc/fstab
}

block_data_mount () {
        echo -e "Mounting /dev/$disk to /data$dcount"
        sudo mkdir -p /data$dcount
        sudo mount -o noatime,barrier=1 -t ext4 /dev/$disk /data$dcount
        UUID=`sudo lsblk -no UUID /dev/$disk`
        echo "UUID=$UUID   /data$dcount    ext4   defaults,_netdev,nofail,noatime,discard,barrier=0 0 2" | sudo tee -a /etc/fstab
}

data_tiering () {
	nvme_check=`echo $disk | grep nvme`
	nvme_chk=`echo -e $?`
	if [ "$nvme_chk" = 0 ]; then 
		if [ "$dcount" = 0 ]; then 
			echo -ne "[DISK]/data$dcount/dfs/dn" >> hdfs_data_tiering.txt
		else
			echo -ne ",[DISK]/data$dcount/dfs/dn" >> hdfs_data_tiering.txt
		fi
	else
		if [ "$dcount" = 0 ]; then
			echo -ne "[ARCHIVE]/data$dcount/dfs/dn" >> hdfs_data_tiering.txt
		else
			echo -ne ",[ARCHIVE]/data$dcount/dfs/dn" >> hdfs_data_tiering.txt
		fi
	fi
}

## Check for x>0 devices
echo -n "Checking for disks..."
## Execute - will format all devices except sda for use as data disks in HDFS 
n=0
dcount=0
for disk in `cat /proc/partitions | grep -ivw 'sda' | grep -ivw 'sda[1-3]' | sed 1,2d | gawk '{print $4}'`; do
	echo -e "\nProcessing /dev/$disk"
	sudo mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 /dev/$disk
        nv_chk=`echo $disk | grep nv`;
        nv_chk=$?
        if [ $nv_chk = "0" ]; then
                nvcount=$((nvcount+1))
                data_mount
        else
                bvcount=$((bvcount+1))
                block_data_mount
        fi
	sudo /sbin/tune2fs -i0 -c0 /dev/$disk
	if [ "$is_worker" = "true" ]; then
		if [ "$enable_data_tiering" = "1" ]; then 
			data_tiering
		fi
	fi
	dcount=$((dcount+1))	
done;
ibvcount=`cat /tmp/bvcount`
if [ $ibvcount -gt $bvcount ]; then
        echo -e "ERROR - $ibvcount Block Volumes detected but $bvcount processed."
else
        echo -e "DONE - $nvcount NVME disks processed, $bvcount Block Volumes processed."
fi

