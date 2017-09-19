## $Id: Cisco.pm,v 1.13 2005/04/27 19:10:53 cmenzes Exp $
package Pancho::Cisco;

## April 19th, 2005 
## Modifed code to scan for the active CATOS management module instead of 
## assuming it was module 1 or module 2 (for sup 720's)
## Kevin Thayer <nufan_wfk@yahoo.com>

use strict;
use Net::SNMP;


# these are device types we can handle in this plugin
# the names should be contained in the sysdescr string
# returned by the devices
# the key is the name and the value is the vendor description
my %types = (
              cisco   => 'Cisco Systems',
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
      return 'Unknown';
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

    ## test to see which os is on remote node
    if ($args->{desc} =~ /Version 1(?:1|0)/) {

      ## place our vendor into our dialogue hash
      $args->{vndr} = 'Cisco (IOS 10.x/11.x)';

      ## run for 10.x and 11.x
      &cisco_transfer_deprecated($args);

      ## detect Catalyst 2950/3550 with 12.1(12) or higher
    } elsif ($args->{desc} =~ /C(?:35|29)50.*Version 12.[1-9]\(1[2-9]/) {

      ## place our vendor into our dialogue hash
      $args->{vndr} = 'Cisco IOS 12.1(12+) C3550|C2950';

      &cisco_transfer_cccopy($args);

      ## detect Catalyst 2900XL/3500XL
    } elsif ($args->{desc} =~ / C(?:(?:800)|35(?:(?:50)|(?:00XL))) /) {
                                                                                
      ## place our vendor into our dialogue hash
      $args->{vndr} = 'Cisco C3500XL/C2950/C3550/C800';

      &cisco_transfer_deprecated($args);

    } elsif ($args->{desc} =~ /Version 12/) {

      ## place our vendor into our dialogue hash
      $args->{vndr} = 'Cisco (IOS 12.x)';

      ## run for 12.x
      &cisco_transfer_cccopy($args);

    } elsif ($args->{desc} =~ /(?:Catalyst)|(?:WS-)/i) {

      ## place our vendor into our dialogue hash
      $args->{vndr} = 'Cisco CatalystOS';

      ## run for Catalysts
      &cisco_transfer_catalyst($args);

    } else {
      ## create error showing that cisco device is not supported
      $args->{err} = "The hardware for $args->{host} is not currently supported.";

      ## log the error
      $args->{log}->log_action($args);

    }

  }

  &cisco_transfer_catalyst_vlan($args) if (($opts->{vlan}) && ($args->{vlan}));

  &cisco_commit($args) if ($opts->{commit});

  &cisco_reload($args) if ($opts->{reload});

}

