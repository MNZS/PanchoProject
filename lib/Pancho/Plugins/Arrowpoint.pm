## $Id: Arrowpoint.pm,v 1.2 2005/04/27 19:10:53 cmenzes Exp $
## Set this to the Pancho::<filename>
#------------------------------------------------------------------------------- 
# Comments:
#  -If you get a 'localopen' failure do a 'save_config' on the CSS.
#  -Still may fail every now and then due to the way you pull configs. If the
#   CSS fails, just try again, it is a timing issue.
#------------------------------------------------------------------------------- 
package Pancho::Arrowpoint;

use strict;
use Net::SNMP;

# these are device types we can handle in this plugin
# the names should be contained in the sysdescr string
# returned by the devices
# the key is the name and the value is the vendor description
my %types = (
              content   => "Cisco Content Switch",
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

      ## Check for Pre Cisco ArrowPoints
      if ($args->{desc} =~ /Content Switch SW Version 0?7.[0-3]/) {

         ## place our vendor into our dialogue hash
         $args->{vndr} = 'Content Switch (pre 7.40)';

         ## run for pre 7.40
         &ap_transfer_deprecated($args);

      ## Check for CSS once they migrated to the Cisco branch of the OID
      } elsif ($args->{desc} =~ /Content Switch SW Version 0?7.[4-9]/) {

         ## place our vendor into our dialogue hash
         $args->{vndr} = 'Content Switch (post 7.40)';

         ## run for post 7.40
         &ap_transfer($args);

      }


   }

   &arrowpoint_commit($args) if ($opts->{commit});

   &arrowpoint_reload($args) if ($opts->{reload});

}

