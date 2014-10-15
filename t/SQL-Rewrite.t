# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl SQL-Rewrite.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 4;
BEGIN { use_ok('SQL::Rewrite') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $sql = 'delete from user where id > 100';
my $ob = SQL::Rewrite->new();

ok ($ob->convert_to_select($sql), 'select * from user where id > 100');
ok ($ob->short_query($sql, 20), 'select * from user where id > 100');
ok ($ob->cut_comment($sql), 'delete from user where id > 100');

done_testing();
