###################################################################################
##
## Avaya.pm
##
## Pancho plugin for Avaya P330 family devices running OS 3.x
##
## Author  : Jean-Francois Taltavull
## Release : 1.0.2 - 2003/11/05
## Last update : 2003/12/15
##
## Mib files : Load.mib.txt Config.mib.txt
## Mib names : LOAD-MIB , Lucent Common Download / Upload MIB  {enterprises 1751} (Lucent)
##             CONFIG-MIB , {enterprises 81} (Lannet)
## Mib version/date : LOAD-MIB : v 1.3.4 , 2000/09/13
##                    CONFIG-MIB : v 10.2.8 , 2001/12/25
## Mib branches : lucent.mibs.load.genOperations.genOpTable.genOpEntry
##                oid : 1751.2.53.1.2.1
##                lucent.mibs.load.genApplications.genAppFileEntry
##                oid : 1751.2.53.2.1
##                lannet.chassis
##                oid : 81.7.1.0
##
## Plugin's features :
##	- upload, download, startup
##	(commit and reload are not supported.)
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
###################################################################################

package Pancho::Avaya;

use strict;
use Net::SNMP;


# These are device types we can handle in this plugin
# the names should be contained in the sysdescr string
# returned by the devices
# the key is the name and the value is the vendor description
my %types = (
              'P330 Stackable Switch' => "Avaya Inc. P330 stackable switch"
            );


## Chassis is one of these
## supported : 
##		'yes'  - chassis is supported by the plugin
##		'no'   - chassis is **not** supported by the plugin
my %chassis = (
	1   => {type => 'let18', supported => 'no'},
	2   => {type => 'let3', supported => 'no'},
	3   => {type => 'let36', supported => 'no'},
	4   => {type => 'let18Extended', supported => 'no'},
	5   => {type => 'lert40', supported => 'no'},
	6   => {type => 'let10', supported => 'no'},
	7   => {type => 'fdx100', supported => 'no'},
	8   => {type => 'stack', supported => 'no'},
	9   => {type => 'let20', supported => 'no'},
	10  => {type => 'let36-01-02', supported => 'no'},
	11  => {type => 'lea', supported => 'no'},
	12  => {type => 'lac', supported => 'no'},
	13  => {type => 'visage', supported => 'no'},
	14  => {type => 'letM770', supported => 'no'},
	15  => {type => 'm770', supported => 'no'},
	16  => {type => 'm770Atm', supported => 'no'},
	17  => {type => 'cajunP120', supported => 'no'},
	18  => {type => 'cajunP330', supported => 'yes'},
	19  => {type => 'cajunP130', supported => 'no'},
	255 => {type => 'unknown', supported => 'no'}
);


## Modules types
## supported == 'no' means module is not supported by this release
## startup-config are supported only when marked 'yes'; 'ask' will be implemented
## in a future release (this concerns modules with a routing option).
my %modules = (
	2501  => {type => 'cajunP333T', supported => 'yes', startup => 'no'},
	2502  => {type => 'cajunP333R', supported => 'no', startup => 'ask'},
	2504  => {type => 'cajunP334T', supported => 'yes', startup => 'no'},
	2505  => {type => 'cajunP332MF', supported => 'yes', startup => 'no'},
	2507  => {type => 'cajunP332G-ML', supported => 'yes', startup => 'no'},
	2510  => {type => 'cajunP332GT-ML', supported => 'yes', startup => 'no'},
	2511  => {type => 'cajunP334T-ML', supported => 'yes', startup => 'yes'},
	2512  => {type => 'cajunP333RLB', supported => 'no', startup => 'ask'},
	2513  => {type => 'cajunP333T-PWR', supported => 'yes', startup => 'no'},
	255   => {type => 'unknown', supported => 'no', startup =>  ' '}
);


## A stack of P330 devices contains one configuration for the stack
## and one configuration for each device. So, in case of a 4 devices stack,
## you have to deal with 5 configurations.
##
## 'stack' is a data structure to describe the devices stack we have to deal with.
my %stack = (	 # devices stack descriptor
	1 => { id => 0, cfgname => '', suffix => '' }
);

my $snmpslowdown = 1;		# to slow down snmp requests loops (seconds)...
				# ...avoiding Avaya snmp agent to be overloaded.
