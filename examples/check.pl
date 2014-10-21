#!/usr/bin/env perl

use SQL::Audit::dbh;
use Data::Dumper;
use SQL::Audit::Check qw(_nondeter_clause _unsafe_parse _function_in_filter);
use SQL::Audit::Log::Record;
use encoding "utf8";
my $dblist = SQL::Audit::dbh->new(
    host => '127.0.0.1',
    port => 3306,
    user => 'test',
    password => 'xxxxxx',
    charset  => 'utf8',
    driver   => 'mysql',
);

my $log = SQL::Audit::Log::Record->new(
    'file' => './log/audit.log',
    'mode'     => '>>',
    'screen'   => 1,
);

my $db_handle = $dblist->get_dbh('test',{AutoCommit => 1});

#my $sql = 'select * from t2 where cur_time = rand()';
#my $sql = "select * from t2 where name like '第一%'  order by chapter_name asc limit 2";
#my $sql = "insert into t2 select * from t3 where chapter id > 100";
my $sql = "select * from t2 where name like '%rzs%'";
my @message;
push @message, "Query: $sql";
my $x = SQL::Audit::Check->new();
if ( $x->check_table('dbh'=>$db_handle, 'table'=>'t2') ) {
   push @message, $x->get_recommend($sql);
   my $row = $x->get_table_status($db_handle, 't2');
   push @message, "Rows: ". $row->{Rows};
   my $engine = $x->get_engine($db_handle, 't2');
   push @message, "Engine: $engine";
}


$log->notice(\@message);
