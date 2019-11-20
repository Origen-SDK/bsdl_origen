require 'origen_testers'
require 'origen'
require_relative '../../config/application.rb'
module BsdlOrigen
  Dir.glob("#{File.dirname(__FILE__)}/bsdl_origen/**/*.rb").sort.each do |file|
    require file
  end
end
