# stdlib modules
require 'net/http'
require 'webrick'
require 'webrick/https'
require 'webrick/httpproxy'

require 'vcr'

require 'vcr_proxy/server'
require 'vcr_proxy/dependency'
require 'vcr_proxy/driver'
require 'vcr_proxy/settings'

if VCRProxy::Dependency.rails3?
  require 'vcr_proxy/railtie'
end

require 'capybara/poltergeist'

VCRProxy.register_poltergeist_driver

if VCRProxy::Dependency.rspec2?
  require 'vcr_proxy/rspec'
end

module VCRProxy
  class << self
    def prepare(opts = {})
      VCR.configure do |c|
        c.default_cassette_options = { :record => :new_episodes }
      end
      Server.new(opts)
    end

    def log
      @logger ||= begin
        if Dependency.rails?
          Rails.logger
        else
          require 'logger'
          Logger.new(STDOUT)
        end
      end
    end

    def port
      Settings.proxy_port
    end

    def host
      Settings.proxy_host
    end

    # start http proxy server and write the pid under tmp/pids
    def start_with_pid
      stop_with_pid

      Process.fork do
        path = get_pid_root.join(Settings.pid_path)
        path.mkdir unless path.directory?

        path = path.join(Settings.pid_name)

        opts = {
          :Port           => Settings.proxy_port,
          :RequestTimeout => 300,
          :ProxyTimeout   => true,
        }

        server = VCRProxy.prepare(opts)

        log.info "VCRProxy starting on #{VCRProxy.port}, pid #{Process.pid}"

        trap('INT') { server.shutdown }

        path.open('w') do |file|
          file.puts Process.pid
        end

        server.start
      end
    end

    # send INT to VCRProxy pid if file found under tmp/pids/
    def stop_with_pid
      path = get_pid_path

      if path.exist?
        `kill -s INT #{path.read.chomp}`
        path.delete
      else
        log.info "Looked in tmp/pids/; no VCRProxy pids found; nothing happened"
      end
    end

    # FIXME how do we implement configuraion
    def configure(opts = {})
      VCR.configure do |c|
        c.hook_into :webmock
        c.cassette_library_dir = Settings.vcr_library_dir 
        c.default_cassette_options = { :record => :new_episodes }
        c.ignore_localhost = true
        c.ignore_hosts "127.0.0.1"
      end
    end

    private

    def get_pid_path
      get_pid_root.join(Settings.pid_path).join(Settings.pid_name)
    end

    def get_pid_root
      if Dependency.rails?
        Rails.root
      else
        require 'pathname'
        Pathname.new '/'
      end
    end
  end
end
