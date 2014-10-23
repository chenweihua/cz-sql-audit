package SQL::Audit::Check;
# Two parts consists the check module: check table and check query.
# the table status (no rows in table, table not exists, table status etc..) is
# necessary to check because of developer maybe spell mistake the table name;
# And the query should be checked so that we can avoid some unsafe clause or
# unsafe functions.
# zhe.chen<chenzhe07@gmail.com>, date: 2014-10-13

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

require Exporter;
@ISA = qw(Exporter);
@EXPORT    = qw( check_table get_engine get_table_status get_recommend);
@EXPORT_OK = qw( _nondeter_clause _unsafe_parse _function_in_filter);
$VERSION = '0.1.0';

sub new {
    my ( $class, %args ) = @_; 
    my $self = { };
    return bless $self, $class;
}

# check table weather is avalible or not.
sub check_table {
   my ( $self, %args )  = @_;

   foreach my $arg ( qw(dbh table) ) {
       warn "Need $arg argument. use \'$arg\' specified." unless $args{$arg};
   }

   my ($dbh, $table) = @args{qw(dbh table)};

   my $sql = "SHOW TABLES LIKE \'$table\'";
   my $row;
   eval {
       $row = $dbh->selectrow_arrayref($sql);
   };

   if ( $@ || !defined $row ) {
       PTDEBUG && _debug($@);
       return 0;
   } 

   PTDEBUG && _debug('Table exists; no privs to check');
   return 1 unless $args{all_privs};

   $sql = "SHOW FULL COLUMNS FROM $table";
   PTDEBUG && _debug($sql);

   eval {
       $row = $dbh->selectrow_hashref($sql);
   };
   if ( $@ ) {
       PTDEBUG && _debug($@);
       return 0;
   }

   if ( !scalar keys %$row ) {
       PTDEBUG && _debug('Table has no columns:', Dumper($row));
       return 0;
   }

   my $privs = $row->{privileges} || $row->{Privileges};

   $sql = "DELETE FROM $table LIMIT 0";
   PTDEBUG && _debug($sql);
   eval {
       $dbh->do($sql);
   };

   my $can_delete = $@ ? 0 : 1;
   PTDEBUG && _debug('User privs on', $table, ':', $privs, ($can_delete ? 'delete' : ''));

   if ( !($privs =~ m/(?:select|insert|update)/ && $can_delete) ) {
       PTDEBUG && _debug('User does not have all privs');
       return 0;
   }

   PTDEBUG && _debug('User has all privs');
   return 1;
}

sub get_engine {
   my ($self, $dbh, $table) = @_;
    
   foreach my $arg ( qw($dbh $table) ) {
       warn "Need $arg argument." unless $arg;
   }

   my $sql = "SHOW CREATE TABLE $table";
   my $row;
   eval {
       $row = $dbh->selectrow_hashref($sql);
   };

   if ( $@ ) {
       PTDEBUG && _debug($@);
       return;
   }

   my ( $engine ) = $row->{'Create Table'} =~ m/\).*(?:ENGINE|TYPE)=(\w+)/;
   PTDEBUG && _debug('Storage engine:',$engine);
   return $engine || undef;
}

sub get_table_status {
    my ( $self, $dbh, $table ) = @_;
    my $sql = "SHOW TABLE STATUS LIKE \'$table\'";
    PTDEBUG && _debug($sql);
    my $row;

    eval{
        $row = $dbh->selectrow_hashref($sql);
    };
    if ( $@ ) {
        PTDEBUG && _debug($@);
        return;
    }
    return $row;
}

# query checks.
sub get_recommend {
    my $self = shift @_;
    my $query = shift @_;
    unless ( $query ) {
        PTDEBUG && _debug("no query specified.");
        return;
    }

    my @msg; # get all message from private methods.

    push @msg, _unsafe_parse($query);
    push @msg, _nondeter_clause($query);
    push @msg, _function_in_filter($query);

    # set more rules in this statement.
    my ($dbh, $table) = @_;
    #print Dumper($dbh);
    if( $dbh && $table ) {
        my @advice;
        if( @advice = $self->other_advise($dbh, $table) ) {
           push @msg,@advice;
        }
    }

    return @msg;
}

