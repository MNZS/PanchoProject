## $Id: Snmp.pm,v 1.4 2004/05/21 15:39:58 cmenzes Exp $
package Pancho::Snmp;
use strict;

use Net::SNMP;

sub new {
   my $self = shift;
   my $ini  = shift;
   my $opts = shift;
   my $snmp = {
               ini   => $ini,
               opts  => $opts,
              };
   bless $snmp, $self;
   return $snmp;
}

#------------------------------------------------------------------------------- 
# create_snmp
# set up an snmp session based on selected options specific to 
# the snmp version
# IN : args - hash ref containing various program args
# OUT: snmp session - snmp session object set with proper params
#------------------------------------------------------------------------------- 
sub create_snmp {
  my $snmp = shift;
  my $args = shift;

  ## create the hash of version independent options to pass to the method
  my %snmp_options = ();

  ## define the host
  $snmp_options{hostname} = $args->{node};

  ## select the version of snmp to be used
  $snmp_options{version} = $snmp->{opts}->{'snmp-version'} || 
                           $snmp->{ini}->val($args->{host},'SnmpVersion') ||
                           '1';

  ## number of retries
  $snmp_options{retries} = $snmp->{opts}->{'snmp-retry'} || 
                           $snmp->{ini}->val($args->{host},'SnmpRetries') || 
                           '1';

  ## set the timeout
  $snmp_options{timeout} = $snmp->{opts}->{'snmp-wait'} || 
                           $snmp->{ini}->val($args->{host},'SnmpWait') ||
                           '5.0';

  ## set the mtu
  $snmp_options{maxmsgsize} = $snmp->{opts}->{'snmp-mtu'} || 
                              $snmp->{ini}->val($args->{host},'SnmpMtu') ||
                              '1500';

  ## turn on/off debug in the net::snmp module
  $snmp_options{debug} = $snmp->{ini}->val($args->{host},'SnmpDebug') || '0';
 
  ## declare our variable to be set and returned
  my $new_session;

  ## test for snmpv3 usage
  if ( $snmp_options{version} eq '3' ) {

    ## snmp user name
    if ( $snmp->{opts}->{'snmp-user'} ||
         $snmp->{ini}->val($args->{host},'SnmpUsername') ) {

      $snmp_options{username} =  
        $snmp->{opts}->{'snmp-user'} ||
        $snmp->{ini}->val($args->{host},'SnmpUsername') ||
        '';

    }

    ## snmp auth key
    if ( $snmp->{opts}->{'snmp-authkey'} ||
         $snmp->{ini}->val($args->{host},'SnmpAuthKey') ) {

      $snmp_options{authkey} =
        $snmp->{opts}->{'snmp-authkey'} ||
        $snmp->{ini}->val($args->{host},'SnmpAuthKey') ||
        '';
  
    }

    ## snmp auth password
    if ( $snmp->{opts}->{'snmp-authpasswd'} ||
         $snmp->{ini}->val($args->{host},'SnmpAuthPassword') ) {

      $snmp_options{authpassword} = 
        $snmp->{opts}->{'snmp-authpasswd'} ||
        $snmp->{ini}->val($args->{host},'SnmpAuthPassword') ||
        '';

    }

    ## snmp auth protocol
    if ( $snmp->{opts}->{'snmp-authprotocol'} ||
         $snmp->{ini}->val($args->{host},'SnmpAuthProtocol') ) {

      $snmp_options{authprotocol} =
        $snmp->{opts}->{'snmp-authprotocol'} ||
        $snmp->{ini}->val($args->{host},'SnmpAuthProtocol') ||
        '';

    }

    ## snmp priv protocol
    if ( $snmp->{opts}->{'snmp-privprotocol'} ||
         $snmp->{ini}->val($args->{host},'SnmpPrivProtocol') ) {

      $snmp_options{privprotocol} =
        $snmp->{opts}->{'snmp-privprotocol'} ||
        $snmp->{ini}->val($args->{host},'SnmpPrivProtocol') ||
        '';

    }

    ## snmp priv key
    if ( $snmp->{opts}->{'snmp-privkey'} ||
         $snmp->{ini}->val($args->{host},'SnmpPrivKey') ) {

      $snmp_options{privkey} =
        $snmp->{opts}->{'snmp-privkey'} ||
        $snmp->{ini}->val($args->{host},'SnmpPrivKey') ||
        '';

    }

    ## snmp priv password
    if ( $snmp->{opts}->{'snmp-privpasswd'} ||
         $snmp->{ini}->val($args->{host},'SnmpPrivPassword') ) {

      $snmp_options{privpassword} =
        $snmp->{opts}->{'snmp-privpasswd'} ||
        $snmp->{ini}->val($args->{host},'SnmpPrivPassword') ||
        '';

    }

    ## initiate session with v3 values
    $new_session = Net::SNMP->session(%snmp_options);

  } else {

    ## set the v1/2c specific session traits
    $snmp_options{community} = $snmp->{opts}->{'snmp-community'} ||
                               $snmp->{ini}->val($args->{host},'SnmpCommunity');

    ## initiate session with v1/2c values
    $new_session = Net::SNMP->session(%snmp_options);
    
  }

  ## provide our new session information to our ios specific subroutine
  return $new_session;

## end create_snmp()
}

1;
