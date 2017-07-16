require 'puppet/provider/iispowershell'
require 'json'

Puppet::Type.type(:iis_vdir).provide(:powershell, parent: Puppet::Provider::Iispowershell) do
  confine operatingsystem: :windows

  # snap_mod: import the WebAdministration module, or add the WebAdministration snap-in.
  $snap_mod = if Facter.value(:os)['release']['major'] != '2008'
                'Import-Module WebAdministration'
              else
                'Add-PSSnapin WebAdministration'
              end

  mk_resource_methods

  def initialize(value = {})
    super(value)
    @property_flush = {
      'vdirattrs' => {}
    }
  end

  def self.prefetch(resources)
    sites = instances
    resources.keys.each do |site|
      if provider = sites.find { |s| s.name == site }
        resources[site].provider = provider
      end
    end
  end

  def self.instances
    virtual_directories = []
    inst_cmd = "#{$snap_mod}; Get-WebVirtualDirectory | Select path, physicalPath, ItemXPath | ConvertTo-JSON -Depth 4"
    dirs_listed = Puppet::Type::Iis_vdir::ProviderPowershell.run(inst_cmd)
    vdir_json = if dirs_listed == ''
                  [] # https://github.com/RossMurr4y/iis/issues/7
                else
                  JSON.parse(dirs_listed)
                end
    vdir_json = [vdir_json] if vdir_json.is_a?(Hash)
    vdir_json.each do |dir|
      dir_hash               = {}
      dir_hash[:name]        = dir['path'].gsub(%r{^\/}, '')
      dir_hash[:path]        = dir['physicalPath']
      dir_hash[:parent_site] = dir['ItemXPath'].scan(/'([^']*)'/).first.first
      dir_hash[:ensure]      = :present
      virtual_directories << new(dir_hash)
    end
    virtual_directories
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    create_switches = [
      "#{$snap_mod};",
      "New-WebVirtualDirectory -Name \"#{@resource[:name]}\"",
      "-PhysicalPath \"#{@resource[:path]}\"",
      "-Site \"#{@resource[:parent_site]}\"",
      '-Force'
    ]
    inst_cmd = create_switches.join(' ')
    begin
      resp = Puppet::Type::Iis_vdir::ProviderPowershell.run(inst_cmd)
    rescue Puppet::ExecutionFailure => e
      raise('Failed to create iis_vdir resource.')
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
      'Remove-WebVirtualDirectory',
      "-Site \"IIS:\\Sites\\#{@property_hash[:parent_site]}",
      "-Name \"#{@property_hash[:name]}\""
    ]
    resp = Puppet::Type::Iis_vdir::ProviderPowershell.run(inst_cmd.join(' '))
    raise(resp) unless resp.empty?
    @property_hash.clear
    exists? ? (return false) : (return true)
  end

  def site=(value)
    @property_flush['vdirattrs'][:parent_site] = value
    @property_hash[:parent_site] = value
  end

  def name=(value)
    @property_flush['vdirattrs'][:name] = value
    @property_hash[:name] = value
  end

  def path=(value)
    @property_flush['vdirattrs'][:path] = value
    @property_hash[:path] = value
  end

  def flush
    command_array = [$snap_mod]
    @property_flush['vdirattrs'].each do |vdirattr, value|
      command_array << "Set-ItemProperty \"IIS:\\\\Sites\\#{@property_hash[:parent_site]}\\#{@property_hash[:name]}\" #{vdirattr} #{value}"
    end
    resp = Puppet::Type::Iis_vdir::ProviderPowershell.run(command_array.join('; '))
    raise(resp) unless resp.empty?
  end
end
