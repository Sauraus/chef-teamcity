#
# Cookbook Name:: teamcity
# Recipe:: mac_os_x
#
# Copyright (C) 2016 Antek S. Baranski
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Do not run this recipe if the node is not a MAC OSX node
return unless platform_family?('mac_os_x')

# Used to escape shell parameters.
require 'shellwords'
# Generate random password string
require 'securerandom'
password = SecureRandom.base64(16)

include_recipe 'homebrew'
homebrew_tap 'xfreebird/utils'
package 'kcpassword'

include_recipe 'java'

home_dir = ::File.join(node['teamcity']['agent']['home'], node['teamcity']['agent']['user'])
root_dir = ::File.join(node['teamcity']['agent']['install_dir'], 'teamcity-agent')

# NOTE: We assume the user got created if the
# #{home_dir}/Library/Preferences/com.apple.SetupAssistant.plist file exists.
bash 'Create Mac OS X teamcity agent user' do
  code <<-EOH
    #!/bin/sh
    . /etc/rc.common
    /usr/bin/dscl . -create #{home_dir}
    /usr/bin/dscl . -create #{home_dir} UserShell /bin/bash
    /usr/bin/dscl . -create #{home_dir} RealName "TeamCity BuildAgent"
    /usr/bin/dscl . -create #{home_dir} UniqueID "#{node['teamcity']['agent']['uid']}"
    /usr/bin/dscl . -create #{home_dir} PrimaryGroupID 20
    /usr/bin/dscl . -create #{home_dir} NFSHomeDirectory #{home_dir}
    /usr/bin/dscl . -passwd #{home_dir} #{Shellwords.escape(password)}
    /usr/sbin/createhomedir -c -u #{node['teamcity']['agent']['user']}
    /usr/local/bin/kcpassword #{Shellwords.escape(password)}
    /usr/bin/defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser '#{node['teamcity']['agent']['user']}'
    sw_vers=$(sw_vers -productVersion)
    sw_build=$(sw_vers -buildVersion)
    mkdir -p #{home_dir}/Library/Preferences
    /usr/bin/defaults write #{home_dir}/Library/Preferences/com.apple.SetupAssistant DidSeeCloudSetup -bool TRUE
    /usr/bin/defaults write #{home_dir}/Library/Preferences/com.apple.SetupAssistant GestureMovieSeen none
    /usr/bin/defaults write #{home_dir}/Library/Preferences/com.apple.SetupAssistant LastSeenCloudProductVersion "${sw_vers}"
    /usr/bin/defaults write #{home_dir}/Library/Preferences/com.apple.SetupAssistant LastSeenBuddyBuildVersion "${sw_build}"
    /usr/sbin/chown -R #{node['teamcity']['agent']['user']}:#{node['teamcity']['agent']['group']} #{home_dir}
  EOH
  sensitive true
  not_if { ::File.exist?("#{home_dir}/Library/Preferences/com.apple.SetupAssistant.plist") }
  notifies :request_reboot, 'reboot[Reboot System]', :immediately
end

directory ::File.join(home_dir, 'Library') do
  owner node['teamcity']['agent']['user']
  group node['teamcity']['agent']['group']
  mode '00700'
  action :create
end

directory ::File.join(home_dir, 'Library', 'LaunchAgents') do
  owner node['teamcity']['agent']['user']
  group node['teamcity']['agent']['group']
  mode '00755'
  action :create
end

template ::File.join(home_dir, 'Library', 'LaunchAgents', 'jetbrains.teamcity.BuildAgent.plist') do
  source 'jetbrains.teamcity.BuildAgent.plist.erb'
  variables work_dir: node['teamcity']['agent']['work_dir'],
            path: root_dir
  owner node['teamcity']['agent']['user']
  group node['teamcity']['agent']['group']
  mode '00755'
end

reboot 'Reboot System' do
  action :nothing
  delay_mins 1
end
