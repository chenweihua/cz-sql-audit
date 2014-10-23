package SQL::Audit;
# wrap the sub modules for easy to use some method.
# zhe.chen <chenzhe07@gmail.com>, date: 2014-10-20
use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);  # Avoids regex performance penalty
use constant PTDEBUG => $ENV{PTDEBUG} || 0;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use SQL::Audit::Check;
use SQL::Audit::Rewrite;
use SQL::Audit::Explain;

require Exporter;
@ISA = qw(Exporter);
@EXPORT    = qw(sql_check sql_rewrite sql_explain);
$VERSION = '0.1.0';

my $check_object    = SQL::Audit::Check->new();
my $rewrite_object  = SQL::Audit::Rewrite->new();
my $explain_object  = SQL::Audit::Explain->new();

sub new {
    my ( $class, %args ) = @_;
    my $self = { };
    return bless $self, $class;
}

sub sql_check {
    my ($self, $dbh, $table, $sql) = @_; 
    my @msg;
    if ($check_object->check_table('dbh' => $dbh, 'table' => $table)) {
        push @msg, $check_object->get_recommend($sql, $dbh, $table);
        my $row = $check_object->get_table_status($dbh, $table);
        push @msg, "Table_rows: ". $row->{Rows} if $row->{Rows} > 100000;
        my $engine = $check_object->get_engine($dbh, $table);
        push @msg, "Engine: $engine" if $engine !~ /innodb/i;
    } else {
        push @msg, "table $table: not exists";
    }   
    #print Dumper(@msg);
    return @msg;
}

sub sql_rewrite {
    my ($self, $sql)  = @_;

    SWITCH: {
        if ( length($sql) + 0 > 100 ) {
           $sql = $rewrite_object->short_query($sql, 100);
        }
        $sql =  $rewrite_object->cut_comment($sql);
        $sql =  $rewrite_object->convert_select_list($sql);

        $sql =~ m/\A\s*select/msi && do {
           $sql = $rewrite_object->sub_query_wrap($sql);
           last SWITCH;
        };

        $sql =  $rewrite_object->convert_to_select($sql);
    }

    return $sql;
}

my %access_mark = (
  's'    => 'system',
  'c'    => 'const' ,
  'e'    => 'eq_ref',
  'f'    => 'fulltext',
  'm'    => 'index_merge',
  'n'    => 'range',
  'r'    => 'ref',
  'o'    => 'ref_or_null',
  'i'    => 'index',
  'u'    => 'unique_subquery',
  'p'    => 'index_subquery',
  'a'    => 'ALL',
  'T'    => 'Using_temporary',
  'F'    => 'Using_filesort',
  '>'    => '',
);

sub sql_explain {
    my ($self, $dbh, $query) = @_;

    my @msg;
    my $explain = $explain_object->query_explain('dbh'=>$dbh, 'query'=>$query);
    if ( !defined $explain ) {
        return;
    }
    $explain    = $explain_object->query_normalize($explain);
    my $mark = $explain_object->query_analyze('explain'=>$explain);
    $dbh->disconnect;

    #print Dumper($explain);
    foreach my $tag (split(//, $mark)) {
        if( $tag =~ m/(?:f|a|T|F)/i ) {
           push @msg, 'index: ' . $access_mark{$tag};
        }
    }

    @msg + 0 > 0 ? return (\@msg, $explain)
                 : return;
}

sub sql_fuzzy {
    my ($self, $query) = @_;
    return if ! defined $query;
    return $rewrite_object->query_statistic($query);
}

1;

# ##########################################################################################
# Documentation.
# ##########################################################################################

=pod

=head1 Name

    SQL::Audit -- Wrap the sub module in Audit directory for developer to use easy.

=head1 SYNOPSIS

Example:
    use SQL::Audit;

    my $audit_object = SQL::Audit->new();
    my @msg = $audit_object->sql_check($db_handle, $tb, $sql_query);
    my $convert_sql = $audit_object->sql_rewrite($sql_query);
    my ($msg, $explain ) = $audit_object->sql_explain($db_handle, $sql_query);

As wrap the sub modules, dbh and table name or sql query should be provide.

=head1 RISKS

The RISKS relay on the sub modules, some unexpected error maybe cause this module down.
use perldoc sub-module for more info.

=head1 CONSTRUCTOR

=head2 new()

Create a C<SQL::Audit>. No ARGS should be provided.

=head2 FUNCTIONS

=over 4

=item sql_check

Wrap the SQL::Audit::Check module, if sql query is not in rules, some unsafe function or 
clause, unsuitable index info can be present in array format.

use perldoc SQL::Audit::Check for more info.

=item sql_rewrite

Wrap the SQL::Audit::Rewrite module, invoke most methods, cut comments, convert to select 
query. The final sql query can be returned.

use perldoc SQL::Audit::Rewrite for more info.

=item sql_explain

The most important for this method is to EXPLAIN SELECT queries which present the index 
use and rows examined. %access_mark contains most type indexes.

use perldoc SQL::Audit::Explain for more info.

=item sql_fuzzy

Staticstic the similar sql, replace the parameter with ? mark, for example:

    select * from t2 where name = 'list'
    convert to
    select * from t2 where name = ?

As this feature, we can set this fuzzy sql as a key into redis or memcached, to avoid repeatable
sql audit.

=back

=head1 AUTHOR

zhe.chen <chenzhe07@gmail.com>

=head1 CHANGELOG

v0.1.0 initial version

=cut 
