Vagrant.configure("2") do |config|
  config.vm.box = "generic/debian12"

  config.vm.synced_folder ".", "/vagrant", type: "rsync",
    rsync__exclude: [".vagrant/", "capturas/", "screencast/"]

  config.vm.define "AlejandroDuquePrestashop" do |ps|
    ps.vm.hostname = "AlejandroDuquePrestashop"
    ps.vm.network "private_network", ip: "192.168.56.10"

    ps.vm.provider "vmware_desktop" do |v|
      v.gui = false
      v.memory = "2048"
      v.cpus = 2
      v.linked_clone = false
    end

    ps.vm.provision "lamp", type: "shell", path: "scripts/install_lamp.sh", run: "never"

    ps.vm.provision "https", type: "shell", path: "scripts/setup_letsencrypt_https.sh",
      env: { "DUCKDNS_TOKEN" => ENV.fetch("DUCKDNS_TOKEN", "") }, run: "never"

    ps.vm.provision "prestashop-info", type: "shell",
      path: "scripts/deploy_prestashop.sh", args: ["preparar"], run: "never"

    ps.vm.provision "prestashop-install", type: "shell",
      path: "scripts/deploy_prestashop.sh", args: ["instalar"], run: "never"
  end
end
