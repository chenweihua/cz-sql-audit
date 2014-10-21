package SQL::Audit::Rewrite;
# Prior to 5.6, MySQL explain query does not support insert, update, delete clause,
# it means we must rewrite these clause who change the data to select query, then
# implement the explain prepare. both DBI and DBD::mysql is no needed.
# zhe.chen<chenzhe07@gmail.com>, date: 2014-09-28

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);  # Avoids regex performance penalty
use constant PTDEBUG => $ENV{PTDEBUG} || 0;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT    = qw(convert_to_select convert_select_list sub_query_wrap cut_comment short_query);
$VERSION = '0.1.0';

# All changed sql maybe contains the following header, include combind query.
my $query_keys = qr#INSERT|UPDATE|DELETE|REPLACE|SELECT#xi;

# negative lookbehind, return ture if not match \)" or \)', for example
# (1245, "chars", "no\'list")i,("list") matches "chars", "no\'list", "list" .
my $quote_re = qr/"(?:(?!(?<!\\)").)*"|'(?:(?!(?<!\\)').)*'/;

# For (1,(2*(3+4)),5) nested pattern can be matched.
my $np;
$np = qr/
         \(
         (?:
            (?> [^()]+ )     # Non-capture group w or o backtracking
            |
            (??{ $np })      # Group with matching parens
         )*
         \)
        /x;

