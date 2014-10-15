package SQL::Explain;
# This module provide some method for us to get the explain query result, it heavily
# relay on the SQL Optimizer which supply the EXPLAIN mechanism. Other more detailed
# rules can be set in query_analyze method.
# zhe.chen<chenzhe07@gmail.com>, date: 2014-10-09

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
@EXPORT    = qw( query_explain query_normalize query_analyze );
@EXPORT_OK = qw( query_index_use );
$VERSION = '0.0.1';

sub new {
    my ( $class, %args ) = @_;
    my $self = { };
    return bless $self, $class;
}

sub query_explain {
    my ( $self, %args ) = @_;

    # args need to be specified.
    foreach ( qw(dbh query) ) {
        warn "need $_ argument, use \'$_\'=> ... specified." unless defined $args{$_};
    }

    my ( $dbh, $query ) = @args{qw(dbh query)};
    if( $query =~ m/^\s*(?:update|delete|insert)/i ) {
        warn "Cannot explain non-select sql as the MySQL version prior 5.6: $query\n";
        return;
    }
    
    #print "$query\n";
    $query = "EXPLAIN $query" if $query !~ m/^\s*explain/i;
    
    my $explain;
    eval {
        $explain = $dbh->selectall_arrayref($query, { Slice => {} });
    };
    if ($@) {
        return;
    }
    PTDEBUG && _debug("explain out:", Dumper($explain));
    return $explain;
}

sub query_normalize {
    my ( $self, $explain ) = @_;
    my @result;

    foreach my $row (@$explain) {
        $row = {%$row};
        #print Dumper(%$row);
        foreach my $col ( qw(key possible_keys key_len ref) ) {
            $row->{$col} = [ split(/,/, $row->{$col} || '') ];
        }

        $row->{Extra} = {
            map {
                my $var = $_;
                if( my ($key, $vals) = $var =~ m/(Using union)\(([^)]+)\)/ ) {
                    #print Dumper($key);
                    $key => [split(/,/, $vals)];
                } else {
                    $var => 1;
                }
            } split(/; /, $row->{Extra}||'') # split on semicolons.
        };
        #print Dumper($row->{Extra});

        push @result, $row;
    }
    return \@result;
}

# http://dev.mysql.com/doc/refman/5.5/en/execution-plan-information.html
# http://dev.mysql.com/doc/refman/5.5/en/explain-output.html#explain-extra-information
sub query_alternate_keys {
    my ($self, $keys, $possible_keys) = @_;
    my %key_used = map{ $_ => 1 } @$keys;
    return [ grep { !$key_used{$_} } @$possible_keys ];
}

sub query_index_use {
    my ($self, %args) = @_;
    foreach my $arg ( qw(database table query explain) ) {
        warn "need $arg argument. use \'$arg\' => ... specified." unless defined $args{$arg};
    }

    my ($db, $table, $query, $explain) = @args{qw(database table query explain)};
    my @result;

    foreach my $row ( @$explain ) {
        next if !defined $row->{table} || $row->{table} =~ m/^<(derived|union)\d/;
        push @result, [
            db  => $db,
            tb  => $table,
            idx => $row->{key},
            alt => $self->query_alternate_keys($row->{key}, $row->{possible_keys}),
        ];
    }

    PTDEBUG && _debug("Index use for:", $query, Dumper(\@result));
    return \@result;
}

sub query_analyze {
    my ($self, %args) = @_;
    my @required_args = qw(explain);
    foreach my $arg ( qw(explain) ) {
        warn "need $arg argument. use \'$arg\' => ... specified." unless defined $args{$arg};
    }

    my ($explain) = @args{@required_args};
    PTDEBUG && _debug("analyze for explain:", Dumper($explain));

    # http://dev.mysql.com/doc/refman/5.5/en/explain-output.html#explain-join-types
    my $access_mark = {
       'system'          => 's',
       'const'           => 'c',
       'eq_ref'          => 'e',
       'fulltext'        => 'f',
       'index_merge'     => 'm',
       'range'           => 'n',
       'ref'             => 'r',
       'ref_or_null'     => 'o',
       'index'           => 'i',
       'unique_subquery' => 'u',
       'index_subquery'  => 'p',
       'ALL'             => 'a',
    };

    my $analyze = '';
    my ($T, $F); # Using temporary, Using filesort

    foreach my $tb (@$explain){
        my $mark;
        if( defined($tb->{type}) ) {
            $mark = $access_mark->{$tb->{type}} || "?";
            $mark = uc $mark if $tb->{Extra}->{'Using index'};
        } else {
            $mark = '-';
        }

        $analyze .= $mark;
        $T = 1 if $tb->{Extra}->{'Using temporary'};
        $F = 1 if $tb->{Extra}->{'Using filesort'};
    }

    if ( $T || $F ) {
        if ( $explain->[-1]->{'Extra'}->{'Using temporary'} || 
             $explain->[-1]->{'Extra'}->{'Using filesort'} ) {
            $analyze .= ">" . ($T ? "T" : "") . ($F ? "F" : "");
        } else {
            $analyze .= ($T ? "T" : "") . ($F ? "F" : "") . ">$analyze";
        }
    }

    PTDEBUG && _debug("mark analyze: ", $analyze);
    return $analyze;
}

