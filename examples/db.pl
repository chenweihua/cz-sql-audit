#!/usr/bin/env perl

use SQL::Audit::dbh;
use Data::Dumper;
use SQL::Audit::Explain;
use encoding "utf8";
my $dblist = SQL::Audit::dbh->new(
    host => '127.0.0.1',
    port => 3306,
    user => 'test',
    password => 'xxxxxx',
    charset  => 'utf8',
    driver   => 'mysql',
);

my $db_handle = $dblist->get_dbh('test',{AutoCommit => 1});

my $sql = "select * from t2 where name like '第一%'  order by name asc limit 2";

my $x = SQL::Audit::Explain->new();
my $explain = $x->query_explain('dbh'=>$db_handle, 'query'=>$sql);
$explain = $x->query_normalize($explain);
$x->query_index_use('database'=>'test', 'table'=>'t2', 'query'=>$sql, 'explain'=>$explain);
my $mark = $x->query_analyze('explain'=>$explain);
$dblist->disconnect($db_handle);
print "mark: $mark\n";
