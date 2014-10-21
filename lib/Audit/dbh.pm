package SQL::Audit::dbh;

# This program is part of SQL audit: get the database handle because of the different 
# database which user use, and this database handle object should be destroy when leave 
# MySQL database. Dependent modules are embedded in this file.
# zhe.chen <chenzhe07@gmail.com>, date: 2014-09-25.

use strict;
use warnings FATAL => 'all';
use constant PTDEBUG => $ENV{PTDEBUG} || 0;
use English qw(-no_match_vars);
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

require Exporter;
@ISA = qw(Exporter);
@EXPORT    = qw( get_dbh disconnect );
$VERSION = '0.1.0';

eval {
    require DBI;
};

my $have_dbi = $@ ? 0 : 1;

sub host {
    my $self = shift;
    $self->{host} = shift if @_;
    return $self->{host};
}

sub port {
    my $self = shift;
    $self->{port} = shift if @_;
    return $self->{port};
}

sub user {
    my $self = shift;
    $self->{user} = shift if @_;
    return $self->{user};
}

sub password {
    my $self = shift;
    $self->{password} = shift if @_;
    return $self->{password};
}

sub charset {
    my $self = shift;
    $self->{charset} = shift if @_;
    return $self->{charset};
}

sub driver {
    my $self = shift;
    $self->{driver} = shift if @_;
    return $self->{driver};
}

sub new {
    my ($class, %args) = @_;
    my @required_args = qw(host port user password);
    PTDEBUG && print Dumper(%args);

    foreach my $arg (@required_args) {
        die "I need a $arg argument" unless $args{$arg};
    }

    my $self = {};
    bless $self, $class;

    # options should be used.
    $self->host($args{'host'} || 127.0.0.1);
    $self->port($args{'port'} || 3306);
    $self->user($args{'user'} || 'audit');
    $self->password($args{'password'} || '');
    $self->charset($args{'charset'} || 'utf8');
    $self->driver($args{'driver'} || 'mysql');

    return $self;
}

sub get_dbh {
    my ($self, $database, $opts) = @_;
    $opts ||= {};
    my $host = $self->{host};
    my $port = $self->{port};
    my $user = $self->{user};
    my $password = $self->{password};
    my $charset  = $self->{charset};
    my $driver   = $self->{driver};
    
    my $defaults = {
        AutoCommit         => 0,
        RaiseError         => 1,
        PrintError         => 0,
        ShowErrorStatement => 1,
        mysql_enable_utf8 => ($charset =~ m/utf8/i ? 1 : 0),
    };
    @{$defaults}{ keys %$opts } = values %$opts;

    if ( $opts->{mysql_use_result} ) {
        $defaults->{mysql_use_result} = 1;
    }

    if ( !$have_dbi ) {
        die "Cannot connect to MySQL because the Perl DBI module is not "
           . "installed or not found.  Run 'perl -MDBI' to see the directories "
           . "that Perl searches for DBI.  If DBI is not installed, try:\n"
           . "  Debian/Ubuntu  apt-get install libdbi-perl\n"
           . "  RHEL/CentOS    yum install perl-DBI\n"
           . "  OpenSolaris    pkg install pkg:/SUNWpmdbi\n";
    }

    my $dbh;
    my $tries = 2;
    while ( !$dbh && $tries-- ) {
        PTDEBUG && print Dumper(join(', ', map { "$_=>$defaults->{$_}" } keys %$defaults ));
        $dbh = eval { DBI->connect("DBI:$driver:database=$database;host=$host;port=$port", $user, $password, $defaults)};

        if( !$dbh && $@ ) {
            if ( $@ =~ m/locate DBD\/mysql/i ){
                die "Cannot connect to MySQL because the Perl DBD::mysql module is "
                   . "not installed or not found.  Run 'perl -MDBD::mysql' to see "
                   . "the directories that Perl searches for DBD::mysql.  If "
                   . "DBD::mysql is not installed, try:\n"
                   . "  Debian/Ubuntu  apt-get install libdbd-mysql-perl\n"
                   . "  RHEL/CentOS    yum install perl-DBD-MySQL\n"
                   . "  OpenSolaris    pgk install pkg:/SUNWapu13dbd-mysql\n";
            } elsif ( $@ =~ m/not a compiled character set|character set utf8/i ) {
                PTDEBUG && print 'Going to try again without utf8 support\n'; 
                delete $defaults->{mysql_enable_utf8};
            }
            if ( !$tries ) {
                die "$@";
            }

        }
    }

    if ( $driver =~ m/mysql/i ) {
        my $sql;
        $sql = 'SELECT @@SQL_MODE';
        PTDEBUG && print "+-- $sql\n";

        my ( $sql_mode ) = eval { $dbh->selectrow_array($sql) };
          die "Error getting the current SQL_MORE: $@" if $@;

        if ( $charset ) {
            $sql = qq{/*!40101 SET NAMES "$charset"*/};
            PTDEBUG && print "+-- $sql\n";
            eval { $dbh->do($sql) };
              die "Error setting NAMES to $charset: $@" if $@;
            PTDEBUG && print "Enabling charset to STDOUT\n";
            if ($charset eq 'utf8') {
                binmode(STDOUT, ':utf8')
                     or die "Can't binmode(STDOUT, ':utf8'): $!\n";
            } else {
                binmode(STDOUT) or die "Can't binmode(STDOUT): $!\n";
            }
        }

        $sql = 'SET @@SQL_QUOTE_SHOW_CREATE = 1'
              . '/*!40101, @@SQL_MODE=\'NO_AUTO_VALUE_ON_ZERO'
              . ($sql_mode ? ",$sql_mode" : '')
              . '\'*/';
        PTDEBUG && print "+-- $sql\n";
        eval {$dbh->do($sql)};
        die "Error setting SQL_QUOTE_SHOW_CREATE, SQL_MODE" . ($sql_mode ? " and $sql_mode" : '') . ": $@" if $@;
    }

    if ( PTDEBUG ) {
        print Dumper($dbh->selectrow_hashref('SELECT DATABASE(), CONNECTION_ID(), VERSION()/*!50038, @@hostname*/')) ;
        print "+-- 'Connection info:', $dbh->{mysql_hostinfo}\n";
        print Dumper($dbh->selectall_arrayref("SHOW VARIABLES LIKE 'character_set%'", { Slice => {}}));
        print '+-- $DBD::mysql::VERSION:' . "$DBD::mysql::VERSION\n";
        print '+-- $DBI::VERSION:' . "$DBI::VERSION\n";
    }
    return $dbh;
}

