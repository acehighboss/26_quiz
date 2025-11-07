#!/bin/bash

DB_ADDRESS="${DB_ADDRESS}"
DB_USERNAME="${DB_USERNAME}"
DB_PASSWORD="${DB_PASSWORD}"
S3_BUCKET_NAME="${S3_BUCKET_NAME}"

SWAPFILE="/swapfile"
SIZE="1G"
TOMCAT_VERSION="10.1.48"

fallocate -l $SIZE $SWAPFILE
chmod 600 $SWAPFILE
mkswap $SWAPFILE
swapon $SWAPFILE
echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab

apt update -y
apt install -y openjdk-17-jdk wget

sleep 10  # 네트워크 안정화 대기
wget -q http://mirror.apache-kr.org/apache/tomcat/tomcat-10/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz

useradd -r -m -U -d /opt/tomcat -s /bin/false tomcat
tar -xf apache-tomcat-$TOMCAT_VERSION.tar.gz -C /opt/tomcat
mv /opt/tomcat/apache-tomcat-$TOMCAT_VERSION /opt/tomcat/tomcat-10
chown -RH tomcat: /opt/tomcat/tomcat-10
chmod +x /opt/tomcat/tomcat-10/bin/*.sh

cat >/etc/systemd/system/tomcat.service <<EOF
[Unit]
Description=Apache Tomcat 10
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
Environment="CATALINA_HOME=/opt/tomcat/tomcat-10"
Environment="CATALINA_BASE=/opt/tomcat/tomcat-10"
Environment="CATALINA_PID=/opt/tomcat/tomcat-10/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"
ExecStart=/opt/tomcat/tomcat-10/bin/startup.sh
ExecStop=/opt/tomcat/tomcat-10/bin/shutdown.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tomcat
sleep 10  # 데몬 재시작 대기
systemctl start tomcat



apt install -y mariadb-client

until mariadb -u "${DB_USERNAME}" -h "${DB_ADDRESS}" -p"${DB_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; do
  echo "Wating for RDS"
  sleep 10
done

echo "RDS Connection"

mariadb -u "${DB_USERNAME}" -h "${DB_ADDRESS}" -p"${DB_PASSWORD}" <<SQL

CREATE DATABASE IF NOT EXISTS care;

USE care;

CREATE TABLE IF NOT EXISTS member (
  id VARCHAR(40),
  pw VARCHAR(100),
  username VARCHAR(21),
  postcode VARCHAR(10),
  address VARCHAR(999),
  detailaddress VARCHAR(333),
  mobile VARCHAR(15),
  PRIMARY KEY(id)
) DEFAULT CHARSET=UTF8;

CREATE TABLE IF NOT EXISTS board (
  no INT,
  title VARCHAR(999),
  content VARCHAR(9999),
  id VARCHAR(40),
  writedate VARCHAR(30),
  hits INT,
  filename VARCHAR(999),
  PRIMARY KEY(no)
) DEFAULT CHARSET=UTF8;
SQL

echo "DATABASE and Table Created"

# aws cli install
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt install -y unzip
unzip awscliv2.zip
sudo ./aws/install
echo "aws cli installed"

# s3 boot.war download
aws s3 cp "s3://${S3_BUCKET_NAME}/boot.war" /opt/tomcat/tomcat-10/webapps/boot.war

until [ -f "/opt/tomcat/tomcat-10/webapps/boot.war" ]; do
  echo "boot downloading from s3"
  sleep 10
done
echo "boot downloaded from s3"

until [ -f "/opt/tomcat/tomcat-10/webapps/boot/WEB-INF/classes/application.properties" ]; do
  echo "war unzip"
  sleep 10
done
echo "boot war unzip complete"

sed -i 's/^spring.datasource.username.*/spring.datasource.username=${DB_USERNAME}/' "/opt/tomcat/tomcat-10/webapps/boot/WEB-INF/classes/application.properties"
sed -i 's/^spring.datasource.password.*/spring.datasource.password=${DB_PASSWORD}/' "/opt/tomcat/tomcat-10/webapps/boot/WEB-INF/classes/application.properties"
sed -i 's|^spring.datasource.url.*|spring.datasource.url=jdbc:mariadb://${DB_ADDRESS}:3306/care |' "/opt/tomcat/tomcat-10/webapps/boot/WEB-INF/classes/application.properties"
echo "application properties modified"

systemctl restart tomcat