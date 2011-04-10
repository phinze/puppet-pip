require 'rubygems'
require 'rspec'
require 'puppet'
require File.expand_path(File.dirname(__FILE__) + '/../lib/puppet/provider/package/pip')

Rspec.configure do |c|
    c.mock_with :mocha
end
