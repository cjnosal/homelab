cp /home/ubuntu/init/creds/alloy.passwd /etc/alloy/alloy.passwd

chgrp -R alloy /etc/alloy
systemctl enable alloy
systemctl start alloy