# handle should be destroy.
sub disconnect {
    my($self) = @_;
    PTDEBUG && $self->print_active_handles($self->get_dbh);
    $self->{get_dbh}->disconnect;
}

sub print_active_handles {
   my ( $self, $thing, $level ) = @_;
   $level ||= 0;
   printf("# Active %sh: %s %s %s\n", ($thing->{Type} || 'undef'), "\t" x $level,
      $thing, (($thing->{Type} || '') eq 'st' ? $thing->{Statement} || '' : ''))
      or die "Cannot print: $OS_ERROR";
   foreach my $handle ( grep {defined} @{ $thing->{ChildHandles} } ) {
      $self->print_active_handles( $handle, $level + 1 );
   }
}

1; # Because this is a module as well as a script.

# ###################################################################################################
# Documentation.
# ###################################################################################################

=pod

=head1 NAME

  SQL::Audit::dbh - Get the database handle which is specified by script.

=head1 SYNOPSIS

Examples:

      use SQL::Audit::dbh;

      my $dblist = SQL::Audit::dbh->new(
          host     => '127.0.0.1',
          port     => 3306,
          user     => 'username',
          password => 'password',
          charset  => 'utf8',
          driver   => 'mysql',
      );

      # specify the database name.
      my $db_handle = $dblist->get_dbh('test',{AutoCommit => 1});
      my $sql = 'SHOW TABLES';

      # execute sql as DBI or DBD::mysql.
      my $table = $db_handle->selectall_arrayref($sql);
      $dblist->disconnect($db_handle);

Note that above script will exit, if disconnect MySQL. different database name
can be assigned to get_dbh method.

=head1 RISKS

As with SQL audit, it assumes just only one audit user used, and well tested,
but different databases will be used by developer members. The module does not
check whether the specified database is exists or not.

=head1 CONSTRUCTOR

=head2 new ([ ARGS ])

Create a C<SQL::Audit::dbh>. host, port, user, password must be provided, script will
be die if lack of one.

You can pass several parameters to new:

=over 4

=item host

This is the ip address of the module to connect, that is the MySQL host ip address, 
127.0.0.1 is the default value if no value assigned. 

=item port

The port number that MySQL have, 3306 is the default.

=item user

MySQL username, should have enough privileges, SELECT, SUPER is recommonded.

=item password

The password for MySQL user.

=item debug

PTDEBUG is used when you switch debug mode. it does not in %ENV by default, enable 
debug mode, take the folling command:

    export PTDEBUG=1

=back

=head1 METHODS

=head2 get_dbh

Database name must be specified, opts is optional. Default execution twice if not
defined dbh handle, It will use several simple sql to detect the availability, and
charset will be checked, utf8 is default.

=head2 disconnect

Destroy the database handle, a sql that had been audited ( replay to mysql by audit 
user), it should be destroyed immediately, the purpose is to reduce the connection.

=head1 AUTHOR

zhe.chen <chenzhe07@gmail.com>

=head1 CHANGELOG

v0.1.0 version

=cut
