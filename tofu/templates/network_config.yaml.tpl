version: 2
ethernets:
  id0:
    match:
      driver: virtio_net
    dhcp4: false
    dhcp6: false
    addresses:
      - ${ip_address}/24
    routes:
      - to: default
        via: ${gateway}
    nameservers:
      addresses:
%{ for dns in dns_servers ~}
        - ${dns}
%{ endfor ~}