my $stacksuffix  = "stk";	# suffix for stack-config file...
my $modulesuffix = "mod";	# ...and for module-config file.
my $masterid;			# 'avaya_setup_stack()' will set it right.




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

	my $mods;	# modules number within the stack


	if ($opts->{commit}) {
		&avaya_log($args, "Commit operation not supported.");
		return;
	};

	if ($opts->{reload}) {
		&avaya_log($args, "Reload operation not supported.");
		return;
	};


	## Which OS version ?
	if ($args->{desc} !~ /SW version 3./) {
		# O.S. version not supported
		&avaya_log($args, "Can't perform operation. Cause : OS version [$args->{desc}] not supported.");
		return;
	}

	## Which hardware ?
	my $hwid = &avaya_get_chassis_type($args);
	if ($chassis{$hwid}->{supported} eq 'no') {
		# hardware not supported
		&avaya_log($args, "Can't perform operation. Cause : chassis [$chassis{$hwid}->{type}] not supported.");
		return;
	}

	## How many modules are stacked ?
	$mods = &avaya_get_modules_number($args);

	if ($mods <= 0) {
		&avaya_log($args, "Can't perform operation. Cause : no module present, nonsense!");
		return;
	}

	else {
		## Ok, go ahead, setup the stack descriptor
		if (&avaya_setup_stack($args, $mods) != $mods) {
			&avaya_log($args, "Can't perform operation. Cause : incoherent modules number.");
			return;
		}
			
	}
	
	## Process each module of the stack
	for (my $i = 0; $i <= $mods; $i++) {
		&avaya_process_module($args, $opts, $stack{$i});
	}
}


#------------------------------------------------------------------------------- 
# avaya_process_module - get module hardware type and launch 'avaya_transfer()'.
# IN : args - hash ref containing various program args
#      opts - hash ref of options passed into program
#      mod  - a stack descriptor entry (a module)
#------------------------------------------------------------------------------- 
sub avaya_process_module {
	my $args = shift;
	my $opts = shift;
	my $mod = shift;

	my $hwt;		# module type


	## Query device for module type
	$hwt = &avaya_get_module_type($args,$mod->{id});

	if ($modules{$hwt}->{supported} eq 'no') {
		# module type not supported
		&avaya_log($args, "Can't perform operation. Cause : module [$modules{$hwt}->{type}] not supported.");
		return;
	}

	## Operation applies on startup-config ?
	if ( ($args->{src} eq "start" or $args->{dst} eq "start")
	     && $modules{$hwt}->{startup} ne "yes" ) {
		# startup config not supported by the device
		&avaya_log($args, "Operations on startup-config not supported for this module [$modules{$hwt}->{type}]."); 
		return;
	}

	## Select operation
	SWITCH: {
		## DEVICE --> TFTP
		$opts->{download} && do {
			if ($args->{src} eq "start") {
				&avaya_transfer($args, $mod, 'startupconfig');
			}
			else  {
				&avaya_transfer($args, $mod, 'runningconfig');
			}
			last SWITCH;
		};
		
		## TFTP --> DEVICE
                ## in this case, the target module **must be** the master module
		## the config file itself contains the effective module number
		$opts->{upload} && do {
			if (grep(/\-$mod->{suffix}.$mod->{id}/, $args->{file}) ) {
				$mod = $stack{$masterid};
				if ($args->{src} eq "start") {
					&avaya_transfer($args, $mod, 'startupconfig');
				}
				else  {
					&avaya_transfer($args, $mod, 'runningconfig');
				}
			}
			last SWITCH;
		};

		&avaya_log($args, "Unknown operation.");
	}
}