sub cisco_transfer_catalyst { 
  my $args = shift;

  ## set up oid to be used in this routine
  my %oid = (

                ## catalyst switch mibs
                cat_ipaddress   => '.1.3.6.1.4.1.9.5.1.5.1.0',
                cat_filename    => '.1.3.6.1.4.1.9.5.1.5.2.0',
                cat_module      => '.1.3.6.1.4.1.9.5.1.5.3.0',
                cat_action      => '.1.3.6.1.4.1.9.5.1.5.4.0',
                cat_result      => '.1.3.6.1.4.1.9.5.1.5.5.0',
                cat_mod2stdbystatus => '.1.3.6.1.4.1.9.5.1.3.1.1.21.2',
                cat_modstatus   => '.1.3.6.1.4.1.9.5.1.3.1.1.21',

            );
  # interface cards will report other (1) as standby status
  # other possible values are active (2), standby (3), error (4) 

  my %tftpResult =        ( 1     => 'inProgress',
                            2     => 'success',
                            3     => 'No Response',
                            4     => 'Too Many Retries',
                            5     => 'No Buffers',
                            6     => 'No Processes',
                            7     => 'Bad Checksum',
                            8     => 'Bad Length',
                            9     => 'Bad Flash',
                            10    => 'Server Error',
                            11    => 'User Canceled',
                            12    => 'Wrong Code',
                            13    => 'File Not Found',
                            14    => 'Invalid Tftp Host',
                            15    => 'Invalid Tftp Module',
                            16    => 'Access Violation',
                            17    => 'Unknown Status : Check TFTP Server',
                            18    => 'Invalid Storage Device',
                            19    => 'Insufficient Space On Storage Device',
                            20    => 'Insufficient Dram Size',
                            21    => 'Incompatible Image',
                          );

  if (($args->{src} eq 'start') or ($args->{dst} eq 'start')) {
    print "\nCopying configurations to and from startup-config\nis not possible using the CatOS.\n\n";

  } else {

    my $tftpmod = 1;

    ## determine the mib value for where the file will be sent
    my $i;
    if ($args->{src} eq 'tftp') { $i = '2'; } else { $i = '3'; }

    ## create the session
    my $s = $args->{snmp}->create_snmp($args);

    ## scan for the active supervisor
    my $curoid = $oid{cat_modstatus};

    ## go through each module's status until we find the active supervisor
    for (my $l = 0; $l < 16; $l++) {

      ## get the next module oid in the stack
      my $ret_ref = $s->get_next_request($curoid);

      if (!$s->error) {

        ## are we in the correct block of oids?
        my @results = keys(%$ret_ref);
        
        if ($results[0] =~ m/^$oid{cat_modstatus}/) {

          ## is this the actice sup?
          $curoid = $results[0];

          ## Value of 2 means this is the active sup
          if ($ret_ref->{$results[0]} == 2) {

            ## sup # is the last element of the oid
            my @oidparts = split(/\./, $results[0]);
            $tftpmod = $oidparts[$#oidparts];
            last;

          ## end if
          }
  
        ## end if
        } else { last; }
 
      ## end if
      } else {

        ## try the defaults if SNMP fails
        last;

      ## end if else
      }

    ## end for
    }

    ## set up the request
    $s->set_request	( ## set the tftp server value
			  $oid{cat_ipaddress}, OCTET_STRING, $args->{tftp},

		     	  ## set up the config file name
			  $oid{cat_filename}, OCTET_STRING, "$args->{path}/$args->{file}",
 
		     	  ## prep the module to go
			  $oid{cat_module}, INTEGER, $tftpmod,

		     	  ## send config
			  $oid{cat_action}, INTEGER, $i,		
		   	);

    ## put error into hash
    $args->{err} = $s->error;

    if (!$args->{err}) {

      ## set default status as "running"
      my $result = '1';

      ## check for the results status
      while (defined($result) && $result == '1') {

        ## get the current status of the tftp server's action
        my $current_state = $s->get_request ($oid{cat_result});

        $result = $current_state->{$oid{cat_result}};

      ## end while
      }


      ## failure!
      if (!defined($result)) {
        $args->{err} = 'SNMP Session failed during transfer';
      } elsif ($result != '2') {

        ## add error message into $args hash
        $args->{err} = $tftpResult{$result};

      ## endif
      }

    ## endif
    }

    ## close snmp session
    $s->close;

    ## log output to screen and possibly external file
    $args->{log}->log_action($args);
      
  }

}

sub cisco_transfer_catalyst_vlan {
  my $args = shift;

  if ( $args->{vndr} eq 'Cisco CatalystOS' ) {

    $args->{err} = "Vlan.dat is not supported for this host platform : $args->{host}";

    $args->{log}->log_action($args);

  }

  ## set up oid to be used in this routine
  my %oid = (
                ## cisco-flash-ops-mib
                method          => '.1.3.6.1.4.1.9.9.10.1.2.1.1.3',
                command         => '.1.3.6.1.4.1.9.9.10.1.2.1.1.2',
                ipaddress       => '.1.3.6.1.4.1.9.9.10.1.2.1.1.4',
                sourcefile      => '.1.3.6.1.4.1.9.9.10.1.2.1.1.5',
                destfile        => '.1.3.6.1.4.1.9.9.10.1.2.1.1.6',
                entrystatus     => '.1.3.6.1.4.1.9.9.10.1.2.1.1.11',
                state           => '.1.3.6.1.4.1.9.9.10.1.2.1.1.8',
             );

  ## pull in src/dst option to determine direction 
  my $i;
  my $source_file;
  my $destination_file;

  ## accomodate locations other than "flash" for vlan.dat location
  my $storageSource;
  $storageSource = $args->{vlan};
  $storageSource =~ tr/A-Z/a-z/;
  $storageSource =~ s/[^a-z0-9\-\_]//g;
  chomp $storageSource;

  if ($args->{src} eq 'tftp') {

    $i = 'copyToFlashWithoutErase';
    $source_file = "$args->{path}/$args->{host}-vlan.dat";
    $destination_file = "$storageSource:vlan.dat";
    
  } else {

    $i = 'copyFromFlash';
    $source_file = "$storageSource:vlan.dat";
    $destination_file = "$args->{path}/$args->{host}-vlan.dat";

  }

  my %command =	(
			copyToFlashWithErase => 1,
			copyToFlashWithoutErase => 2,
			copyFromFlash => 3,
			copyFromFlhLog => 4,
		);

  my %state =	(
    			copyInProgress               =>  1 ,
    			copyOperationSuccess         =>  2 ,
    			copyInvalidOperation         =>  3 ,
    			copyInvalidProtocol          =>  4 ,
    			copyInvalidSourceName        =>  5 ,
    			copyInvalidDestName          =>  6 ,
    			copyInvalidServerAddress     =>  7 ,
    			copyDeviceBusy               =>  8 ,
    			copyDeviceOpenError          =>  9 ,
    			copyDeviceError              =>  10,
    			copyDeviceNotProgrammable    =>  11,
    			copyDeviceFull               =>  12,
    			copyFileOpenError            =>  13,
    			copyFileTransferError        =>  14,
    			copyFileChecksumError        =>  15,
    			copyNoMemory                 =>  16,
    			copyUnknownFailure           =>  17,
		);

  ## generate random number used for mib instances
  srand(time | $$);
  my $rand = int(rand(900))+10;

  ## start snmp session
  my $s = $args->{snmp}->create_snmp($args);

  ## copy files across network
  $s->set_request   (  ## select method of transfer
                       "$oid{method}.$rand", INTEGER, 1,

                       ## select copy command
                       "$oid{command}.$rand", INTEGER, $command{$i},

                       ## select source file location
                       "$oid{sourcefile}.$rand", OCTET_STRING, "$source_file",

                       ## set tftpserver ip address
                       "$oid{ipaddress}.$rand", IPADDRESS, $args->{tftp},

                       ## set the filename being written
                       "$oid{destfile}.$rand", OCTET_STRING, "$destination_file",

                       ## set the session status
                       "$oid{entrystatus}.$rand", INTEGER, 4,
                    );

  ## add error message into $args hash
  $args->{err} = $s->error;

  ## if no error...
  if (!$args->{err}) {

    ## set default status as "running"
    my $result = '1';

    ## check for the results status
    while(defined($result) && $result == $state{copyInProgress}) {

      ## get the current status of the tftp server's action
      my $current_state = $s->get_request ("$oid{state}.$rand");

      $result = $current_state->{"$oid{state}.$rand"};

    ## end while
    }

    ## failure!
    if (!defined($result)) {
      $args->{err} = 'SNMP Session failed during transfer';

    } elsif ($result != '2') {
 
      ## add error message into $args hash
      $args->{err} = (grep { $state{$_} == $result } keys %state)[0];

    ## endif
    }

    ## clear the rowstatus for the remote device
    $s->set_request ("$oid{entrystatus}.$rand", INTEGER, 6);
    
  ## endif
  }

  ## close the snmp session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

}

sub cisco_transfer_deprecated {
  my $args = shift;

  ## build oid list for subroutine
  my %oid = (	## deprecated lsystem mibs
                wrnet           => '.1.3.6.1.4.1.9.2.1.55.',
                confnet         => '.1.3.6.1.4.1.9.2.1.53.',
            );


  if (($args->{src} eq 'start') or ($args->{dst} eq 'start')) {
    print "\nCopying configurations to and from startup-config\nis not possible using deprecated mibs.\n\n";    
 
  } else {
    my $mib;

    ## set up proper value for $mib
    if ($args->{src} eq 'tftp') {
      $mib = $oid{confnet};
    } else {
      $mib = $oid{wrnet};
    }

    $mib = "$mib$args->{tftp}"; 

    my $s = $args->{snmp}->create_snmp($args);

    ## set up the request
    $s->set_request($mib, OCTET_STRING, "$args->{path}/$args->{file}");

    ## put error into hash
    $args->{err} = $s->error;

    ## close snmp session
    $s->close;

    ## log output to screen and possibly external file
    $args->{log}->log_action($args);

  }
}

sub cisco_transfer_cccopy {
  my $args = shift;


  ##
  ## NOTES TO SELF ON INCLUDING SCP TRANSPORT PROTOCOL
  ## 	ccCopyUserName AND ccCopyUserPassword
  ##


  ## set up oid to be used in this routine
  my %oid = (
                ## 
                method          => '.1.3.6.1.4.1.9.9.96.1.1.1.1.2',

		##
                source          => '.1.3.6.1.4.1.9.9.96.1.1.1.1.3',

		##
                destination     => '.1.3.6.1.4.1.9.9.96.1.1.1.1.4',

		##
                ipaddress       => '.1.3.6.1.4.1.9.9.96.1.1.1.1.5',

		##
                filename        => '.1.3.6.1.4.1.9.9.96.1.1.1.1.6',

		##
                rowstatus       => '.1.3.6.1.4.1.9.9.96.1.1.1.1.14',

		##
                state           => '.1.3.6.1.4.1.9.9.96.1.1.1.1.10',

		##
                cause           => '.1.3.6.1.4.1.9.9.96.1.1.1.1.13',
             );

  my %filelocation =      ( tftp          => '1',
                            start         => '3',
                            run           => '4',
                          );

  my %state =             ( waiting       => '1',
                            running       => '2',
                            success       => '3',
                            failed        => '4',
                          );

  my %cause =             ( 1     => 'Unknown Copy Failure',
                            2     => 'Bad File Name',
                            3     => 'Network timeout',
                            4     => 'Not Enough Memory',
                            5     => 'Source Configuration doesnt exist.',
                          );


  ## generate random number used for mib instances
  srand(time | $$);
  my $rand = int(rand(900))+10;

  ## start snmp session
  my $s = $args->{snmp}->create_snmp($args);

  ## copy files across network
  $s->set_request   (  ## select method of transfer
                       "$oid{method}.$rand", INTEGER, 1,

                       ## select source file location
                       "$oid{source}.$rand", INTEGER, $filelocation{$args->{src}},

                       ## select destination file location
                       "$oid{destination}.$rand", INTEGER, $filelocation{$args->{dst}},

                       ## set tftpserver ip address
                       "$oid{ipaddress}.$rand", IPADDRESS, $args->{tftp},

                       ## set the filename being written
                       "$oid{filename}.$rand", OCTET_STRING, "$args->{path}/$args->{file}",

                       ## set the session status
                       "$oid{rowstatus}.$rand", INTEGER, 4,
                    );

  ## add error message into $args hash
  $args->{err} = $s->error;

  ## if no error...
  if (!$args->{err}) {

    ## set default status as "running"
    my $result = '1';

    ## check for the results status
    while( 
           ( defined($result) ) 
             && 
           (
             ($result == "$state{running}") 
               || 
             ($result == "$state{waiting}")
           ) 
         ) {

      ## get the current status of the tftp server's action
      my $current_state = $s->get_request ("$oid{state}.$rand");

      $result = $current_state->{"$oid{state}.$rand"};

    ## end while
    }

    ## failure!
    if (!defined($result)) {
      $args->{err} = 'SNMP Session failed during transfer';

    } elsif ($result != '3') {
 
      ## send snmp reqest to find cause of problem
      my $cause_req = $s->get_request ("$oid{cause}.$rand");

      ## assign result to the value returned from the query
      $result = $cause_req->{"$oid{cause}.$rand"};

      ## add error message into $args hash
      $args->{err} = $cause{$result};

    ## endif
    }

    ## clear the rowstatus for the remote device
    $s->set_request ("$oid{rowstatus}.$rand", INTEGER, 6);
    
  ## endif
  }

  ## close the snmp session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

}

sub cisco_commit {
  my $args = shift;

  if ( $args->{vndr} eq 'Cisco CatalystOS' ) {

    $args->{err} = "Committing to startup-configuration is not supported for this host platform : $args->{host}";

    $args->{log}->log_action($args);

  }

  ## set args for logging 
  $args->{src} = 'commit';

  my %oid = (
                  commit => '.1.3.6.1.4.1.9.2.1.54.0',
            );

  ## write config to memory
  my $s = $args->{snmp}->create_snmp($args);

  ## write to memory
  $s->set_request($oid{commit}, INTEGER, 1);

  ## grab an error if it exists
  #$args->{err} = $s->error;

  ## close session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

}

sub cisco_reload { 
  my $args = shift;

  ## set args for logging purposes
  $args->{src} = 'reload';

  my %oid = (
                  reload          => '.1.3.6.1.4.1.9.2.9.9.0',
            );

  ## start the session
  my $s = $args->{snmp}->create_snmp($args);

  ## reload the router
  $s->set_request($oid{reload}, INTEGER, 2);

  ## put error value into hash
  $args->{err} = $s->error;

  ## close the session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

}


# this must be here or else it won't return true
1;
