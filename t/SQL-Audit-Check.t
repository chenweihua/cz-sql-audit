# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl SQL-Check.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 7;
BEGIN { 
    use_ok('SQL::Audit::dbh');
    use_ok('SQL::Audit::Check');
};

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $sql1 = 'select * from t2';
my $sql2 = 'insert into t select * from t2';
my $sql3 = 'select * from t2 where cur_time = now()';
my $sql4 = 'select * from t2 order by rand()';
my $sql5 = 'update t2 set name = uuid() where id = 100';

my $x = SQL::Audit::Check->new();

ok( $x->get_recommend($sql1), qr/no where/i );
ok( $x->get_recommend($sql2), qr/deterministic/i );
ok( $x->get_recommend($sql3), qr/unsafe/i );
ok( $x->get_recommend($sql4), qr/function/i );
ok( $x->get_recommend($sql5), qr/unsafe/i );

done_testing();