## For post 7.40 Cisco CSS devices
sub ap_transfer {

   my $args = shift;

#   $args->{warn} = "Config collection not supported on this code (yet...)";
#   $args->{log}->log_action($args);

  my $SecondTry = 0;

  ## Try a second time since these things are dumb
  TOP:

  ## The copy table is used to transfer files to and from a CS11XXX.  To use 
  ## this table use the following sequence of operations:
  ##
  ## 1. Create a row within the apCopyTable by instantiating an apCopyStatus
  ##     object.  The instantiation should be performed by using the 
  ##     apCopyNextIndex object.
  ## 2. Specify the protocol to be used for the transfer using the apCopyProtocol
  ##     object.  The default is FTP.  This table does not support copying FROM
  ##     the CS11XXX using HTTP.
  ## 3. Specify the source information with the following objects:
  ##     apCopySourceIpAddress, apCopySourceLocalDirectory, apCopySourceFileName.
  ## 4. Specify the destination information with the following objects:
  ##     apCopyDestIpAddress, apCopyDestLocalDirectory, apCopyDestFileName
  ## 5. Optionally specify credentials required for the transfer using the 
  ##     apCopyCredentialUserName and apCopyCredentialPassword objects.
  ## 5a.Optionally specify the port to use (for HTTP only)
  ## 6. Commence the copy operation using the apCopyControl object
  ## 7. Monitor the copy operation using the apCopyProgress and apCopyBytesTrans-
  ##    ferred objects.
  ## 8. Inspect the completion result using the apCopyFinalStatus object.
  ## 9. Destroy the row through the apCopyStatus object.

  my %oid = (
         ## apCopyNextIndex
         ## integer
         nextindex                => ".1.3.6.1.4.1.9.9.368.1.61.7.0",
   
         ## apCopyIndex
         ## integer
         index                    => ".1.3.6.1.4.1.9.9.368.1.61.2.1.1",

         ## apCopyDirection
         ## integer
         action                   => ".1.3.6.1.4.1.9.9.368.1.61.2.1.2",
      
         ## apCopyProtocol
         ## integer
         protocol                 => ".1.3.6.1.4.1.9.9.368.1.61.2.1.3",

         ## apCopySourceIpAddress
         ## IP Address
         ## only valid when copy direction is to unit
         srcip                    => ".1.3.6.1.4.1.9.9.368.1.61.2.1.6",

         ## apCopySourceLocalDirectory
         ## integer
         ## only valid when copy direction is from unit
         # 1: none(0)
         # 2: script(1)
         # 3: log(2)
         # 4: archive(4)
         # 5: root(5)
         # 6: core(6)
         srcdir                   => ".1.3.6.1.4.1.9.9.368.1.61.2.1.7",

         ## apCopySourceFileName
         ## Octet string
         srcfile                  => ".1.3.6.1.4.1.9.9.368.1.61.2.1.8",

         ## apCopyDestIpAddress
         ## IP Address
         ## only valid when copy direction is from unit
         dstip                    => ".1.3.6.1.4.1.9.9.368.1.61.2.1.9",

         ## apCopyDestLocalDirectory
         ## integer
         ## only valid when copy direction is to unit
         # 1: none(0)
         # 2: script(1)
         # 3: log(2)
         # 4: installed-software(3)
         # 5: archive(4)
         # 6: root(5)
         # 7: core(6) 
         dstdir                   => ".1.3.6.1.4.1.9.9.368.1.61.2.1.10",

         ## apCopyDestFileName
         ## Octet string
         dstfile                  => ".1.3.6.1.4.1.9.9.368.1.61.2.1.11",

         ## apCopyControl
         ## integer
         # 1: none(0)
         # 2: start(1)
         # 3: stop(2)
         copycontrol              => ".1.3.6.1.4.1.9.9.368.1.61.2.1.12",

         ## apCopyProgress
         ## integer
         progress                 => ".1.3.6.1.4.1.9.9.368.1.61.2.1.13",

         ## apCopyFinalStatus
         ## integer
         status                   => ".1.3.6.1.4.1.9.9.368.1.61.2.1.15",

         ## apCopyStatus
         ## integer
         # 4: createAndGo(4)
         # 6: destroy(6)
         copystatus               => ".1.3.6.1.4.1.9.9.368.1.61.2.1.16",

    );

    my %protocol = (
         local                    =>  0,
         tftp                     =>  1,
         ftp                      =>  2,
         http                     =>  3,
    );

    my %state = (
         none                     =>  0,
         'in-progress'            =>  1,
         complete                 =>  2,
         aborted                  =>  3,
    );

    my %cause = (
         success                  =>  0,
         failure                  =>  1,
         'localopen-failure'      =>  2,
         'locallock-failure'      =>  3,
         'connect-failure'        =>  4,
         'reject-failure'         =>  5,
         'notfound-failure'       =>  6,
         'notaccepted-failure'    =>  7,
         'credential-failure'     =>  8,
         aborted                  =>  9,
         none                     =>  99,
    );


    ## determine the mib value for where the file will be sent
    #  0: none
    #  1: from-unit
    #  2: to-unit
    #  3: local
    my ($direction, $src_file, $dst_file);
    if ($args->{src} eq "tftp") { 
       $direction = "2"; 
       $src_file = "$args->{path}/$args->{file}";
       $dst_file = "startup-config";
    } else {
       $direction = "1"; 
       $src_file = "startup-config";
       $dst_file = "$args->{path}/$args->{file}";
    }

    ## set up snmp session parameters
    my $s = $args->{snmp}->create_snmp($args);

    # create the new row in apCopyTable using the nextindex value
    my $next_index = $s->get_request ($oid{nextindex});
    my $index = $next_index->{$oid{nextindex}};

    ## set the new row to createAndGo
    $s->set_request ( "$oid{copystatus}.$index", INTEGER, 4);

    ## set the protocol to tftp
    $s->set_request ( "$oid{protocol}.$index", INTEGER, $protocol{tftp});

    ## set file transfer direction
    $s->set_request ( "$oid{action}.$index", INTEGER, $direction);

    ## set dstdir / srcip when uploading
    if ($args->{src} eq "tftp") {
      $s->set_request( "$oid{dstdir}.$index", INTEGER, 5 );
      $s->set_request ( "$oid{srcip}.$index", IPADDRESS, $args->{tftp} );

    ## set srcdir / dstip when downloading
    } else {
      $s->set_request("$oid{srcdir}.$index", INTEGER, 5);
      $s->set_request ( "$oid{dstip}.$index", IPADDRESS, $args->{tftp});
    }

    ## set the src file
    $s->set_request ( "$oid{srcfile}.$index", OCTET_STRING, $src_file);

    ## set the dst file
    $s->set_request ( "$oid{dstfile}.$index", OCTET_STRING, $dst_file);

    ## grab an error message if it exists
    my $error = $s->error;
    ## put error value into hash
    $args->{err} = $error;

    if ($error && !$SecondTry) {
       $SecondTry = 1;
       goto TOP;
    }

    ## if no error...
    if (!$error) {
      ## kick off copy by setting copycontrol to start
      $s->set_request ( "$oid{copycontrol}.$index", INTEGER, 1 );

      ## check for the results status
      my ($current_state, $result);
      do {
        sleep (1);
        ## get the current status of the tftp server's action
        $current_state = $s->get_request ("$oid{progress}.$index");
        $result = $current_state->{"$oid{progress}.$index"};

      } while ($result == "$state{'in-progress'}");

    ## check for errors
    my $final_status = $s->get_request("$oid{status}.$index");
    my $status = $final_status->{"$oid{status}.$index"};

    ## failure!
    if ($status ne "0") {
      ## add error message into $args hash
      my $problem = (grep { $cause{$_} == $status } keys %cause)[0];
      $args->{err} = "Problem with copy operation. Cause: $problem";
    } ## endif

    ## clear the rowstatus for the remote device
    $s->set_request ("$oid{copystatus}.$index", INTEGER, 6);
    
  } ## endif

  ## close the snmp session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

}