# read more comment syntax from http://dev.mysql.com/doc/refman/5.5/en/comments.html
#  style 1: # ...
#  style 2: -- ...
#  style 3: /* ... */
my $ol_re = qr/(?:--|#)[^'"\r\n]*(?=[\r\n]|\Z)/;  # One-line comments
my $ml_re = qr#/\*[^!].*?\*/#sm;         # But not /*!version */, maybe muti-line comment


sub new {
    my ( $class, %args ) = @_;
    my $self = { };
    return bless $self, $class;
}

sub cut_comment {
    my ( $self, $query ) = @_;
    return unless $query;
    $query =~ s/$ol_re//g;
    $query =~ s/$ml_re//g;
    return $query;
}

sub convert_select_list {
    my($self, $query) = @_;
    $query =~ s{
                \A\s*select(.*)\bfrom\b
               }
               {
                $1 =~ m/\*/ ? "SELECT 1 FROM" : "SELECT ISNULL(coalesce($1)) FROM"
               }exi;
    return $query;
}

# http://dev.mysql.com/doc/refman/5.5/en/update.html
# http://dev.mysql.com/doc/refman/5.5/en/insert.html
# http://dev.mysql.com/doc/refman/5.5/en/replace.html
# http://dev.mysql.com/doc/refman/5.5/en/delete.html
sub convert_to_select {
    my ( $self, $query ) = @_;
    return unless $query =~ m/$query_keys/;

    return if $query =~ m/=\s*\(\s*SELECT /i;

    $query =~ s{
                 \A.*?
                 update(?:(?:low_priority|ignore))?\s+(.*?)
                 \s+set\b(.*?)
                 (?:\s*where\b(.*?))?
                 (limit\s*[0-9]+(?:\s*,\s*[0-9]+)?)?
                 \Z
               }
               {
                _update_to_select($1, $2, $3, $4)
               }exsi
           || $query =~ s{
                          \A.*?
                          (?:insert(?:\s+ignore)?|replace)\s+
                          .*?\binto\b(.*?)\(([^\)]+)\)\s*
                          values?\s*(\(.*?\))\s*
                          (?:\blimit\b|on\s+duplicate\s+key.*)?\s*
                          \Z
                         }
                         {
                          _insert_to_select($1, $2, $3)
                         }exsi
           || $query =~ s{
                          \A.*?
                          (?:insert(?:\s+ignore)?|replace)\s+
                          (?:.*?\binto\b)\b(.*?)\s*
                          set\s+(.*?)\s*
                          (?:\blimit\b|on\s+duplicate\s+key.*)?\s*
                          \Z
                         }
                         {
                          _insert_to_select_set($1, $2)
                         }exsi
           || $query =~ s{
                          \A.*?
                          delete\s+(.*?)
                          \bfrom\b(.*)
                          \Z
                         }
                         {
                          _delete_to_select($1, $2)
                         }exsi;

   $query =~ s/\s*on\s+duplicate\s+key\s+update.*//si;

   # ?= return true if match 'select' query, replace with '' before 'select' keyword.
   $query =~ s/\A.*?(?=\bselect\s*\b)//ism; 

   return $query;
}

sub _delete_to_select {
    my ( $delete, $join ) = @_;
    if ( $join =~ m/\bjoin\b/ ) {
        return "SELECT 1 FROM $join";
    }
    return "SELECT * FROM $join";
}

sub _insert_to_select {
    my ( $tb1, $cols, $vals ) = @_;
    PTDEBUG && _debug('args:', @_);

    my @cols = split(/,/,$cols);
    PTDEBUG && _debug('cols:', @cols);

    $vals =~ s/^\(|\)$//g; # Strip leading/trailling parens
    my @vals = $vals =~ m/($quote_re|[^,]*${np}[^,]*|[^,]+)/g;
    PTDEBUG && _debug('vals:', @vals);

    if ( @cols == @vals ) {
        return "SELECT * FROM $tb1 WHERE "
               . join(' AND ', map { "$cols[$_] = $vals[$_]" } (0..$#cols));
    } else {
        return "SELECT * FROM $tb1 LIMIT 1"
    }
}

sub _insert_to_select_set {
    my ( $from, $set ) = @_;
    $set =~ s/,/ AND /g;
    return "SELECT * FROM $from WHERE $set";
}

sub _update_to_select {
    my ( $from, $set, $where, $limit ) = @_;

    #set book_id = 1002, name = "list"
    $set =~ s/\s*?=\s*?[^,]+(?:\s*?)//g;
    return "SELECT $set FROM $from "
           . ( $where ? "WHERE $where" : '' )
           . ( $limit ? " $limit "     : '' );
}

sub sub_query_wrap {
    my ( $self, $query ) = @_;
    return unless $query;

    print "Query:$query\n";
    return $query =~ m/\A\s*select/sxi
                  ? "SELECT 1 FROM ($query) AS x LIMIT 1"
                  : $query;
}

# Query should be rewrite by simple ways if sql is too long to view.
# for example: delete from user_table where id in (.., .., .., ....) to
# delete from user_table where id in (.,.., /*.. omitted n items .. */)
sub short_query {
   my ($self, $query, $length) = @_;

   $query =~ s{
               \A(
                  (?:INSERT|REPLACE)
                  (?:\s+LOW_PRIORITY|DELAYED|HIGH_PRIORITY)?
                  (?:\s\w+)*\s+\S+\s+VALUES\s*\(.*?\)
                 )
                 \s*,\s*\(.*?(ON\s+DUPLICATE|\Z)
              }
              {
               $1 /* ... omitted ... */ $2
              }xsi;

   return $query unless $query =~ m/IN\s*\(\s*(?!select)/i;
   
   my $query_length = length($query);
   if ( $length +0 > 0 && $query_length + 0 > $length ) {
       $query =~ s{
                   (\bIN\s*\()   # opening of an IN list
                   ([^\)]+)      # contents of the list 
                   (?=\))        # close of the list 
                  }
                  {
                   $1 . _short($2)
                  }gexis
   }

   return $query;
}

sub _short {
   my $snippet = shift @_;
   my @values  = split(/,/, $snippet);
   return $snippet unless @values > 20;

   my @retain_values = splice(@values, 0, 20);

   # scalar(@values): notice splice had removed first 20 items
   return join(',', @retain_values)
          . "/*... omitted "
          . scalar(@values)
          . " items ... */"; 
}

# replace parameter with ?, for the memcached/redis cached.
sub query_statistic {
    my($self, $query) = @_; 
    print $query,"\n";
    $query =~ s{
                  \s*?((?:(?:=|<|<=|>|>=|LIKE)))\s*?
                  (?:'\w+?'|"\w+?"|\d+)\s*?
               }
               {   
                  _stat_comp($1)
               }gmexsi;

     $query =~ s{
                   (\s*?BETWEEN\s*?\w+?\s*?AND\s*?\w+)
                }
                {
                   _stat_range($1)
                }gmexsi;

     $query =~ s{
                   \s+?((?:IN|VALUES))\s*
                   \(
                    \s*?(?:\d+|'.*?'|".*?")\s*?,.*?
                   \)
               }
               {   
                    _stat_in($1)
               }gmexsi;

     $query =~ s{
                   \bLIMIT\b\s*?
                   \d+\s*?(?:,\s*?\d+|)
                }
                {
                   _stat_limit()
                }gmexsi;

    return $query;
}

sub _stat_comp {
    my $mark = shift;
    return " $mark ? "
}

sub _stat_range {
    my $mark = shift;
    print "mark: $mark\n";
    return " BETWEEN ? AND ?";
}

sub _stat_in {
    my $mark = shift;
    return " $mark ( ? )"
}

sub _stat_limit {
    return "LIMIT ?, ?";
}

sub _debug {
  my ($package, undef, $line ) = caller;
  @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp }
       map { defined $_ ? $_ : 'undef' }
       @_;

  print STDERR "+-- # $package: $line $PID", join(' ', @_), "\n";
}

1;

# ##################################################################################
# Documentation.
# ##################################################################################

=pod

=head1 Name

    SQL::Audit::Rewrite - Rewrite the insert, update, delete that related to change data to 
                          select queries.

=head1 SYNOPSIS

Example:

    use SQL::Audit::Rewrite;
    my $sql = 'update book set book_id = 1002, name = "list", chapter_num = 100 where 
               book_id = 1003';

    my $ob = SQL::Audit::Rewrite->new();
    my $query = $ob->convert_to_select($sql);
    print "Query: $query\n";

    # if the query is too long to view cosie, it can be shorten by short_query.
    my $sql = 'delete from book where book_id in (1003, 1004, 1005, 1006, 2, 5, 1, 7, 
               9, 4, 42,33,333,456, 86, 71, 81, 90, 91, 98, 10001, 20001, 30001, 51)';

    my $query = $ob->convert_to_select(SQL::Rewrite->short_query($sql, 20));

Note that insert into .... select ... convert to select ...., and the new() method only 
process the INSERT(REPLACE), UPDATE, DELETE queries.

=head1 RISKS

This module assumes developers use the as far as possible not complicated sql queries, 
which means very complicated SQL maybe convert to an unknown select clause, such as 
use join with many tables, or multi leval sub-queries. All the functions in module use 
the regular expressions, so it's not easy to be found some minor mistakes.

=head1 CONSTRUCTOR

=head2 new()

Create a C<SQL::Audit::Rewrite>. No ARGS should be provided.

=head2 FUNCTIONS
 
=over 4

=item cut_comment

Striping the comment in queries, See more information from the mysql manual page: 
http://dev.mysql.com/doc/refman/5.5/en/comments.html, for example:

       delete from user where user_id = 1001 # delete special user
       convert to:
       delete from user where user_id = 1001

Three style comments can be found in manual page, cut_comment is optional to use, whether 
treatment does not affect the results.

=item convert_select_list

The more complicated sub select, more difficult to regular match, we can use this funtion
to convert queries by simple way. for example:

      select * from user_test where id > 100
      convert to:
      SELECT 1 FROM user_test where id > 100

=item convert_to_select

This function process the main convert, include INSERT(REPLACE), UPDATE, DELETE,it is very 
dependent on regular expressions. this function refer to the following manual pages:

      http://dev.mysql.com/doc/refman/5.5/en/update.html
      http://dev.mysql.com/doc/refman/5.5/en/insert.html
      http://dev.mysql.com/doc/refman/5.5/en/replace.html
      http://dev.mysql.com/doc/refman/5.5/en/delete.html

Retun null if the query does not match the query keys, which means that query maybe can not
convert.

The private method is used to process the convert progress:

_delete_to_select:
    if match the join key word, convert to SELECT 1 FROM:

       delete from user where id in (select id from user join user_test where user.id = user_test.id)
       convert to:
       SELECT 1 FROM  user where id in (select id from user join user_test where user.id = user_test.id)

    else convert to SELECT * FROM:

       delete from user where id > 100
       convert to:
       SELECT * FROM  user where id > 100

_insert_to_select
    if one row insert into table, every filed in values should be matched, convert to:

       insert into book(book_id, name, chapter_num) values(2654, "2list", 200)
       convert to:
       SELECT * FROM  book WHERE book_id = 2654 AND  name =  "2list" AND  chapter_num =  200

    multi rows convert to:

       insert into book(book_id, name, chapter_num) values(1253,"list","100"),(2654, "2list", 200)
       convert to:
       SELECT * FROM  book LIMIT 1

_insert_to_select_set
    if set use by insert clause, convert to:

       insert into book set book_id = 2654, name = "2list", chapter_num = 200
       convert to:
       SELECT * FROM  book WHERE book_id = 2654 AND  name = "2list" AND  chapter_num = 200

_update_to_select
    similar to delete_to_selete, but the filed should be matched, and put the set list to select:

       update book set book_id = 1002, name = "list", chapter_num = 100 where book_id = 1003
       convert to:
       SELECT  book_id, name, chapter_num FROM book WHERE  book_id = 1003

=item short_query

If the query is too long to view cosie, such as many items in IN list, it can be shortened by 
short_query function, 20 items is remaining by default. for example:

    delete from book where book_id in (1003, 1004, 1005, 1006, 2, 5, 1, 7, 9, 4, 42, 33, 333, 456, 
                                       86, 71, 81, 90, 91, 98, 10001, 20001, 30001, 51)
    convert to:
    delete from book where book_id in (1003, 1004, 1005, 1006, 2, 5, 1, 7, 9, 4, 42, 33, 333, 456,
                                       86, 71, 81, 90, 91, 98/*... omitted 4 items ... */)

short_query need the length args to judge whether to short or not, and only short IN list query:

    my $ob = SQL::Audit::Rewrite->new();
    my $query = $ob->short_query($sql, 20);

    the two statement above and the following statement is the same effect:

    my $query = SQL::Audit::Rewrite->($sql, 20)   # 20 is the length parameter.

the private function _short is used by short_query, return the retain items that had been shortened

_short
    Format and retrun the rest of the items.

=item query_statistic

Staticstic the similar sql, replace the parameter with ? mark, for example:

    select * from t2 where name = 'list'
    convert to
    select * from t2 where name = ?

As this feature, we can set this fuzzy sql as a key into redis or memcached, to avoid repeatable
sql audit.

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
