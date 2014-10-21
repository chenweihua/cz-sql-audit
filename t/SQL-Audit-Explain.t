# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl SQL-Explain.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN { 
    use_ok('SQL::Audit::Explain');
    use_ok('SQL::Audit::Rewrite');
};

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $sql = 'delete from user where id > 100';
my $ob = SQL::Audit::Rewrite->new();

my $query = $ob->convert_to_select($sql);
my $eo = SQL::Audit::Explain->new();

sub explain {
    my $query = shift;
    if( $query =~ m/^\s*(?:update|delete|insert)/i ) {
        warn "Cannot explain non-select sql as the MySQL version prior 5.6: $query\n";
        return;
    }
    
    #print "$query\n";
    $query = "EXPLAIN $query" if $query !~ m/^\s*explain/i;
}

ok (explain($query), qr/explain select * from user where id > 100/i);

done_testing();
