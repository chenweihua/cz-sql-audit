#!/usr/bin/env perl

use SQL::Audit::Rewrite;

#my $sql = 'update t1 set num = 1002, name = "list", chaps = 100 where id = 1003';
my $sql = 'delete from t1 where id in (1003, 1004, 1005, 1006, 2, 5, 1, 7, 9, 4, 42, 33, 333, 456, 86, 71, 81, 90, 91, 98, 10001, 20001, 30001, 51)';
#my $sql = 'insert into t1 select /*321224 */ * from book_list limit 2';
#my $sql = 'delete from t1 where id > 100';
my $ob = SQL::Audit::Rewrite->new();
my $query = $ob->short_query($sql, 20);
my $query = $ob->convert_to_select($query);
print "Q: $query\n";
