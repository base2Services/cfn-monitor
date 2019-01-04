require "thor"
require "cfn_monitor/version"
require "cfn_monitor/query"
require "cfn_monitor/generate"
require "cfn_monitor/deploy"

module CfnMonitor
  class Commands < Thor

    map %w[--version -v] => :__print_version
    desc "--version, -v", "print the version"
    def __print_version
      puts CfnMonitor::VERSION
    end

    class_option :silent,
        aliases: :s,
        type: :boolean,
        default: false,
        desc: "Don't print cfndsl output"

    # class_option :verbose,
    #   aliases: :V,
    #   type: :boolean,
    #   default: false,
    #   lazy_default: true,
    #   desc: "Extra logging"
    #
    # class_option :region,
    #   group: :aws,
    #   aliases: :r,
    #   type: :string,
    #   desc: "AWS Region"
    #
    # class_option :profile,
    #   group: :aws,
    #   aliases: :p,
    #   type: :string,
    #   desc: "Profile name in AWS credentials file"

    desc "generate", "Generate monitoring cloudformation templates"
    long_desc <<-LONG
    Generates cloudformation templates from the alarm configuration and output to the output/ directory.
    LONG
    method_option :application, aliases: :a, type: :string, desc: "application name"
    # method_option :validate, aliases: :v, type: :boolean, default: true, desc: "validate cfn templates"
    def generate
      CfnMonitor::Generate.run(options)
    end

    desc "query", "Queries a cloudformation stack for monitorable resources"
    long_desc <<-LONG
    This will provide a list of resources in the correct config syntax,
    including the nested stacks and the default templates for those resources.
    LONG
    method_option :application, aliases: :a, type: :string, desc: "application name"
    method_option :stack, aliases: :s, type: :string, desc: "cfn stack name"
    def query
      CfnMonitor::Query.run(options)
    end

    desc "deploy", "Deploys generated cfn templates to S3 bucket"
    long_desc <<-LONG
    Deploys generated cloudformation templates to the specified S3 source_bucket
    LONG
    method_option :application, aliases: :a, type: :string, desc: "application name"
    def deploy
      CfnMonitor::Deploy.run(options)
    end

  end
end
