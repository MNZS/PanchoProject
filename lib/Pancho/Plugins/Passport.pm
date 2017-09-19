##########################################################################
##
## Passport.pm
##
## Pancho plugin for Nortel Passport 8000 serie devices
##
## Author  : Jean-Francois Taltavull
## Release : 1.0 - 2003/10/27
## Last update : 2003/12/05 
##
## Mib file : rapid_city.mib, rc_vlan.mib
## Mib name : RAPID-CITY {enterprises 2272}
## Mib version/date : v542, 2002/04/01
## Mib branch : 2k copy file  - enterprises.rcMgmt.rc2k.rc2kCopyFile  (oid : 2272.1.100.7)
##
## Caveats :
##	downloading and uploading device's configuration mean transfering /config.cfg file.
##
## Plugin's features :
##	- upload, download
##	(commit, startup and reload are not supported.)
##
##
## Copyright (c) 2003 Jean-François Taltavull
##               All rights reserved
##
## Some parts of code written by Russel Vrolyk.
##
## This code is part of the Pancho project.
##       http://www.pancho.org 
##  Copyright (c) 2001-2002 Charles J. Menzes
##           All rights reserved.
##
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
package Pancho::Passport;

use strict;
use Net::SNMP;

# these are device types we can handle in this plugin
# the names should be contained in the sysdescr string
# returned by the devices
# the key is the name and the value is the vendor description
my %types = (
              'Passport-8' => "Nortel Passport 8000 serie",
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
		&passport_log($args,"Operations on startup-config not supported.");
		return 0;
	}


	SWITCH: {
			($opts->{download} || $opts->{upload}) && do {
				&passport_transfer($args);
				last SWITCH;
			};

			$opts->{commit} && do {
				&passport_log($args,"Commit operation not supported.");
				last SWITCH;
			};

			$opts->{reload} && do {
				&passport_log($args,"Reload operation not supported.");
				last SWITCH;
			};

			&passport_log($args,"Unknown operation.");
	}
}


sub passport_transfer {
	my $args = shift;

	my %oid = (
		## rc2kCopyFileSource
		filesource => ".1.3.6.1.4.1.2272.1.100.7.1.0",

		## rc2kCopyFileDestination
		filedest  => ".1.3.6.1.4.1.2272.1.100.7.2.0",

		## rc2kCopyFileAction
		action	  => ".1.3.6.1.4.1.2272.1.100.7.3.0",

		## rc2kCopyFileResult
		result    => ".1.3.6.1.4.1.2272.1.100.7.4.0"
	);

	my %action = (
		none  => 1,
		start => 2
	);
			
	my %state = (
		none	           => 1,  
		inProgress	   => 2,  
		success            => 3,  
		fail		   => 4,  
		invalidSource      => 5,
		invalidDestination => 6,
		outOfMemory        => 7,
		outOfSpace         => 8,
		fileNotFound       => 9
	);


	## determine the mib value for action object
	my $filesrc; my $filedst; 
	if ($args->{src} eq "tftp") {
		$filesrc = "$args->{utftp}:$args->{file}";
		$filedst = "config.cfg";
	}
	else {
		$filesrc = "config.cfg";
		$filedst = "$args->{utftp}:$args->{file}";
	}

	## set up snmp session parameters
	my $s = $args->{snmp}->create_snmp($args);

	$s->set_request ( 
		## set the source filename
		$oid{filesource}, OCTET_STRING, $filesrc,
		## set the destination filename
		$oid{filedest}, OCTET_STRING, $filedst,
		## set action code
		$oid{action}, INTEGER, $action{'start'}
	);

	## grab an error message if it exists
	my $error = $s->error;
	## put error value into hash
	$args->{err} = $error;

	if (!$error) {
		## OK, no error
		## get the current status of the tftp action
		sleep $snmpslowdown;
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
		if ($result != "$state{'success'}") {
			## transfer failure
			&passport_log($args, "problem with transfer operation. Result = "
				      . $result);
		}
	        else {
			## success, log output to screen and possibly external file
			$args->{log}->log_action($args);
		}
	}

	else {
		## Error : can't trigger transfer operation...
		&passport_log($args, "can't trigger transfer operation.");
	}

	## close the snmp session
	$s->close;
}


#-------------------------------------------------------------------------------
# passport_log
# Add a leading "Plugin Passport" to the message and logs it
#-------------------------------------------------------------------------------

sub passport_log {
        my $args = shift;
        my $msg = shift;

        $args->{err} = "Plugin Passport - $msg";
        $args->{log}->log_action($args);
}


# this must be here or else it won't return true
1;