## For pre 7.40 Cisco CSS devices (ArrowPoint)
sub ap_transfer_deprecated {

  my $args = shift;
  my $SecondTry = 0;

  ## Try a second time since these things are dumb
  TOP:

  ## The copy table is used to transfer files to and from a CS11XXX.  To use 
  ## this table use the following sequence of operations:
  ##
  ## 1. Create a row within the apCopyTable by instantiating an apCopyStatus
  ##     object.  The instantiation should be performed by using the 
  ##     apCopyNextIndex object.
  ## 2. Specify the protocol to be used for the transfer using the apCopyProtocol
  ##     object.  The default is FTP.  This table does not support copying FROM
  ##     the CS11XXX using HTTP.
  ## 3. Specify the source information with the following objects:
  ##     apCopySourceIpAddress, apCopySourceLocalDirectory, apCopySourceFileName.
  ## 4. Specify the destination information with the following objects:
  ##     apCopyDestIpAddress, apCopyDestLocalDirectory, apCopyDestFileName
  ## 5. Optionally specify credentials required for the transfer using the 
  ##     apCopyCredentialUserName and apCopyCredentialPassword objects.
  ## 5a.Optionally specify the port to use (for HTTP only)
  ## 6. Commence the copy operation using the apCopyControl object
  ## 7. Monitor the copy operation using the apCopyProgress and apCopyBytesTrans-
  ##    ferred objects.
  ## 8. Inspect the completion result using the apCopyFinalStatus object.
  ## 9. Destroy the row through the apCopyStatus object.

  my %oid = (
         ## apCopyNextIndex
         ## integer
         nextindex                => ".1.3.6.1.4.1.2467.1.61.7.0",
   
         ## apCopyIndex
         ## integer
         index                    => ".1.3.6.1.4.1.2467.1.61.2.1.1",

         ## apCopyDirection
         ## integer
         action                   => ".1.3.6.1.4.1.2467.1.61.2.1.2",
      
         ## apCopyProtocol
         ## integer
         protocol                 => ".1.3.6.1.4.1.2467.1.61.2.1.3",

         ## apCopySourceIpAddress
         ## IP Address
         ## only valid when copy direction is to unit
         srcip                    => ".1.3.6.1.4.1.2467.1.61.2.1.6",

         ## apCopySourceLocalDirectory
         ## integer
         ## only valid when copy direction is from unit
         # 1: none(0)
         # 2: script(1)
         # 3: log(2)
         # 4: archive(4)
         # 5: root(5)
         # 6: core(6)
         srcdir                   => ".1.3.6.1.4.1.2467.1.61.2.1.7",

         ## apCopySourceFileName
         ## Octet string
         srcfile                  => ".1.3.6.1.4.1.2467.1.61.2.1.8",

         ## apCopyDestIpAddress
         ## IP Address
         ## only valid when copy direction is from unit
         dstip                    => ".1.3.6.1.4.1.2467.1.61.2.1.9",

         ## apCopyDestLocalDirectory
         ## integer
         ## only valid when copy direction is to unit
         # 1: none(0)
         # 2: script(1)
         # 3: log(2)
         # 4: installed-software(3)
         # 5: archive(4)
         # 6: root(5)
         # 7: core(6) 
         dstdir                   => ".1.3.6.1.4.1.2467.1.61.2.1.10",

         ## apCopyDestFileName
         ## Octet string
         dstfile                  => ".1.3.6.1.4.1.2467.1.61.2.1.11",

         ## apCopyControl
         ## integer
         # 1: none(0)
         # 2: start(1)
         # 3: stop(2)
         copycontrol              => ".1.3.6.1.4.1.2467.1.61.2.1.12",

         ## apCopyProgress
         ## integer
         progress                 => ".1.3.6.1.4.1.2467.1.61.2.1.13",

         ## apCopyFinalStatus
         ## integer
         status                   => ".1.3.6.1.4.1.2467.1.61.2.1.15",

         ## apCopyStatus
         ## integer
         # 4: createAndGo(4)
         # 6: destroy(6)
         copystatus               => ".1.3.6.1.4.1.2467.1.61.2.1.16",

    );

    my %protocol = (
         local                    =>  0,
         tftp                     =>  1,
         ftp                      =>  2,
         http                     =>  3,
    );

    my %state = (
         none                     =>  0,
         'in-progress'            =>  1,
         complete                 =>  2,
         aborted                  =>  3,
    );

    my %cause = (
         success                  =>  0,
         failure                  =>  1,
         'localopen-failure'      =>  2,
         'locallock-failure'      =>  3,
         'connect-failure'        =>  4,
         'reject-failure'         =>  5,
         'notfound-failure'       =>  6,
         'notaccepted-failure'    =>  7,
         'credential-failure'     =>  8,
         aborted                  =>  9,
         none                     =>  99,
    );


    ## determine the mib value for where the file will be sent
    #  0: none
    #  1: from-unit
    #  2: to-unit
    #  3: local
    my ($direction, $src_file, $dst_file);
    if ($args->{src} eq "tftp") { 
       $direction = "2"; 
       $src_file = "$args->{path}/$args->{file}";
       $dst_file = "startup-config";
    } else {
       $direction = "1"; 
       $src_file = "startup-config";
       $dst_file = "$args->{path}/$args->{file}";
    }

    ## set up snmp session parameters
    my $s = $args->{snmp}->create_snmp($args);

    # create the new row in apCopyTable using the nextindex value
    my $next_index = $s->get_request ($oid{nextindex});
    my $index = $next_index->{$oid{nextindex}};

    ## set the new row to createAndGo
    $s->set_request ( "$oid{copystatus}.$index", INTEGER, 4);

    ## set the protocol to tftp
    $s->set_request ( "$oid{protocol}.$index", INTEGER, $protocol{tftp});

    ## set file transfer direction
    $s->set_request ( "$oid{action}.$index", INTEGER, $direction);

    ## set dstdir / srcip when uploading
    if ($args->{src} eq "tftp") {
      $s->set_request( "$oid{dstdir}.$index", INTEGER, 5 );
      $s->set_request ( "$oid{srcip}.$index", IPADDRESS, $args->{tftp} );

    ## set srcdir / dstip when downloading
    } else {
      $s->set_request("$oid{srcdir}.$index", INTEGER, 5);
      $s->set_request ( "$oid{dstip}.$index", IPADDRESS, $args->{tftp});
    }

    ## set the src file
    $s->set_request ( "$oid{srcfile}.$index", OCTET_STRING, $src_file);

    ## set the dst file
    $s->set_request ( "$oid{dstfile}.$index", OCTET_STRING, $dst_file);

    ## grab an error message if it exists
    my $error = $s->error;
    ## put error value into hash
    $args->{err} = $error;

    if ($error && !$SecondTry) {
       $SecondTry = 1;
       goto TOP;
    }

    ## if no error...
    if (!$error) {
      ## kick off copy by setting copycontrol to start
      $s->set_request ( "$oid{copycontrol}.$index", INTEGER, 1 );

      ## check for the results status
      my ($current_state, $result);
      do {
        sleep (1);
        ## get the current status of the tftp server's action
        $current_state = $s->get_request ("$oid{progress}.$index");
        $result = $current_state->{"$oid{progress}.$index"};

      } while ($result == "$state{'in-progress'}");

    ## check for errors
    my $final_status = $s->get_request("$oid{status}.$index");
    my $status = $final_status->{"$oid{status}.$index"};

    ## failure!
    if ($status ne "0") {
      ## add error message into $args hash
      my $problem = (grep { $cause{$_} == $status } keys %cause)[0];
      $args->{err} = "Problem with copy operation. Cause: $problem";
    } ## endif

    ## clear the rowstatus for the remote device
    $s->set_request ("$oid{copystatus}.$index", INTEGER, 6);
    
  } ## endif

  ## close the snmp session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

}

