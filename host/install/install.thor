require 'erubis'
require 'yaml'
require 'active_support/core_ext'

module Hetzner
  SERVER_CONFIG_DIR = '/root/hetzner'

  module Helpers
    def backup_file_suffix
      "_backup_#{Time.new.strftime('%Y%m%d-%H%M')}"
    end

    def config
      YAML.load_file(File.join(SERVER_CONFIG_DIR, 'host', 'install', 'config.yml'))
    end
  end

  module Host
    class Install < Thor
      include Helpers

      desc "configure_hostname", "set hostname"
      def configure_hostname
        hostname  = config['server']['host']['hostname']
        server_ip = config['server']['host']['ip']
        if hostname.present?
          # backup origin configuration
          FileUtils.cp('/etc/hostname', '/etc/hostname' + backup_file_suffix, :verbose => true)
          FileUtils.cp('/etc/hosts', '/etc/hosts' + backup_file_suffix, :verbose => true)

          # set new configuration
          open('/etc/hostname', 'w') { |f| f.write(hostname) }
          hosts = open('/etc/hosts').read
          open('/etc/hosts', 'w') do |f|
            f.write(hosts.gsub(/#{server_ip}.*$/, "#{server_ip} #{hostname}"))
          end

          # restart service
          system('/etc/init.d/hostname restart')
        end
      end

      desc "configure_network", "setup network"
      def configure_network
        # network configuration
        FileUtils.cp('/etc/network/interfaces', '/etc/network/interfaces' + backup_file_suffix, :verbose => true)
        eruby = Erubis::Eruby.new(open(SERVER_CONFIG_DIR + '/host/install/templates/etc/network/interfaces').read)
        open('/etc/network/interfaces', 'a') do |f|
          f.write(eruby.result(
            :gateway => config['server']['host']['subnet']['gateway'],
            :maske   => config['server']['host']['subnet']['maske'],
            :ips     => config['server']['host']['subnet']['ips']
          ))
        end

        # sysctl.conf
        FileUtils.cp('/etc/sysctl.conf', '/etc/sysctl.conf' + backup_file_suffix, :verbose => true)
        FileUtils.cp(SERVER_CONFIG_DIR + '/host/install/templates/etc/sysctl.conf', '/etc/sysctl.conf', :verbose => true)

        # restart service
        system('/etc/init.d/networking restart')
      end

      desc "configure_munin", "setup monitoring tool munin"
      def configure_munin
        FileUtils.cp('/etc/munin/munin.conf', '/etc/munin/munin.conf' + backup_file_suffix, :verbose => true)
        eruby = Erubis::Eruby.new(open(SERVER_CONFIG_DIR + '/host/install/templates/etc/munin/munin.conf').read)
        open('/etc/munin/munin.conf', 'w') { |f| f.write(eruby.result) }

        system('/etc/init.d/munin-node stop')
        system('/etc/init.d/munin-node start')

        open('/etc/munin/munin-htpasswd', 'w') { |f| f.write(config['server']['host']['tools']['munin']['htpasswd']) }
        FileUtils.cp('/etc/munin/apache.conf', '/etc/munin/apache.conf' + backup_file_suffix, :verbose => true)
        FileUtils.cp(SERVER_CONFIG_DIR + '/host/install/templates/etc/munin/apache.conf', '/etc/munin/apache.conf', :verbose => true)

        system('/etc/init.d/apache2 stop')
        system('/etc/init.d/apache2 start')
      end
    end

    class Vm < Thor
      include Helpers

      desc "create", "create a new VM"
      method_options(
        :name      => :required, # e.g. vm-001
        :user_name => 'server',
        :user_pass => :required, # e.g. NE36D2
        :ip        => :required, # e.g. 79.48.232.9
        :cpus      => 4,
        :ram       => 4096,
        :swap      => 1024,
        :hdd       => 20480
      )
      def create
        FileUtils.mkdir_p('/root/vms', :verbose => true)
        if File.exists?("/root/vms/#{options[:name]}")
          say("Folder '/root/vms/#{options[:name]}' already exists.", Color::RED); exit
        end

        vm_network_gateway  = config['server']['host']['subnet']['gateway']   # e.g. 79.48.232.14
        vm_network_mask     = config['server']['host']['subnet']['maske']     # e.g. 255.255.255.248
        vm_network_net      = config['server']['host']['subnet']['net']       # e.g. 176.9.0.0
        vm_network_bcast    = config['server']['host']['subnet']['broadcast'] # e.g. 176.9.0.31
        vm_network_dns      = config['server']['host']['subnet']['dns']       # e.g. '213.133.98.98 213.133.99.99 213.133.100.100'

        shell_cmd = %{ubuntu-vm-builder kvm lucid -v  \
          --cpus=#{options[:cpus]} \
          --mem=#{options[:ram]} \
          --swapsize=#{options[:swap]} \
          --rootsize=#{options[:hdd]} \
          --bridge=br0 \
          --libvirt=qemu:///system \
          --flavour=server \
          --hostname=#{options[:name]} \
          --ip=#{options[:ip]} \
          --mask=#{vm_network_mask} \
          --net=#{vm_network_net} \
          --bcast=#{vm_network_bcast} \
          --gw=#{vm_network_gateway} \
          --dns=#{vm_network_dns} \
          --mirror=http://de.archive.ubuntu.com/ubuntu \
          --components='main,universe' \
          --addpkg='openssh-server,acpid,htop,wget,screen' \
          --user=#{options[:user_name]} \
          --pass=#{options[:user_pass]} \
          --timezone='CET' \
          --dest=/root/vms/#{options[:name]}}
        puts(shell_cmd); system(shell_cmd)

        shell_cmd = "virsh autostart #{options[:name]}"
        puts(shell_cmd); system(shell_cmd)

        shell_cmd = "virsh start #{options[:name]}"
        puts(shell_cmd); system(shell_cmd)

        shell_cmd = 'virsh -c qemu:///system list --all'
        puts(shell_cmd); system(shell_cmd)
      end

      desc "edit", "edit the given VM"
      method_options(:name => :required)
      def edit
        shell_cmd = "virsh edit #{options[:name]}"
        puts(shell_cmd); system(shell_cmd)
      end

      desc "list", "show list of all VM's"
      def list
        shell_cmd = 'virsh -c qemu:///system list --all'
        puts(shell_cmd); system(shell_cmd)
      end

      desc "start", "start the given VM"
      method_options(:name => :required)
      def start
        shell_cmd = "virsh start #{options[:name]}"
        puts(shell_cmd); system(shell_cmd)
      end

      desc "stop", "stop the given VM"
      method_options(:name => :required)
      def stop
        shell_cmd = "virsh shutdown #{options[:name]}"
        puts(shell_cmd); system(shell_cmd)
      end

      desc "backup", "backup the given VM"
      method_options(:name => :required)
      def backup
        FileUtils.mkdir_p("/root/backups/vms/#{options[:name]}", :verbose => true)
        shell_cmd = "virsh save #{options[:name]} /root/backups/vms/#{options[:name]}/vm#{backup_file_suffix}"
        puts(shell_cmd); system(shell_cmd)
        invoke :start
      end

      desc "backups", "get list of backups for the given VM"
      method_options(:name => :required)
      def backups
        FileUtils.mkdir_p("/root/backups/vms/#{options[:name]}", :verbose => true)
        shell_cmd = "ls -lh /root/backups/vms/#{options[:name]}/"
        puts(shell_cmd); system(shell_cmd)
      end

      desc "restore", "restore the given VM dump"
      method_options(:name => :required, :file => :required)
      def restore
        shell_cmd = "virsh restore /root/backups/vms/#{options[:name]}/#{options[:file]}"
        puts(shell_cmd); system(shell_cmd)
      end
    end
  end
end
