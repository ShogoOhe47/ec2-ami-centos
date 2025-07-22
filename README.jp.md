# CentOS 6 AMI

ap-northeast-1 でのみ展開

| version  | AMI ID |
| ------------- | ------------- |
| CentOS 6.0  | ami-042dfee91569046a3  |
| CentOS 6.1  | -  |

# 使い方

1. AMI から起動する。
2. 'ec2-user' でログインする

# オリジナルの CentOS からの変更点
CentOS 6 は 2018 年 11 月 3 日となっており、そのままでは動作しないためいくつかの変更を行っています。
 - ec2-user での RSA 公開鍵 (キーペア) ログイン
   - /etc/rc.d/rc.local で起動時にキーペアの情報を IMDSv2 から取得しています
 - リポジトリを CentOS Vault に変更: [公式の Vault](https://vault.centos.org/6.0/) には HTTPS 接続が行えないため [kernel.org の http サーバーを参照](https://archive.kernel.org/centos-vault/6.0/) 
   - /etc/yum/vars/releasever でインストールバージョンを管理しています
 
## できないこと
 - cloud-init の導入
   - [fedraproject のアーカイブ](https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/Packages/c/cloud-init-0.7.4-2.el6.noarch.rpm) からインストールできそうだが上手く行っていない
 - Nitro インスタンスでの実行
   - [ENA ドライバ](https://github.com/amzn/amzn-drivers/)の[ビルド](https://repost.aws/ja/knowledge-center/install-ena-driver-rhel-ec2)で linux/kconfig.h が必要だが、提供されるのが CentOS 6.5 以降のため

# AMI のビルドに使用したスクリプト

ドライバーシステムとなる CentOS に、インストール先 EBS ボリュームをアタッチすることでインストールできるスクリプトを作っています。
```
./install-centos6.sh {install_version} {boot_device} {yum_cache}
./install-centos6.sh 6.0 /dev/xvdb tmpfs
```
 - install_version : インストールする CentOS のバージョン
 - boot_device : インストール先の EBS ボリューム
 - yum_cache : インストール先の /var/cache/yum として使用される tmpfs またはデバイス

## フルスクラッチでインストールしている理由、/var/cache/yum を分ける理由

EBS スナップショットのサイズ削減のため。
EBS スナップショットは仕組み上、ファイルシステム上のサイズではなく、空のボリュームに対する変更点が記録されます。

つまり、「新しい EBS ボリュームにインストール」し、「yum のキャッシュのような一過性のデータが EBS に記録されない工夫をする」ことで、スナップショットのサイズを削減できます。
結果、CentOS 6.x では 700~1000MB 程度がスナップショットの最小サイズになっています。

