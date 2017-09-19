## This script creates a default config file that make install
## will copy into the sys_confdir
## the config is at the end of this file and we simply read through it
## and modify a few things like tftpserver to guessed values
use Sys::Hostname;

my $alone = shift @ARGV;
if ($alone && -e "pancho.conf") {
   print "Config file exists. Skipping config file creation.\n";
   exit;
}

my $host = hostname;

open(CONFIG,">pancho.conf");
while (<DATA>) {
   if ($_ =~ /^TftpServer=/) {
      print CONFIG "TftpServer=$host\n";
   } elsif ($_ =~ /^TftpRoot=/) {
      if (-e '/tftpboot') {
         print CONFIG $_;
      } else {
         print CONFIG "# $_";
      }
   } else {
      print CONFIG $_;
   }
   
}
close (CONFIG);


__DATA__
# A single hash mark beginning a line should be considered a comment

# global parameters affect all nodes. 
# globals may be superceded by the same options appearing under a
#  specific node.

[global]

# sets the server where configs should be read and written
# may be either a hostname or ip address
TftpServer=

# sets the tftproot directory used in pre/post commands
TftpRoot=/tftpboot

# set the logfile location.
# removing this option disables logging.
#LogFile=/var/log/pancho

# set the maximum number of forked processes ran simultaneously
ForkLimit=5

# the default filename read or written for a devices takes the format
# of <hostname>.cfg
# the Style option allows you to set an alternative format. the keywords
# ::HOST:: and ::DATE:: are substituted with the respective information.
# the StyleDate option allows you to specify a string (man date) that will
# be used for the ::DATE:: substitution. These options may be specified
# globally or locally.
#StylePattern=::HOST::.::DATE::-confg
StylePattern=::HOST::-confg
StyleDate=%Y%m%d

# sets snmp options
SnmpVersion=1
SnmpRetries=1
SnmpWait=5.0
SnmpMtu=1500
SnmpDebug=0
SnmpCommunity=private

