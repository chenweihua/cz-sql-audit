# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl SQL-Log-Record.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN { 
    use_ok('SQL::Audit::Log::Record');
    use_ok('Log::Dispatch');
};

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $log = SQL::Audit::Log::Record->new(
    'filename' => './audit.log',
    'mode'     => '>>',
    'screen'   => 1,
);

my @msg;
push @msg, 'master status';
push @msg, 'slave status';

ok ($log->debug(\@msg), qr/status/i);
$log->error("hello world", qr/hello/i);
