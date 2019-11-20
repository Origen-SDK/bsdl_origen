# coding: utf-8
config = File.expand_path('../config', __FILE__)
require "#{config}/version"

Gem::Specification.new do |spec|
  spec.name          = "bsdl_origen"
  spec.version       = BsdlOrigen::VERSION
  spec.authors       = ["nxa16226"]
  spec.email         = ["nxa16226@nxp.com"]
  spec.summary       = "Boundary Scan Description Language pattern generator"
  #spec.homepage      = "http://origen.mycompany.net/bsdl_origen"

  spec.required_ruby_version     = '>= 2'
  spec.required_rubygems_version = '>= 1.8.11'

  # Only the files that are hit by these wildcards will be included in the
  # packaged gem, the default should hit everything in most cases but this will
  # need to be added to if you have any custom directories
  spec.files         = Dir["lib/bsdl_origen.rb", "lib/bsdl_origen/**/*.rb", "templates/**/*", "config/**/*.rb",
                           "bin/*", "lib/tasks/**/*.rake", "pattern/**/*.rb", "program/**/*.rb",
                           "app/lib/**/*.rb", "app/templates/**/*",
                           "app/patterns/**/*.rb", "app/flows/**/*.rb", "app/blocks/**/*.rb"
                          ]
  spec.executables   = []
  spec.require_paths = ["lib", "app/lib"]

  # Add any gems that your plugin needs to run within a host application
  spec.add_runtime_dependency "origen", ">= 0.54.4"
  
  spec.add_runtime_dependency "origen_testers", ">= 0.6.1"
  end
