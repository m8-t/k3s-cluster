version: 2
ethernets:
  enp0s3:
    dhcp4: false
    dhcp6: false
    addresses:
      - ${ip_address}/24
    routes:
      - to: 0.0.0.0/0
        via: ${gateway}
    nameservers:
      addresses:
%{ for dns in dns_servers ~}
        - ${dns}
%{ endfor ~}
