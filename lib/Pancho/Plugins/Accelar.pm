##########################################################################
##
## Accelar.pm
##
## Pancho plugin for Nortel Passport/Accelar family devices
##
## Author  : Jean-Francois Taltavull
## Release : 1.0 - 2003/10/27
## Last update : 2003/12/05
##
## Mib files : rapid_city.mib, rc_vlan.mib
## Mib name : RAPID-CITY {enterprises 2272}
## Mib version/date : v542, 2002/04/01
## Mib branch : TFTP Upload/Download  - enterprises.rcMgmt.rcTftp (oid : 2272.1.2)
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
package Pancho::Accelar;

use strict;
use Net::SNMP;

# these are device types we can handle in this plugin
# the names should be contained in the sysdescr string
# returned by the devices
# the key is the name and the value is the vendor description
my %types = (
              Accelar => "Nortel Passport/Accelar family",
              'Passport-1' => "Nortel Passport/Accelar family",
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
		&accelar_log($args,"Operations on startup-config not supported.");
		return 0;
	}


	SWITCH: {
			($opts->{download} || $opts->{upload}) && do {
				&accelar_transfer($args);
				last SWITCH;
			};

			$opts->{commit} && do {
				&accelar_log($args,"Commit operation not supported.");
				last SWITCH;
			};

			$opts->{reload} && do {
				&accelar_log($args,"Reload operation not supported.");
				last SWITCH;
			};

			&accelar_log($args,"Unknown operation.");
	}
}


sub accelar_transfer {
	my $args = shift;

	my %oid = (
		## rcTftpHost
		tftphost=> ".1.3.6.1.4.1.2272.1.2.1.0",

		## rcTftpFile  
		file	=> ".1.3.6.1.4.1.2272.1.2.2.0",

		## rcTftpAction 
		action 	=> ".1.3.6.1.4.1.2272.1.2.3.0",

		## rcTftpResult
		result	=> ".1.3.6.1.4.1.2272.1.2.4.0",

		## rcSysConfigFileName
		cf => ".1.3.6.1.4.1.2272.1.1.34.0"
	);

	my %action = (
		none			=> 1,
		downloadconfig		=> 2,
		uploadconfig		=> 3,
		downloadswtoflash	=> 4,
		downloadswtopcmcia	=> 5,
		uploadsw		=> 6,
		downloadswtodram	=> 7
	);
			
	my %state = (
		none			=> 1,  
		inProgress		=> 2,  
		noResponse		=> 3,  
		fileAccessError		=> 4,  
		badFlash		=> 5,  
		flashEraseFailed	=> 6,  
		pcmciaEraseFailed	=> 7,  
		success			=> 8,  
		fail			=> 9,  
		writeToNvramFailed	=> 10,  
		flashWriteFailed	=> 11,  
		pcmciaWriteFailed	=> 12,  
		configFileTooBig	=> 13,  
		imageFileTooBig		=> 14,  
		noPcmciaDetect		=> 15,  
		pcmciaNotSupported	=> 16,  
		invalidFile		=> 17,  
		noMemory		=> 18,  
		xferError		=> 19,  
		crcError		=> 20,  
		readNvramFailed		=> 21,  
		pcmciaWriteProtect	=> 22 
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
		$oid{tftphost}, IPADDRESS, $args->{tftp},
		## set the filename being written/read
		$oid{file}, OCTET_STRING, "$args->{path}/$args->{file}",
		## set transfer direction and launch it
		$oid{action}, INTEGER, $act
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
			&accelar_log($args, "problem with transfer operation. Result = "
				      . $result);
		}
	        else {
			## success, log output to screen and possibly external file
			$args->{log}->log_action($args);
		}
	}

	else {
		## Error : can't trigger transfer operation...
		&accelar_log($args, "can't trigger transfer operation.");
	}

	## close the snmp session
	$s->close;
}


#-------------------------------------------------------------------------------
# accelar_log
# Add a leading "Plugin Accelar" to the message and logs it
#-------------------------------------------------------------------------------

sub accelar_log {
        my $args = shift;
        my $msg = shift;

        $args->{err} = "Plugin Accelar - $msg";
        $args->{log}->log_action($args);
}


# this must be here or else it won't return true
1;
