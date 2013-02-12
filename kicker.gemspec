# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kicker/version'

Gem::Specification.new do |gem|
  gem.name          = "kicker"
  gem.version       = Kicker::VERSION
  gem.authors       = ["Simon McCartney"]
  gem.email         = ["simon@mccartney.ie"]
  gem.description   = %q{Utility for kicking an application stack into life on Amazon EC2}
  gem.summary       = %q{Stacks are built from a collection of instances required to build an application stack. 
Each instance is described in the Stackfile & provisioned using variety of methods. Supported models include:
EC2 Create with user-data, cloud-init from user-data (installs masterless puppet), puppet provision the instance.

Other models could include using a puppet master, Chef Solo or Chef Server/Hosted.
Amazon EC2 interaction is done through fog, so other providers should be easily added.

The guiding principle is that your Stackfile should be shareable & re-useable by others, and support templates, so that other users can use the template and easily adjust items in the stack (such as the instance size used, DNS Domain updated during deploy, EC2 account & location)
}
  gem.homepage      = "https://github.com/simonmcc/kicker"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.add_development_dependency('rdoc')
  gem.add_development_dependency('aruba')
  gem.add_development_dependency('rake', '~> 0.9.2')
  gem.add_dependency('methadone', '~> 1.2.4')
  gem.add_dependency('fog', '~> 1.7.0')
end
