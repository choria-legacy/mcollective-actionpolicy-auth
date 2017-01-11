#!/bin/env rspec

require 'spec_helper'
require File.join(File.dirname(__FILE__), '../../', 'util', 'actionpolicy.rb')

module MCollective
  module Util
    describe ActionPolicy do
      let(:request) { stub(:agent => 'rspec_agent', :caller => 'rspec_caller', :action => 'rspec_action') }
      let(:config) { stub(:configdir => '/rspecdir', :pluginconf => {}) }
      let(:fixtures_dir) { File.join(File.dirname(__FILE__), 'fixtures') }
      let(:actionpolicy) { ActionPolicy.new(request) }

      before do
        Config.stubs(:instance).returns(config)
      end

      describe "#action_in_actions?" do
        it 'should correctly determine if the action is in the actions' do
          expect(actionpolicy.action_in_actions?('one two three')).to be(false)
          expect(actionpolicy.action_in_actions?('rspec_action another_action')).to be(true)
          expect(actionpolicy.action_in_actions?('another_action rspec_action')).to be(true)
        end
      end

      describe '#caller_in_groups?' do
        before(:each) do
          Log.stubs(:debug)
          actionpolicy.parse_group_file(File.join(fixtures_dir, "groups"))
        end

        it 'should return false for nil groups' do
          expect(actionpolicy.caller_in_groups?(nil)).to be(false)
        end

        it 'should find the caller in the groups' do
          expect(actionpolicy.caller_in_groups?("sysadmin")).to be(true)
          expect(actionpolicy.caller_in_groups?("app_admin")).to be(false)
          expect(actionpolicy.caller_in_groups?("single_group")).to be(true)
          expect(actionpolicy.caller_in_groups?("foo")).to be(false)
        end
      end

      describe '#caller_in_callerids?' do
        it 'should correctly determine if the caller is in the ids' do
          expect(actionpolicy.caller_in_callerids?('one two three')).to be(false)
          expect(actionpolicy.caller_in_callerids?('rspec_caller another_caller')).to be(true)
          expect(actionpolicy.caller_in_callerids?('another_caller rspec_caller')).to be(true)
        end
      end

      describe '#parse_group_file' do
        before(:each) do
          Log.stubs(:debug)
          Log.stubs(:warn)
        end

        it 'should do nothing for nil groups files' do
          expect(actionpolicy.parse_group_file(nil)).to be_nil
        end

        it 'should do nothing for non existing group files' do
          File.expects(:exist?).with('/nonexisting/g_file').returns(false)
          expect(actionpolicy.parse_group_file('/nonexisting/g_file')).to be_nil
        end

        it 'should do nothing for unreadable group files' do
          File.expects(:exist?).with('/nonexisting/g_file').returns(true)
          File.expects(:readable?).with('/nonexisting/g_file').returns(false)
          expect(actionpolicy.parse_group_file('/nonexisting/g_file')).to be_nil
        end

        it 'should parse the groups correctly' do
          groups = actionpolicy.parse_group_file(File.join(fixtures_dir, 'groups'))

          # specifically verifies that only valid groups are in the list
          expect(groups).to eq(
            'sysadmin' => ['cert=sa1', 'cert=sa2', 'rspec_caller'],
            'app_admin' => ['cert=aa1', 'cert=aa2'],
            'single_group' => ['rspec_caller'],
          )
        end
      end

      describe '#authorize' do
        it 'should create a new ActionPolicy object and call #authorize_request' do
          actionpolicy.expects(:authorize_request)
          ActionPolicy.expects(:new).returns(actionpolicy)
          ActionPolicy.authorize(request)
        end
      end

      describe '#initialize' do
        it 'should set the default values' do
          expect(actionpolicy.config).to be(config)
          expect(actionpolicy.agent).to eq('rspec_agent')
          expect(actionpolicy.caller_id).to eq('rspec_caller')
          expect(actionpolicy.action).to eq('rspec_action')
          expect(actionpolicy.allow_unconfigured).to be(false)
          expect(actionpolicy.configdir).to eq('/rspecdir')
          expect(actionpolicy.groups).to eq({})
          expect(actionpolicy.enable_default).to be(false)
          expect(actionpolicy.default_name).to eq('default')
        end

        it 'should set allow_unconfigured if set in config file' do
          config.stubs(:pluginconf).returns({'actionpolicy.allow_unconfigured' => '1'})
          result = ActionPolicy.new(request)
          expect(result.allow_unconfigured).to be(true)
        end
      end

      describe '#authorize_request' do
        before do
          Log.stubs(:debug)
        end

        it 'should deny the request if policy file does not exist and allow_unconfigured is false' do
          actionpolicy.expects(:lookup_policy_file).returns(nil)

          expect{
            actionpolicy.authorize_request
          }.to raise_error RPCAborted
        end

        it 'should return true if policy file does not exist but allow_unconfigured is true' do
          actionpolicy.expects(:lookup_policy_file).returns(nil)
          actionpolicy.allow_unconfigured = true

          expect(actionpolicy.authorize_request).to be(true)
        end

        it 'should parse the policy file if it exists' do
          actionpolicy.expects(:lookup_policy_file).returns('/rspecdir/policyfile')
          actionpolicy.expects(:parse_policy_file).with('/rspecdir/policyfile')
          actionpolicy.authorize_request
        end

        it 'should enforce precedence of enable_default over allow_unconfigured' do
          actionpolicy.allow_unconfigured = true
          actionpolicy.enable_default = true
          actionpolicy.expects(:lookup_policy_file).returns('/rspec/default')
          actionpolicy.expects(:parse_policy_file).with('/rspec/default')
          actionpolicy.authorize_request

        end
      end

      describe '#parse_policy_file' do

        before do
          Log.stubs(:debug)
        end

        it 'should deny the request if allow_unconfigured is false and no lines match' do
          File.expects(:read).with('policyfile').returns('')

          expect{
            actionpolicy.parse_policy_file('policyfile')
          }.to raise_error RPCAborted
        end

        it 'should skip comment lines' do
          File.expects(:read).with('policyfile').returns('#')

          expect{
            actionpolicy.parse_policy_file('policyfile')
          }.to raise_error RPCAborted
        end

        # Fixtures

        it 'should parse the default alllow policy' do
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'default_allow'))).to be(true)
        end

        it 'should parse the default deny policy' do
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'default_deny'))
          }.to raise_error RPCAborted
        end

        # Example fixtures

        it 'should parse example1 correctly' do
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example1'))).to be(true)
        end

        it 'should parse example2 correctly' do
          request.stubs(:caller).returns('uid=500')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example2'))).to be(true)

          request.stubs(:caller).returns('uid=501')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example2'))
          }.to raise_error RPCAborted

        end

        it 'should parse example3 correctly' do
          request.stubs(:action).returns('rspec')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example3'))).to be(true)

          request.stubs(:action).returns('notrspec')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example3'))
          }.to raise_error RPCAborted

        end

        it 'should parse example4 correctly' do
          Util.stubs(:get_fact).with('foo').returns('bar')
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example4'))).to be(true)

          Util.stubs(:get_fact).with('foo').returns('notbar')
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example4'))
          }.to raise_error RPCAborted

        end

        it 'should parse example5 correctly' do
          Util.stubs(:has_cf_class?).with('rspec').returns(true)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example5'))).to be(true)

          Util.stubs(:has_cf_class?).with('rspec').returns(false)
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example5'))
          }.to raise_error RPCAborted

        end

        it 'should parse example6 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example6'))).to be(true)

          request.stubs(:caller).returns('uid=501')
          request.stubs(:action).returns('notrspec')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example6'))
          }.to raise_error RPCAborted

        end

        it 'should parse example7 correctly' do
          request.stubs(:caller).returns('uid=500')
          Util.stubs(:get_fact).with('foo').returns('bar')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example7'))).to be(true)

          request.stubs(:caller).returns('uid=501')
          Util.stubs(:get_fact).with('foo').returns('notbar')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example7'))
          }.to raise_error RPCAborted

        end

        it 'should parse example8 correctly' do
          request.stubs(:caller).returns('uid=500')
          Util.stubs(:has_cf_class?).with('rspec').returns(true)
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example8'))).to be(true)

          Util.stubs(:has_cf_class?).with('rspec').returns(false)
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example8'))
          }.to raise_error RPCAborted

        end

        it 'should parse example9 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:get_fact).with('foo').returns('bar')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example9'))).to be(true)

          request.stubs(:caller).returns('uid=501')
          request.stubs(:action).returns('notrspec')
          Util.stubs(:get_fact).with('foo').returns('notbar')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example9'))
          }.to raise_error RPCAborted

        end

        it 'should parse example10 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:has_cf_class?).with('rspec').returns(true)
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example10'))).to be(true)

          request.stubs(:caller).returns('uid=501')
          request.stubs(:action).returns('notrspec')
          Util.stubs(:has_cf_class?).with('rspec').returns(false)
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example10'))
          }.to raise_error RPCAborted



        end

        it 'should parse example11 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:has_cf_class?).with('rspec').returns(true)
          Util.stubs(:get_fact).with('foo').returns('bar')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example10'))).to be(true)

          request.stubs(:caller).returns('uid=501')
          request.stubs(:action).returns('notrspec')
          Util.stubs(:has_cf_class?).with('rspec').returns(false)
          Util.stubs(:get_fact).with('foo').returns('notbar')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example10'))
          }.to raise_error RPCAborted
        end

        it 'should parse example12 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:has_cf_class?).with('rspec').returns(true)
          Util.stubs(:get_fact).with('foo').returns('bar')
          Util.stubs(:get_fact).with('bar').returns('foo')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example12'))).to be(true)
        end

        it 'should parse example13 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:has_cf_class?).with('one').returns(true)
          Util.stubs(:has_cf_class?).with('two').returns(true)
          Util.stubs(:has_cf_class?).with('three').returns(false)
          Util.stubs(:get_fact).with('foo').returns('bar')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example13'))).to be(true)
        end

        it 'should parse example14 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:has_cf_class?).with('one').returns(true)
          Util.stubs(:has_cf_class?).with('two').returns(false)
          Util.stubs(:get_fact).with('foo').returns('bar')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example14'))).to be(true)
        end

        it 'should parse example15 correctly' do
          # first field
          request.stubs(:caller).returns('uid=500')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example15'))).to be(true)

          # second field
          request.stubs(:caller).returns('uid=600')
          Util.stubs(:get_fact).with('customer').returns('acme')
          Util.stubs(:has_cf_class?).with('acme::devserver').returns(true)
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example15'))).to be(true)

          # third field
          request.stubs(:caller).returns('uid=600')
          request.stubs(:action).returns('status')
          Util.stubs(:get_fact).with('customer').returns('acme')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example15'))).to be(true)

          # forth field
          request.stubs(:caller).returns('uid=600')
          request.stubs(:action).returns('status')
          Util.stubs(:get_fact).with('customer').returns('acme')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example15'))).to be(true)

          # fith field
          request.stubs(:caller).returns('uid=700')
          request.stubs(:action).returns('restart')
          Util.stubs(:get_fact).with('environment').returns('development')
          Matcher.stubs(:eval_compound_fstatement).with('value' => 'enabled', 'name' => 'puppet', 'operator' => '==', 'params' => nil, 'r_compare' => 'false').returns(true)
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example15'))).to be(true)
        end

        it 'should parse example16 correctly' do
          # match uid in the list
          request.stubs(:caller).returns('uid=600')
          actionpolicy = ActionPolicy.new(request)
          expect(actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example16'))).to be(true)

          # match uid not in the list
          request.stubs(:caller).returns('uid=800')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(fixtures_dir, 'example16'))
          }.to raise_error RPCAborted
        end
      end

      describe '#check_policy' do
        before(:each) do
          Log.stubs(:debug)
          actionpolicy.parse_group_file(File.join(fixtures_dir, "groups"))
        end

        it 'should return false if the policy line does not include the caller' do
          expect(actionpolicy.check_policy('caller', nil, nil, nil)).to be(false)
          expect(actionpolicy.check_policy('app_admin', nil, nil, nil)).to be(false)
        end

        it 'should return false if the policy line does not include the action' do
          expect(actionpolicy.check_policy(nil, 'action', nil, nil)).to be(false)
        end

        it 'should parse both facts and classes if callers and actions match' do
          actionpolicy.expects(:parse_facts).with('*').returns(true).twice
          actionpolicy.expects(:parse_classes).with('*').returns(true).twice
          expect(actionpolicy.check_policy('rspec_caller', 'rspec_action', '*', '*')).to be(true)
          expect(actionpolicy.check_policy('sysadmin', 'rspec_action', '*', '*')).to be(true)
        end

        it 'should parse a compound statement if callers and actions match but classes are excluded' do
          actionpolicy.expects(:parse_compound).with('*').returns(true)
          expect(actionpolicy.check_policy('rspec_caller', 'rspec_action', '*', nil)).to be(true)
        end
      end

      describe '#parse_facts' do
        it 'should return true if facts is a wildcard' do
          expect(actionpolicy.parse_facts('*')).to be(true)
        end

        it 'should parse compound fact statements' do
          actionpolicy.stubs(:is_compound?).returns(true)
          actionpolicy.expects(:parse_compound).with('foo=bar and bar=foo').returns(true)
          expect(actionpolicy.parse_facts('foo=bar and bar=foo')).to be(true)
        end

        it 'should parse all facts' do
          actionpolicy.stubs(:is_compound?).returns(false)
          actionpolicy.expects(:lookup_fact).twice.returns(true)
          expect(actionpolicy.parse_facts('foo=bar bar=foo')).to be(true)
        end
      end

      describe '#parse_classes' do
        it 'should return true if classes is a wildcard' do
          expect(actionpolicy.parse_classes('*')).to be(true)
        end

        it 'should parse compound class statements' do
          actionpolicy.stubs(:is_compound?).returns(true)
          actionpolicy.expects(:parse_compound).with('foo=bar and bar=foo').returns(true)
          expect(actionpolicy.parse_facts('foo=bar and bar=foo')).to be(true)
        end

        it 'should parse all classes' do
          actionpolicy.stubs(:is_compound?).returns(false)
          actionpolicy.expects(:lookup_fact).times(3).returns(true)
          expect(actionpolicy.parse_facts('foo bar baz')).to be(true)
        end
      end

      describe '#lookup_fact' do
        it 'should return false if a class is found in the fact field' do
          Log.expects(:warn).with('Class found where fact was expected')
          expect(actionpolicy.lookup_fact('rspec')).to be(false)
        end

        it 'should lookup a fact value and return its true value' do
          Util.expects(:get_fact).with('foo').returns('bar')
          expect(actionpolicy.lookup_fact('foo=bar')).to be(true)
        end
      end

      describe '#lookup_class' do
        it 'should return false if a fact is found in the class field' do
          Log.expects(:warn).with('Fact found where class was expected')
          expect(actionpolicy.lookup_class('foo=bar')).to be(false)
        end

        it 'should lookup a fact value and return its true value' do
          Util.expects(:has_cf_class?).with('rspec').returns(true)
          expect(actionpolicy.lookup_class('rspec')).to be(true)
        end
      end

      describe '#lookup' do
        it 'should call #lookup_fact if a fact was passed' do
          actionpolicy.expects(:lookup_fact).with('foo=bar').returns(true)
          expect(actionpolicy.lookup('foo=bar')).to be(true)
        end

        it 'should call #lookup_class if a class was passed' do
          actionpolicy.expects(:lookup_class).with('/rspec/').returns(true)
          expect(actionpolicy.lookup('/rspec/')).to be(true)
        end
      end

      describe '#lookup_policy_file' do
        before do
          Log.stubs(:debug)
        end

        it 'should return the path of the policyfile is present' do
          File.expects(:exist?).with('/rspecdir/policies/rspec_agent.policy').returns(true)
          expect(actionpolicy.lookup_policy_file).to eq('/rspecdir/policies/rspec_agent.policy')
        end

        it 'should return the default file path if one is specified' do
          config.stubs(:pluginconf).returns({'actionpolicy.enable_default' => '1'})
          File.expects(:exist?).with('/rspecdir/policies/rspec_agent.policy').returns(false)
          File.expects(:exist?).with('/rspecdir/policies/default.policy').returns(true)
          expect(actionpolicy.lookup_policy_file).to eq('/rspecdir/policies/default.policy')
        end

        it 'should return a custom default file path if one is specified' do
          config.stubs(:pluginconf).returns({'actionpolicy.enable_default' => '1',
                                             'actionpolicy.default_name' => 'rspec'})
          File.expects(:exist?).with('/rspecdir/policies/rspec_agent.policy').returns(false)
          File.expects(:exist?).with('/rspecdir/policies/rspec.policy').returns(true)
          expect(actionpolicy.lookup_policy_file).to eq('/rspecdir/policies/rspec.policy')
        end

        it 'should return false if no policy file exists' do
          File.expects(:exist?).with('/rspecdir/policies/rspec_agent.policy').returns(false)
          expect(actionpolicy.lookup_policy_file).to be(false)
        end
      end

      describe '#eval_statement' do
        it 'should return the logical string if param is not an statement or fstatement' do
          expect(actionpolicy.eval_statement({'and' => 'and'})).to eq('and')
        end

        it 'should lookup the value of a statement if param is a statement' do
          actionpolicy.expects(:lookup).with('foo=bar').returns(true)
          expect(actionpolicy.eval_statement({'statement' => 'foo=bar'})).to be(true)
        end

        it 'should lookup the value of a data function if param is a fstatement' do
          Matcher.expects(:eval_compound_fstatement).with("rspec('data').value=result").returns(true)
          expect(actionpolicy.eval_statement({'fstatement' => "rspec('data').value=result"})).to be(true)
        end

        it 'should log a failure message and return false if the fstatement cannot be parsed' do
          Matcher.expects(:eval_compound_fstatement).with("rspec('data').value=result").raises('error')
          Log.expects(:warn).with('Could not call Data function in policy file: error')
          expect(actionpolicy.eval_statement({'fstatement' => "rspec('data').value=result"})).to be(false)
        end
      end

      describe '#is_compound?' do
        it 'should return false if a compound statement was not identified' do
          expect(actionpolicy.is_compound?('not')).to be(true)
          expect(actionpolicy.is_compound?('!rspec')).to be(true)
          expect(actionpolicy.is_compound?('and')).to be(true)
          expect(actionpolicy.is_compound?('or')).to be(true)
          expect(actionpolicy.is_compound?("data('field').value=othervalue")).to be(true)
        end

        it 'should return true if a compound statement was identified' do
          expect(actionpolicy.is_compound?('f1=v1 f1=v2')).to be(false)
          expect(actionpolicy.is_compound?('class1 class2 /class*/')).to be(false)
        end
      end

      describe '#deny' do
        it 'should log the failure and raise an RPCAborted error' do
          Log.expects(:debug).with('fail')
          expect{
            actionpolicy.deny('fail')
          }.to raise_error RPCAborted
        end
      end
    end
  end
end
