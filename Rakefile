specdir = File.join([File.dirname(__FILE__), "spec"])

require 'rake'
begin
  require 'rspec/core/rake_task'
rescue LoadError
end

if defined?(RSpec::Core::RakeTask)
  desc "Run plugin tests"
  RSpec::Core::RakeTask.new(:test) do |t|
    require "#{specdir}/spec_helper.rb"
    t.pattern = 'spec/**/*_spec.rb'

   tmp_load_path = $LOAD_PATH.map { |f| f.shellescape }.join(" -I ")
   t.rspec_opts = tmp_load_path + " " + File.read("#{specdir}/spec.opts").chomp
  end
end

task :default => :test