# http://dev.mysql.com/doc/refman/5.5/en/replication-rbr-safe-unsafe.html
# unsafe functions.
my @unsafe_function = qw(
    FOUND_ROWS
    GET_LOCK
    IS_FREE_LOCK
    IS_USED_LOCK
    LOAD_FILE
    MASTER_POS_WAIT
    RAND
    RELEASE_LOCK
    ROW_COUNT
    SESSION_USER
    SLEEP
    SYSDATE
    SYSTEM_USER
    USER
    UUID
    UUID_SHORT
);

# maybe detect error, such as insert into user(c1,c2) values( .. )
sub _unsafe_parse {
    my ( $query ) = @_;
    unless ($query) {
        warn "SQL query need.";
        return;
    }

    my @msg;

    #regular match
    my $reg = join('|', @unsafe_function);
    my @func = $query =~ m/((?:$reg))\(/gsxi;
    if ( @func ) {
        push @msg, "Warn: SQL has unsafe function: " 
                   . join(' and ', map{ uc $_ } @func)
                   . ", replace with application.";
    }
    return @msg;
}

# unsafe clause
# delayed in insert clause; LIMIT in update clause; update and delete no where clause; 
# update, insert, delete with sub query clause with no order by or limit clause, 
# maybe cause differ between master and slave and no where or limit can be dangerous; 
# select no where , order by or limit maybe dangerous. the other system variables or
# udfs clause cannot be detected.
my %unsafe_clause = (
    'DELAYED'    => "Warn: DELAYED could differ on master and slave, in addtion "
                    .  "to note DELAYED keyword can be only used in MyISAM engine.",

    'DUPLICATE KEY UPDATE' => "Warn: SQL is not deterministic when the table contains "
                             . "more than one primary or unique key, could differ on "
                             . "master and slave.",

    'LIMIT'      => "Warn: the order in which rows are retried is not specifide, "
                    .  "SQL maybe update/delete differ rows on master and slave.",

    'LOAD DATA'  => "Warn: from MySQL 5.5.6, LOAD DATA is unsafe clause, may be differ "
                    . "on master and slave when binlog format is statement-based. and "
                    . "a switch to row-based format when using mixed format logging.",

    'WHERE'      => "Warn: select/update/delete clause with no WHERE is dangerous.",

    'ORDER BY'   => "Warn: delete/update/insert .... select clause with no ORDER BY is "
                    . "not deterministic, may be differ on master and slave.",

    'LIKE'       => "Warn: can be dangerous when table has many rows. replace with LIKE "
                    . "\'..%\' or sphinx.",
);

sub _nondeter_clause {
    my ($query) = @_;
    unless ($query) {
        warn "SQL query need.";
        return;
    }

    my @msg;
    SWITCH: {
        $query =~ m/\bDELAYED\b/sxi && do {
             push @msg, $unsafe_clause{'DELAYED'};
        };  

        $query =~ m/DUPLICATE\b\s+\bKEY\b\s+UPDATE/sxi && do {
             push @msg, $unsafe_clause{'DUPLICATE KEY UPDATE'};
        };  

        $query =~ m/(?:UPDATE|DELETE)\b.+\bLIMIT\b/sxi && do {
             push @msg, $unsafe_clause{'LIMIT'};
        };  

        $query =~ m/\bLOAD\b\s+\bDATA\b/sxi && do {
             push @msg, $unsafe_clause{'LOAD DATA'};
        };

        $query =~ m/\bLIKE\b\s+(?:'|")\%/sxi && do {
             push @msg, $unsafe_clause{'LIKE'};
        };

        $query =~ m/\bWHERE\b/sxi && do {
             if( $query =~ /(?:UPDATE|DELETE|INSERT).+\bSELECT\b/i) {
                 if ( $query !~ /\bORDER\b\s+\bBY/sxi ) { 
                     push @msg, $unsafe_clause{'ORDER BY'};
                 }   
             }   
        };  
        $query !~ m/\bWHERE\b/sxi && do {
             if ( $query !~ m/^\s*\bINSERT\b\s*/sxi ){
                 push @msg, $unsafe_clause{'WHERE'};
             }   
        };
    }

    return @msg;
}

# Developer maybe use function in filter clause, eg:
# where cur_time = now();
# order by rand();

my @filter_function = qw(
   NOW
   RAND
   CONNECTION_ID
   CURDATE
   CURRENT_DATE
   CURRENT_TIME
   CURRENT_TIMESTAMP
   CURTIME
   LOCALTIME
   LOCALTIMESTAMP
   UNIX_TIMESTAMP
   UTC_DATE
   UTC_TIME
   UTC_TIMESTAMP
   LAST_INSERT_ID
);

sub _function_in_filter {
    my ($query) = @_;
    unless( $query ) {
        PTDEBUG && _debug('no query');
        return;
    }

    my @msg;
    my ($filter) = $query =~ m/\bFROM\b\s+\w+\s+(.*)/sxi; 
    if( $filter ) {
       # regular match
       my $reg = join('|', @filter_function);
       my @func = $filter =~ m/((?:$reg))\(/sxi;
       if ( @func ) {
           push @msg, "Warn: SQL has function: "
                      . join(' and ', map { uc $_ } @func)
                      . " in filter condition clause, index maybe invalid.";
        }
    }
    return @msg;

}

sub other_advise {
    my ($self, $dbh, $table) = @_;
    foreach ( qw($dbh $table) ) {
        warn "need $_ argument" unless defined $_;
        return;
    }

   # $stat is the table status 
   my $status = $self->get_table_status($dbh, $table);
   my @msg;

   if ($status->{Collation} ne 'utf8_general_ci') {
       push @msg, "Notice table collation is not utf8_general_ci.";
   }

   if ($status->{Engine} ne 'InnoDB') {
       push @msg, "Notice table engine is not InnoDB.";
   }

   return @msg;
}

sub _debug {
  my ($package, undef, $line ) = caller;
  @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp }
       map { defined $_ ? $_ : 'undef' }
       @_;

  print STDERR "+-- # $package: $line $PID", join(' ', @_), "\n";
}

1; # Because this is a module as well as a script.

# ###########################################################################################
# Documentation.
# ###########################################################################################

=pod

=head1 Name

    SQL::Audit::Check -- Check table whether is avalible or not, and detect the queries is normal
                         because developer maybe use unsafe funtions or non-determitation clause.

=head1 SYNOPSIS

Example:

    use SQL::Audit::dbh;
    use Data::Dumper;
    use SQL::Audit::Check;
    use encoding "utf8";
    my $dblist = SQL::Audit::dbh->new(
        host => '127.0.0.1',
        port => 3306,
        user => 'test',
        password => 'xxxxxxxx',
        charset  => 'utf8',
        driver   => 'mysql',
    );

    my $db_handle = $dblist->get_dbh('test',{AutoCommit => 1});

    #my $sql = 'select * from t2 where cur_time = rand()';
    #my $sql = "select * from t2 where name like '第一%'  order by name asc limit 2";
    my $sql = "insert into t1 select * from t2 where chapter id > 100";

    print $sql,"\n";
    my $x = SQL::Audit::Check->new();
    if ( $x->check_table('dbh'=>$db_handle, 'table'=>'t1') ) {
       my @message = $x->get_recommend($sql);
       #print Dumper(@message);
       my $row = $x->get_table_status($db_handle, 't1');
       #print Dumper(@row);
       my $engine = $x->get_engine($db_handle, 't1');
       print Dumper($engine);
    }

Note that check_table method return ture or false values, so it can be consider boolean value, the other 
methods should be used after check_table.

=head1 RISKS

Tow patial consists this module, check_table, get_engine and get_table_status achive the comman status check,
and get_recommend's most important task is detect the query whether ok or not. The unsafe functions and unsafe
clause not all containt, so the test environment need more comprehensive test, it return null when it cannot 
detect queries is ok. Some unsafe factor can be collect and join in privite methods.

=head1 CONSTRUCTOR

=head2 new()

Create a C<SQL::Audit::Check>. No ARGS should be provided.

=head2 FUNCTIONS

=over 4

=item check_table

The following things this method do:
    1. connect to database;
    2. get table status, return 1 if there exists table, and don't check privileges;
    3. if all_privs provide, get the table columns, return 0 if no columns;
    4. return 0 unless user no privileges by use delete to check user privielges.
As the above reasons, this method should at least provide dbh and table.

example:
 
    SQL::Audit::Check->check_table('dbh'=>$db_handle, 'table'=>'test_table');

=item get_engine

To get the table engine, Innodb engine is recommended. the following private method invoke this method.
dbh and table name is needed.

example:
    my $engine = SQL::Audit::Check->get_engine('dbh'=>$db_hanle, 'table'=>'test_table');

=item get_table_status

To get the common table status used by 'show table status like "table_name"', return the reference.
dbh and table name is needed.

example:
    my $status = SQL::Audit::Check->get_table_status('dbh'=>$db_handle, 'table'=>'test_table');
    use Data::Dumper;
    print Dumper($status);

=item get_recommend

Some private methods consists this method, the query must be exists and dbh and table are optional args.
The order of the 3 push lines is non-sequence, but should before the other_advise method. some private 
method include:

=item _unsafe_parse

The unsafe function in the array unsafe_function is coming from MySQL refman, links can be found:
http://dev.mysql.com/doc/refman/5.5/en/replication-rbr-safe-unsafe.html

most of the functions can cause differ result on master and slave, some of them because of the concurrent 
control mechanism in the DBMS system, developer maybe use one or more these functions in a SQL query. this
method match one or more unsafe function, and return warn messages in array format.

(?:$reg) means multiple match.

the sql query is needed.

=item _nondeter_clause

As some unsafe clause can cause differ rows on master and slave, MySQL refman page give some of these, but
it doesn't contained all, more rules can be set in this method. very common keyword is in hash unsafe_clause,
multi-keywords can be match and return values in array format.

non-determitation means that select or update differ rows on master and slave, such as:

    insert into test_table select * from t1 limit 10;

if master rows bigger than slave, means that master meybe result with id from 1 to 10, but slave result with
id from 1 to 11, miss one value, so what happed, test_table on the master has the rows from 1 to 10, but slave
has values from 1 to 11.

the WHERE is special because it should be split several cases, no where and complex query is noticed.

the sql query is needed.

=item _function_in_filter

The same as _unsafe_parse, some of them maybe used in WHERE or ORDER BY clause by developer, many index cannot
be used without the isolate filed, such as:

    select * from test_table where cur_time = now()
    select * from test_table order by rand()

It's very dengerous when MySQL concurrent threads is huge because of index cannot be used.

=item other_advise

this method is optional, as the MySQL developing guideline demand developer use InnoDB engine and utf8 decode, 
this simple check the engine and decode factors.

dbh and table is needed, get_recommend method wouldn't execute it if dbh and table doesn't provide.

get_recommend return messages in arrays format, use Dumper present:

   my @message = SQL::Chech->get_recommend($sql);
   print Dumper(@message);

=item _debug

If the PTDEBUG is enabled, _debug function return the detailed information, such as package name, 
line number, etc...

Use the following syntax to enable PTDEBUG in shell context:

    # export PTDEBUG=1

=back

=head1 AUTHOR

zhe.chen <chenzhe07@gmail.com>

=head1 CHANGELOG

v0.1.0 version

=cut
