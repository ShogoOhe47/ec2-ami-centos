# CentOS 6 AMI

ap-northeast-1 でのみ展開

| version  | AMI ID |
| ------------- | ------------- |
| CentOS 6.0  |  ami-01c56f11f81ccd789  |
| CentOS 6.1  |  ami-0d8b027f289b533a3  |
| CentOS 6.2  |  ami-083d3006b51208bfc  |
| CentOS 6.3  |  ami-07bb999161ccb399d  |
| CentOS 6.4  |  ami-000e8f28505eb8ecf  |
| CentOS 6.5  |  ami-09c1e1bd3d9719f22  |
| CentOS 6.6  |  ami-0a662aa5a510de9eb, ami-0edd3e7ca69ed0797 (*1) |
| CentOS 6.7  |  ami-0f5f94df8c0aa951d, ami-0ed2436fc21b406d4 (*1) |
| CentOS 6.8  |  ami-000dfc5f1842b4fce, ami-0e397a0bfcbe997ba (*1) |
| CentOS 6.9  |  ami-04b471c820e90bbcc, ami-00e938eee68482e28 (*1) |
| CentOS 6.10  |  ami-005587d906be21ed1, ami-0d9ae85f1031de3e2 (*1) |

*1 ... ENA ドライバインストール済。kernel 変更時には再ビルドが必要。

# 使い方

1. AMI から起動する。
2. 'ec2-user' でログインする

# オリジナルの CentOS からの変更点
CentOS 6 は 2018 年 11 月 3 日となっており、そのままでは動作しないためいくつかの変更を行っています。
 - ec2-user での RSA 公開鍵 (キーペア) ログイン
   - /etc/rc.d/rc.local で起動時にキーペアの情報を IMDSv2 から取得しています
 - リポジトリを CentOS Vault に変更: [公式の Vault](https://vault.centos.org/6.0/) には HTTPS 接続が行えないため [kernel.org の http サーバーを参照](https://archive.kernel.org/centos-vault/6.0/) 
   - /etc/yum/vars/releasever でインストールバージョンを管理しています

## インストールされているパッケージ
 - パッケージグループ Core (postfix を除く)
 - kernel
 - xfsprogs

## できないこと
 - cloud-init の導入
   - [fedraproject のアーカイブ](https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/Packages/c/cloud-init-0.7.4-2.el6.noarch.rpm) からインストールできそうだが上手く行っていない
 - Nitro インスタンスでの実行
   - CentOS 6.6 以降の AMI では最新ではないですが ENA 2.9.1 ドライバはインストールしているので、Nitro インスタンスでも「起動は」確認しました。
   - NVMe ドライバが無いなどフルサポートではありません (そもそもベースとなる RHEL 6 自体が Nitro でサポートされていない)。
```
https://repost.aws/ja/knowledge-center/install-ena-driver-rhel-ec2
注: RHEL 6 は Amazon EC2 本番環境対応の NVMe ドライバーを含んでいません。なお、NVME ドライバーへのアップグレードはできません。Nitro ベースのインスタンスや、NVMe インスタンスストアボリュームを使用するインスタンスタイプを使用するには、RHEL 7.4 以降にアップグレードしてください。
```
   - [ENA ドライバ](https://github.com/amzn/amzn-drivers/)の[ビルド](https://repost.aws/ja/knowledge-center/install-ena-driver-rhel-ec2)に起因した問題。
   - CentOS 6.0 ~ 6.4 では "linux/kconfig.h: No such file or directory" のためビルドに失敗する。
     これは CentOS 6.5 の kernel-devel-2.6.32-431.el6.x86_64.rpm で解決される。
   - CentOS 6.5 では "error: net/busy_poll.h: No such file or directory" のためビルドに失敗する。
   - CentOS 6.6 以降では [ENA Linux 2.9.1](https://github.com/amzn/amzn-drivers/releases/tag/ena_linux_2.9.1) であればビルドに成功する。2.10.0 以降ではビルドエラーになる (CentOS 6.10 でも解決せず)。
```
/home/ec2-user/amzn-drivers-ena_linux_2.10.0/kernel/linux/ena/ena_netdev.c: In function 'ena_config_host_info':
/home/ec2-user/amzn-drivers-ena_linux_2.10.0/kernel/linux/ena/ena_netdev.c:3176: error: implicit declaration of function 'pci_dev_id'
```

# AMI のビルドに使用したスクリプト

'install-centos6.sh' は、CentOS 6 をインストールするスクリプトです。
ドライバーシステムとなる CentOS 環境(インスタンス)に、インストール先となる EBS ボリュームをアタッチすることでインストールすることができます。
```
./install-centos6.sh {install_version} {boot_device}
./install-centos6.sh 6.0 /dev/xvdb
```
 - install_version : インストールする CentOS のバージョン
 - boot_device : インストール先の EBS ボリューム

実際の動作では、6.0 ~ 6.10 の EBS をまとめてマウントして連続してインストールを行っています。

## フルスクラッチでインストールしている理由、/var/cache/yum を分ける理由

EBS スナップショットのサイズ削減のため。
EBS スナップショットは仕組み上、ファイルシステム上のサイズではなく、空のボリュームに対する変更点が記録されます。

つまり、「新しい EBS ボリュームにインストール」し、「yum のキャッシュのような一過性のデータが EBS に記録されない工夫をする」ことで、スナップショットのサイズを削減できます。
結果、CentOS 6.x では 770~1000MB 程度がスナップショットの最小サイズになっています。


## ENA ドライバのインストール
NSS が古く curl などで取得できないため、ENA Linux 2.9.1 を取得し、sftp 等でアップロードしておく。
https://github.com/amzn/amzn-drivers/archive/refs/tags/ena_linux_2.9.1.tar.gz

前提: インストール先と同じ kernel が動作している CentOS でビルドを実施。
1 AMI で右記を作成: 作業用スタンス、AMI 作成用ボリューム (-> 新しい AMI の元となる)

ビルド
```
sudo yum install kernel-devel-$(uname -r) gcc patch rpm-build -y
tar zxf amzn-drivers-ena_linux_2.9.1.tar.gz
cd amzn-drivers-ena_linux_2.9.1/kernel/linux/ena
sudo make
```

AMI 作成用ボリュームにインストール
```
sudo mount /dev/xvdb1 /mnt/

sudo cp ena.ko /mnt/lib/modules/$(uname -r)/
sudo chroot /mnt depmod
sudo sed -i '/kernel/s/$/ net.ifnames=0/' /mnt/boot/grub/grub.conf
sudo cat /mnt/boot/grub/grub.conf
default=0
timeout=0
hiddenmenu
title CentOS6.9
        root (hd0,0)
        kernel /boot/vmlinuz-2.6.32-696.el6.x86_64 ro root=LABEL=/ console=tty0 console=ttyS0,115200 xen_pv_hvm=enable net.ifnames=0
        initrd /boot/initramfs-2.6.32-696.el6.x86_64.img

sudo umount /mnt/
```
