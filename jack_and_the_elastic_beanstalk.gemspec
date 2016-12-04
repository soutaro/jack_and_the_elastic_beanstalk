# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'jack_and_the_elastic_beanstalk/version'

Gem::Specification.new do |spec|
  spec.name          = "jack_and_the_elastic_beanstalk"
  spec.version       = JackAndTheElasticBeanstalk::VERSION
  spec.authors       = ["Soutaro Matsumoto"]
  spec.email         = ["matsumoto@soutaro.com"]

  spec.summary       = %q{Jack and the Elastic Beanstalk.}
  spec.description   = %q{Jack and the Elastic Beanstalk.}
  spec.homepage      = "https://github.com/sideci/jack_and_the_elastic_beanstalk"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.13"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"

  spec.add_runtime_dependency 'dotenv', "~> 2.1"
  spec.add_runtime_dependency 'rainbow', '~> 2.1'
  spec.add_runtime_dependency "aws-sdk", "~> 2.6"
  spec.add_runtime_dependency "thor", "~> 0.19"
end
