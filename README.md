# About dsgrouputil #

Using computer groups can greatly simplify management of machines in an Open Directory environment, but the standard utilities for working with them from the command line are somewhat lacking. `dsgrouputil` fills in some of the gaps.

## System Requirements ##
`dsgrouputil` requires Mac OS X 10.6.

## Usage Examples ##
    # Check to see if a computer is a member of a computer group;
    # dseditgroup(8)'s checkmember option does not work with computer groups.
    $ dsgrouputil -o checkmember -t computer -m lappy486 -g saleslaptops
    computer lappy486 is a member of saleslaptops
    
    # The Open Directory name of the computer may not match the current name
    # if the user has renamed it locally - in that case, commands such as
    # `dscl /Search -read /Computers/$(scutil --get LocalHostName)` will
    # fail. The -currentHost option uses the hardware UUID and ethernet address
    # to locate the computer account, regardless of name.
    $ scutil --get LocalHostName
    tandy400
    
    $ dsgrouputil -o checkmember -t computer -currentHost 1 -g saleslaptops
    computer lappy486 is a member of saleslaptops
    
    # Of course, if you know the hardware UUID or ethernet address of a
    # machine, you can use those directly:
    $ dsgrouputil -o checkmember -t computer \
      -mu C5CE5C0B-7B7C-42C3-B0FF-458D255BCB34 -g saleslaptops
    computer compy386 is *not* a member of saleslaptops
    
    $ dsgrouputil -o checkmember -t computer -me '00:1f:f3:53:98:09' -g saleslaptops
    computer corpynt6 is *not* a member of saleslaptops
    
    $ dsgrouputil -o checkmember -t computer -me '00:1f:f3:53:98:09' -g filevault
    computer corpynt6 is a member of computer group filevault
    
    # You can also specify the group by GUID, in case someone happens to change
    # the short name.
    $ dsgrouputil -o checkmember -t computer -m lappy486 \
      -gu 70787DB0-EAFE-42D8-B74E-6351A0A13247
    computer lappy486 is a member of saleslaptops
    
    # When scripting, use the -q option to silence output. The exit status will
    # be set to zero if the membership check succeeded, and non-zero otherwise.
    $ if dsgrouputil -q 1 -o checkmember -t computer -currentHost 1 -g saleslaptops; then
        echo "I am in sales"
      fi
    
    # Checking membership also works with users, groups, and computer groups.
    $ dsgrouputil -o checkmember -t user -m lemke -g localadmins
    user lemke is a member of group localadmins
    
    $ dsgrouputil -o checkmember -t group -m vips -g localadmins
    group vips is a member of group localadmins
    
    $ dsgrouputil -o checkmember -t computergroup -m saleslaptops -g macbooks
    computergroup saleslaptops is a member of computergroup macbooks
    
    # Users, groups, and computer groups don't have ethernet addresses, but
    # they do have GUIDs.
    $ dsgrouputil -o checkmember -t user \
      -mu B1E813DD-82BC-4029-BF95-21BF85FEE887 -g localadmins
    user lemke is a member of group localadmins
    
    # Sometimes you may want a list of all computer groups that a
    # certain machine is in. For standard users, this can be done with
    # id(1), but `id` does not work for computers, and it is difficult to
    # use dscl for recursive nested group resolution from a script.
    $ dsgrouputil -o enumerate -t computer -currentHost 1
    computer lappy486 is a member of computergroups:
    saleslaptops
    macbooks
    filevault
    
    # It can be useful to enumerate any computer groups that a particular
    # computer group is nested within.
    $ dsgrouputil -o enumerate -t computergroup -m saleslaptops
    computergroup saleslaptops is a member of computergroups:
    macbooks
    filevault
    
    # User group nesting can be enumerated as well.
    $ dsgrouputil -o enumerate -t user -m lemke
    user lemke is a member of groups:
    boardmembers
    vips
    localadmins
    
    $ dsgrouputil -o enumerate -t group -m boardmembers
    group boardmembers is a member of groups:
    vips
    localadmins
    
    # By default, all DirectoryService nodes in the search path are examined,
    # but the -n option allows you to specify just one node to work with.
    $ dsgrouputil -o checkmember -n /LDAPv3/127.0.0.1 -t user -m lemke -g vips
    user lemke is a member of group localadmins
    
    $ dsgrouputil -o checkmember -n /Local/Default -t user -m lemke -g vips       
    Can't find user record for lemke in node /Local/Default

## License ##
Copyright (c) 2010 Ben Gollmer.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.