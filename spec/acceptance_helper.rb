# coding: utf-8

require 'yaml'
require 'cloudservers'

require 'spec_helper'

class Babushka::Logging
  def self.print_log message, printable, as
    # Re-enable logging for the acceptance specs.
    print_log!(message, printable, as)
  end

  def self.write_to_persistent_log message
    # Don't overwrite logs when running acceptance specs.
  end
end

class VM
  include Babushka::LogHelpers
  include Babushka::ShellHelpers

  SERVER_NAME = 'babushka-specs'

  def babushka task
    run("babushka \"#{task}\" --defaults").tap {|result|
      # Fetch the debug log if the dep failed
      run "cat ~/.babushka/logs/\"#{task}\"" unless result
    }
  end

  def run cmd, user = 'root'
    log "\nRunning on #{user}@#{host}: #{cmd}" do
      shell "ssh #{user}@#{host} '#{cmd}'", :log => true
    end
  end

  def server
    @_server || (existing_server || create_server).tap {|s|
      wait_for_server
    }
  end

  private

  def existing_server
    server_detail = connection.list_servers_detail.detect {|s| s[:name] == SERVER_NAME }
    unless server_detail.nil?
      @_server = connection.get_server(server_detail[:id])
      log "A #{image[:name]} server is already running at #{@_server.addresses[:public].first}."
      @_server
    end
  end

  def create_server
    log_block "Creating a #{flavor[:ram]}MB #{image[:name]} rackspace instance" do
      @_server = connection.create_server(image_args)
    end
  end

  def wait_for_server
    if server.status != 'ACTIVE'
      log_block "Waiting for the server to come online" do
        until server.status == 'ACTIVE'
          sleep 3
          print '.'
          server.refresh
        end
        log "Online at #{server.addresses[:public].first}."
        server.status == 'ACTIVE'
      end
    end
  end

  def host
    server.addresses[:public].first
  end

  def image_args
    {
      :name => SERVER_NAME,
      :imageId => image[:id],
      :flavorId => flavor[:id],
      :personality => {
        public_key => '/root/.ssh/authorized_keys'
      }
    }
  end

  def image
    connection.list_images.detect {|image| image[:name].downcase[cfg['image_name'].downcase] } ||
      raise(RuntimeError, "Couldn't find an image that matched '#{cfg['image_name']}' in #{connection.list_images.map {|i| i[:name] }}.")
  end

  def flavor
    connection.list_flavors.detect {|flavor| flavor[:ram] == 256 } ||
      raise(RuntimeError, "Couldn't find the specs for a 256MB instance.")
  end

  def connection
    @_connection ||= CloudServers::Connection.new(
      :username => cfg['username'], :api_key => cfg['api_key']
    )
  end

  def cfg
    @_cfg ||= YAML.load_file(Babushka::Path.path / 'conf/rackspace.yml')
  end

  def public_key
    Dir.glob(File.expand_path("~/.ssh/id_[dr]sa.pub")).first
  end
end

RSpec::Matchers.define :meet do |expected|
  match {|vm|
    vm.babushka(expected).should =~ /^\} ✓ #{Regexp.escape(expected)}\z/
  }
  failure_message {|vm|
    "The '#{expected}' dep couldn't be met."
  }
end
