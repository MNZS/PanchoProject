use ExtUtils::MakeMaker;

# whether or not to prompt the user for missing and out of date modules
# defaults to yes
my $NOASK = 1;

# does the user want to run pancho in the old style
# as a stand alone program
my $ALONE = 0;

# we need these to run pancho
$DEPS = {
   'Net::SNMP'             => '4.0.3',
   'Config::IniFiles'      => '2.30',
   'Parallel::ForkManager' => '0.7.4',
};

# this whole thing is just so MakeMaker doesn't gripe
# about an unknown arg
my @new_args;
foreach (@ARGV) {
   if (/^CONFDIR=(.+)/) {
      $CONFDIR = $1;
      # set this so we can easily refer to it in the following subs
      $MY::CONFDIR = $CONFDIR;
   } elsif (/^ALONE/i) {
      $ALONE = 1;
   } elsif (/^NOASK/i) {
      $NOASK = 0;
   } else {
      push(@new_args,$_);
   }
}
# if we aren't on a win32 system 
# and the user specified a PREFIX but not INSTALLSCRIPT
# then set it to PREFIX/bin
# otherwise if not on win32 and no INSTALLSCRIPT set it to /usr/local/bin
if ($^O !~ m/win/i && (grep(/PREFIX/,@ARGV) && not grep(/INSTALLSCRIPT/,@ARGV))) {
   push(@new_args,'INSTALLSCRIPT=$(PREFIX)/bin');
} elsif ($^O !~ m/win/i && not grep(/INSTALLSCRIPT/,@ARGV)) {
   push(@new_args,'INSTALLSCRIPT=/usr/local/bin');
}
@ARGV = @new_args;

if ($ALONE) {
   print "Configuring Pancho for standalone use.\n";
} else {
   if ($^O =~ m/win/i) {
      print "\nYou have chosen to do a full install of Pancho on Windows.\n";
      print "For this to work you must have nmake or an alternative 'make' program.\n\n";
   } 
   print "Configuring Pancho.\n";
}

my @missing_mods;
my @upgrade_mods;
# check for modules
foreach my $mod (keys %$DEPS) {
   my $eval = "require $mod";
   eval $eval;
   if ($@) {
      push (@missing_mods, $mod);
   }
   elsif ($mod->VERSION < $DEPS->{$mod}) {
      push (@upgrade_mods, $mod);
   }
}

if ($NOASK) {
   installMods(\@missing_mods, 'missing');
   installMods(\@upgrade_mods, 'upgrade');
}

if ($ALONE) {
   system("perl build_pancho.PL ALONE");
   system("perl build_config.PL ALONE");
   if ($^O !~ m/win/i) {
      system("chmod 755 pancho");
   }
   system("perl -MExtUtils::MakeMaker -e \"MY->fixin(shift)\" pancho");
   print "Pancho is now ready for use. Please edit pancho.conf for your use.\n\n";
   exit;
}


# override constants in order to add the conf dir
sub MY::constants {
   package MY;
   my $inherited = shift->SUPER::constants(@_);

   my $used_prefix = grep(/PREFIX/,@ARGV);
   # define etc dir
   # this will be one of the following:
   # * PREFIX/etc if user specified a prefix
   # * just CONFDIR if user specified confdir
   # * PREFIX/etc if the platform is windows
   # * the default is /usr/local/etc 
   if ($CONFDIR) {
      $inherited .= "\nSYS_CONFDIR = $CONFDIR\n";
   } elsif ($used_prefix) {
      $inherited .= "\nSYS_CONFDIR = \$(PREFIX)/etc\n";
   } elsif ($^O =~ m/win/i) {
      $inherited .= "\nSYS_CONFDIR = \$(PREFIX)/etc\n";
   } else {
      $inherited .= "\nSYS_CONFDIR = /usr/local/etc\n";
   }

   $inherited;
}

