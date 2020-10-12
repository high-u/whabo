# xxx

## setup

25 GB SSD $5/mo $0.007/h
Ubuntu 20.04 x64

```bash
ssh root@192.0.2.1

adduser hig
# ex. password: apple-banana-strawberry-melon-watermelon-orange

# sudo 権限付与
gpasswd -a hig sudo

# sudo の時にパスワード不要にする
visudo
# 下記を追加
# hig ALL=NOPASSWD:ALL
# エディタ終了は ctrl + x (ubuntu はこれらしい)

su - hig
pwd
mkdir ~/.ssh
chmod 700 ~/.ssh
# ローカル PC の `cat ~/.ssh/id_rsa.pub` をコピーしておく。scp の方が良いか？
vim ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit

# パスワードでのログインを禁止、とおまじない
vim /etc/ssh/sshd_config
# 下記のように編集。3 つめは、docker-compose のバグ？で必要。これしないと `ERROR: for http-echo_redis-cli_1 ChannelException(2, 'Connect failed')` のようなエラーが発生することがある。 https://github.com/docker/compose/issues/6463
# PubkeyAuthentication yes
# PasswordAuthentication no
# MaxSessions 500

# 上記 sshd_config を反映させる
service sshd restart

exit
```

ローカルで

`~/.ssh/config` に下記を追加

```bash
cat <<EOF >> ~/.ssh/config
Host vultr
  HostName 192.0.2.1
  User hig
  IdentityFile ~/.ssh/id_rsa
EOF

ssh vultr
```

install docker https://docs.docker.com/engine/install/ubuntu/

```bash
sudo apt-get remove docker docker-engine docker.io containerd runc
sudo apt-get update
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"


sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
apt-cache madison docker-ce

DOCKER_CE_VERSION=5:19.03.13~3-0~ubuntu-focal
sudo apt-get install -y docker-ce=$DOCKER_CE_VERSION docker-ce-cli=$DOCKER_CE_VERSION containerd.io
sudo docker run hello-world

# sudo なしで docker を使う
sudo groupadd docker
sudo gpasswd -a $USER docker
sudo systemctl restart docker

```

install docker-compose https://docs.docker.com/compose/install/

```bash
sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version

```

ドメインでの接続確認

```bash
docker run -d --name nginx -p 8080:80 nginx:stable-alpine
curl localhost:8080
```

vultr で DNS 追加
Domain: whabo.ga
Default IP: 192.0.2.1

※ freenom でドメイン購入時に、vultr のネームサーバを設定している
ns1.vultr.com
ns2.vultr.com

http://192.0.2.1:8080/

http://whabo.ga:8080/
つながった

## vultr API Key

Account -> API

※アクセスできる IP アドレスの指定が必要。(自動で追加されていたが)

vultr にアクセスしている操作中の PC の IP アドレスは自動で追加されている。
今回 whabo のデプロイ先であるマシンの IP アドレス (192.0.2.1) を追加する。

試しに

```bash
curl -H 'API-Key: YOURKEY' "https://api.vultr.com/v1/server/list"
```

## whabo

参考 https://www.vultr.com/docs/wildcard-lets-encrypt-ssl-for-one-click-lamp

ローカルで。ここから WHABO のインストール。

```bash
# Docker コンテキストを作成
docker context create vultr --docker "host=ssh://hig@192.0.2.1"

# 確認
docker -c vultr ps
# SSL証明書の格納 volume を作成
docker -c vultr volume create --driver local whabo-certs
# volume 確認
docker -c vultr volume ls
docker -c vultr volume inspect whabo-certs

# whabo 関連のコンテナを動かす network を作成
docker -c vultr network create -d bridge reverse-proxy-net
# network 確認
docker -c vultr network ls
docker -c vultr network inspect reverse-proxy-net

# whabo のリポジトリを取得
git clone https://github.com/high-u/whabo.git
cd whabo

# https://go-acme.github.io/lego/dns/vultr/
cp env/vultr.env .env
# .env ファイルを編集
vim .env
# ```
# DOMAIN=example.com
# SUBDOMAIN=*.example.com
# EMAIL=admin@example.com
# DAYS=30
#
# DNS=vultr
# VULTR_API_KEY=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# VULTR_HTTP_TIMEOUT=60
# VULTR_POLLING_INTERVAL=60
# VULTR_PROPAGATION_TIMEOUT=300
# VULTR_TTL=300
# ```

# SSL 証明書の取得
docker-compose -c vultr up lego-get-certs
# 証明書の確認
ssh vultr sudo ls -la /var/lib/docker/volumes/whabo-certs/_data/certificates

# SSL 証明書の更新用コンテナ
docker-compose -c vultr up -d lego-update-certs

# redis
docker-compose -c vultr up -d routing-table
# OpenResty
docker-compose -c vultr up -d --build reverse-proxy
# 確認
docker-compose -c vultr ps
#           Name                         Command               State                     Ports
# --------------------------------------------------------------------------------------------------------------
# whabo_lego-get-certs_1      sh -c                            Exit 0
#                             lego --accept-tos - ...
# whabo_lego-update-certs_1   sh -c                            Up
#                             echo "lego --email  ...
# whabo_reverse-proxy_1       /usr/bin/openresty -g daem ...   Up       0.0.0.0:443->443/tcp, 0.0.0.0:80->80/tcp
# whabo_routing-table_1       docker-entrypoint.sh redis ...   Up       6379/tcp

```

デプロイしてみる

```bash
docker-compose -c vultr -f example/http-echo/docker-compose.yaml up -d
# hello.whabo.ga でアクセスできるように、redis に登録
#   `http-echo` は、docker-compose の services で指定している名称
#   5678 はサーバが Listen しているポート ※ ホストに公開しているポートではない
docker-compose -c vultr exec -T routing-table redis-cli set http-echo "http-echo:5678"
# 登録データを確認
docker-compose -c vultr exec -T routing-table redis-cli get http-echo

```

wordpress

```bash
docker-compose -c vultr -f example/wordpress/docker-compose.yaml up -d
docker-compose -c vultr exec -T routing-table redis-cli set wordpress "wordpress:80"
```

wekan

```bash
docker-compose -c vultr -f example/wekan/docker-compose.yaml up -d
docker-compose -c vultr exec -T routing-table redis-cli set wekan "wekan:8080"
```
