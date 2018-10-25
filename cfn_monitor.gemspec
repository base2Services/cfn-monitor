
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "cfn_monitor/version"

Gem::Specification.new do |spec|
  spec.name          = "cfn_monitor"
  spec.version       = CfnMonitor::VERSION
  spec.authors       = ["Base2Services", "Jared Brook", "Angus Vine"]
  spec.email         = ["itsupport@base2services.com"]

  spec.summary       = %q{Configure and generate a cloudwatch monitoring cloudformation stack}
  spec.description   = %q{CloudWatch monitoring tool can query a cloudformation stack and return
                          monitorable resources that can be placed into a config file. This config
                          can then be used to generate a cloudformation stack to create and manage
                          cloudwatch alarms.}
  spec.homepage      = "https://github.com/base2Services/cfn-monitor/blob/master/README.md"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 0.19.1"
  spec.add_dependency "cfndsl", "~> 0.16.6"
  spec.add_dependency "aws-sdk-cloudformation", "~> 1", "<2"
  spec.add_dependency "aws-sdk-s3", "~> 1", "<2"
  spec.add_dependency "aws-sdk-elasticloadbalancingv2", "~> 1", "<2"

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rspec", "~> 0"
end