#------------------------------------------------------------------------------- 
# avaya_transfer - launch operation trough snmp requests
# IN : args - hash ref containing various program args
#      mod  - ref to a stack descriptor entry (a module)
#      cgft - 'running' ou 'startup'
#------------------------------------------------------------------------------- 
sub avaya_transfer {
	my $args = shift;
	my $mod  = shift;	# 'stack' array entry (a module)
	my $cfgt = shift;	# config type (running or startup)

	## The Load MIB defines upload, download and copy of application software
	## and configuration information.

	## genOpTable (genOperations group)
	## Each row in the genOpTable represents an operation that this system can
	## perform.The genOpTable contains all configuration information nessary
	## to perform upload, download, and copy operations within the system.
	## Source, Destination, operational trigger, operational status and
	## error logging information are contained on a per row basis (each row
	## again representing an operation that this table can perform).
	## The genOpTable is indexed by the genOpModuleId object, the number
	## of the slot for which the entry, the genOpEntry object, contains informations.

	## genAppFileTable (genApplication group)
	## Each row in the genAppFileTable uniquely defines an application in the system.
	## Applications can be defined as any entity that can be read or written from or
	## to the system.  This includes software images, boot code, configuration files,
	## prom code, etc.
	## Each row contains information used to catalog the application (FILE)
	## entries present in the system. A walk of the genAppFileTable should
	## provide a directory-like listing of all application software,
	## bootcode, configuration files and misc. accessable embedded software
	## in the system.  Each entry contains information about the application
	## such as type, size, version number and date stamp.


	my %oid = (
		## genOpTable entry
		opfilesystemtype => ".1.3.6.1.4.1.1751.2.53.1.2.1.20",
		opsourceindex => ".1.3.6.1.4.1.1751.2.53.1.2.1.4",
		opdestindex => ".1.3.6.1.4.1.1751.2.53.1.2.1.5",
		opserverip => ".1.3.6.1.4.1.1751.2.53.1.2.1.6",
		opprotocol => ".1.3.6.1.4.1.1751.2.53.1.2.1.9",
		opfilename => ".1.3.6.1.4.1.1751.2.53.1.2.1.10",
		opresetsupported => ".1.3.6.1.4.1.1751.2.53.1.2.1.16",
		openablereset => ".1.3.6.1.4.1.1751.2.53.1.2.1.17",
		oprunningstate => ".1.3.6.1.4.1.1751.2.53.1.2.1.3",
		oplastfailure => ".1.3.6.1.4.1.1751.2.53.1.2.1.12",
		oplastfailuredisplay  => ".1.3.6.1.4.1.1751.2.53.1.2.1.13"
	);

	my %operation = (
		uploadconfig => 1,
		downloadconfig => 2,
		report => 3,
		uploadsoftware => 4,
		downloadsoftware => 5,
		localconfigfilecopy => 6,
		localswfilecopy => 7,
		uploadlogfile => 8,
		erasefile => 9,
		show => 10,
		syncstandbyagent => 11
	);

	my %state = (
		idle => 1,
		beginoperation => 2,
		waitingip => 3,
		runningip => 4,
		copyinglocal => 5,
		readingconfig => 6,
		executing => 7
	);

	my %protocol = (
		tftp  =>    1 ,
		ftp   =>    2 ,
		localpeer =>    3,
		localserver =>  4
	);

	my %resetsupported = (
		yes => 1,
		no => 2
	);

	my %reset = (
		enable => 1,
		disable => 2
	);

	my %failure = (
		noerror => 1,  
		generror => 2,  
		configerror => 3,  
		busy => 4,  
		timeout => 5,  
		cancelled => 6,  
		incompatiblefile => 7,  
		filetoobig => 8,  
		protocolerror => 9,  
		flashwriteerror => 10,  
		nvramwriteerror => 11,  
		conffilegenerr => 12,  
		conffileparseerror => 13,  
		conffileexecerror => 14,  
		undefinederror => 100,  
		filenotfound => 101,  
		accessviolation => 102,  
		outofmemory => 103,  
		illegaloperation => 104,  
		unknowntransferid => 105,  
		filealreadyexists => 106,  
		nosuchuser => 107  
	);

	my ($op, $sdoid, $fname);


	## Look for file entry into AppFileTable
	my $fent = &avaya_look_for_file_entry($args, $mod->{id}, $cfgt, $mod->{cfgname});

	if (!$fent) {
		## failed, entry not found in AppFileTable
		&avaya_log($args, "Problem with transfer operation. Cause : entry not found in AppFileTable.");
		return 0;
	}

	## Set up parameters for the transfer operation
	if ($args->{src} eq "tftp") { 
		## TFTP --> DEVICE
		$op = $operation{downloadconfig};
		$sdoid = $oid{opdestindex};
		$fname = "$args->{path}/$args->{file}",
	}
	else {
		## DEVICE --> TFTP
		$op = $operation{uploadconfig};
		$sdoid = $oid{opsourceindex};
		$fname = "$args->{path}/$args->{file}-$mod->{suffix}.$mod->{id}",
	}


	## Set up snmp session parameters for the transfer operation
	my $s = $args->{snmp}->create_snmp($args);

	## If supported, disable 'reset after completion' feature
	my $rst = $s->get_request("$oid{opresetsupported}.$mod->{id}.$op");
	if ($rst->{"$oid{opresetsupported}.$mod->{id}.$op"} == $resetsupported{yes}) {
		## disable reset
		$s->set_request("$oid{openablereset}.$mod->{id}.$op", INTEGER, $reset{disable});
	}

	## Trigger transfer operation
	$s->set_request( 
		## tftp server ip address
		"$oid{opserverip}.$mod->{id}.$op", IPADDRESS, $args->{tftp},
		## set the protocol to tftp
		"$oid{opprotocol}.$mod->{id}.$op", INTEGER, $protocol{tftp},
		## source|destination
                "$sdoid.$mod->{id}.$op", INTEGER32, $fent,
		## file name (on the tftp server)
		"$oid{opfilename}.$mod->{id}.$op", OCTET_STRING, $fname,
		## trigger the transfer
		"$oid{oprunningstate}.$mod->{id}.$op", INTEGER, $state{beginoperation}
	);


	## Grab an error message if it exists
	my $error = $s->error;
	## Put error value into hash
	$args->{err} = $error;

	if (!$error) {
		## OK, no error while triggering the transfer, so grab the running state
		my $current_state = $s->get_request ("$oid{oprunningstate}.$mod->{id}.$op");
		my $result = $current_state->{"$oid{oprunningstate}.$mod->{id}.$op"};

		## Loop and check for the the operation status (the running state)
		while ($result != "$state{'idle'}") {
			## get the current status of the tftp server's action
			sleep $snmpslowdown;
			$current_state = $s->get_request ("$oid{oprunningstate}.$mod->{id}.$op");
			$result = $current_state->{"$oid{oprunningstate}.$mod->{id}.$op"};
		}

		## Check for errors
		my $final_status = $s->get_request("$oid{oplastfailure}.$mod->{id}.$op");
		my $status = $final_status->{"$oid{oplastfailure}.$mod->{id}.$op"};


		if ($status != $failure{noerror}) {
			## failure! Add error message into $args hash
			my $errmsg = $s->get_request("$oid{oplastfailuredisplay}.$mod->{id}.$op");
			&avaya_log($args, "Problem with transfer operation. Cause: "
				   . $errmsg->{"$oid{oplastfailuredisplay}.$mod->{id}.$op"});
		}

		else {
			## OK, transfer completed
			$args->{log}->log_action($args);
		}
	}

	else {
		## Error : can't trigger transfer operation...
		&avaya_log($args, "Can't trigger transfer operation.");
	}
		

	## Close snmp session
	$s->close;

}


