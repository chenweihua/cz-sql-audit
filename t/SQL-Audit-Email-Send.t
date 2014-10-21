# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl SQL-Log-Record.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 2;
BEGIN { 
    use_ok('SQL::Audit::Email::Send');
};

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use SQL::Audit::Email::Send;
my @mail = ('chenzhe07@gmail.com');
my $smtp = SQL::Audit::Email::Send->new(
    subject  => 'SQL audit message.',
    mailto   => \@mail,
    mailfrom => 'sql_audit@pwrd.com',
);

my @msg;
push @msg, 'mail test';
push @msg, 'warnings query.';
$smtp->send( @msg );

ok ($smtp->send( @msg ), 1);
