##########################################################################
##
## Baystack.pm
##
## Plancho plugin for Nortel Baystack and BPS 2000 devices
##
## Author  : Jean-Francois Taltavull
## Release : 1.0 - 2003/08/23
## Last update : 2003/12/05
##
## Mib files : s5age139.mib, s5roo115.mib, synro172.mib
## Mib name : S5-AGENT-MIB (5000 Agent MIB, Bay Networks)  {enterprises 45} (Synoptics)
## Mib version/date : 1.3.9 , 1998/10/14
## Mib branches : synoptics.products.series5000.s5Agent.s5AgentInfo.s5AgentGbl 
##                synoptics.products.series5000.s5Agent.s5AgentInfo.s5AgMyIfTable
##		  oids : 45.1.6.4.2.1
##		         45.1.6.4.2.2
##
## Caveats :
##	- these devices send their configuration as a raw memory image.
##
## Plugin's features :
##	- upload, download
##	(commit, startup and reload are not supported.)
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
package Pancho::Baystack;

use strict;
use Net::SNMP;

# these are device types we can handle in this plugin
# the names should be contained in the sysdescr string
# returned by the devices
# the key is the name and the value is the vendor description
my %types = (
              BayStack => "Nortel/Baystack family",
	     'Business Policy Switch 2000' => "Nortel/Baystack family"
            );

my $snmpslowdown = 3;           # to slowdown snmp requests loops (seconds)


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
	}
	else {
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


	if (($args->{src} eq "start") or ($args->{dst} eq "start")) {
		# startup config not supported
		&baystack_log($args,"Operations on startup-config not supported.");
		return 0;
	}


	SWITCH: {
			($opts->{download} || $opts->{upload}) && do {
				&baystack_transfer($args);
				last SWITCH;
			};

			$opts->{commit} && do {
				&baystack_log($args,"Commit operation not supported.");
				last SWITCH;
			};

			$opts->{reload} && do {
				&baystack_log($args,"Reload operation not supported.");
				last SWITCH;
			};

			&baystack_log($args,"Unknown operation.");
	}
}


sub baystack_transfer {
	my $args = shift;

	my %oid = (
		## s5AgMyIfLdSvrAddr
		tftphost=> ".1.3.6.1.4.1.45.1.6.4.2.2.1.5.1",

		## s5AgMyIfCfgFname
		file	=> ".1.3.6.1.4.1.45.1.6.4.2.2.1.4.1",

		## s5AgInfoFileAction
		action => ".1.3.6.1.4.1.45.1.6.4.2.1.24.0",

		## s5AgInfoFileStatus
		result => ".1.3.6.1.4.1.45.1.6.4.2.1.25.0"
	);

	my %action = (
		none			=> 1,
		downloadconfig		=> 2,
		downloadsw		=> 3,
		uploadconfig		=> 4,
		uploadsw		=> 5
	);
			
	my %state = (
		none			=> 1,  
		inProgress		=> 2,  
		success			=> 3,  
		fail			=> 4  
	);


	## determine the mib value for action object
	my $act;
	if ($args->{src} eq "tftp") {
		$act = $action{downloadconfig};
	}
	else {
		$act = $action{uploadconfig};
	}

	## set up snmp session parameters
	my $s = $args->{snmp}->create_snmp($args);

	$s->set_request ( 
		## set the tftp server address
		## $oid{tftphost}, OCTET_STRING, $args->{tftp},
		$oid{tftphost}, IPADDRESS, $args->{tftp},
		## set the filename being written/read
		$oid{file}, OCTET_STRING, "$args->{path}/$args->{file}",
		## set file transfer direction
		$oid{action}, INTEGER, $act,
	);

	## grab an error message if it exists
	my $error = $s->error;
	## put error value into hash
	$args->{err} = $error;

	if (!$error) {
		## OK, no error
		## get the current status of the tftp action
		my $current_state = $s->get_request("$oid{result}");
		my $result = $current_state->{"$oid{result}"};

		## loop and check for completion
		while ($result && $result == "$state{'inProgress'}") {
			## get the current status of the tftp action
			sleep $snmpslowdown;
			$current_state = $s->get_request("$oid{result}");
			$result = $current_state->{"$oid{result}"};
		}

		## check the final state
		if ($result && $result != "$state{'success'}") {
			## transfer failure
			&baystack_log($args, "problem with transfer operation. Result = "
				      . $result);
		}
	        else {
			## success, log output to screen and possibly external file
			$args->{log}->log_action($args);
		}
	}

	else {
		## Error : can't trigger transfer operation...
		&baystack_log($args, "can't trigger transfer operation.");
	}

	## close the snmp session
	$s->close;
}


#-------------------------------------------------------------------------------
# baystack_log
# Add a leading "Plugin Baystack" to the message and logs it
#-------------------------------------------------------------------------------

sub baystack_log {
        my $args = shift;
        my $msg = shift;

        $args->{err} = "Plugin Baystack - $msg";
        $args->{log}->log_action($args);
}


# this must be here or else it won't return true
1;
