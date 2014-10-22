use strict;
use warnings;
use 5.006;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    NAME              => 'SQL::Audit',
    VERSION_FROM      => 'lib/SQL/Audit.pm',
    PREREQ_PM         => {
           "DBI" => 0,
           "DBD::mysql"    => 0,
           "Log::Dispatch" => 0,
           "Authen::SASL"  => 0,
    },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
    (ABSTRACT_FROM  => 'lib/SQL/Audit.pm', # retrieve abstract from module
    AUTHOR          => 'zhe.chen <chenzhe07@gmail.com>') : ()),
    "VERSION"       => '0.1.0',
    "test"          => {
           "TESTS" => "t/*.t"
    }
);
