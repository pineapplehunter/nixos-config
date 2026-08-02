{
  systemd.network.networks = {
    "99-ethernet-default-dhcp".networkConfig.MulticastDNS = "yes";
    "99-wireless-client-dhcp".networkConfig.MulticastDNS = "yes";
  };

  users.users.andy = {
    isNormalUser = true;
    description = "Write-access to samba media shares";
    extraGroups = [ "users" ];
  };

  services = {
    samba = {
      enable = true;
      openFirewall = true;
      settings.timemachine = {
        "path" = "/samba/timemachine";
        "valid users" = "andy";
        "public" = "no";
        "writeable" = "yes";
        "force user" = "andy";
        # Below are the most important settings for macOS compatibility.
        "fruit:aapl" = "yes";
        "fruit:time machine" = "yes";
        "vfs objects" = "catia fruit streams_xattr";
      };
    };

    # Make Samba discoverable from Windows.
    samba-wsdd = {
      enable = true;
      openFirewall = true;
    };

    avahi.extraServiceFiles.timemachine = ''
      <?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">%h</name>
        <service>
          <type>_smb._tcp</type>
          <port>445</port>
        </service>
        <service>
          <type>_device-info._tcp</type>
          <port>0</port>
          <txt-record>model=TimeCapsule8,119</txt-record>
        </service>
        <service>
          <type>_adisk._tcp</type>
          <txt-record>dk0=adVN=timemachine,adVF=0x82</txt-record>
          <txt-record>sys=waMa=0,adVF=0x100</txt-record>
        </service>
      </service-group>
    '';
  };
}
