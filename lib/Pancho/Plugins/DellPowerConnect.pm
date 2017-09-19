# $Id: DellPowerConnect.pm,v 1.2 2004/09/06 04:39:34 cmenzes Exp $

# Author: Justin Ellison <justin@pancho.org>

package Pancho::DellPowerConnect;

use strict;
use Net::SNMP;


# these are device types we can handle in this plugin
# the names should be contained in the sysdescr string
# returned by the devices
# the key is the name and the value is the vendor description
my %types = (
              'powerconnect'   => "Dell PowerConnect Series",
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

   if ($opts->{upload} || $opts->{download}) {
	&transfer_config($args);
   } elsif ($opts->{commit}) {
   	&commit($args);
	} elsif ($opts->{reload}) {
	    &reload($args);
	    }
   ## add code here to handle the various transfer types
   ## and options
   ## You'll need to have the ability to handle (or at least
   ## provide output for) the following:
   ## upload & download
   ## commit
   ## reload

   ## to deal create an snmp session you can use the snmp object
   ## stored in args
   ## it will return a Net::SNMP object instantiated with the proper
   ## host and snmp settings
   ## example:
   ## my $snmp_obj = $args->{snmp}->create_snmp($args);
   ## 
   ## Now you can proceed to use normal Net::SNMP methods on 
   ## the returned object.
   ## $snmp_obj->set_request($some_oid,INTEGER,$val);

   ## if you need to log an error you can do so by setting the
   ## string in $args->{err} and then calling
   ## $args->{log}->log_action($args)
   ## example:
   ## $args->{err} = "Sample Error";
   ## $args->{log}->log_action($args);
}

sub transfer_config {
  my $args = shift;

  my %oid = (
  		tftpserverip	=> ".1.3.6.1.4.1.674.10895.1.11.32.0",
		filename	=> ".1.3.6.1.4.1.674.10895.1.11.33.0",
		# 1 for download config to switch, 2 for upload to tftp
		operation	=> ".1.3.6.1.4.1.674.10895.1.11.34.0",
	     );
  my $operation;
  if ($args->{dst} eq 'tftp') {
     $operation = 2;
     } elsif ($args->{dst} eq 'run') {
     	$operation = 1;
  }
#make an snmp session
  my $s=$args->{snmp}->create_snmp($args);
#Do it!
  $s->set_request	("$oid{tftpserverip}", IPADDRESS, $args->{tftp},
  			"$oid{filename}", OCTET_STRING, "$args->{path}/$args->{file}",
			"$oid{operation}", INTEGER, $operation,
			);
  $args->{err} = $s->error;
  $s->close;
  $args->{log}->log_action($args);

} #end sub


sub commit {

  my $args = shift;
  ## set args for logging 
  $args->{src} = "commit";

  my %oid = (
                  commit => ".1.3.6.1.4.1.674.10895.1.11.19.0",
            );

  my $s = $args->{snmp}->create_snmp($args);

  ## write to memory
  $s->set_request($oid{commit}, INTEGER, 1);

  ## close session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

} #end sub

sub reload {

  my $args = shift;
  $args->{src} = "reload";
  my %oid = (
  		reload => ".1.3.6.1.4.1.674.10895.1.3.2.0",
	    );
    ## start the session
  my $s = $args->{snmp}->create_snmp($args);

  ## reload the router
  $s->set_request($oid{reload}, INTEGER, 1);

  ## put error value into hash
  $args->{err} = $s->error;

  ## close the session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

} #end sub

# this must be here or else it won't return true
1;
