# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl SQL-dbh.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN { use_ok('SQL::Audit::dbh') };
require_ok( 'DBI' );

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

ok (
  SQL::Audit::dbh->new(
      host => '127.0.0.1',
      port => 3306,
      user => 'test',
      password => 'xxxxxx',
      charset  => 'utf8',
      driver   => 'mysql',
  ), undef
);

done_testing();
