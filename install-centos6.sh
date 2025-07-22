#!/bin/bash

# CentOS 6.x install to EBS
# ./install-centos6.sh  6.0  /dev/xvdb  tmpfs
#  arg1: install version. 6.0. 6.1, ...
#  arg2: target EBS volume
#  arg3: yum cache method

#CENTOS_VERSION=6.0
CENTOS_VERSION=$1
#DEVICE=/dev/xvdb
DEVICE=$2
if [[ ${DEVICE} != /dev/xv* ]]; then
  echo "Invalid device path: ${DEVICE}"
fi
DISK=/mnt
BOOTUUID="1e2fe6d5-203b-4b0f-affa-1ebce0695e4b"

YUM_CACHE=$3
TMPFS_YUM_SIZE=200


# check
parted ${DEVICE} --script | grep "Partition Table"
if [ $? -eq 0 ]; then
  echo "device ${DEVICE} already has partition table"
  exit 1
fi

if [ `whoami` != 'root' ]; then
  echo "This script need to run as root user."
  exit 1
fi

# create log file
timestamp=`date "+%Y%m%d-%H%M%S"`
LOGFILE="/tmp/createvolume_CentOS-${CENTOS_VERSION}_${timestamp}.log"
function log () {
  logstamp='['`date "+%Y%m%d-%H%M%S"`'] '
  echo ${logstamp} $@ | tee -a ${LOGFILE}
}

log "=== config ===\n install CentOS ${CENTOS_VERSION} to ${DEVICE}\n\n"


# init volume
log 'init volume...'
parted ${DEVICE} --script mklabel msdos mkpart primary ext4 0% 100%
mkfs -t ext4 ${DEVICE}1
parted ${DEVICE} --script >> ${LOGFILE}
mount ${DEVICE}1 $DISK

e2label ${DEVICE}1 /
tune2fs -U $BOOTUUID ${DEVICE}1
tune2fs -l ${DEVICE}1 | grep -e name -e UUID
tune2fs -l ${DEVICE}1 >> ${LOGFILE}

# create tmpfs for yum cache
log 'mount /var/cache/yum.'
mkdir -p $DISK/var/cache/yum
if [ ${YUM_CACHE} = "tmpfs" ]; then
  mount -t tmpfs -o size=${TMPFS_YUM_SIZE}m yumcache $DISK/var/cache/yum
  log " - mount tmpfs for /var/cache/yum: ${TMPFS_YUM_SIZE}MB"
elif [[ ${YUM_CACHE} = /dev/x* ]]; then
  mount ${YUM_CACHE} $DISK/var/cache/yum
  log " - mount ${YUM_CACHE} for /var/cache/yum"
fi
df -h >> ${LOGFILE}

# create root directory
log  'create directories in install root.'
mkdir $DISK/etc $DISK/proc $DISK/dev

tee $DISK/etc/fstab <<EOF >/dev/null
UUID=$BOOTUUID / ext4 defaults,noatime 1 1
none /dev/pts devpts gid=5,mode=620 0 0
none /dev/shm tmpfs defaults 0 0
none /proc proc defaults 0 0
none /sys sysfs defaults 0 0
EOF

mount -t proc none $DISK/proc


# yum configuration for install
log  'temp yum configuration for install'
wget -O /tmp/RPM-GPG-KEY-CentOS-6 https://vault.centos.org/6.1/os/x86_64/RPM-GPG-KEY-CentOS-6

cat<<EOF > /tmp/repos.conf
[ami-base]
name=CentOS-6 - Base
baseurl=https://vault.centos.org/${CENTOS_VERSION}/os/x86_64/
gpgcheck=1
gpgkey=file:///tmp/RPM-GPG-KEY-CentOS-6
EOF


# install packages
log  'install core packages'
setarch x86_64 yum -y -c /tmp/repos.conf --installroot=$DISK --disablerepo=* --enablerepo=ami-base groupinstall Core | tee -a ${LOGFILE}
setarch x86_64 yum -y -c /tmp/repos.conf --installroot=$DISK --disablerepo=* --enablerepo=ami-base install kernel | tee -a ${LOGFILE}
setarch x86_64 yum -y -c /tmp/repos.conf --installroot=$DISK --disablerepo=* --enablerepo=ami-base install ruby rsync grub | tee -a ${LOGFILE}


# grub config
log  'install grub'
cp $DISK/usr/*/grub/*/*stage* $DISK/boot/grub/
mount --rbind /dev $DISK/dev

tee $DISK/boot/grub/menu.lst <<EOF >/dev/null 
default=0
timeout=0
hiddenmenu
title CentOS$CENTOS_VERSION
        root (hd0,0)
        kernel /boot/vmlinuz-$(rpm --root=$DISK -q --queryformat "%{version}-%{release}.%{arch}\n" kernel) ro root=LABEL=/ console=ttyS0 xen_pv_hvm=enable
        initrd /boot/initramfs-$(rpm --root=$DISK -q --queryformat "%{version}-%{release}.%{arch}\n" kernel).img
