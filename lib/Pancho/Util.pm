## $Id: Util.pm,v 1.20 2005/02/23 15:24:23 cmenzes Exp $
package Pancho::Util;
use strict;

use POSIX qw(strftime);
use Socket;
use FindBin;

sub new {
   my $self = shift;
   my $ini  = shift;
   my $opts = shift;
   my $util = {
               ini   => $ini,
               opts  => $opts,
               plugins => _process_plugins($ini->val('global','PluginDir')),
              };
   bless $util, $self;
   return $util;
}

#------------------------------------------------------------------------------- 
# find_plugin
# Given a device type and list of modules this will
# find the module that says it can handle the given 
# device.
# IN : device - device to look for
# OUT: the module name or 0 if none were found
#------------------------------------------------------------------------------- 
sub find_plugin {
   my $self    = shift;
   my $device  = shift;
   foreach my $mod (@{$self->{plugins}}) {
      my $devices = $mod->device_types();
      if (grep { $device =~ m/$_/gi } @$devices) {
         return $mod;
      }
   }
   return 0;
}

#------------------------------------------------------------------------------- 
# _process_plugins
# Process files in plugin directory and look for valid plugins
# IN : dir - location of plugin directory
# OUT: array containing list of modules that are valid for use
#------------------------------------------------------------------------------- 
sub _process_plugins {
   my $dir = shift;
   my @modules;
   ## read system installed plugins
   my $found = 0;
   foreach my $inc (@INC) {
      # if we already processed a directory then skip
      # the rest
      last if ($found);
      if (-e "$inc/Pancho") {
         $found = 1;
         foreach (<$inc/Pancho/Plugins/*.pm>) {
            eval {
               require $_;
            };
            if ($@) {
               print STDERR "Cannot load plugin $_. Cause $@\n";
               next;
            } else {
               $_ =~ m|^.*/(\w+)\.pm$|;
               my $mod = $1;
               $mod = "Pancho::$mod";
               if (defined $mod->device_types()) {
                  push(@modules,$mod);
               }
            }
         }
      }
   }
   ## read user defined directories here
   if ($dir && -e $dir) {
      foreach (<$dir/*.pm>) {
         eval {
            require $_;
         };
         if ($@) {
            print STDERR "Cannot load plugin $_. Cause $@\n";
            next;
         } else {
            $_ =~ m|^.*/(\w+)\.pm$|;
            my $mod = $1;
            $mod = "Pancho::$mod";
            if (defined $mod->device_types()) {
               push(@modules,$mod);
            }
         }
      }
   }
   return \@modules;
}

#-------------------------------------------------------------------------------
# discover_host_address
# Find the host address of the remote device
# IN : args - hash ref containing various program args
# OUT: hostname or 0
#------------------------------------------------------------------------------- 
sub discover_host_address {
  my $self = shift;
  my $args = shift;

  my $node = gethostbyname($args->{host});

  return 0 if (!$node);

  $node = inet_ntoa($node);

  return $node;
}

#------------------------------------------------------------------------------- 
# set_params
# Sets up the proper params
# IN : args - hash ref containing various program args
#      opts - hash ref of options passed into program
# OUT: N/A
#------------------------------------------------------------------------------- 
sub set_params {
   my $util = shift;
   my $args = shift;
   my $opts = shift;
   _set_tftp_params($args,$util->{ini},$opts);
   _set_file_params($args,$util->{ini},$opts);
   _set_path_params($args,$util->{ini},$opts);
   _set_transfer_params($args,$opts);
}

#-------------------------------------------------------------------------------
# _set_tftp_params
# Sets up the proper tftp params
# IN : args - hash ref containing various program args
#      ini  - object ref for ini object
#      opts - options passed to program via cmd line
# OUT: hostname or 0
#------------------------------------------------------------------------------- 
sub _set_tftp_params {
  my $args = shift;
  my $ini  = shift;
  my $opts = shift;

  ## declare a varible for the unresolved tftp server name
  $args->{utftp} = $opts->{tftpserver} || $ini->val($args->{host},'TftpServer');

  ## resolve fqdn/hostname for tftpserver
  if (!$args->{utftp}) {
    $args->{err} = "A TFTP Server was not specified for $args->{host}";
    $args->{log}->log_action($args);
    return 1;

  } elsif ($args->{utftp} =~ /[a-zA-Z]/) {

    ## resolve the fqdn and set to a hash value
    my $i = gethostbyname($args->{utftp});

    ## if the tftp server does not resolve, log action and drop out
    if ( !$i ) {

      $args->{err} = "The TFTP Server could not be resolved : $args->{utftp}";

      ## log the error
      $args->{log}->log_action($args);

      return 1;

    } else {

      $args->{tftp} = inet_ntoa($i);

    }

  } else {

    $args->{tftp} = $args->{utftp};

  }
}

sub _set_file_params {
  my $args = shift;
  my $ini  = shift;
  my $opts = shift;

  ## set value of filename on tftpserver
  if ($opts->{filename}) {
    $args->{file} = $opts->{filename};

  ## check for specific style for filename
  } elsif ( ($ini->val($args->{host},'StylePattern')) && 
	    ($opts->{download}) ||
	    ($opts->{upload}) ) {

    ## date needs to be set
    my $date = _set_date($ini,$args);

    ## set our provided style pattern to our file to be passed
    $args->{file} = $ini->val($args->{host},'StylePattern')
                 || "$args->{host}.cfg";

    $args->{file} =~ s/::HOST::/$args->{host}/g;
    $args->{file} =~ s/::NICK::/$args->{nick}/g;
    $args->{file} =~ s/::NODE::/$args->{node}/g;
    $args->{file} =~ s/::IPADDRESS::/$args->{node}/g;
    $args->{file} =~ s/::DATE::/$date/g;

  } else {

    if ($args->{nick}) {
      $args->{file} = "$args->{nick}.cfg";
    } else {
      $args->{file} = "$args->{host}.cfg";
    }

  }

}

