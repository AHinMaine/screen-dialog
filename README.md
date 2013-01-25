# screen-dialog #

Dialog for launching GNU screen sessions

The default action for each menuitem is to treat it as host and open a corresponding ssh session.

## USAGE ##

Append to your .screenrc configuration file:

    screen -t menu 0 ${HOME}/bin/s-dialog.pl

(Alter the path to where you placed the script accordingly.)

## CONFIG ##

Configuration items will be loaded from $HOME/.s.conf in simple yaml format:

```yaml
---
screen: /usr/bin/screen
ssh: /usr/bin/ssh
sshproxyhost: jump-server.example.com
hostsfile: /home/username/.hosts
```


### MENUITEMS ###

#### HOSTS ####

The script is fairly flexible in what format it will parse.

   plain hostsname:
       server01.example.com

   hostname with username:
       user@server01.example.com

   hostname with username and a tag comment:
       user@server01.example.com # mail server

   hostname and port with username and a tag comment:
       user@servertest01.example.com:2222 # lab server

See the included example .hosts file.

#### NON-HOSTS ####

Not everything in the hosts file necessarily has to be a plain host.  Other actions are available, but currently this is hard-coded into the script.  Near the top, there is a dispatch table "$do" where handling for other items can be placed.

For example, the 'corelist' key refers to the screenopenlist function, passing the filename ${HOME}/.hosts.coreservers as a parameter.  This means that if you add an entry to your hosts file called 'corelist', choosing that menu item will cause the s-dialog script read the file $HOME/.hosts.coreservers file and beginning acting on every line in the file.  This can be used to keep a default set of screen windows that you wish to open automatically after choosing the 'corelist' menuitem.


## KEY BINDINGS ##

Searching is accomplished by simply starting to type on the keyboard.  The list of entries will begin reflecting the pared down list of hosts immediately in an incremental search fashion.

Acceptable keys for searching: 

* a-z
* 0-9
* -
* .
* Backspace also behaves as expected.


Other keys:

* F9 or CTRL-x    - Menu
* Spacebar        - Instead of creating a new window for the selected menu item, try switching to an existing instance.
* /               - Show an actual search filter dialog box



