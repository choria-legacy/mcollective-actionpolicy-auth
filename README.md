Action Policy Authorization Plugin
=============================

This is a plugin that provides fine grained action level authorization for agents.

Installation
=============================

  * Follow the [basic plugin install guide](http://projects.puppetlabs.com/projects/mcollective-plugins/wiki/InstalingPlugins) by placing actionpolicy.rb
    and actionpolicy.ddl in the util directory.

Note that it is not currently possible to use the 'mco plugin package' command to package this plugin.

Configuration
=============================

There are three configuration options for the actionpolicy plugin

  * allow_unconfigured - allow requests to agents that do not have policy files configured
  * enable_default - enables a default policy file
  * default_name - the name of the default policy file

General authentication configuration options can also be set in the config file.

    # Enables system wide rpc authorization
    rpcauthorization = 1
    # Sets the authorization provider to use the actionpolicy plugin
    rpcauthprovider = action_policy

Enabling a default policy

    plugin.actionpolicy.enable_default = 1
    plugin.actionpolicy.default_name = default

This allows you to create a policy file called default.policy which will be used unless a specific policy file exists. Note that if both
allow_unconfigured and enable_default are configured all requests will go through the default policy, as enable_default takes precedence
over allow_unconfigured.

Usage
=============================

Policies are defined in files like <configdir>/policies/<agent>.policy

Example: Puppet agent policy file

    policy default deny
    allow   uid=500     *                       *                *
    allow   uid=600     *                       customer=acme    acme::devserver
    allow   uid=600     enable disable status   customer=acme    *
    allow   uid=700     restart                 (puppet().enabled=false and environment=production) or environment=development

The above policy can be described as:

  * allow unix user id 500 to do all actions on all servers.
  * allow unix user id 600 to do all actions on machines with the fact customer=acme and the config class acme::devserver
  * allow unix user id 600 to do enable, disable and status on all other machines with fact customer=acme
  * allow unix user id 700 to restart services at any time in development but in production only when Puppet has been disabled
  * Everything else gets denied

The format of the userid will depend on your security plugin, other plugins might have a certificate name as caller it.

Like with actions you can space separate facts and config classes too which means all facts of classes listed has to be present on the system.

The last line in the example uses the compound statement language to do matching on facts and classes and allows any data plugin to be used.
This requires at least MCollective 2.2.x. When using data plugins in action policies you should avoid using slow ones as this will impact
the response times of agents and impact the client waiting time etc.

Using it in a specific Agent
=============================

You can now activate it in your agents:

    module MCollective::Agent
        class Service<RPC::Agent
            authorized_by :action_policy

            # ...
        end
    end


System wide configuration
=============================

You can apply this policy to all agents – but ones that specify specific policies as above will use that:

    # authorization
    rpcauthorization = 1
    rpcauthprovider = action_policy
    plugin.actionpolicy.allow_unconfigured = 1

This enables system wide authorization, tells it to use the action_policy plugin and tells it to allow agents without a policy to be used.
If you had set allow_unconfigured to 0 all requests to agents without policy files will be denied. This is configured in your server.cfg file.