sub _set_path_params {
  my $args = shift;
  my $ini = shift;
  my $opts = shift;

  if ($opts->{download} || $opts->{upload}) {
  ## determine the path within the tftproot
  $args->{path} = $opts->{path}
               || $ini->val($args->{host},'TftpPath')
               || "";
  $args->{path} =~ s/::HOST::/$args->{host}/g;
  $args->{path} =~ s/::NICK::/$args->{nick}/g;
  $args->{path} =~ s/::NODE::/$args->{node}/g;
  $args->{path} =~ s/::IPADDRESS::/$args->{node}/g;
  ## date needs to be set
  my $date = _set_date($ini,$args);
  $args->{path} =~ s/::DATE::/$date/g;
  }

}

sub _set_transfer_params {
  my $args = shift;
  my $opts = shift;

  if ($opts->{upload}) {

    if ($opts->{start}) {
      $args->{src} = 'tftp';
      $args->{dst} = 'start';

    } else {
      $args->{src} = 'tftp';
      $args->{dst} = 'run';

    }

  } elsif ($opts->{download}) {
 
    if ($opts->{start}) {
      $args->{src} = 'start';
      $args->{dst} = 'tftp';

    } else {
      $args->{src} = 'run';
      $args->{dst} = 'tftp';

    }
  }

}

sub _set_date {
  my $ini  = shift;
  my $args = shift;
  my $date_pattern = $ini->val($args->{host},'StyleDate')
                  || '%Y%m%d';

  my $date = strftime("$date_pattern",localtime);
  return $date;
}

#-------------------------------------------------------------------------------
# pre_process - runs commands before action is done
# IN : args - hash ref containing various program args
# OUT:  returns 0 if the post command ran successfully
#      and 1 if it failed    
#------------------------------------------------------------------------------- 
sub pre_process {
   my $self = shift;
   my $args = shift;
   # set up the command to run
   my $cmd = $self->{ini}->val($args->{host},'Pre')
                 || $self->{ini}->val('global','Pre')
                 || '';
   # set cmd to cli arg if it exists and isn't 1
   $cmd = $self->{opts}->{pre} if ($self->{opts}->{pre} && $self->{opts}->{pre} ne 1);

   return if (($cmd eq '') || (not $self->{opts}->{pre}));

   my $date_pattern = $self->{ini}->val($args->{host},'StyleDate')
                   || $self->{ini}->val('global','StyleDate')
                   || '%Y%m%d';
   my $date = strftime("$date_pattern",localtime);
   my $fullpath = $self->{ini}->val('global','tftproot')."/$args->{path}";
   $fullpath =~ s|//|/|g;
   # fill any place holders in with their corresponding 
   # values
   $cmd =~ s/::HOST::/$args->{host}/g;
   $cmd =~ s/::NICK::/$args->{nick}/g;
   $cmd =~ s/::NODE::/$args->{node}/g;
   $cmd =~ s/::IPADDRESS::/$args->{node}/g;
   $cmd =~ s/::DATE::/$date/g;
   $cmd =~ s/::FULLPATH::/$fullpath/g;
   $cmd =~ s/::FILENAME::/$args->{file}/g;
                                                                                                                                    
   my $status = system($cmd);
   # log an error if necessary
   if ($status) {  
      $args->{err} = "Pre process \'$cmd\' failed for $args->{host}. Not processing host.";
      $args->{log}->log_action($args);
   }  
   return $status == 0 ? 0 : 1;
} 

#-------------------------------------------------------------------------------
# post_process - runs commands after action is done
# IN : args - hash ref containing various program args
# OUT:  returns 0 if the post command ran successfully
#      and 1 if it failed    
#------------------------------------------------------------------------------- 
sub post_process {
   my $self = shift;
   my $args = shift;
   # set up the command to run   
   my $cmd = $self->{ini}->val($args->{host},'Post')
                 || $self->{ini}->val('global','Post')
                 || '';                   
   # set cmd to cli arg if it exists and isn't 1
   $cmd = $self->{opts}->{post} if ($self->{opts}->{post} && $self->{opts}->{post} ne 1);

   return if (($cmd eq '') || (not $self->{opts}->{post}));

   # check for errors on host process
   # and bail if they exist
   if ($args->{err} ne "") {
      $args->{err} = "Not running post process because $args->{host} had errors.";
      $args->{log}->log_action($args);
      return 1;
   }

   my $date_pattern = $self->{ini}->val($args->{host},'StyleDate')
                   || $self->{ini}->val('global','StyleDate') 
                   || '%Y%m%d';
   my $date = strftime("$date_pattern",localtime);
   my $fullpath = $self->{ini}->val('global','tftproot')."/$args->{path}";
   $fullpath =~ s|//|/|g;
   # fill any place holders in with their corresponding 
   # values                                            
   $cmd =~ s/::HOST::/$args->{host}/g;
   $cmd =~ s/::NICK::/$args->{nick}/g;
   $cmd =~ s/::NODE::/$args->{node}/g;
   $cmd =~ s/::IPADDRESS::/$args->{node}/g;
   $cmd =~ s/::DATE::/$date/g;
   $cmd =~ s/::FULLPATH::/$fullpath/g;
   $cmd =~ s/::FILENAME::/$args->{file}/g;

   my $status = system($cmd);
   # log an error if necessary
   if ($status) { 
      $args->{err} = "Post process \'$cmd\' failed for $args->{host}.";
      $args->{log}->log_action($args);
   }
   return $status == 0 ? 0 : 1;
}          

1;
