## $Id: Log.pm,v 1.6 2003/10/01 14:55:30 cmenzes Exp $
package Pancho::Log;
use strict;

use POSIX qw(strftime);
use Sys::Hostname;
use Fcntl ':flock';


sub new {
   my $self = shift;
   my $ini  = shift;
   my $opts = shift;
   my $log = {
               ini   => $ini,
               opts  => $opts,
              };
   bless $log, $self;
   return $log;
}

#------------------------------------------------------------------------------- 
# log_action
# Logs actions and errors to logfile and screen
# IN : args - hash ref containing various program args
#------------------------------------------------------------------------------- 
sub log_action { 
  my $log = shift;
  my $args = shift;
  ## create the format for log file writes
  my $format = &_log_format($args)
    if ($log->{ini}->val('global','LogFile'));

  ## pull as global for filename comments
  my $user = getlogin || getpwuid($<) || "Unknown";

  my $localhost = hostname();

  my $displaypath = &_log_displaypath($args);

  ## open log file for writing and put cursor at end of file
  if ($log->{ini}->val('global','LogFile')) {

    my $i = $log->{ini}->val('global','LogFile');

    open(FH, ">>$i") or warn 
       "\n\nCan't open file specified for logging.\nPlease check the path specified.\n\n";
    flock(FH,2);
    seek(FH,0,2);

  }

  ## log if error 
  if ($args->{err}) {
    ## log to screen
    print STDERR "\nERROR ($args->{host}): $args->{err}\n\n";
    ## log to screen
    print FH "$format (ERROR) $args->{host} $args->{err}\n"
      if ($log->{ini}->val('global','LogFile'));

  ## log if source is tftp...
  } elsif ($args->{src} eq "tftp") {

    ## ...and destination is run...
    if ($args->{dst} eq "run") {

      ## log to screen
      print "\nSUCCESS: copied $args->{utftp}:$displaypath to $args->{host}:running-config\n\n";
      ## log to external file
      print FH "$format (SUCCESS) copied $args->{utftp}:$displaypath to $args->{host}:running-config by $user on $localhost\n"
        if ($log->{ini}->val('global','LogFile'));
  
    ## ...and destination is start...
    } elsif ($args->{dst} eq "start") {

      ## log to screen
      print "\nSUCCESS: copied $args->{utftp}:$displaypath $args->{host}:startup-config\n\n";
      ## log to external file
      print FH "$format (SUCCESS) copied $args->{utftp}:$displaypath $args->{host}:startup-config by $user on $localhost\n"
        if ($log->{ini}->val('global','LogFile'));
    }

  ## log if source destination is tftp...
  } elsif ($args->{dst} eq "tftp") {

    ## ...and source is run....
    if ($args->{src} eq "run") {

      ## log to screen
      print "\nSUCCESS: copied $args->{host}:running-config to $args->{utftp}:$displaypath\n\n";
      ## log to external file
      print FH "$format (SUCCESS) copied $args->{host}:running-config to $args->{utftp}:$displaypath by $user on $localhost\n"
        if ($log->{ini}->val('global','LogFile'));

    ## ...and source is start...
    } elsif ($args->{src} eq "start") {

      ## log to screen
      print "\nSUCCESS: copied $args->{host}:startup-config to $args->{utftp}:$displaypath\n\n";
      ## log to external file
      print FH "$format (SUCCESS) copied $args->{host}:startup-config to $args->{utftp}:$displaypath by $user on $localhost\n"
        if ($log->{ini}->val('global','LogFile'));

    }

  ## end if for tftp loop
  }

  ## logging if reloading...
  if ($args->{src} eq "reload") {
    if (!$args->{err}) {
      ## log to screen
      print "\nSUCCESS: initialized a reload of $args->{host}.\n\n";
      ## log to external file
      print FH "$format (SUCCESS) initialized reload on $args->{host} by $user on $localhost\n"
        if ($log->{ini}->val('global','LogFile'));
    }
  }

  ## logging if committing...
  if ($args->{src} eq "commit") {
    if (!$args->{err}) {
      ## log to screen
      print "\nSUCCESS: copied $args->{host}:running-config to $args->{host}:startup-config\n\n";
      ## log to external file
      print FH "$format (SUCCESS) copied $args->{host}:running-config to $args->{host}:startup-config by $user on $localhost\n"
        if ($log->{ini}->val('global','LogFile'));
    }
  }

  ## close logging file
  if ($log->{ini}->val('global','LogFile')) {
    flock(FH,8);
    close(FH);
  }

## end log_action
}

#------------------------------------------------------------------------------- 
# _log_format
# This sets the format of the timestamps in the log file
# OUT: format - scalar the contains formatted data
#------------------------------------------------------------------------------- 
sub _log_format {

  my %clock =   (       month   => strftime("%b", localtime),
                        day     => strftime("%d", localtime),
                        time    => strftime("%T [%Z/%z]", localtime),
                );

  my $format = "$clock{month} $clock{day} $clock{time} pancho:";

  return $format;

}

#------------------------------------------------------------------------------- 
# _log_displaypath
# This cleans up the path shown when logging
# OUT: displaypath - scalar containing cleaned up path
#------------------------------------------------------------------------------- 
sub _log_displaypath {
  my $args = shift;

  my $displaypath = "$args->{path}/$args->{file}";

  ## get rid of the leading slash
  if (substr($displaypath,0,1) eq "/") {
    $displaypath = reverse("$displaypath");
    chop $displaypath;
    $displaypath = reverse("$displaypath");
  }

  return $displaypath;

}

1;
