require 'rubygems'
require 'json'
require 'active_support/core_ext'

module Hetzner
  module Host
    class Vm < Thor
      include Actions

      desc "create", "create a new VM"
      method_options(
        :name      => :required, # e.g. vm-001
        :user_name => 'server',
        :user_pass => :required, # e.g. NE36D2
        :ip        => :required, # e.g. 79.48.232.9
        :cpus      => 4,
        :ram       => 4096,
        :swap      => 1024,
        :hdd       => 51200,
        :config    => :required
      )
      def create
        run "mkdir -p /root/vms"

        if File.exists?("/root/vms/#{options[:name]}")
          say("VM '/root/vms/#{options[:name]}' already exists.", Color::RED)
          exit
        end

        file = File.join('/root', 'hetzner', 'host', 'install', 'config', options[:config])
        unless File.exists?(file)

          file = options[:config]
          unless File.exists?(file)
            say("Can not find configuration '#{file}'", Color::RED)
            exit
          end

        end

        config = JSON.parse(File.read(file))

        vm_network_gateway  = config['server']['host']['subnet']['gateway']   # e.g. 79.48.232.14
        vm_network_mask     = config['server']['host']['subnet']['maske']     # e.g. 255.255.255.248
        vm_network_net      = config['server']['host']['subnet']['net']       # e.g. 176.9.0.0
        vm_network_bcast    = config['server']['host']['subnet']['broadcast'] # e.g. 176.9.0.31
        vm_network_dns      = config['server']['host']['subnet']['dns']       # e.g. '213.133.98.98 213.133.99.99 213.133.100.100'

        shell_cmd = %{ubuntu-vm-builder kvm precise -v  \
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
        run(shell_cmd)

        run "virsh autostart #{options[:name]}"
        run "virsh start #{options[:name]}"
        run 'virsh -c qemu:///system list --all'
      end

      desc "edit", "edit the given VM"
      method_options(:name => :required)
      def edit
        run "virsh edit #{options[:name]}"
      end

      desc "list", "show list of all VM's"
      def list
        run 'virsh -c qemu:///system list --all'
      end

      desc "start", "start the given VM"
      method_options(:name => :required)
      def start
        run "virsh start #{options[:name]}"
      end

      desc "stop", "stop the given VM"
      method_options(:name => :required)
      def stop
        run "virsh shutdown #{options[:name]}"
      end

      desc "backup", "backup the given VM"
      method_options(:name => :required)
      def backup
        run "mkdir -p /root/backups/vms/#{options[:name]}"
        backup_name = "vm_backup_#{Time.new.strftime('%Y%m%d-%H%M')}"
        run "virsh save #{options[:name]} /root/backups/vms/#{options[:name]}/#{backup_name}"
        invoke :start
      end

      desc "backups", "get list of backups for the given VM"
      method_options(:name => :required)
      def backups
        run "mkdir -p /root/backups/vms/#{options[:name]}"
        run "ls -lh /root/backups/vms/#{options[:name]}/"
      end

      desc "restore", "restore the given VM dump"
      method_options(:name => :required, :file => :required)
      def restore
        run "virsh shutdown #{options[:name]}"
        run "virsh restore /root/backups/vms/#{options[:name]}/#{options[:file]}"
      end
    end
  end
end