sub arrowpoint_commit {

   my $args = shift;

   $args->{err} = "A CSS does not support a commit.";
   $args->{log}->log_action($args);

}

sub arrowpoint_reload {
  my $args = shift;

  my %oid = (
      ## apSnmpExtReloadConfigVal
      ## integer
      setreload => ".1.3.6.1.4.1.2467.1.22.6.0",
      # set to number between 1 and 2^32 -2 to enable reload via snmp
      # DON'T set to 2^32 -1 since that will allow any number to trigger a reload
      # set to 0 to disable reload

		## apSnmpExtReloadSet
		reload	=> ".1.3.6.1.4.1.2467.1.22.7.0"
      # set to number specified in apSnmpExtReloadConfigVal var to trigger reboot
            );

  ## create reload key
  srand(time | $$);
  my $reload_key = int(rand(900))+10;

  ## start the session
  my $s = $args->{snmp}->create_snmp($args);

  ## set 'key'
  $s->set_request($oid{setreload}, INTEGER, $reload_key);

  ## reload the router
  $s->set_request($oid{reload}, INTEGER, $reload_key);

  ## grab error if exists
  my $error = $s->error;

  ## put error value into hash
  $args->{err} = $error;

  ## close the session
  $s->close;

  ## log output to screen and possibly external file
  $args->{log}->log_action($args);

}


# this must be here or else it won't return true
1;
