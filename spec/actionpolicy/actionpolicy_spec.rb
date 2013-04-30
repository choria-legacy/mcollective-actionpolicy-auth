#!/bin/env rspec

require 'spec_helper'
require File.join(File.dirname(__FILE__), '../../', 'util', 'actionpolicy.rb')

module MCollective
  module Util
    describe ActionPolicy do
      let(:request) do
        request = mock
        request.stubs(:agent).returns('rspec_agent')
        request.stubs(:caller).returns('rspec_caller')
        request.stubs(:action).returns('rspec_action')
        request
      end

      let(:config) do
        config = mock
        config.stubs(:configdir).returns('/rspecdir')
        config.stubs(:pluginconf).returns({})
        config
      end

      let(:actionpolicy) { ActionPolicy.new(request) }

      before do
        Config.stubs(:instance).returns(config)
        @fixtures_dir = File.join(File.dirname(__FILE__), 'fixtures')
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
          actionpolicy.config.should == config
          actionpolicy.agent.should == 'rspec_agent'
          actionpolicy.caller.should == 'rspec_caller'
          actionpolicy.action.should == 'rspec_action'
          actionpolicy.allow_unconfigured.should == false
          actionpolicy.configdir.should == '/rspecdir'
        end

        it 'should set allow_unconfigured if set in config file' do
          config.stubs(:pluginconf).returns({'actionpolicy.allow_unconfigured' => '1'})
          result = ActionPolicy.new(request)
          result.allow_unconfigured.should == true
        end
      end

      describe '#authorize_request' do
        before do
          Log.stubs(:debug)
        end

        it 'should deny the request if policy file does not exist and allow_unconfigured is false' do
          ActionPolicy.any_instance.expects(:lookup_policy_file).returns(nil)

          expect{
            actionpolicy.authorize_request
          }.to raise_error RPCAborted
        end

        it 'should return true if policy file does not exist but allow_unconfigured is true' do
          ActionPolicy.any_instance.expects(:lookup_policy_file).returns(nil)
          config.stubs(:pluginconf).returns({'actionpolicy.allow_unconfigured' => 'y'})

          actionpolicy.authorize_request.should be_true
        end

        it 'should parse the policy file if it exists' do
          ActionPolicy.any_instance.expects(:lookup_policy_file).returns('/rspecdir/policyfile')
          ActionPolicy.any_instance.expects(:parse_policy_file).with('/rspecdir/policyfile')
          actionpolicy.authorize_request
        end

        it 'should enforce precedence of enable_default over allow_unconfigured' do
          config.stubs(:pluginconf).returns({'actionpolicy.allow_unconfigured' => 'y',
                                             'actionpolicy.enable_default' => 'y'})
          ActionPolicy.any_instance.expects(:lookup_policy_file).returns('/rspec/default')
          ActionPolicy.any_instance.expects(:parse_policy_file).with('/rspec/default')
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
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'default_allow')).should be_true
        end

        it 'should parse the default deny policy' do
          expect{
            actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'default_deny'))
          }.to raise_error RPCAborted
        end

        # Example fixtures

        it 'should parse example1 correctly' do
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example1')).should be_true
        end

        it 'should parse example2 correctly' do
          request.stubs(:caller).returns('uid=500')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example2')).should be_true

          request.stubs(:caller).returns('uid=501')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example2'))
          }.to raise_error RPCAborted

        end

        it 'should parse example3 correctly' do
          request.stubs(:action).returns('rspec')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example3')).should be_true

          request.stubs(:action).returns('notrspec')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example3'))
          }.to raise_error RPCAborted

        end

        it 'should parse example4 correctly' do
          Util.stubs(:get_fact).with('foo').returns('bar')
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example4')).should be_true

          Util.stubs(:get_fact).with('foo').returns('notbar')
          expect{
            actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example4'))
          }.to raise_error RPCAborted

        end

        it 'should parse example5 correctly' do
          Util.stubs(:has_cf_class?).with('rspec').returns(true)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example5')).should be_true

          Util.stubs(:has_cf_class?).with('rspec').returns(false)
          expect{
            actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example5'))
          }.to raise_error RPCAborted

        end

        it 'should parse example6 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example6')).should be_true

          request.stubs(:caller).returns('uid=501')
          request.stubs(:action).returns('notrspec')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example6'))
          }.to raise_error RPCAborted

        end

        it 'should parse example7 correctly' do
          request.stubs(:caller).returns('uid=500')
          Util.stubs(:get_fact).with('foo').returns('bar')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example7')).should be_true

          request.stubs(:caller).returns('uid=501')
          Util.stubs(:get_fact).with('foo').returns('notbar')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example7'))
          }.to raise_error RPCAborted

        end

        it 'should parse example8 correctly' do
          request.stubs(:caller).returns('uid=500')
          Util.stubs(:has_cf_class?).with('rspec').returns(true)
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example8')).should be_true

          Util.stubs(:has_cf_class?).with('rspec').returns(false)
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example8'))
          }.to raise_error RPCAborted

        end

        it 'should parse example9 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:get_fact).with('foo').returns('bar')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example9')).should be_true

          request.stubs(:caller).returns('uid=501')
          request.stubs(:action).returns('notrspec')
          Util.stubs(:get_fact).with('foo').returns('notbar')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example9'))
          }.to raise_error RPCAborted

        end

        it 'should parse example10 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:has_cf_class?).with('rspec').returns(true)
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example10')).should be_true

          request.stubs(:caller).returns('uid=501')
          request.stubs(:action).returns('notrspec')
          Util.stubs(:has_cf_class?).with('rspec').returns(false)
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example10'))
          }.to raise_error RPCAborted



        end

        it 'should parse example11 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:has_cf_class?).with('rspec').returns(true)
          Util.stubs(:get_fact).with('foo').returns('bar')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example10')).should be_true

          request.stubs(:caller).returns('uid=501')
          request.stubs(:action).returns('notrspec')
          Util.stubs(:has_cf_class?).with('rspec').returns(false)
          Util.stubs(:get_fact).with('foo').returns('notbar')
          actionpolicy = ActionPolicy.new(request)
          expect{
            actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example10'))
          }.to raise_error RPCAborted
        end

        it 'should parse example12 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:has_cf_class?).with('rspec').returns(true)
          Util.stubs(:get_fact).with('foo').returns('bar')
          Util.stubs(:get_fact).with('bar').returns('foo')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example12')).should be_true
        end

        it 'should parse example13 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:has_cf_class?).with('one').returns(true)
          Util.stubs(:has_cf_class?).with('two').returns(true)
          Util.stubs(:has_cf_class?).with('three').returns(false)
          Util.stubs(:get_fact).with('foo').returns('bar')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example13')).should be_true
        end

        it 'should parse example14 correctly' do
          request.stubs(:caller).returns('uid=500')
          request.stubs(:action).returns('rspec')
          Util.stubs(:has_cf_class?).with('one').returns(true)
          Util.stubs(:has_cf_class?).with('two').returns(false)
          Util.stubs(:get_fact).with('foo').returns('bar')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example14')).should be_true
        end

        it 'should parse example15 correctly' do
          # first field
          request.stubs(:caller).returns('uid=500')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example15')).should be_true

          # second field
          request.stubs(:caller).returns('uid=600')
          Util.stubs(:get_fact).with('customer').returns('acme')
          Util.stubs(:has_cf_class?).with('acme::devserver').returns(true)
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example15')).should be_true

          # third field
          request.stubs(:caller).returns('uid=600')
          request.stubs(:action).returns('status')
          Util.stubs(:get_fact).with('customer').returns('acme')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example15')).should be_true

          # forth field
          request.stubs(:caller).returns('uid=600')
          request.stubs(:action).returns('status')
          Util.stubs(:get_fact).with('customer').returns('acme')
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example15')).should be_true

          # fith field
          request.stubs(:caller).returns('uid=700')
          request.stubs(:action).returns('restart')
          Util.stubs(:get_fact).with('environment').returns('development')
          Matcher.stubs(:eval_compound_fstatement).with('value' => 'enabled', 'name' => 'puppet', 'operator' => '==', 'params' => nil, 'r_compare' => 'false').returns(true)
          actionpolicy = ActionPolicy.new(request)
          actionpolicy.parse_policy_file(File.join(@fixtures_dir, 'example15')).should be_true


        end
      end

      describe '#check_policy' do
        it 'should return false if the policy line does not include the caller' do
          actionpolicy.check_policy('caller', nil, nil, nil).should be_false
        end

        it 'should return false if the policy line does not include the action' do
          actionpolicy.check_policy(nil, 'action', nil, nil).should be_false
        end

        it 'should parse both facts and classes if callers and actions match' do
          actionpolicy.expects(:parse_facts).with('*').returns(true)
          actionpolicy.expects(:parse_classes).with('*').returns(true)
          actionpolicy.check_policy('rspec_caller', 'rspec_action', '*', '*').should be_true
        end

        it 'should parse a compound statement if callers and actions match but classes are excluded' do
          actionpolicy.expects(:parse_compound).with('*').returns(true)
          actionpolicy.check_policy('rspec_caller', 'rspec_action', '*', nil).should be_true
        end
      end

      describe '#parse_facts' do
        it 'should return true if facts is a wildcard' do
          actionpolicy.parse_facts('*').should be_true
        end

        it 'should parse compound fact statements' do
          actionpolicy.stubs(:is_compound?).returns(true)
          actionpolicy.expects(:parse_compound).with('foo=bar and bar=foo').returns(true)
          actionpolicy.parse_facts('foo=bar and bar=foo').should be_true
        end

        it 'should parse all facts' do
          actionpolicy.stubs(:is_compound?).returns(false)
          actionpolicy.expects(:lookup_fact).twice.returns(true)
          actionpolicy.parse_facts('foo=bar bar=foo').should be_true
        end
      end

      describe '#parse_classes' do
        it 'should return true if classes is a wildcard' do
          actionpolicy.parse_classes('*').should be_true
        end

        it 'should parse compound class statements' do
          actionpolicy.stubs(:is_compound?).returns(true)
          actionpolicy.expects(:parse_compound).with('foo=bar and bar=foo').returns(true)
          actionpolicy.parse_facts('foo=bar and bar=foo').should be_true
        end

        it 'should parse all classes' do
          actionpolicy.stubs(:is_compound?).returns(false)
          actionpolicy.expects(:lookup_fact).times(3).returns(true)
          actionpolicy.parse_facts('foo bar baz').should be_true
        end
      end

      describe '#lookup_fact' do
        it 'should return false if a class is found in the fact field' do
          Log.expects(:warn).with('Class found where fact was expected')
          actionpolicy.lookup_fact('rspec').should be_false
        end

        it 'should lookup a fact value and return its true value' do
          Util.expects(:get_fact).with('foo').returns('bar')
          actionpolicy.lookup_fact('foo=bar').should be_true
        end
      end

      describe '#lookup_class' do
        it 'should return false if a fact is found in the class field' do
          Log.expects(:warn).with('Fact found where class was expected')
          actionpolicy.lookup_class('foo=bar').should be_false
        end

        it 'should lookup a fact value and return its true value' do
          Util.expects(:has_cf_class?).with('rspec').returns(true)
          actionpolicy.lookup_class('rspec').should be_true
        end
      end

      describe '#lookup' do
        it 'should call #lookup_fact if a fact was passed' do
          actionpolicy.expects(:lookup_fact).with('foo=bar').returns(true)
          actionpolicy.lookup('foo=bar').should be_true
        end

        it 'should call #lookup_class if a class was passed' do
          actionpolicy.expects(:lookup_class).with('/rspec/').returns(true)
          actionpolicy.lookup('/rspec/').should be_true
        end
      end

      describe '#lookup_policy_file' do
        before do
          Log.stubs(:debug)
        end

        it 'should return the path of the policyfile is present' do
          File.expects(:exist?).with('/rspecdir/policies/rspec_agent.policy').returns(true)
          actionpolicy.lookup_policy_file.should == '/rspecdir/policies/rspec_agent.policy'
        end

        it 'should return the default file path if one is specified' do
          config.stubs(:pluginconf).returns({'actionpolicy.enable_default' => '1'})
          File.expects(:exist?).with('/rspecdir/policies/rspec_agent.policy').returns(false)
          File.expects(:exist?).with('/rspecdir/policies/default.policy').returns(true)
          actionpolicy.lookup_policy_file.should == '/rspecdir/policies/default.policy'
        end

        it 'should return a custom default file path if one is specified' do
          config.stubs(:pluginconf).returns({'actionpolicy.enable_default' => '1',
                                             'actionpolicy.default_name' => 'rspec'})
          File.expects(:exist?).with('/rspecdir/policies/rspec_agent.policy').returns(false)
          File.expects(:exist?).with('/rspecdir/policies/rspec.policy').returns(true)
          actionpolicy.lookup_policy_file.should == '/rspecdir/policies/rspec.policy'
        end

        it 'should return nil if no policy file exists' do
          File.expects(:exist?).with('/rspecdir/policies/rspec_agent.policy').returns(false)
          actionpolicy.lookup_policy_file.should == nil
        end
      end

      describe '#eval_statement' do
        it 'should return the logical string if param is not an statement or fstatement' do
          actionpolicy.eval_statement({'and' => 'and'}).should == 'and'
        end

        it 'should lookup the value of a statement if param is a statement' do
          actionpolicy.expects(:lookup).with('foo=bar').returns(true)
          actionpolicy.eval_statement({'statement' => 'foo=bar'}).should be_true
        end

        it 'should lookup the value of a data function if param is a fstatement' do
          Matcher.expects(:eval_compound_fstatement).with("rspec('data').value=result").returns(true)
          actionpolicy.eval_statement({'fstatement' => "rspec('data').value=result"}).should be_true
        end

        it 'should log a failure message and return false if the fstatement cannot be parsed' do
          Matcher.expects(:eval_compound_fstatement).with("rspec('data').value=result").raises('error')
          Log.expects(:warn).with('Could not call Data function in policy file: error')
          actionpolicy.eval_statement({'fstatement' => "rspec('data').value=result"}).should be_false
        end
      end

      describe '#is_compound?' do
        it 'should return false if a compound statement was not identified' do
          actionpolicy.is_compound?('not').should be_true
          actionpolicy.is_compound?('!rspec').should be_true
          actionpolicy.is_compound?('and').should be_true
          actionpolicy.is_compound?('or').should be_true
          actionpolicy.is_compound?("data('field').value=othervalue").should be_true
        end

        it 'should return true if a compound statement was identified' do
          actionpolicy.is_compound?('f1=v1 f1=v2').should be_false
          actionpolicy.is_compound?('class1 class2 /class*/').should be_false
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