#------------------------------------------------------------------------------- 
# avaya_get_chassis_type
# gets chassis hardware type
# IN : args - hash ref containing various program args
# OUT: chassis hardware type
#------------------------------------------------------------------------------- 
sub avaya_get_chassis_type {
	my $args = shift;

	my %oid = ( 
		## chHWType
		## integer
		## chassis hardware type
		hwtype => '.1.3.6.1.4.1.81.7.1.0'
	);

	## Start the snmp session
	my $s = $args->{snmp}->create_snmp($args);

	## Get hardware type
	my $hwt = $s->get_request($oid{hwtype});

	## Close snmp session
	$s->close;

	return $hwt->{$oid{hwtype}};
}


#------------------------------------------------------------------------------- 
# avaya_get_modules_number
# queries the chassis for number of stacked modules
# IN : args - hash ref containing various program args
# OUT: number of modules
#------------------------------------------------------------------------------- 
sub avaya_get_modules_number {
	my $args = shift;

	my %oid = ( 
		## chNumberOfSlots
		## integer
		## number of slots (i.e modules) within chassis
		numofslots => '.1.3.6.1.4.1.81.7.2.0'
	);


	## Start the snmp session
	my $s = $args->{snmp}->create_snmp($args);

	## Get hardware type
	my $nslots = $s->get_request($oid{numofslots});

	## Close snmp session
	$s->close;

	return $nslots->{$oid{numofslots}};
}


#------------------------------------------------------------------------------- 
# avaya_look_for_file_entry
# Search genAppFileTable for the right entry
# IN : args - hash ref containing various program args
#      mid  - module's number
#      cfgt - 'running' or 'startup'
#      cfgn - 'stack' or 'module'
# OUT:
#      != 0 - id of entry in genAppFileTable
#      0    - entry not found
#------------------------------------------------------------------------------- 

