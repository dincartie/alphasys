Hardware > Add > Serial Port > serial0
systemctl enable --now serial-getty@ttyS0.service
vim /etc/default/grub >> GRUB_CMDLINE_LINUX_DEFAULT=`console=ttyS0,115200n8`
update-grub
