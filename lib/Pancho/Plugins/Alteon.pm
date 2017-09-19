##########################################################################
##
## Alteon.pm
##
## Plancho plugin for Nortel ALTEON Web Switches devices (WebOS 8, 9, 10)
#
## Author  : Jean-Francois Taltavull
## Release : 1.0 - july 2002
## Last update : 2003/12/05
##
## Mib file : altswitch.mib
## Mib name : ALTEON-PRIVATE-MIBS {enterprises 1872}
## Mib version/date : es83c_esmallis/3, 2001/07/28
## Mib branch : enterprises.private-mibs.switch.agent.agGeneral
##		oid : 1872.2.1.2.1
##
## Plugin's features :
##	- upload, download, commit, reload
##	(startup are not supported.)
##
##
## Copyright (c) 2003 Jean-François Taltavull - All rights reserved
##
## Some parts of code written by Russel Vrolyk.
##
## This code is part of the Pancho project.
##       http://www.pancho.org 
##  Copyright (c) 2001-2002 Charles J. Menzes - All rights reserved.
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
##
##########################################################################
package Pancho::Alteon;

use strict;
use Net::SNMP;

# these are device types we can handle in this plugin
# the names should be contained in the sysdescr string
# returned by the devices
# the key is the name and the value is the vendor description
my %types = (
              alteon      => "Alteon",
              acedirector => "Alteon",
	      aceswitch	  => 'ACEswitch 180',
            );

#------------------------------------------------------------------------------- 
# device_types
# IN : N/A
# OUT: returns an array ref of devices this plugin can handle
#------------------------------------------------------------------------------- 
sub device_types {
   my $self = shift;
   my @devices = keys %types;
   return \@devices;
}

#------------------------------------------------------------------------------- 
# device_description
# IN : scalar containing sysdescr
# OUT: returns scalar containing description or 'Unknown' if it doesn't exist
#------------------------------------------------------------------------------- 
sub device_description {
   my $self = shift;
   my $name = shift || return 0;
   my $sn = '';
   if ($sn = (grep { $name =~ m/$_/gi } keys %types)[0]) {
     return $types{$sn};
   } else {
      return "Unknown";
   }
}

#------------------------------------------------------------------------------- 
# process_device - figures out what device type we have and tries to
# operate on it based on args given
# IN : args - hash ref containing various program args
#      opts - hash ref of options passed into program
#------------------------------------------------------------------------------- 
sub process_device {
   my $self = shift;
   my $args = shift;
   my $opts = shift;

  &alteon_transfer($args) if ($opts->{upload} || $opts->{download});

  &alteon_commit($args) if ($opts->{commit});

  &alteon_reload($args) if ($opts->{reload});
}

sub alteon_transfer {
  my $args = shift;

  my %oid = (
		## agTftpAction 
		action 		=> ".1.3.6.1.4.1.1872.2.1.2.1.21.0",
		
		## agTftpCfgFileName  
		filename 	=> ".1.3.6.1.4.1.1872.2.1.2.1.19.0",

		## agTftpServer
		tftpserver	=> ".1.3.6.1.4.1.1872.2.1.2.1.18.0",

		## agLastSetErrorReason
		tftpresult	=> ".1.3.6.1.4.1.1872.2.1.2.1.17.0",

		## agApplyConfiguration
		applyconfig	=> ".1.3.6.1.4.1.1872.2.1.2.1.2.0",

		## agTftpLastActionStatus
		status		=> ".1.3.6.1.4.1.1872.2.1.2.1.22.0",
            );

  if (($args->{src} eq "start") or ($args->{dst} eq "start")) {
    print "\nCopying configurations to and from startup-config\nis not possible on this platform.\n\n";

  } else {

    ## determine the mib value for where the file will be sent
    my $direction;
    if ($args->{src} eq "tftp") { $direction = "3"; } else { $direction = "4"; }

    ## set up snmp session parameters
    my $s = $args->{snmp}->create_snmp($args);

    $s->set_request ( 
                      ## set the filename being written/read
                      $oid{filename}, OCTET_STRING, "$args->{path}/$args->{file}",
  
                      ##set the tftp server address
                      $oid{tftpserver}, OCTET_STRING, $args->{tftp},

		                ## set file transfer direction
                      $oid{action}, INTEGER, $direction,

                    );

    ## add error message into $args hash
    $args->{err} = $s->error;

    ## add apply to new config if no error
    $s->set_request ( $oid{applyconfig}, INTEGER, 2 )
      unless ($args->{err}); 

    ## close the snmp session
    $s->close;

    ## log output to screen and possibly external file
    $args->{log}->log_action($args);

  }

## end of alteon_transfer
}

sub alteon_commit {
  my $args = shift;

  ## set args for logging purposes
  $args->{src} = "commit";

  my %oid = (
		## agSaveConfiguration  
		commit	=> ".1.3.6.1.4.1.1872.2.1.2.1.1.0",
            );

  ## write config to memory
  my $s = $args->{snmp}->create_snmp($args);

  ## write to memory
  $s->set_request($oid{commit}, INTEGER, 2);

  ## add error message into $args hash
  $args->{err} = $s->error;

  ## close session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

}

sub alteon_reload {
  my $args = shift;

  ## set args for logging purposes
  $args->{src} = "reload";

  my %oid = (
		## agReset  
		reload	=> ".1.3.6.1.4.1.1872.2.1.2.1.4.0",
            );

  ## start the session
  my $s = $args->{snmp}->create_snmp($args);

  ## reload the router
  $s->set_request($oid{reload}, INTEGER, 3);

  ## put error value into hash
  $args->{err} = $s->error;

  ## close the session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

}

# this must be here or else it won't return true
1;
