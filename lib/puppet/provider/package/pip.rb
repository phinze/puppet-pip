# Puppet package provider for Python's `pip` package management frontend.
# <http://pip.openplans.org/>

require 'puppet/provider/package'
require 'xmlrpc/client'

Puppet::Type.type(:package).provide :pip,
  :parent => ::Puppet::Provider::Package do

  desc "Python packages via `pip`."

  has_feature :installable, :uninstallable, :upgradeable, :versionable

  # Parse lines of output from `pip freeze`, which are structured as
  # _package_==_version_.
  def self.parse(line)
    if line.chomp =~ /^([^=]+)==([^=]+)$/
      {:ensure => $2, :name => $1, :provider => name}
    else
      nil
    end
  end

  # Return an array of structured information about every installed package
  # that's managed by `pip` or an empty array if `pip` is not available.
  def self.instances
    packages = []
    find_pip
    execpipe "#{command :pip} freeze" do |process|
      process.collect do |line|
        next unless options = parse(line)
        packages << new(options)
      end
    end
    packages
  rescue Puppet::DevError
    []
  end

  # Return structured information about a particular package or `nil` if
  # it is not installed or `pip` itself is not available.
  def query
    self.class.find_pip
    execpipe "#{command :pip} freeze" do |process|
      process.each do |line|
        options = self.class.parse(line)
        return options if options[:name].downcase == @resource[:name].downcase
      end
    end
    nil
  rescue Puppet::DevError
    nil
  end

  # Ask the PyPI API for the latest version number.  There is no local
  # cache of PyPI's package list so this operation will always have to
  # ask the web service.
  def latest
    client = XMLRPC::Client.new2("http://pypi.python.org/pypi")
    client.http_header_extra = {"Content-Type" => "text/xml"}
    result = client.call("package_releases", @resource[:name])
    result.first
  end

  # Install a package.  The ensure parameter may specify installed,
  # latest, a version number, or, in conjunction with the source
  # parameter, an SCM revision.  In that case, the source parameter
  # gives the fully-qualified URL to the repository.
  def install
    args = %w{install -q}
    if @resource[:source]
      args << "-e"
      if String === @resource[:ensure]
        args << "#{@resource[:source]}@#{@resource[:ensure]}#egg=#{
          @resource[:name]}"
      else
        args << "#{@resource[:source]}#egg=#{@resource[:name]}"
      end
    else
      case @resource[:ensure]
      when String
        args << "#{@resource[:name]}==#{@resource[:ensure]}"
      when :latest
        args << "--upgrade" << @resource[:name]
      else
        args << @resource[:name]
      end
    end
    lazy_pip *args
  end

  # Uninstall a package.  Uninstall won't work reliably on Debian/Ubuntu
  # unless this issue gets fixed.
  # <http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=562544>
  def uninstall
    lazy_pip "uninstall", "-y", "-q", @resource[:name]
  end

  def update
    install
  end

  # Execute a `pip` command.  If Puppet doesn't yet know how to do so,
  # try to teach it and if even that fails, raise the error.
  private
  def lazy_pip(*args)
    pip *args
  rescue NoMethodError => e
    self.class.find_pip
    pip *args
  end

  def self.find_pip
    if pathname = `which pip`.chomp
      self.commands :pip => pathname
      command :pip
    else
      raise "could not find `pip` command"
    end
  end
end
