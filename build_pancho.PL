## this script reads pancho.in and creates pancho
## it expects the lib dir and the confdir to be passed as cmd line 
## or alone to be passed
## arguments
foreach (@ARGV) {
   if (/^CONFDIR=(.+)/) {
      $CONFDIR = $1;
   } elsif (/^LIB=(.+)/) {
      $LIB = $1;
   } elsif (/^ALONE/) {
      $ALONE = 1;
   }
}

open(IN,"<pancho.in");
open(OUT,">pancho");
while(<IN>) {
   if ($_ eq "## CUSTOM LIB ##\n") {
      if ($ALONE) {
         print OUT "use FindBin;\n";
         print OUT "use lib \"\$FindBin::Bin/lib\";\n";
      } else {
         if ($LIB) {
            $LIB =~ s|//|/|g;
            print OUT "use lib \"$LIB\";\n";
         } 
      }
   } elsif ($_ eq "## CONFIG FILE ##\n") {
      if ($ALONE) {
         print OUT "my \$config_file = \"\$FindBin::Bin/pancho.conf\";\n";
      } else {
         my $config_line = "my \$config_file = \"$CONFDIR/pancho.conf\";\n";
         # remove any double slashes
         $config_line =~ s|//|/|g;
         print OUT $config_line;
      }
   } else {
      print OUT $_;
   }
}
close(IN);
close(OUT);
