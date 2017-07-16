require 'puppet/provider/iispowershell'
require 'json'

Puppet::Type.type(:iis_app).provide(:powershell, parent: Puppet::Provider::Iispowershell) do
  confine operatingsystem: :windows
  confine powershell_version: %i[5.0 4.0 3.0]

  def initialize(value = {})
    super(value)
    @property_flush = {
      'appattrs' => {}
    }
  end

  # snap_mod: import the WebAdministration module, or add the WebAdministration snap-in.
  $snap_mod = if Facter.value(:os)['release']['major'] != '2008'
                'Import-Module WebAdministration'
              else
                'Add-PSSnapin WebAdministration'
              end

  mk_resource_methods

  def self.prefetch(resources)
    sites = instances
    resources.keys.each do |site|
      if provider = sites.find { |s| s.name == site }
        resources[site].provider = provider
      end
    end
  end

  def self.instances
    inst_cmd = "#{$snap_mod}; Get-WebApplication | Select path, physicalPath, applicationPool, ItemXPath | ConvertTo-JSON -Depth 4"
    apps_listed = Puppet::Type::Iis_app::ProviderPowershell.run(inst_cmd)
    app_json = if apps_listed == ''
                 [] # https://github.com/RossMurr4y/iis/issues/7
               else
                 JSON.parse(apps_listed)
               end
    app_json = [app_json] if app_json.is_a?(Hash)
    app_json.map do |app|
      app_hash                = {}
      app_hash[:ensure]       = :present
      app_hash[:name]         = app['path'].gsub(%r{^\/}, '')
      app_hash[:physicalpath] = app['physicalPath']
      app_hash[:app_pool]     = app['applicationPool']
      app_hash[:parent_site]  = app['ItemXPath'].scan(/'([^']*)'/).first.first
      new(app_hash)
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    create_switches = [
      "#{$snap_mod};",
      "New-WebApplication -Name \"#{@resource[:name]}\"",
      "-PhysicalPath \"#{@resource[:physicalpath]}\"",
      "-Site \"#{@resource[:parent_site]}\"",
      "-ApplicationPool \"#{@resource[:app_pool]}\"",
      '-Force'
    ]
    inst_cmd = create_switches.join(' ')
    begin
      resp = Puppet::Type::Iis_app::ProviderPowershell.run(inst_cmd)
    rescue Puppet::ExecutionFailure => e
      raise('Failed to create iis_app resource.')
    end

    @resource.original_parameters.each_key do |k|
      @property_hash[k] = @resource[k]
    end
    @property_hash[:ensure] = :present unless @property_hash[:ensure]

    exists? ? (return true) : (return false)
  end

  def destroy
    inst_cmd = [
      "#{$snap_mod};",
      'Remove-WebApplication',
      "-Site \"#{@property_hash[:parent_site]}\"",
      "-Name \"#{@property_hash[:name]}\""
    ]
    resp = Puppet::Type::Iis_app::ProviderPowershell.run(inst_cmd.join(' '))
    raise(resp) unless resp.empty?

    @property_hash.clear
    exists? ? (return false) : (return true)
  end

  def app_pool=(value)
    @property_flush['appattrs']['applicationPool'] = value
    @property_hash[:app_pool] = value
  end

  def site=(value)
    @property_flush['appattrs']['ItemXPath'] = value
    @property_hash[:parent_site] = value
  end

  def flush
    command_array = [$snap_mod]
    @property_flush['appattrs'].each do |appattr, value|
      command_array << "Set-ItemProperty \"IIS:\\\\Sites\\#{@property_hash[:parent_site]}\\#{@property_hash[:name]}\" #{appattr} #{value}"
    end
    resp = Puppet::Type::Iis_app::ProviderPowershell.run(command_array.join('; '))
    raise(resp) unless resp.empty?
  end
end
