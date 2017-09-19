## $Id: Foundry.pm,v 1.2 2004/09/06 14:39:34 cmenzes Exp $
## Set this to the Pancho::<filename>
package Pancho::Foundry;

use strict;
use Net::SNMP;


# these are device types we can handle in this plugin
# the names should be contained in the sysdescr string
# returned by the devices
# the key is the name and the value is the vendor description
my %types = (
              foundry   => "Foundry Networks",
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

  &foundry_transfer($args) if ($opts->{upload} || $opts->{download});

  &foundry_commit($args) if ($opts->{commit});

  &foundry_reload($args) if ($opts->{reload});

}

sub foundry_transfer {
  my $args = shift;

  ## set up oid to be used in this routine
  my %oid = (
		## snAgTftpServerIp
		tftpserver	=> ".1.3.6.1.4.1.1991.1.1.2.1.5.0",

		## snAgCfgLoad 
		action		=> ".1.3.6.1.4.1.1991.1.1.2.1.9.0",

		## snAgCfgFname
		filename	=> ".1.3.6.1.4.1.1991.1.1.2.1.8.0",

	    );

  ## set up parameters for transfer direction
  my $direction;
  if ($args->{src} eq "tftp") {

    if ($args->{dst} eq "run") {

      ## copy tftp run
      $direction = "23";

    } else { 

      ## copy tftp start
      $direction = "21";

    }

  } else {

    if ($args->{src} eq "start") {

      ## copy start tftp
      $direction = "20";

    } else {

      ## copy run tftp
      $direction = "22";

    }

  }

  ## set up snmp session parameters
  my $s = $args->{snmp}->create_snmp($args);

  $s->set_request (
		    ## set the filename being written/read
		    $oid{filename}, OCTET_STRING, "$args->{path}/$args->{file}",
		  );

  $s->set_request (
		    ##set the tftp server address
		    $oid{tftpserver}, IPADDRESS, $args->{tftp},
		  );

  $s->set_request (
		    ## set file transfer direction
                    $oid{action}, INTEGER, $direction,
		  );

  ## add error message into $args hash
  $args->{err} = $s->error;

  ## close the snmp session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

## end of foundry_transfer
}

sub foundry_commit {
  my $args = shift;

  ## set up args for logging
  $args->{src} = "commit";

  ## set up oid to be used in this routine
  my %oid = ( 
              ## snAgWriteNVRAM  
              commit	=> ".1.3.6.1.4.1.1991.1.1.2.1.3.0",
            );

  ## write config to memory
  my $s = $args->{snmp}->create_snmp($args);

  ## write to memory
  $s->set_request($oid{commit}, INTEGER, 3);

  ## grab an error if it exists
  $args->{err} = $s->error;

  ## close session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

}

sub foundry_reload {

  ## pull in dialogue from previous sub-routine
  my $args = shift;

  ## set up oid
  my %oid = ( ## snAgReload 
	      reload	=> ".1.3.6.1.4.1.1991.1.1.2.1.1.0",
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
