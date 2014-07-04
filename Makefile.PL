use 5.014002;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'MBclient',
    VERSION_FROM      => 'lib/MBclient.pm', # finds $VERSION
    LICENSE           => 'MIT',
    MIN_PERL_VERSION  => '5.006_001',
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/MBclient.pm', # retrieve abstract from module
       AUTHOR         => 'Lefebvre Loic <lle@cpan.org>') : ()),
);
