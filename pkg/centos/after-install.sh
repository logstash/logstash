/sbin/chkconfig --add logstash

chown -R logstash:logstash /opt/logstash
chown logstash /var/log/logstash
chown logstash:logstash /var/lib/logstash
chmod +x /etc/rc.d/init.d/logstash
chmod +x /opt/logstash/bin/logstash
