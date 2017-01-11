#!ruby
source 'https://rubygems.org'

group :test do
  gem 'rake'
  gem 'rspec', '~> 3.5.0'
  gem 'mocha', '~> 1.2.0'
end

mcollective_version = ENV['MCOLLECTIVE_GEM_VERSION']

if mcollective_version
  gem 'mcollective-client', mcollective_version, :require => false
else
  gem 'mcollective-client', :require => false
end