sub _debug {
  my ($package, undef, $line ) = caller;
  @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp }
       map { defined $_ ? $_ : 'undef' }
       @_;

  print STDERR "+-- # $package: $line $PID", join(' ', @_), "\n";
}

1; # Because this is a module as well as a script.
# ##########################################################################################
# Documentation.
# ##########################################################################################

=pod

=head1 Name

    SQL::Explain -- Explain the select clause to get the detailed execute plain, then can 
                    find this query whether used suitable key or not.

=head1 SYNOPSIS

Example:

        use SQL::dbh;
        use SQL::Explain;
        use encoding "utf8";
        my $dblist = SQL::dbh->new(
               host => '127.0.0.1',
               port => 3306,
               user => 'test',
               password => 'xxxxxxxx',
               charset  => 'utf8',
               driver   => 'mysql',
        );

        my $db_handle = $dblist->get_dbh('mybook66',{AutoCommit => 1});
        my $sql = "select * from chapter where chapter_name like '第一%'  order by chapter_name asc limit 2";
        my $x = SQL::Explain->new();
        my $explain = $x->query_explain('dbh'=>$db_handle, 'query'=>$sql);
        $explain = $x->query_normalize($explain);
        $x->query_index_use('database'=>'test', 'table'=>'chapter', 'query'=>$sql, 'explain'=>$explain);
        my $mark = $x->query_analyze('explain'=>$explain);
        $dblist->disconnect($db_handle);

Note that all methods are based on query_explain which get the explain results, so before use 
query_explain, You cannot use the other methods.

=head1 RISKS

All of the methods relay on the EXPLAIN mechanism, We change the query with EXPLAIN header to get the execute 
plain what we needed, even the query contain multi-join or multi-table. But it would be exit when you try to
explain the non-select clause.

=head1 CONSTRUCTOR

=head2 new()

Create a C<SQL::Explain>. No ARGS should be provided.

=head2 FUNCTIONS

=over 4

=item query_explain

It's the basis method, there are two things that operate:
    1. Add EXPLAIN to the header position of the SQL query;
    2. Return the database handle which contains the EXPLAIN result;

As these features, dbh(database handle) and SQL query should be provided. Args can be hash format:
    eg: SQL::Explain->query_explain('dbh'=>$db_handle, 'query'=>$sql);

=item query_normalize

The purpose of this method is normalize the result which comes from query_explain, specify an anonymous array
if the filed is multi-value, null or an empty string. eg:

    Extra:NULL   =>  Extra:[]
    Extra:Using where; Using filesort   =>  Extra:[ 'Using where' => 1, 'Using filesort' => 1 ]

=item query_index_use

Make a report for key usage, include following items:

    database
    table
    index used
    possible keys

So the database, table, query and explain consist of the args because the result format, and the result that 
retruned may be anonymous hash or anonymous array of hash.

=item query_analyze

It's very important for us to known which type or join we are used in our SQL queries. Does the key used 
suitable? Weather used the filesort or temporary or not. this method return the mark that present the fetures 
which queries used.

Two things this method do:
    1. check the type that explain result repsent, more items in the hash access_mark.
    2. check the Extra filed and retrun special mark to present the query use the filesort or temporary funs.

the mark '>T' and '>F' means the query have the temporary or filesort funs. 
for example: 
    query_analyze return the string 'a>F', means the query EXPLAIN result have a ALL type and Using filesort.

=item _debug

If the PTDEBUG is enabled, _debug function return the detailed information, such as package name, 
line number, etc...

note that must enable 'use English qw(-no_match_vars)' when you want use $PID variables.

Use the following syntax to enable PTDEBUG in shell context:

    # export PTDEBUG=1

=back

=head1 AUTHOR

zhe.chen <chenzhe07@gmail.com>

=head1 CHANGELOG

v0.0.1 initial version

=cut