# override install in order to create conf dir and copy config
sub MY::install {
    package MY;
    my $inherited = shift->SUPER::install(@_);

    # commands to actually create and copy the files
    my $mkdir = "\t\$(MKPATH) \$(SYS_CONFDIR)\n";

    my $copy  = "\t\@ if [ -f \"\$(SYS_CONFDIR)/pancho.conf\" ]; then \\\n"; 
    $copy    .= "\t\techo;\\\n\t\techo Not copying configuration file.  One already exists.;\\\n\t\techo;\\\n";
    $copy    .= "\telse \\\n";
    $copy    .= "\t\t\$(CP) pancho.conf \$(SYS_CONFDIR);\\\n";
    $copy    .= "\t\techo;\\\n\t\techo Configuration file has been installed into \$(SYS_CONFDIR);\\\n\t\techo;\\\n";
    $copy    .= "\tfi\n";

    # add copy of config file into SYS_CONFDIR
    $inherited =~ s|(^install\s*::.*)|$1\n$mkdir$copy|m;
    
    $inherited;
}

# override realclean to remove pancho and pancho.conf
sub MY::realclean {
    package MY;
    my $inherited = shift->SUPER::realclean(@_);

    # commands to remove the files from build directory
    my $rm1 = "\t\$(RM_F) pancho.conf\n";
    my $rm2 = "\t\$(RM_F) pancho";

    # add copy of config file into SYS_CONFDIR
    $inherited =~ s|(^realclean purge\s*::.*)|$1\n$rm1$rm2|m;
    
    $inherited;
}

# override processPL in order to pass args to our filter program
sub MY::processPL {
    package MY;
    my $inherited = shift->SUPER::processPL(@_);

    # Add Makefile as a dependancy of pancho
    $inherited =~ s|(^pancho ::)\s*|$1 Makefile |m 
      or die "no target for pancho in: $inherited";
    
    # Pass an extra argument to filter.PL
    my $args = "CONFDIR=\$(SYS_CONFDIR) ";
    $args .= "LIB=\$(INSTALLSITELIB) " if (grep(/PREFIX/,@ARGV) || grep(/LIB/,@ARGV));
    $inherited =~ s|(^\s+\$\(PERL.*\s+build_pancho.PL).*$|$1 $args\n|m
      or die "no call to build_pancho.PL in: $inherited";

    $inherited;
}

WriteMakefile(
    'NAME'         => 'Pancho',
#    'PREREQ_PM'    => $DEPS,
    'VERSION_FROM' => 'pancho.in',
    'AUTHOR'       => 'Charles Menzes <charles@lunarmedia.net>',
    'EXE_FILES'    => [ 'pancho' ],
    'PL_FILES'     => {'build_pancho.PL' => 'pancho', 'build_config.PL' => 'pancho.conf'},
);

sub installMods {
   my $mods   = shift;
   my $type   = shift;
   my $install = 0;
   if (@$mods) {
      if ($^O =~ m/win/i) {
         print "\nThe following Perl modules are missing or are out of date.\n";
         print "You must install them before Pancho will run.\n\n";
         foreach my $mod (@$mods) {
            print "$mod\n";
         }
         print "\n";
         return;
      }
      if ($type eq 'upgrade') { 
         print "Some required modules appear to be out of date.  Would you like to update them now? ";
      } else {
         print "You are missing some required modules.  Would you like to install them now? ";
      }
      $install = <STDIN>;
      chomp($install);
   }
   if ($install =~ /y/i) {
      my $pass_argv = 0;
      if (@ARGV) {
         print "Would you like to install the modules using the same parameters you specified for Pancho? ";
         $pass_argv = <STDIN>;
         chomp($pass_argv);
      }
      foreach my $mod (@$mods) {
         my $pid = fork;
         warn "fork failed: $!" unless defined $pid;
         if (not $pid) {
            my $mod_dir = $mod;
            $mod_dir =~ s/::/-/;
            $mod_dir .= "-" . $DEPS->{$mod};
            ## command needs to cd to proper directory
            ## and then execute perl Makefile.PL and make install
            my $command = "cd modules/$mod_dir; perl Makefile.PL ";
            $command .= join (" ", @ARGV) if ($pass_argv =~ /y/i);
            $command .= "; make install";
            exec($command);
         } else {
            wait();
         }
      }
   }
}
