use strict;
use warnings;
use 5.006;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    NAME              => 'SQL',
    PREREQ_PM         => {
           "DBI" => 0,
           "Log::Dispatch" => 0,
           "Data::Dumper" => 0,
    },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
    (ABSTRACT_FROM  => 'lib/SQL/', # retrieve abstract from module
    AUTHOR          => 'zhe.chen <chenzhe07@gmail.com>') : ()),
    "VERSION"       => '0.0.1',
    "test"          => {
           "TESTS" => "t/*.t"
    }
);
