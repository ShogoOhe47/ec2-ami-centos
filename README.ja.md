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
| CentOS 6.6  |  ami-0a662aa5a510de9eb  |
| CentOS 6.7  |  ami-0f5f94df8c0aa951d  |
| CentOS 6.8  |  ami-000dfc5f1842b4fce  |
| CentOS 6.9  |  ami-04b471c820e90bbcc  |
| CentOS 6.10  |  ami-005587d906be21ed1  |


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
   - [ENA ドライバ](https://github.com/amzn/amzn-drivers/)の[ビルド](https://repost.aws/ja/knowledge-center/install-ena-driver-rhel-ec2)で linux/kconfig.h が必要だが、提供されるのが CentOS 6.5 以降のため

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

