require 'pp'
require 'fog'

module Stack

  Logger = Logger.new(STDOUT)
  Logger.level = ::Logger::INFO
  Logger.datetime_format = "%Y-%m-%d %H:%M:%S"
  Logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime} #{severity}: #{msg}\n"
  end

  @@gemhome = File.absolute_path(File.realpath(File.dirname(File.expand_path(__FILE__)) + '/..'))

  def Stack.load_config(configfile, stack)
    config_raw = File.read(configfile)
    eval(config_raw)

    config = StackConfig::Stacks[stack]
    config[:stackhome] = File.dirname(File.expand_path(configfile))
    config
  end

  def Stack.connect(config)
    connection = Fog::Compute.new({ :provider => config[:provider],
                                    :aws_access_key_id => config[:aws_access_key_id],
                                    :aws_secret_access_key => config[:aws_secret_access_key],
                                    :region => config[:region] })
    connection
  end

  def Stack.populate_config(config)

    config[:find_file_paths] = Array.new if config[:find_file_paths].nil?
    config[:mime_encode_user_data] = true if config[:mime_encode_user_data].nil?
    config[:maintain_dns] = true if config[:maintain_dns].nil?

    # build out the full config for each node, supplying defaults from the
    # global config if explicitly supplied
    config[:node_details] = Hash.new if config[:node_details].nil?

    config[:roles].each do |role, role_details|
      fqdn = role.to_s + '.' + config[:dns_domain]

      config[:node_details][fqdn] = {
        # set the node details from the role, if not specified in the role, use the config global
        # (takes advantage of left to right evaluation of ||)
        :flavor_id          => (role_details[:flavor_id] || config[:flavor_id]),
        :count              => (role_details[:count] || 1),
        :publish_private_ip => (role_details[:publish_private_ip] || false),
        :dns_wildcard       => (role_details[:dns_wildcard] || false),
        :bootstrap          => (role_details[:bootstrap] || 'user-data.sh'),
        :cloud_config_yaml  => (role_details[:cloud_config_yaml] || 'cloud-init.yaml'),
      }
    end
  end

  def Stack.generate_hostnames(config)
    stack_hostnames = Array.new
    config[:roles].each do |role, role_details|
      fqdn = role.to_s + '.' + config[:dns_domain]
      stack_hostnames << fqdn
    end
    stack_hostnames
  end

  def Stack.deploy_all(config)
    # generate the hostnames & details from the config & apply defaults where required
    Stack.populate_config(config)

    # create a connection
    connection = Stack.connect(config)

    running_instances = Stack.get_running(config)
    config[:roles].each do |role, role_details|
      hostname = role.to_s
      fqdn = role.to_s + '.' + config[:dns_domain]

      if !running_instances[fqdn].nil?
        Logger.info "Skipping creation od #{fqdn} instance as it already exists"
        server = running_instances[fqdn]
      else
        # Ubuntu 8.04/Hardy doesn't do full cloud-init, so we have to script setting the hostname
        libdir = File.realpath(@@gemhome + '/lib')

        bootstrap_abs = Stack.find_file(config, config[:node_details][fqdn][:bootstrap])
        cloud_config_yaml_abs = Stack.find_file(config, config[:node_details][fqdn][:cloud_config_yaml])

        if config[:mime_encode_user_data]
          Logger.debug "mime encoding user-data..."
          multipart_cmd = "#{libdir}/write-mime-multipart #{bootstrap_abs} #{cloud_config_yaml_abs}"
          user_data = `#{multipart_cmd}`
        else
          # Ubuntu Hardy seems to struggle with some mime-encoded user-data
          # so allow the user to forse submitting user-data un-mimed,
          # in which case we can only pass one file & it must be the bootstrap script
          Logger.debug "mime encoding user-data disabled, only sending the bootstrap script"
          user_data = File.read(bootstrap_abs)
        end

        user_data.gsub!(/rentpro-unconfigured/, hostname)
        user_data.gsub!(/rentpro-stage.local/, config[:dns_domain])


        # pp multipart
        #
        puts "Bootstraping new instance - #{fqdn}, in #{config[:availability_zone]}, flavor #{config[:node_details][fqdn][:flavor_id]}, image_id #{config[:image_id]}"
        server = connection.servers.create({
                                          :name => fqdn,
                                          :hostname => fqdn,
                                          :availability_zone => config[:availability_zone],
                                          :flavor_id => config[:node_details][fqdn][:flavor_id],
                                          :image_id => config[:image_id],
                                          :key_name => config[:keypair],
                                          :user_data => user_data,
                                          :tags => { 'Name' => fqdn },
                                          })

        print "Waiting for instance to be ready..."
        server.wait_for { ready? }
        puts "#{role.to_s} is booted, #{server.public_ip_address}/#{server.private_ip_address}"
      end

      if config[:maintain_dns]
        Logger.info "Updating DNS for #{fqdn}"
        # create/update the public & private DNS for this host
        Stack.update_dns(role.to_s + '-public.' + config[:dns_domain], server.public_ip_address, config)
        Stack.update_dns(role.to_s + '-private.' + config[:dns_domain], server.private_ip_address, config)

        # create the dns
        if (role_details[:publish_private_ip] == true && (!role_details[:publish_private_ip].nil?))
          ip_address = server.private_ip_address
        else
          ip_address = server.public_ip_address
        end
        Stack.update_dns(fqdn, ip_address, config)
        #
        # is this a wildcard DNS host, then claim the *.domain.net
        if (role_details[:dns_wildcard] == true && (!role_details[:dns_wildcard].nil?))
          wildcard = "*." + config[:dns_domain]
          Stack.update_dns(wildcard, ip_address, config)
        end
      end
    end
  end

  def Stack.update_dns(fqdn, ip_address, config)
    # now register it in DNS
    dns = Fog::DNS.new({ :provider => config[:provider],
                          :aws_access_key_id => config[:aws_access_key_id],
                          :aws_secret_access_key => config[:aws_secret_access_key] })

    dns.get_hosted_zone(config[:dns_id])
    bmtw = dns.zones.get(config[:dns_id])

    record = bmtw.records.get(fqdn)
    if record
      Logger.info "Updating #{fqdn} with #{ip_address}"
      record.modify(:value => ip_address) if record
    else
      Logger.info "Creating #{fqdn} with #{ip_address}"
      bmtw.records.create(:value => ip_address, :name => fqdn, :type => 'A')
    end
  end

  def Stack.show_dns(config)
    # now register it in DNS
    dns = Fog::DNS.new({ :provider => config[:provider],
                          :aws_access_key_id => config[:aws_access_key_id],
                          :aws_secret_access_key => config[:aws_secret_access_key] })

    zone = dns.zones.get(config[:dns_id])
    if zone.records.empty?
      puts "No DNS records found in #{config[:dns_domain]}"
    else
      printf("%40s %20s %5s %5s\n", 'fqdn', 'value', 'type', 'ttl')
      zone.records.each do |record|
        printf("%40s %20s %5s %5d\n", record.name, record.value, record.type, record.ttl)
      end
    end
  end

  def Stack.get_running(config)
    # create a connection
    connection = Stack.connect(config)

    # generate all the names that this stack will use
    stack_hostnames = Stack.generate_hostnames(config)

    # Amazon EC2, use the tags hash to find hostnames
    running_instances = Hash.new
    connection.servers.each do |instance|
      # pp instance
      if (!instance.tags['Name'].nil? && instance.state != 'terminated' && instance.state != 'shutting-down')
        hostname = instance.tags['Name']
        if stack_hostnames.include?(hostname)
          running_instances[hostname] = instance
        end
      end
    end
    running_instances
  end

  def Stack.show_running(config)
    running_instances = Stack.get_running(config)
    running_instances.each do |instance, instance_details|
      # display some details
      puts "#{instance} id=#{instance_details.id} flavor_id=#{instance_details.flavor_id} public_ip=#{instance_details.public_ip_address} private_ip=#{instance_details.private_ip_address}"
    end
  end

  def Stack.delete_node(config, fqdn)
    running_instances = Stack.get_running(config)
    if running_instances[fqdn].nil?
      puts "ERROR: #{fqdn} isn't running!"
      exit
    else
      Stack.connect(config)
      pp running_instances[fqdn]
      running_instances[fqdn].destroy
    end
  end

  def Stack.show_details(config)
    # create a connection
    connection = Stack.connect(config)

    pp connection.describe_regions
    pp connection.describe_availability_zones

    pp connection.servers

    Stack.populate_config(config)
    pp config[:node_details]
  end

  def upload_keys(config)
    if (key_pair = connection.key_pairs.get(config[:keypair]).nil?)
      key_pair = connection.key_pairs.create( :name => config[:keypair], :public_key => File.read("rentpro-deploy.pub") )
    else
      puts "#{config[:keypair]} key_pair already exists"
    end
  end

  def shutdown_all(config)
    # shutdown all instances
    connection.servers.select do |server|
      puts "Running server:"
      # pp server
    #  server.ready? && server.destroy
    end
  end

  def Stack.validate(config)
    # sanity check
    # check credentials, keys, flavor, image, dns etc
    connection = Stack.connect(config)
    pp connection
    pp connection.images.get(config[:image_id])
  end

  def Stack.find_file(config, filename)
    # find a file, using the standard path precedence
    # 1) cwd
    # 2) stackhome
    # 2) stackhome + find_file_paths
    # 3) gemhome/lib

    if filename.nil? || filename.empty?
      raise ArgumentError
    end

    dirs = [ '.' ]  # current directory
    dirs.push(config[:stackhome])
    config[:find_file_paths].each { |fp| dirs.push(File.join(config[:stackhome], fp)) }
    dirs.push(File.join(@@gemhome, 'lib'))
    dirs.push('')   # find absolute paths
    dirs.flatten!

    Logger.debug "find_file, looking for #{filename} in #{dirs}"
    filename_fqp = ''
    dirs.each do |dir|
      fqp = File.join(dir, filename)
      Logger.debug "find_file: checking #{fqp}"
      if File.file?(fqp)
      Logger.debug "find_file: found #{fqp}!"
        filename_fqp =  File.expand_path(fqp)
      end
    end

    if filename_fqp.empty?
      Logger.warn "couldn't find #{filename} in #{dirs}"
      filename_fqp = nil
    end
    filename_fqp
  end
end
