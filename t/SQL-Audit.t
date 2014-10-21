# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl SQL-Explain.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 2;
BEGIN { 
    use_ok('SQL::Audit');
};

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $sql = 'delete from user where id > 100';
my $ob = SQL::Audit->new();

my $query = $ob->sql_rewrite($sql);

ok ($query, qr/select * from user where id > 100/i);

done_testing();