sub avaya_look_for_file_entry {
	my $args = shift;
	my $mid  = shift;
	my $cfgt = shift;
	my $cfgn = shift;

	my %oid = ( 
		## genAppFileTable
		##   genAppFileType
		##   integer
		##   file type of the entry
		filetype => '.1.3.6.1.4.1.1751.2.53.2.1.1.3',
		##   genAppFileName
		##   string
		##   file name of the entry
		filename => '.1.3.6.1.4.1.1751.2.53.2.1.1.2'
	);

	my %filetype = (
		runningconfig => 1,
		startupconfig => 2,
		defaultconfig => 3,
		report => 4,
		genconfigfile => 5,
		logfile => 6,
		nvramfile => 7,
		swruntimeimage => 8,
		swbootimage => 9,
		swcomponent => 10,
		other => 11,
		swwebimage => 12
	);

 
	## Start the snmp session
	my $s = $args->{snmp}->create_snmp($args);

	## genAppFileTable : look for an entry with the right file type and name
	my $ft;
	my $fn;
	my $fent = 0;
	do {
		$fent++;
		$ft = $s->get_request("$oid{filetype}.$mid.$fent");
		$fn = $s->get_request("$oid{filename}.$mid.$fent");
	}
	until (!$ft
		|| ( ($ft->{"$oid{filetype}.$mid.$fent"} == $filetype{$cfgt})
                      && ($fn->{"$oid{filename}.$mid.$fent"} eq $cfgn)
		   )
	      );

	## Close snmp session
	$s->close;

	if (!$ft) {
		## entry not found
		return 0;
	}
	else {
		## ok, entry found
		return $fent;
	}
}


#------------------------------------------------------------------------------- 
# avaya_get_module_type
# Gets the hardware type of a stacked module
# IN : args -  hash ref containing various program args
#      mid  - module id
# OUT:
#      module's type
#------------------------------------------------------------------------------- 
sub avaya_get_module_type {
	my $args = shift;
	my $mid = shift;
	  
	my %oid = ( 
		## genGroupTable
		##   OpGroupType
		##   integer
		##   type of module
		grouptype => '.1.3.6.1.4.1.81.8.1.1.4'
	);


	## Start the snmp session
	my $s = $args->{snmp}->create_snmp($args);

	## Get module type
	my $gt = $s->get_request("$oid{grouptype}.$mid");

	## Close snmp session
	$s->close;

	return $gt->{"$oid{grouptype}.$mid"};
}


#------------------------------------------------------------------------------- 
# avaya_setup_stack
# Builds the stack descriptor
# IN : args - hash ref containing various program args
#      mods - number of stacked modules
# OUT:
#      number of modules
#------------------------------------------------------------------------------- 
sub avaya_setup_stack {
	my $args = shift;
	my $mods = shift;

	my %oid = ( 
		## GenGroupTable
		##   genGroupMngType
		##   integer
		##   module's management type
		mngtype   => '.1.3.6.1.4.1.81.8.1.1.39'
	);

	my %mngtype = (
		agent => 1,
		subagent => 2,
		sensor => 3,
		notsupported => 255
	);


	## Start the snmp session
	my $s = $args->{snmp}->create_snmp($args);

	## Cruise the P330 stack...
	my ($mt, $i);
	for ($i = 1; $i <= $mods; $i++) {
		## get management agent type
		$mt = $s->get_request("$oid{mngtype}.$i");
		if ($mt->{"$oid{mngtype}.$i"} == $mngtype{agent}) {
			## the master
			$masterid = $i;
			$stack{0}  = { id => $i, cfgname => 'stack-config', suffix => $stacksuffix };
			$stack{$i} = { id => $i, cfgname => 'module-config', suffix => $modulesuffix };
		}
		elsif ($mt->{"$oid{mngtype}.$i"} == $mngtype{subagent}) {
			## a slave
			$stack{$i} = { id => $i, cfgname => 'module-config', suffix => $modulesuffix };
		}
		else {
			## agent type is 'sensor' or 'notsupported'
			&avaya_log($args, "module's agent type invalid.\n");
			return -1;
		}
	}

	## Close snmp session
	$s->close;
	
	return $i - 1;
}


#------------------------------------------------------------------------------- 
# avaya_log
# Add a leading "Plugin Avaya" to the message and logs it
#------------------------------------------------------------------------------- 

sub avaya_log {
	my $args = shift;
	my $msg = shift;

	$args->{err} = "Plugin Avaya - $msg";
	$args->{log}->log_action($args);
}


# this must be here or else it won't return true
1;