EOF


chroot $DISK ln -s /boot/grub/menu.lst /boot/grub/grub.conf
chroot $DISK ln -s /boot/grub/grub.conf /etc/grub.conf

cat <<EOF | chroot $DISK grub --batch
device (hd0) ${DEVICE}
root (hd0,0)
setup (hd0)
EOF


# network config
log  'create network interface configuration'
tee $DISK/etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF >/dev/null
DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Ethernet
USERCTL=yes
PEERDNS=yes
IPV6INIT=no
EOF

tee $DISK/etc/sysconfig/network <<EOF >/dev/null
NETWORKING=yes
EOF


# disable SELinux
log  'disabling SELinux'
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' $DISK/etc/selinux/config


# set the timezone to GMT 
log  'set the timezone to GMT'
rm -f $DISK/etc/localtime
cp -p $DISK/usr/share/zoneinfo/GMT $DISK/etc/localtime


# update yum.conf: use vault repository
log  'update yum repositories: mirror.centos.org -> archive.kernel.org/centos-vault/'
sed -i 's@^mirrorlist=http://mirrorlist.centos.org/@#mirrorlist=http://mirrorlist.centos.org/@g' $DISK/etc/yum.repos.d/CentOS-Base.repo
sed -i '/^#baseurl=http:\/\/mirror.centos.org\/centos\//{ h; p; s@#baseurl=http://mirror.centos.org/centos/@#baseurl=https://vault.centos.org/@; }' $DISK/etc/yum.repos.d/CentOS-Base.repo
sed -i '/^#baseurl=http:\/\/mirror.centos.org\/centos\//{ h; p; s@#baseurl=http://mirror.centos.org/centos/@baseurl=http://archive.kernel.org/centos-vault/@; }' $DISK/etc/yum.repos.d/CentOS-Base.repo

echo ${CENTOS_VERSION} > $DISK/etc/yum/vars/releasever


# tmp config: enable root login
log  'enable tmp root account'
#chroot $DISK sh -c 'echo "***" | passwd --stdin root'

#sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/g' $DISK/etc/ssh/sshd_config
sed -i 's/#UseDNS yes/UseDNS no/g' $DISK/etc/ssh/sshd_config


# create ec2-user in init script
log 'create init script for ec2-user'
tee $DISK/etc/rc.d/rc.local <<EOF >/dev/null 
#!/bin/sh
#
# This script will be executed *after* all the other init scripts.
# You can put your own initialization stuff in here if you don't
# want to do the full Sys V style init stuff.

touch /var/lock/subsys/local

# Update the Amazon EC2 AMI creation tools
rpm -Uvh http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.noarch.rpm

# Update ec2-metadata
curl -o /usr/bin/ec2-metadata http://s3.amazonaws.com/ec2metadata/ec2-metadata
chmod 755 /usr/bin/ec2-metadata


# create ec2-user
if [ ! -d /home/ec2-user ] ; then
  useradd ec2-user >& /tmp/ec2-user
fi

if [ ! -d /home/ec2-user/.ssh ] ; then
  mkdir /home/ec2-user/.ssh
  chmod 0700 /home/ec2-user/.ssh
  chown ec2-user:ec2-user /home/ec2-user/.ssh
fi

ATTEMPTS=5
FAILED=0
# Fetch public key using HTTP
TOKEN=\`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"\`
while [ ! -f /home/ec2-user/.ssh/authorized_keys ]; do
  curl -H "X-aws-ec2-metadata-token: \$TOKEN" -f http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key > /tmp/openssh-key 2>/dev/null
  if [ $? -eq 0 ]; then
    cat /tmp/openssh-key >> /home/ec2-user/.ssh/authorized_keys
    chmod 0600 /home/ec2-user/.ssh/authorized_keys
    chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys
    rm -f /tmp/openssh-key
    echo "Successfully retrieved AWS public key from instance metadata"
  else
    FAILED=$(($FAILED + 1))
    if [ $FAILED -ge $ATTEMPTS ]; then
      echo "Failed to retrieve AWS public key after $FAILED attempts, quitting"
      break
    fi
    echo "Could not retrieve AWS public key (attempt #$FAILED/$ATTEMPTS), retrying in 5 seconds..."
    sleep 5
  fi
done
EOF

# enable sudo for ec2-user
cat <<EOF >> $DISK/etc/sudoers

## sudoers drop-in dir
#includedir /etc/sudoers.d
EOF

mkdir $DISK/etc/sudoers.d
tee $DISK/etc/sudoers.d/ec2-user <<EOF >/dev/null
ec2-user  ALL=(ALL)  NOPASSWD:ALL
EOF
chmod 750 $DISK/etc/sudoers.d
chmod 440 $DISK/etc/sudoers.d/ec2-user



# unmount
log 'unmount volume'
umount $DISK/proc
umount $DISK/dev
umount $DISK/var/cache/yum
sleep 5
umount $DISK

# finish!
log 'finidh!'
